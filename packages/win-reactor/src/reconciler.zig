const std = @import("std");
const backend = @import("backend.zig");
const context = @import("context.zig");
const element = @import("element.zig");
const RecordingBackend = @import("recording_backend.zig").RecordingBackend;
const render_cx = @import("render_cx.zig");

pub const Allocator = std.mem.Allocator;
pub const Backend = backend.Backend;
pub const WidgetId = backend.WidgetId;
pub const Element = element.Element;
pub const RequestRerender = render_cx.RequestRerender;

const ContextId = context.ContextId;
const ContextIdSet = render_cx.ContextIdSet;

pub const Tree = struct {
    element: Element,
    mounted: MountedElement,

    fn deinit(self: *Tree, allocator: Allocator) void {
        self.element.deinit(allocator);
        self.mounted.deinit(allocator);
        self.* = undefined;
    }
};

pub const MountedWidget = struct {
    id: WidgetId,
    children: []MountedElement = &.{},
};

pub const MountedComponent = struct {
    id: usize,
    render_cx: *render_cx.RenderCx,
    last_rendered: Element,
    rendered: *MountedElement,
    read_contexts: ContextIdSet = .empty,
};

pub const MountedProvider = struct {
    child: *MountedElement,
};

pub const MountedGroup = struct {
    children: []MountedElement = &.{},
};

pub const MountedElement = union(enum) {
    widget: MountedWidget,
    component: MountedComponent,
    provider: MountedProvider,
    group: MountedGroup,
    empty,

    pub fn deinit(self: *MountedElement, allocator: Allocator) void {
        switch (self.*) {
            .widget => |*widget| {
                deinitMountedSlice(allocator, widget.children);
            },
            .component => |*component_state| {
                component_state.rendered.deinit(allocator);
                allocator.destroy(component_state.rendered);
                component_state.last_rendered.deinit(allocator);
                component_state.read_contexts.deinit(allocator);
                component_state.render_cx.deinit();
                allocator.destroy(component_state.render_cx);
            },
            .provider => |*provider| {
                provider.child.deinit(allocator);
                allocator.destroy(provider.child);
            },
            .group => |*group| {
                deinitMountedSlice(allocator, group.children);
            },
            .empty => {},
        }
        self.* = .empty;
    }

    pub fn rootCount(self: *const MountedElement) usize {
        return switch (self.*) {
            .widget => 1,
            .component => |component_state| component_state.rendered.rootCount(),
            .provider => |provider| provider.child.rootCount(),
            .group => |group| blk: {
                var total: usize = 0;
                for (group.children) |*child| total += child.rootCount();
                break :blk total;
            },
            .empty => 0,
        };
    }

    pub fn collectRootIds(
        self: *const MountedElement,
        allocator: Allocator,
        out: *std.ArrayListUnmanaged(WidgetId),
    ) Allocator.Error!void {
        switch (self.*) {
            .widget => |widget| try out.append(allocator, widget.id),
            .component => |component_state| try component_state.rendered.collectRootIds(allocator, out),
            .provider => |provider| try provider.child.collectRootIds(allocator, out),
            .group => |group| {
                for (group.children) |*child| {
                    try child.collectRootIds(allocator, out);
                }
            },
            .empty => {},
        }
    }
};

const ParentContext = struct {
    parent: ?WidgetId,
    order: *std.ArrayListUnmanaged(WidgetId),
};

pub const Reconciler = struct {
    allocator: Allocator,
    backend: Backend,
    context_stack: context.ContextStack,
    request_rerender: RequestRerender = RequestRerender.none(),
    forced_components: std.AutoHashMapUnmanaged(usize, void) = .empty,
    next_component_id: usize = 1,

    pub fn init(
        allocator: Allocator,
        backend_impl: Backend,
        request_rerender: RequestRerender,
    ) Reconciler {
        return .{
            .allocator = allocator,
            .backend = backend_impl,
            .context_stack = context.ContextStack.init(allocator),
            .request_rerender = request_rerender,
        };
    }

    pub fn deinit(self: *Reconciler) void {
        self.context_stack.deinit();
        self.forced_components.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn setRequestRerender(self: *Reconciler, request_rerender: RequestRerender) void {
        self.request_rerender = request_rerender;
    }

    pub fn reconcile(self: *Reconciler, tree: *?Tree, next: *const Element) anyerror!void {
        if (tree.*) |*existing| {
            try self.update(existing, next);
            return;
        }
        tree.* = try self.mount(next);
    }

    pub fn mount(self: *Reconciler, next: *const Element) anyerror!Tree {
        var element_clone = try next.clone(self.allocator);
        errdefer element_clone.deinit(self.allocator);

        var order: std.ArrayListUnmanaged(WidgetId) = .empty;
        defer order.deinit(self.allocator);

        var parent_ctx = ParentContext{
            .parent = null,
            .order = &order,
        };

        var mounted = try self.mountElement(&parent_ctx, next);
        errdefer mounted.deinit(self.allocator);

        return .{
            .element = element_clone,
            .mounted = mounted,
        };
    }

    pub fn update(self: *Reconciler, tree: *Tree, next: *const Element) anyerror!void {
        var next_clone = try next.clone(self.allocator);
        errdefer next_clone.deinit(self.allocator);

        var order: std.ArrayListUnmanaged(WidgetId) = .empty;
        defer order.deinit(self.allocator);
        try tree.mounted.collectRootIds(self.allocator, &order);

        var parent_ctx = ParentContext{
            .parent = null,
            .order = &order,
        };

        try self.updateElement(&parent_ctx, &tree.mounted, &tree.element, next);

        var desired: std.ArrayListUnmanaged(WidgetId) = .empty;
        defer desired.deinit(self.allocator);
        try tree.mounted.collectRootIds(self.allocator, &desired);
        if (!widgetIdSlicesEql(order.items, desired.items)) {
            try self.backend.reorderChildren(null, desired.items);
        }

        tree.element.deinit(self.allocator);
        tree.element = next_clone;
    }

    pub fn unmount(self: *Reconciler, tree: *?Tree) anyerror!void {
        if (tree.*) |*existing| {
            try self.unmountTree(existing);
            tree.* = null;
        }
    }

    pub fn unmountTree(self: *Reconciler, tree: *Tree) anyerror!void {
        var order: std.ArrayListUnmanaged(WidgetId) = .empty;
        defer order.deinit(self.allocator);
        try tree.mounted.collectRootIds(self.allocator, &order);

        var parent_ctx = ParentContext{
            .parent = null,
            .order = &order,
        };
        try self.unmountElement(&parent_ctx, &tree.mounted);
        tree.element.deinit(self.allocator);
        tree.* = undefined;
    }

    fn mountElement(self: *Reconciler, parent_ctx: *ParentContext, el: *const Element) anyerror!MountedElement {
        return switch (el.*) {
            .widget => |widget| self.mountWidget(parent_ctx, &widget),
            .component => |component_element| self.mountComponent(parent_ctx, &component_element),
            .provider => |provider| self.mountProvider(parent_ctx, &provider),
            .group => |group| self.mountGroup(parent_ctx, &group),
            .empty => .empty,
        };
    }

    fn mountWidget(
        self: *Reconciler,
        parent_ctx: *ParentContext,
        widget: *const element.WidgetElement,
    ) anyerror!MountedElement {
        const id = try self.backend.mountWidget(
            parent_ctx.parent,
            parent_ctx.order.items.len,
            widget.kind,
        );
        try parent_ctx.order.append(self.allocator, id);
        errdefer {
            removeWidgetId(parent_ctx.order, id);
            self.backend.unmountWidget(id) catch {};
        }

        try self.applyProperties(id, widget.props);
        try self.applyEvents(id, widget.events);

        var child_order: std.ArrayListUnmanaged(WidgetId) = .empty;
        defer child_order.deinit(self.allocator);

        var child_ctx = ParentContext{
            .parent = id,
            .order = &child_order,
        };
        const mounted_children = try self.mountLiveChildren(&child_ctx, widget.children);

        return .{
            .widget = .{
                .id = id,
                .children = mounted_children,
            },
        };
    }

    fn mountComponent(
        self: *Reconciler,
        parent_ctx: *ParentContext,
        component_element: *const element.ComponentElement,
    ) anyerror!MountedElement {
        const cx = try self.allocator.create(render_cx.RenderCx);
        errdefer self.allocator.destroy(cx);
        cx.* = render_cx.RenderCx.init(self.allocator, self.request_rerender);
        errdefer cx.deinit();
        cx.setContextStack(&self.context_stack);

        cx.beginRender();
        var rendered = try component_element.render(cx);
        errdefer rendered.deinit(self.allocator);
        try cx.finishRender();

        const rendered_ptr = try self.allocator.create(MountedElement);
        errdefer self.allocator.destroy(rendered_ptr);
        rendered_ptr.* = try self.mountElement(parent_ctx, &rendered);
        errdefer {
            self.unmountElement(parent_ctx, rendered_ptr) catch {};
            self.allocator.destroy(rendered_ptr);
        }

        try cx.flushEffects();
        const read_contexts = cx.takeReadContexts();

        return .{
            .component = .{
                .id = self.takeNextComponentId(),
                .render_cx = cx,
                .last_rendered = rendered,
                .rendered = rendered_ptr,
                .read_contexts = read_contexts,
            },
        };
    }

    fn mountProvider(
        self: *Reconciler,
        parent_ctx: *ParentContext,
        provider: *const element.ProviderElement,
    ) anyerror!MountedElement {
        const child = try self.allocator.create(MountedElement);
        errdefer self.allocator.destroy(child);

        const mark = try provider.pushToContextStack(&self.context_stack);
        defer self.context_stack.popToMark(mark);

        child.* = try self.mountElement(parent_ctx, provider.child);
        return .{
            .provider = .{
                .child = child,
            },
        };
    }

    fn mountGroup(
        self: *Reconciler,
        parent_ctx: *ParentContext,
        group: *const element.GroupElement,
    ) anyerror!MountedElement {
        return .{
            .group = .{
                .children = try self.mountLiveChildren(parent_ctx, group.children),
            },
        };
    }

    fn mountLiveChildren(
        self: *Reconciler,
        parent_ctx: *ParentContext,
        children: []const Element,
    ) anyerror![]MountedElement {
        const live_children = try collectLiveChildren(self.allocator, children);
        defer self.allocator.free(live_children);

        var mounted_children: std.ArrayListUnmanaged(MountedElement) = .empty;
        errdefer {
            for (mounted_children.items) |*child| {
                self.unmountElement(parent_ctx, child) catch {};
            }
            mounted_children.deinit(self.allocator);
        }

        for (live_children) |child| {
            var mounted_child = try self.mountElement(parent_ctx, child);
            errdefer self.unmountElement(parent_ctx, &mounted_child) catch {};
            try mounted_children.append(self.allocator, mounted_child);
        }

        return try mounted_children.toOwnedSlice(self.allocator);
    }

    fn updateElement(
        self: *Reconciler,
        parent_ctx: *ParentContext,
        mounted: *MountedElement,
        old: *const Element,
        new: *const Element,
    ) anyerror!void {
        if (!old.canUpdate(new)) {
            var replacement = try self.mountElement(parent_ctx, new);
            errdefer replacement.deinit(self.allocator);
            try self.unmountElement(parent_ctx, mounted);
            mounted.* = replacement;
            return;
        }

        if (canSkipUpdate(old, new) and !self.subtreeNeedsUpdate(mounted)) {
            return;
        }

        switch (mounted.*) {
            .widget => |*widget_state| {
                std.debug.assert(old.* == .widget and new.* == .widget);
                try self.diffProperties(widget_state.id, old.widget.props, new.widget.props);
                try self.diffEvents(widget_state.id, old.widget.events, new.widget.events);

                var child_order: std.ArrayListUnmanaged(WidgetId) = .empty;
                defer child_order.deinit(self.allocator);
                try collectMountedSliceRootIds(self.allocator, widget_state.children, &child_order);

                var child_ctx = ParentContext{
                    .parent = widget_state.id,
                    .order = &child_order,
                };
                const next_children = try self.reconcileLiveChildren(
                    &child_ctx,
                    old.widget.children,
                    new.widget.children,
                    widget_state.children,
                );

                var desired: std.ArrayListUnmanaged(WidgetId) = .empty;
                defer desired.deinit(self.allocator);
                try collectMountedSliceRootIds(self.allocator, next_children, &desired);
                if (!widgetIdSlicesEql(child_order.items, desired.items)) {
                    try self.backend.reorderChildren(widget_state.id, desired.items);
                }

                if (widget_state.children.len > 0) self.allocator.free(widget_state.children);
                widget_state.children = next_children;
            },
            .component => |*component_state| {
                std.debug.assert(old.* == .component and new.* == .component);

                const forced_self = self.forced_components.contains(component_state.id);
                const own_dirty = component_state.render_cx.peekStateDirty();
                const descendants_dirty = self.subtreeNeedsUpdate(component_state.rendered);
                const rerender = forced_self or own_dirty or old.component.shouldUpdate(&new.component);

                if (!rerender) {
                    if (descendants_dirty) {
                        try self.updateElement(
                            parent_ctx,
                            component_state.rendered,
                            &component_state.last_rendered,
                            &component_state.last_rendered,
                        );
                    }
                    return;
                }

                component_state.render_cx.setRequestRerender(self.request_rerender);
                component_state.render_cx.setContextStack(&self.context_stack);
                component_state.render_cx.beginRender();

                var rendered = try new.component.render(component_state.render_cx);
                errdefer rendered.deinit(self.allocator);
                try component_state.render_cx.finishRender();

                try self.updateElement(
                    parent_ctx,
                    component_state.rendered,
                    &component_state.last_rendered,
                    &rendered,
                );
                try component_state.render_cx.flushEffects();

                component_state.last_rendered.deinit(self.allocator);
                component_state.last_rendered = rendered;
                component_state.read_contexts.deinit(self.allocator);
                component_state.read_contexts = component_state.render_cx.takeReadContexts();
            },
            .provider => |*provider_state| {
                std.debug.assert(old.* == .provider and new.* == .provider);

                var newly_forced: std.ArrayListUnmanaged(usize) = .empty;
                defer {
                    for (newly_forced.items) |component_id| {
                        _ = self.forced_components.remove(component_id);
                    }
                    newly_forced.deinit(self.allocator);
                }
                try self.forceChangedContextSubscribers(
                    provider_state.child,
                    old.provider.provisions,
                    new.provider.provisions,
                    &newly_forced,
                );

                const mark = try new.provider.pushToContextStack(&self.context_stack);
                defer self.context_stack.popToMark(mark);

                try self.updateElement(
                    parent_ctx,
                    provider_state.child,
                    old.provider.child,
                    new.provider.child,
                );
            },
            .group => |*group_state| {
                std.debug.assert(old.* == .group and new.* == .group);
                const next_children = try self.reconcileLiveChildren(
                    parent_ctx,
                    old.group.children,
                    new.group.children,
                    group_state.children,
                );
                if (group_state.children.len > 0) self.allocator.free(group_state.children);
                group_state.children = next_children;
            },
            .empty => {
                std.debug.assert(old.* == .empty and new.* == .empty);
            },
        }
    }

    fn reconcileLiveChildren(
        self: *Reconciler,
        parent_ctx: *ParentContext,
        old_children_declared: []const Element,
        new_children_declared: []const Element,
        old_children_mounted: []MountedElement,
    ) anyerror![]MountedElement {
        const old_live = try collectLiveChildren(self.allocator, old_children_declared);
        defer self.allocator.free(old_live);
        const new_live = try collectLiveChildren(self.allocator, new_children_declared);
        defer self.allocator.free(new_live);

        std.debug.assert(old_live.len == old_children_mounted.len);

        const has_keys = childrenHaveKeys(old_live) or childrenHaveKeys(new_live);
        if (has_keys) {
            return self.reconcileKeyedChildren(parent_ctx, old_live, new_live, old_children_mounted);
        }
        return self.reconcilePositionalChildren(parent_ctx, old_live, new_live, old_children_mounted);
    }

    fn reconcilePositionalChildren(
        self: *Reconciler,
        parent_ctx: *ParentContext,
        old_live: []*const Element,
        new_live: []*const Element,
        old_children_mounted: []MountedElement,
    ) anyerror![]MountedElement {
        var next_children: std.ArrayListUnmanaged(MountedElement) = .empty;

        const common = @min(old_live.len, new_live.len);
        var i: usize = 0;
        while (i < common) : (i += 1) {
            var child = old_children_mounted[i];
            old_children_mounted[i] = .empty;
            try self.updateElement(parent_ctx, &child, old_live[i], new_live[i]);
            try next_children.append(self.allocator, child);
        }

        while (i < new_live.len) : (i += 1) {
            var child = try self.mountElement(parent_ctx, new_live[i]);
            errdefer self.unmountElement(parent_ctx, &child) catch {};
            try next_children.append(self.allocator, child);
        }

        while (i < old_children_mounted.len) : (i += 1) {
            try self.unmountElement(parent_ctx, &old_children_mounted[i]);
        }

        return try next_children.toOwnedSlice(self.allocator);
    }

    fn reconcileKeyedChildren(
        self: *Reconciler,
        parent_ctx: *ParentContext,
        old_live: []*const Element,
        new_live: []*const Element,
        old_children_mounted: []MountedElement,
    ) anyerror![]MountedElement {
        var used = try self.allocator.alloc(bool, old_children_mounted.len);
        defer self.allocator.free(used);
        @memset(used, false);

        var next_children: std.ArrayListUnmanaged(MountedElement) = .empty;

        for (new_live, 0..) |new_child, new_index| {
            if (findMatchingOldChild(old_live, new_child, used, new_index)) |old_index| {
                used[old_index] = true;
                var child = old_children_mounted[old_index];
                old_children_mounted[old_index] = .empty;
                try self.updateElement(parent_ctx, &child, old_live[old_index], new_child);
                try next_children.append(self.allocator, child);
            } else {
                var child = try self.mountElement(parent_ctx, new_child);
                errdefer self.unmountElement(parent_ctx, &child) catch {};
                try next_children.append(self.allocator, child);
            }
        }

        for (old_children_mounted, 0..) |*old_child, index| {
            if (!used[index]) {
                try self.unmountElement(parent_ctx, old_child);
            }
        }

        return try next_children.toOwnedSlice(self.allocator);
    }

    fn unmountElement(
        self: *Reconciler,
        parent_ctx: *ParentContext,
        mounted: *MountedElement,
    ) anyerror!void {
        var root_ids: std.ArrayListUnmanaged(WidgetId) = .empty;
        defer root_ids.deinit(self.allocator);
        try mounted.collectRootIds(self.allocator, &root_ids);

        self.runUnmountHooks(mounted);
        for (root_ids.items) |id| {
            removeWidgetId(parent_ctx.order, id);
        }

        var index = root_ids.items.len;
        while (index > 0) : (index -= 1) {
            try self.backend.unmountWidget(root_ids.items[index - 1]);
        }

        mounted.deinit(self.allocator);
    }

    fn runUnmountHooks(self: *Reconciler, mounted: *MountedElement) void {
        switch (mounted.*) {
            .widget => |*widget_state| {
                for (widget_state.children) |*child| {
                    self.runUnmountHooks(child);
                }
            },
            .component => |*component_state| {
                self.runUnmountHooks(component_state.rendered);
                component_state.render_cx.runCleanups();
            },
            .provider => |*provider_state| {
                self.runUnmountHooks(provider_state.child);
            },
            .group => |*group_state| {
                for (group_state.children) |*child| {
                    self.runUnmountHooks(child);
                }
            },
            .empty => {},
        }
    }

    fn applyProperties(
        self: *Reconciler,
        id: WidgetId,
        properties: []const element.Property,
    ) anyerror!void {
        for (properties) |*property| {
            try self.backend.setProperty(id, property);
        }
    }

    fn applyEvents(
        self: *Reconciler,
        id: WidgetId,
        handlers: []const element.EventHandler,
    ) anyerror!void {
        for (handlers) |*handler| {
            try self.backend.attachEvent(id, handler);
        }
    }

    fn diffProperties(
        self: *Reconciler,
        id: WidgetId,
        old: []const element.Property,
        new: []const element.Property,
    ) anyerror!void {
        for (new) |*new_property| {
            if (findProperty(old, new_property.name)) |old_property| {
                if (old_property.eql(new_property)) continue;
            }
            try self.backend.setProperty(id, new_property);
        }

        for (old) |*old_property| {
            if (findProperty(new, old_property.name) == null) {
                try self.backend.unsetProperty(id, old_property.name);
            }
        }
    }

    fn diffEvents(
        self: *Reconciler,
        id: WidgetId,
        old: []const element.EventHandler,
        new: []const element.EventHandler,
    ) anyerror!void {
        for (new) |*new_handler| {
            if (findEvent(old, new_handler.name)) |old_handler| {
                if (old_handler.eql(new_handler)) continue;
            }
            try self.backend.attachEvent(id, new_handler);
        }

        for (old) |*old_handler| {
            if (findEvent(new, old_handler.name) == null) {
                try self.backend.detachEvent(id, old_handler.name);
            }
        }
    }

    fn subtreeNeedsUpdate(self: *const Reconciler, mounted: *const MountedElement) bool {
        return switch (mounted.*) {
            .widget => |widget_state| blk: {
                for (widget_state.children) |*child| {
                    if (self.subtreeNeedsUpdate(child)) break :blk true;
                }
                break :blk false;
            },
            .component => |component_state| {
                if (self.forced_components.contains(component_state.id)) return true;
                if (component_state.render_cx.peekStateDirty()) return true;
                return self.subtreeNeedsUpdate(component_state.rendered);
            },
            .provider => |provider_state| self.subtreeNeedsUpdate(provider_state.child),
            .group => |group_state| blk: {
                for (group_state.children) |*child| {
                    if (self.subtreeNeedsUpdate(child)) break :blk true;
                }
                break :blk false;
            },
            .empty => false,
        };
    }

    fn forceChangedContextSubscribers(
        self: *Reconciler,
        mounted: *const MountedElement,
        old: []const element.ContextProvision,
        new: []const element.ContextProvision,
        newly_forced: *std.ArrayListUnmanaged(usize),
    ) anyerror!void {
        var changed: std.ArrayListUnmanaged(ContextId) = .empty;
        defer changed.deinit(self.allocator);
        try collectChangedContextIds(self.allocator, old, new, &changed);
        if (changed.items.len == 0) return;

        var affected: std.ArrayListUnmanaged(usize) = .empty;
        defer affected.deinit(self.allocator);
        try self.collectAffectedComponents(mounted, changed.items, &affected);

        for (affected.items) |component_id| {
            if (self.forced_components.contains(component_id)) continue;
            try self.forced_components.put(self.allocator, component_id, {});
            try newly_forced.append(self.allocator, component_id);
        }
    }

    fn collectAffectedComponents(
        self: *const Reconciler,
        mounted: *const MountedElement,
        changed: []const ContextId,
        out: *std.ArrayListUnmanaged(usize),
    ) Allocator.Error!void {
        switch (mounted.*) {
            .widget => |widget_state| {
                for (widget_state.children) |*child| {
                    try self.collectAffectedComponents(child, changed, out);
                }
            },
            .component => |component_state| {
                if (contextSetIntersects(component_state.read_contexts, changed)) {
                    try out.append(self.allocator, component_state.id);
                }
                try self.collectAffectedComponents(component_state.rendered, changed, out);
            },
            .provider => |provider_state| try self.collectAffectedComponents(provider_state.child, changed, out),
            .group => |group_state| {
                for (group_state.children) |*child| {
                    try self.collectAffectedComponents(child, changed, out);
                }
            },
            .empty => {},
        }
    }

    fn takeNextComponentId(self: *Reconciler) usize {
        const id = self.next_component_id;
        self.next_component_id += 1;
        return id;
    }
};

fn collectLiveChildren(
    allocator: Allocator,
    children: []const Element,
) Allocator.Error![]*const Element {
    var out: std.ArrayListUnmanaged(*const Element) = .empty;
    errdefer out.deinit(allocator);

    for (children) |*child| {
        try appendLiveChild(&out, allocator, child);
    }
    return try out.toOwnedSlice(allocator);
}

fn appendLiveChild(
    out: *std.ArrayListUnmanaged(*const Element),
    allocator: Allocator,
    child: *const Element,
) Allocator.Error!void {
    switch (child.*) {
        .empty => {},
        .group => |group| {
            if (group.key) |_| {
                try out.append(allocator, child);
            } else {
                for (group.children) |*group_child| {
                    try appendLiveChild(out, allocator, group_child);
                }
            }
        },
        else => try out.append(allocator, child),
    }
}

fn childrenHaveKeys(children: []*const Element) bool {
    for (children) |child| {
        if (child.key() != null) return true;
    }
    return false;
}

fn findMatchingOldChild(
    old_live: []*const Element,
    new_child: *const Element,
    used: []bool,
    new_index: usize,
) ?usize {
    for (old_live, 0..) |old_child, old_index| {
        if (used[old_index]) continue;
        if (!old_child.canUpdate(new_child)) continue;
        if (effectiveKeyMatch(old_child, old_index, new_child, new_index)) {
            return old_index;
        }
    }
    return null;
}

fn effectiveKeyMatch(
    old_child: *const Element,
    old_index: usize,
    new_child: *const Element,
    new_index: usize,
) bool {
    const old_key = old_child.key();
    const new_key = new_child.key();
    if (old_key != null or new_key != null) {
        return optionalStringEql(old_key, new_key);
    }
    return old_index == new_index and std.mem.eql(u8, old_child.kindName(), new_child.kindName());
}

fn findProperty(properties: []const element.Property, name: []const u8) ?*const element.Property {
    for (properties) |*property| {
        if (std.mem.eql(u8, property.name, name)) return property;
    }
    return null;
}

fn findEvent(events: []const element.EventHandler, name: []const u8) ?*const element.EventHandler {
    for (events) |*event_handler| {
        if (std.mem.eql(u8, event_handler.name, name)) return event_handler;
    }
    return null;
}

fn canSkipUpdate(old: *const Element, new: *const Element) bool {
    return elementEql(old, new);
}

fn elementEql(old: *const Element, new: *const Element) bool {
    return switch (old.*) {
        .widget => |old_widget| switch (new.*) {
            .widget => |new_widget| optionalStringEql(old_widget.key, new_widget.key) and
                old_widget.kind == new_widget.kind and
                propertiesEql(old_widget.props, new_widget.props) and
                eventsEql(old_widget.events, new_widget.events) and
                elementsEql(old_widget.children, new_widget.children),
            else => false,
        },
        .component => |old_component| switch (new.*) {
            .component => |new_component| blk: {
                if (!optionalStringEql(old_component.key, new_component.key)) break :blk false;
                if (old_component.memoized != new_component.memoized) break :blk false;
                if (!old_component.sameDefinition(&new_component)) break :blk false;
                if (!old_component.memoized) break :blk false;
                break :blk old_component.propsEqual(&new_component);
            },
            else => false,
        },
        .provider => |old_provider| switch (new.*) {
            .provider => |new_provider| optionalStringEql(old_provider.key, new_provider.key) and
                provisionsEql(old_provider.provisions, new_provider.provisions) and
                elementEql(old_provider.child, new_provider.child),
            else => false,
        },
        .group => |old_group| switch (new.*) {
            .group => |new_group| optionalStringEql(old_group.key, new_group.key) and
                elementsEql(old_group.children, new_group.children),
            else => false,
        },
        .empty => new.* == .empty,
    };
}

fn propertiesEql(lhs: []const element.Property, rhs: []const element.Property) bool {
    if (lhs.len != rhs.len) return false;
    for (lhs, rhs) |*lhs_property, *rhs_property| {
        if (!lhs_property.eql(rhs_property)) return false;
    }
    return true;
}

fn eventsEql(lhs: []const element.EventHandler, rhs: []const element.EventHandler) bool {
    if (lhs.len != rhs.len) return false;
    for (lhs, rhs) |*lhs_handler, *rhs_handler| {
        if (!lhs_handler.eql(rhs_handler)) return false;
    }
    return true;
}

fn provisionsEql(lhs: []const element.ContextProvision, rhs: []const element.ContextProvision) bool {
    if (lhs.len != rhs.len) return false;
    for (lhs, rhs) |*lhs_provision, *rhs_provision| {
        if (!lhs_provision.eql(rhs_provision)) return false;
    }
    return true;
}

fn elementsEql(lhs: []const Element, rhs: []const Element) bool {
    if (lhs.len != rhs.len) return false;
    for (lhs, rhs) |*lhs_child, *rhs_child| {
        if (!elementEql(lhs_child, rhs_child)) return false;
    }
    return true;
}

fn optionalStringEql(lhs: ?[]const u8, rhs: ?[]const u8) bool {
    if (lhs) |lhs_value| {
        if (rhs) |rhs_value| {
            return std.mem.eql(u8, lhs_value, rhs_value);
        }
        return false;
    }
    return rhs == null;
}

fn collectMountedSliceRootIds(
    allocator: Allocator,
    mounted_children: []const MountedElement,
    out: *std.ArrayListUnmanaged(WidgetId),
) Allocator.Error!void {
    for (mounted_children) |*mounted_child| {
        try mounted_child.collectRootIds(allocator, out);
    }
}

fn deinitMountedSlice(allocator: Allocator, mounted_children: []MountedElement) void {
    for (mounted_children) |*child| {
        child.deinit(allocator);
    }
    if (mounted_children.len > 0) allocator.free(mounted_children);
}

fn widgetIdSlicesEql(lhs: []const WidgetId, rhs: []const WidgetId) bool {
    return std.mem.eql(WidgetId, lhs, rhs);
}

fn removeWidgetId(order: *std.ArrayListUnmanaged(WidgetId), id: WidgetId) void {
    for (order.items, 0..) |existing, index| {
        if (existing == id) {
            _ = order.orderedRemove(index);
            return;
        }
    }
}

fn contextSetIntersects(read_contexts: ContextIdSet, changed: []const ContextId) bool {
    for (changed) |context_id| {
        if (read_contexts.contains(context_id)) return true;
    }
    return false;
}

fn collectChangedContextIds(
    allocator: Allocator,
    old: []const element.ContextProvision,
    new: []const element.ContextProvision,
    out: *std.ArrayListUnmanaged(ContextId),
) Allocator.Error!void {
    var all_ids: std.ArrayListUnmanaged(ContextId) = .empty;
    defer all_ids.deinit(allocator);

    for (old) |*provision| {
        try appendUniqueContextId(allocator, &all_ids, provision.context_id);
    }
    for (new) |*provision| {
        try appendUniqueContextId(allocator, &all_ids, provision.context_id);
    }

    for (all_ids.items) |context_id| {
        const old_visible = lastProvision(old, context_id);
        const new_visible = lastProvision(new, context_id);
        if (old_visible == null or new_visible == null) {
            try out.append(allocator, context_id);
            continue;
        }
        if (!old_visible.?.eql(new_visible.?)) {
            try out.append(allocator, context_id);
        }
    }
}

fn appendUniqueContextId(
    allocator: Allocator,
    out: *std.ArrayListUnmanaged(ContextId),
    context_id: ContextId,
) Allocator.Error!void {
    for (out.items) |existing| {
        if (existing.raw == context_id.raw) return;
    }
    try out.append(allocator, context_id);
}

fn lastProvision(
    provisions: []const element.ContextProvision,
    context_id: ContextId,
) ?*const element.ContextProvision {
    var index = provisions.len;
    while (index > 0) : (index -= 1) {
        const provision = &provisions[index - 1];
        if (provision.context_id.raw == context_id.raw) return provision;
    }
    return null;
}

fn noopCallbackA() void {}
fn noopCallbackB() void {}

fn buildLeaf(
    allocator: Allocator,
    key: ?[]const u8,
    property_name: []const u8,
    value: anytype,
) !Element {
    var builder = element.leaf(allocator);
    defer builder.deinit();
    if (key) |owned_key| {
        _ = try builder.withKey(owned_key);
    }
    _ = try builder.prop(property_name, value);
    return builder.build();
}

fn buildLeafWithEvent(
    allocator: Allocator,
    key: ?[]const u8,
    property_name: []const u8,
    value: anytype,
    event_name: []const u8,
    callback: element.EventCallback,
) !Element {
    var builder = element.leaf(allocator);
    defer builder.deinit();
    if (key) |owned_key| {
        _ = try builder.withKey(owned_key);
    }
    _ = try (try builder.prop(property_name, value)).on(event_name, callback);
    return builder.build();
}

fn StateCapture(comptime T: type) type {
    return struct {
        setter: ?render_cx.SetState(T) = null,
    };
}

fn ReducerCapture(comptime State: type, comptime Action: type) type {
    return struct {
        update: ?render_cx.Updater(State) = null,
        dispatch: ?render_cx.Dispatch(State, Action) = null,
    };
}

const TestRerenderCounter = struct {
    count: u32 = 0,

    fn request(raw: ?*anyopaque) void {
        const self: *TestRerenderCounter = @ptrCast(@alignCast(raw.?));
        self.count += 1;
    }
};

const TestLog = struct {
    items: [16][]const u8 = undefined,
    len: usize = 0,

    fn push(self: *TestLog, value: []const u8) void {
        self.items[self.len] = value;
        self.len += 1;
    }

    fn slice(self: *const TestLog) []const []const u8 {
        return self.items[0..self.len];
    }
};

const CountAction = union(enum) {
    add: i32,
    reset,
};

fn incrementReducer(state: *const i32) i32 {
    return state.* + 1;
}

fn countReducer(state: *const i32, action: CountAction) i32 {
    return switch (action) {
        .add => |amount| state.* + amount,
        .reset => 0,
    };
}

test "initial mount mounts widgets, props, and grouped children" {
    var backend_state = RecordingBackend.init(std.testing.allocator);
    defer backend_state.deinit();

    var reconciler = Reconciler.init(
        std.testing.allocator,
        Backend.from(&backend_state),
        RequestRerender.none(),
    );
    defer reconciler.deinit();

    var title = try buildLeaf(std.testing.allocator, "title", "text", @as([]const u8, "hello"));
    defer title.deinit(std.testing.allocator);
    var button = try buildLeafWithEvent(
        std.testing.allocator,
        "button",
        "role",
        @as([]const u8, "primary"),
        "click",
        element.EventCallback.fromFunction(noopCallbackA),
    );
    defer button.deinit(std.testing.allocator);
    var group = try element.group(std.testing.allocator, .{ &title, &button });
    defer group.deinit(std.testing.allocator);

    var root_builder = element.container(std.testing.allocator);
    _ = try (try root_builder.prop("spacing", @as(f32, 8))).child(&group);
    defer root_builder.deinit();

    var root = try root_builder.build();
    defer root.deinit(std.testing.allocator);

    var tree = try reconciler.mount(&root);
    defer reconciler.unmountTree(&tree) catch unreachable;

    try std.testing.expectEqual(@as(usize, 7), backend_state.calls.items.len);
    try std.testing.expectEqual(element.WidgetKind.container, backend_state.calls.items[0].mount_widget.kind);
    try std.testing.expectEqual(@as(?WidgetId, null), backend_state.calls.items[0].mount_widget.parent);
    try std.testing.expectEqualStrings("spacing", backend_state.calls.items[1].set_property.property.name);
    try std.testing.expectEqual(element.WidgetKind.leaf, backend_state.calls.items[2].mount_widget.kind);
    try std.testing.expectEqual(@as(?WidgetId, 1), backend_state.calls.items[2].mount_widget.parent);
    try std.testing.expectEqualStrings("text", backend_state.calls.items[3].set_property.property.name);
    try std.testing.expectEqual(element.WidgetKind.leaf, backend_state.calls.items[4].mount_widget.kind);
    try std.testing.expectEqual(@as(?WidgetId, 1), backend_state.calls.items[4].mount_widget.parent);
    try std.testing.expectEqualStrings("role", backend_state.calls.items[5].set_property.property.name);
    try std.testing.expectEqualStrings("click", backend_state.calls.items[6].attach_event.handler.name);
}

test "memoized component rerender with identical props produces zero backend calls" {
    const Props = struct {
        value: i32,
        renders: *u32,
    };
    const Render = struct {
        fn call(props: *const Props, cx: *render_cx.RenderCx) element.Error!Element {
            props.renders.* += 1;
            return buildLeaf(cx.getAllocator(), null, "value", props.value);
        }
    };

    var backend_state = RecordingBackend.init(std.testing.allocator);
    defer backend_state.deinit();
    var reconciler = Reconciler.init(
        std.testing.allocator,
        Backend.from(&backend_state),
        RequestRerender.none(),
    );
    defer reconciler.deinit();

    var renders: u32 = 0;

    var first = try element.memo(
        std.testing.allocator,
        "counter",
        Props{ .value = 1, .renders = &renders },
        Render.call,
    );
    defer first.deinit(std.testing.allocator);

    var tree = try reconciler.mount(&first);
    defer reconciler.unmountTree(&tree) catch unreachable;
    try std.testing.expectEqual(@as(u32, 1), renders);

    backend_state.clearCalls();

    var second = try element.memo(
        std.testing.allocator,
        "counter",
        Props{ .value = 1, .renders = &renders },
        Render.call,
    );
    defer second.deinit(std.testing.allocator);

    try reconciler.update(&tree, &second);
    try std.testing.expectEqual(@as(u32, 1), renders);
    try std.testing.expectEqual(@as(usize, 0), backend_state.calls.items.len);
}

test "prop changes emit property update and event detach" {
    var backend_state = RecordingBackend.init(std.testing.allocator);
    defer backend_state.deinit();
    var reconciler = Reconciler.init(
        std.testing.allocator,
        Backend.from(&backend_state),
        RequestRerender.none(),
    );
    defer reconciler.deinit();

    var first = try buildLeafWithEvent(
        std.testing.allocator,
        null,
        "text",
        @as([]const u8, "before"),
        "click",
        element.EventCallback.fromFunction(noopCallbackA),
    );
    defer first.deinit(std.testing.allocator);

    var tree = try reconciler.mount(&first);
    defer reconciler.unmountTree(&tree) catch unreachable;
    backend_state.clearCalls();

    var builder = element.leaf(std.testing.allocator);
    _ = try builder.prop("text", @as([]const u8, "after"));
    defer builder.deinit();
    var second = try builder.build();
    defer second.deinit(std.testing.allocator);

    try reconciler.update(&tree, &second);

    try std.testing.expectEqual(@as(usize, 2), backend_state.calls.items.len);
    try std.testing.expectEqualStrings("text", backend_state.calls.items[0].set_property.property.name);
    try std.testing.expectEqualStrings("after", backend_state.calls.items[0].set_property.property.get([]const u8).?);
    try std.testing.expectEqualStrings("click", backend_state.calls.items[1].detach_event.name);
}

test "adding and removing children emits mount and unmount calls" {
    var backend_state = RecordingBackend.init(std.testing.allocator);
    defer backend_state.deinit();
    var reconciler = Reconciler.init(
        std.testing.allocator,
        Backend.from(&backend_state),
        RequestRerender.none(),
    );
    defer reconciler.deinit();

    var child_a = try buildLeaf(std.testing.allocator, "a", "text", @as([]const u8, "A"));
    defer child_a.deinit(std.testing.allocator);
    var root_builder = element.container(std.testing.allocator);
    _ = try root_builder.child(&child_a);
    defer root_builder.deinit();
    var first = try root_builder.build();
    defer first.deinit(std.testing.allocator);

    var tree = try reconciler.mount(&first);
    defer reconciler.unmountTree(&tree) catch unreachable;
    backend_state.clearCalls();

    var updated_a = try buildLeaf(std.testing.allocator, "a", "text", @as([]const u8, "A"));
    defer updated_a.deinit(std.testing.allocator);
    var child_b = try buildLeaf(std.testing.allocator, "b", "text", @as([]const u8, "B"));
    defer child_b.deinit(std.testing.allocator);
    var add_builder = element.container(std.testing.allocator);
    _ = try (try add_builder.child(&updated_a)).child(&child_b);
    defer add_builder.deinit();
    var second = try add_builder.build();
    defer second.deinit(std.testing.allocator);

    try reconciler.update(&tree, &second);
    try std.testing.expectEqual(element.WidgetKind.leaf, backend_state.calls.items[0].mount_widget.kind);
    backend_state.clearCalls();

    var final_a = try buildLeaf(std.testing.allocator, "a", "text", @as([]const u8, "A"));
    defer final_a.deinit(std.testing.allocator);
    var remove_builder = element.container(std.testing.allocator);
    _ = try remove_builder.child(&final_a);
    defer remove_builder.deinit();
    var third = try remove_builder.build();
    defer third.deinit(std.testing.allocator);

    try reconciler.update(&tree, &third);
    try std.testing.expectEqual(@as(usize, 1), backend_state.calls.items.len);
    try std.testing.expectEqual(@as(WidgetId, 3), backend_state.calls.items[0].unmount_widget);
}

test "keyed child reorder emits reorder call without remounting" {
    var backend_state = RecordingBackend.init(std.testing.allocator);
    defer backend_state.deinit();
    var reconciler = Reconciler.init(
        std.testing.allocator,
        Backend.from(&backend_state),
        RequestRerender.none(),
    );
    defer reconciler.deinit();

    var child_a = try buildLeaf(std.testing.allocator, "a", "text", @as([]const u8, "A"));
    defer child_a.deinit(std.testing.allocator);
    var child_b = try buildLeaf(std.testing.allocator, "b", "text", @as([]const u8, "B"));
    defer child_b.deinit(std.testing.allocator);
    var child_c = try buildLeaf(std.testing.allocator, "c", "text", @as([]const u8, "C"));
    defer child_c.deinit(std.testing.allocator);
    var builder = element.container(std.testing.allocator);
    _ = try (try (try builder.child(&child_a)).child(&child_b)).child(&child_c);
    defer builder.deinit();
    var first = try builder.build();
    defer first.deinit(std.testing.allocator);

    var tree = try reconciler.mount(&first);
    defer reconciler.unmountTree(&tree) catch unreachable;
    backend_state.clearCalls();

    var next_a = try buildLeaf(std.testing.allocator, "a", "text", @as([]const u8, "A"));
    defer next_a.deinit(std.testing.allocator);
    var next_b = try buildLeaf(std.testing.allocator, "b", "text", @as([]const u8, "B"));
    defer next_b.deinit(std.testing.allocator);
    var next_c = try buildLeaf(std.testing.allocator, "c", "text", @as([]const u8, "C"));
    defer next_c.deinit(std.testing.allocator);
    var reorder_builder = element.container(std.testing.allocator);
    _ = try (try (try reorder_builder.child(&next_c)).child(&next_a)).child(&next_b);
    defer reorder_builder.deinit();
    var second = try reorder_builder.build();
    defer second.deinit(std.testing.allocator);

    try reconciler.update(&tree, &second);

    try std.testing.expectEqual(@as(usize, 1), backend_state.calls.items.len);
    try std.testing.expectEqual(@as(?WidgetId, 1), backend_state.calls.items[0].reorder_children.parent);
    try std.testing.expectEqualSlices(
        WidgetId,
        &[_]WidgetId{ 4, 2, 3 },
        backend_state.calls.items[0].reorder_children.children,
    );
}

test "provider changes force memoized consumers to rerender" {
    const ThemeContext = context.Context([]const u8);
    const theme = ThemeContext.init("light");

    const Props = struct {
        theme: *const context.Context([]const u8),
        renders: *u32,
    };
    const Render = struct {
        fn call(props: *const Props, cx: *render_cx.RenderCx) element.Error!Element {
            props.renders.* += 1;
            const theme_value = try cx.useContext([]const u8, props.theme);
            return buildLeaf(cx.getAllocator(), null, "theme", theme_value);
        }
    };

    var backend_state = RecordingBackend.init(std.testing.allocator);
    defer backend_state.deinit();
    var reconciler = Reconciler.init(
        std.testing.allocator,
        Backend.from(&backend_state),
        RequestRerender.none(),
    );
    defer reconciler.deinit();

    var renders: u32 = 0;
    var consumer = try element.memo(
        std.testing.allocator,
        "consumer",
        Props{ .theme = &theme, .renders = &renders },
        Render.call,
    );
    defer consumer.deinit(std.testing.allocator);
    var first = try element.provide(
        std.testing.allocator,
        &consumer,
        &theme,
        @as([]const u8, "dark"),
    );
    defer first.deinit(std.testing.allocator);

    var tree = try reconciler.mount(&first);
    defer reconciler.unmountTree(&tree) catch unreachable;
    try std.testing.expectEqual(@as(u32, 1), renders);
    backend_state.clearCalls();

    var consumer_again = try element.memo(
        std.testing.allocator,
        "consumer",
        Props{ .theme = &theme, .renders = &renders },
        Render.call,
    );
    defer consumer_again.deinit(std.testing.allocator);
    var second = try element.provide(
        std.testing.allocator,
        &consumer_again,
        &theme,
        @as([]const u8, "light"),
    );
    defer second.deinit(std.testing.allocator);

    try reconciler.update(&tree, &second);
    try std.testing.expectEqual(@as(u32, 2), renders);
    try std.testing.expectEqual(@as(usize, 1), backend_state.calls.items.len);
    try std.testing.expectEqualStrings("theme", backend_state.calls.items[0].set_property.property.name);
    try std.testing.expectEqualStrings("light", backend_state.calls.items[0].set_property.property.get([]const u8).?);
}

test "useState rerenders memoized components in place" {
    const Capture = StateCapture(i32);
    const Props = struct {
        capture: *Capture,
        renders: *u32,
    };
    const Render = struct {
        fn call(props: *const Props, cx: *render_cx.RenderCx) element.Error!Element {
            props.renders.* += 1;
            const state = try cx.useState(i32, 0);
            props.capture.setter = state.set;
            return buildLeaf(cx.getAllocator(), null, "count", state.value.*);
        }
    };

    var capture: Capture = .{};
    var renders: u32 = 0;
    var rerenders: TestRerenderCounter = .{};
    var backend_state = RecordingBackend.init(std.testing.allocator);
    defer backend_state.deinit();
    var reconciler = Reconciler.init(
        std.testing.allocator,
        Backend.from(&backend_state),
        RequestRerender.init(@ptrCast(&rerenders), TestRerenderCounter.request),
    );
    defer reconciler.deinit();

    var first = try element.memo(
        std.testing.allocator,
        "counter",
        Props{ .capture = &capture, .renders = &renders },
        Render.call,
    );
    defer first.deinit(std.testing.allocator);

    var tree = try reconciler.mount(&first);
    defer reconciler.unmountTree(&tree) catch unreachable;
    try std.testing.expectEqual(@as(u32, 1), renders);

    const leaf_id = backend_state.rootChildren()[0];
    try std.testing.expectEqual(@as(i32, 0), backend_state.propertyValue(i32, leaf_id, "count").?);

    backend_state.clearCalls();
    capture.setter.?.call(1);
    try std.testing.expectEqual(@as(u32, 1), rerenders.count);

    var second = try element.memo(
        std.testing.allocator,
        "counter",
        Props{ .capture = &capture, .renders = &renders },
        Render.call,
    );
    defer second.deinit(std.testing.allocator);

    try reconciler.update(&tree, &second);
    try std.testing.expectEqual(@as(u32, 2), renders);
    try std.testing.expectEqual(@as(usize, 1), backend_state.calls.items.len);
    try std.testing.expect(backend_state.sawPropertySet(i32, leaf_id, "count", 1));
    try std.testing.expectEqual(@as(i32, 1), backend_state.propertyValue(i32, leaf_id, "count").?);

    backend_state.clearCalls();

    var third = try element.memo(
        std.testing.allocator,
        "counter",
        Props{ .capture = &capture, .renders = &renders },
        Render.call,
    );
    defer third.deinit(std.testing.allocator);

    try reconciler.update(&tree, &third);
    try std.testing.expectEqual(@as(u32, 2), renders);
    try std.testing.expectEqual(@as(usize, 0), backend_state.calls.items.len);
}

test "useEffect runs after mount and state updates" {
    const Capture = StateCapture(i32);
    const Props = struct {
        capture: *Capture,
        log: *TestLog,
    };
    const EffectContext = struct {
        log: *TestLog,
        value: i32,
    };
    const RunEffect = struct {
        fn run(ctx: *const EffectContext) void {
            switch (ctx.value) {
                0 => ctx.log.push("effect-0"),
                1 => ctx.log.push("effect-1"),
                else => ctx.log.push("effect-other"),
            }
        }
    };
    const Render = struct {
        fn call(props: *const Props, cx: *render_cx.RenderCx) element.Error!Element {
            const state = try cx.useState(i32, 0);
            props.capture.setter = state.set;
            try cx.useEffect(state.value.*, EffectContext{
                .log = props.log,
                .value = state.value.*,
            }, RunEffect.run);
            return buildLeaf(cx.getAllocator(), null, "count", state.value.*);
        }
    };

    var capture: Capture = .{};
    var log: TestLog = .{};
    var backend_state = RecordingBackend.init(std.testing.allocator);
    defer backend_state.deinit();
    var reconciler = Reconciler.init(
        std.testing.allocator,
        Backend.from(&backend_state),
        RequestRerender.none(),
    );
    defer reconciler.deinit();

    var first = try element.memo(
        std.testing.allocator,
        "effect-counter",
        Props{ .capture = &capture, .log = &log },
        Render.call,
    );
    defer first.deinit(std.testing.allocator);

    var tree = try reconciler.mount(&first);
    defer reconciler.unmountTree(&tree) catch unreachable;
    try std.testing.expectEqualSlices([]const u8, &[_][]const u8{"effect-0"}, log.slice());

    const leaf_id = backend_state.rootChildren()[0];
    backend_state.clearCalls();
    capture.setter.?.call(1);

    var second = try element.memo(
        std.testing.allocator,
        "effect-counter",
        Props{ .capture = &capture, .log = &log },
        Render.call,
    );
    defer second.deinit(std.testing.allocator);

    try reconciler.update(&tree, &second);
    try std.testing.expectEqualSlices(
        []const u8,
        &[_][]const u8{ "effect-0", "effect-1" },
        log.slice(),
    );
    try std.testing.expectEqual(@as(i32, 1), backend_state.propertyValue(i32, leaf_id, "count").?);
}

test "useEffectWithCleanup cleans up on rerender and unmount" {
    const Capture = StateCapture(i32);
    const Props = struct {
        capture: *Capture,
        log: *TestLog,
    };
    const EffectContext = struct {
        log: *TestLog,
        value: i32,
    };
    const CleanupContext = struct {
        log: *TestLog,
        value: i32,
    };
    const RunEffect = struct {
        fn run(ctx: *const EffectContext) ?CleanupContext {
            switch (ctx.value) {
                0 => ctx.log.push("effect-0"),
                1 => ctx.log.push("effect-1"),
                else => ctx.log.push("effect-other"),
            }
            return .{
                .log = ctx.log,
                .value = ctx.value,
            };
        }
    };
    const RunCleanup = struct {
        fn run(ctx: *CleanupContext) void {
            switch (ctx.value) {
                0 => ctx.log.push("cleanup-0"),
                1 => ctx.log.push("cleanup-1"),
                else => ctx.log.push("cleanup-other"),
            }
        }
    };
    const Render = struct {
        fn call(props: *const Props, cx: *render_cx.RenderCx) element.Error!Element {
            const state = try cx.useState(i32, 0);
            props.capture.setter = state.set;
            try cx.useEffectWithCleanup(CleanupContext, state.value.*, EffectContext{
                .log = props.log,
                .value = state.value.*,
            }, RunEffect.run, RunCleanup.run);
            return buildLeaf(cx.getAllocator(), null, "count", state.value.*);
        }
    };

    var capture: Capture = .{};
    var log: TestLog = .{};
    var backend_state = RecordingBackend.init(std.testing.allocator);
    defer backend_state.deinit();
    var reconciler = Reconciler.init(
        std.testing.allocator,
        Backend.from(&backend_state),
        RequestRerender.none(),
    );
    defer reconciler.deinit();

    var first = try element.memo(
        std.testing.allocator,
        "cleanup-counter",
        Props{ .capture = &capture, .log = &log },
        Render.call,
    );
    defer first.deinit(std.testing.allocator);

    var tree = try reconciler.mount(&first);
    var mounted = true;
    defer if (mounted) reconciler.unmountTree(&tree) catch unreachable;
    try std.testing.expectEqualSlices([]const u8, &[_][]const u8{"effect-0"}, log.slice());

    capture.setter.?.call(1);

    var second = try element.memo(
        std.testing.allocator,
        "cleanup-counter",
        Props{ .capture = &capture, .log = &log },
        Render.call,
    );
    defer second.deinit(std.testing.allocator);

    try reconciler.update(&tree, &second);
    try std.testing.expectEqualSlices(
        []const u8,
        &[_][]const u8{ "effect-0", "cleanup-0", "effect-1" },
        log.slice(),
    );

    try reconciler.unmountTree(&tree);
    mounted = false;
    try std.testing.expectEqualSlices(
        []const u8,
        &[_][]const u8{ "effect-0", "cleanup-0", "effect-1", "cleanup-1" },
        log.slice(),
    );
}

test "useReducer and useReducerFn drive backend diffs" {
    const Capture = ReducerCapture(i32, CountAction);
    const Props = struct {
        capture: *Capture,
        renders: *u32,
    };
    const Render = struct {
        fn call(props: *const Props, cx: *render_cx.RenderCx) element.Error!Element {
            props.renders.* += 1;
            const reduced = try cx.useReducer(i32, 0);
            const reduced_fn = try cx.useReducerFn(i32, CountAction, countReducer, 10);
            props.capture.update = reduced.update;
            props.capture.dispatch = reduced_fn.dispatch;

            var builder = element.leaf(cx.getAllocator());
            defer builder.deinit();
            _ = try (try builder.prop("reduced", reduced.value.*)).prop("reduced_fn", reduced_fn.value.*);
            return builder.build();
        }
    };

    var capture: Capture = .{};
    var renders: u32 = 0;
    var rerenders: TestRerenderCounter = .{};
    var backend_state = RecordingBackend.init(std.testing.allocator);
    defer backend_state.deinit();
    var reconciler = Reconciler.init(
        std.testing.allocator,
        Backend.from(&backend_state),
        RequestRerender.init(@ptrCast(&rerenders), TestRerenderCounter.request),
    );
    defer reconciler.deinit();

    var first = try element.memo(
        std.testing.allocator,
        "reducers",
        Props{ .capture = &capture, .renders = &renders },
        Render.call,
    );
    defer first.deinit(std.testing.allocator);

    var tree = try reconciler.mount(&first);
    defer reconciler.unmountTree(&tree) catch unreachable;
    const leaf_id = backend_state.rootChildren()[0];

    backend_state.clearCalls();
    capture.update.?.call(incrementReducer);
    capture.update.?.call(incrementReducer);
    capture.dispatch.?.call(.{ .add = 5 });
    capture.dispatch.?.call(.reset);
    try std.testing.expectEqual(@as(u32, 4), rerenders.count);

    var second = try element.memo(
        std.testing.allocator,
        "reducers",
        Props{ .capture = &capture, .renders = &renders },
        Render.call,
    );
    defer second.deinit(std.testing.allocator);

    try reconciler.update(&tree, &second);
    try std.testing.expectEqual(@as(u32, 2), renders);
    try std.testing.expectEqual(@as(i32, 2), backend_state.propertyValue(i32, leaf_id, "reduced").?);
    try std.testing.expectEqual(@as(i32, 0), backend_state.propertyValue(i32, leaf_id, "reduced_fn").?);
}

test "hook-order mismatch during component rerender propagates" {
    const Props = struct {
        include_ref: bool,
    };
    const Render = struct {
        fn call(props: *const Props, cx: *render_cx.RenderCx) element.Error!Element {
            _ = try cx.useState(i32, 1);
            if (props.include_ref) {
                _ = try cx.useRef(u32, 0);
            }
            return buildLeaf(cx.getAllocator(), null, "value", @as(i32, 1));
        }
    };

    var backend_state = RecordingBackend.init(std.testing.allocator);
    defer backend_state.deinit();
    var reconciler = Reconciler.init(
        std.testing.allocator,
        Backend.from(&backend_state),
        RequestRerender.none(),
    );
    defer reconciler.deinit();

    var first = try element.component(
        std.testing.allocator,
        "hook-order",
        Props{ .include_ref = true },
        Render.call,
    );
    defer first.deinit(std.testing.allocator);

    var tree = try reconciler.mount(&first);
    defer reconciler.unmountTree(&tree) catch unreachable;
    backend_state.clearCalls();

    var second = try element.component(
        std.testing.allocator,
        "hook-order",
        Props{ .include_ref = false },
        Render.call,
    );
    defer second.deinit(std.testing.allocator);

    try std.testing.expectError(error.HookOrderMismatch, reconciler.update(&tree, &second));
    try std.testing.expectEqual(@as(usize, 0), backend_state.calls.items.len);
}

test "event handlers swap on rerender without leaking active registrations" {
    const Capture = StateCapture(bool);
    const EventCounts = struct {
        first: u32 = 0,
        second: u32 = 0,
    };
    const EventCallbacks = struct {
        fn first(raw: ?*anyopaque) void {
            const counts: *EventCounts = @ptrCast(@alignCast(raw.?));
            counts.first += 1;
        }

        fn second(raw: ?*anyopaque) void {
            const counts: *EventCounts = @ptrCast(@alignCast(raw.?));
            counts.second += 1;
        }
    };
    const Props = struct {
        capture: *Capture,
        counts: *EventCounts,
    };
    const Render = struct {
        fn call(props: *const Props, cx: *render_cx.RenderCx) element.Error!Element {
            const toggled = try cx.useState(bool, false);
            props.capture.setter = toggled.set;

            var builder = element.leaf(cx.getAllocator());
            defer builder.deinit();

            const callback = if (toggled.value.*)
                element.EventCallback.init(@ptrCast(props.counts), EventCallbacks.second)
            else
                element.EventCallback.init(@ptrCast(props.counts), EventCallbacks.first);
            _ = try builder.on("click", callback);
            return builder.build();
        }
    };

    var capture: Capture = .{};
    var counts: EventCounts = .{};
    var rerenders: TestRerenderCounter = .{};
    var backend_state = RecordingBackend.init(std.testing.allocator);
    defer backend_state.deinit();
    var reconciler = Reconciler.init(
        std.testing.allocator,
        Backend.from(&backend_state),
        RequestRerender.init(@ptrCast(&rerenders), TestRerenderCounter.request),
    );
    defer reconciler.deinit();

    var first = try element.memo(
        std.testing.allocator,
        "swap-handler",
        Props{ .capture = &capture, .counts = &counts },
        Render.call,
    );
    defer first.deinit(std.testing.allocator);

    var tree = try reconciler.mount(&first);
    var mounted = true;
    defer if (mounted) reconciler.unmountTree(&tree) catch unreachable;

    const leaf_id = backend_state.rootChildren()[0];
    try std.testing.expectEqual(@as(usize, 1), backend_state.activeEventCount());

    try backend_state.fireEvent(leaf_id, "click");
    try std.testing.expectEqual(@as(u32, 1), counts.first);
    try std.testing.expectEqual(@as(u32, 0), counts.second);

    backend_state.clearCalls();
    capture.setter.?.call(true);
    try std.testing.expectEqual(@as(u32, 1), rerenders.count);

    var second = try element.memo(
        std.testing.allocator,
        "swap-handler",
        Props{ .capture = &capture, .counts = &counts },
        Render.call,
    );
    defer second.deinit(std.testing.allocator);

    try reconciler.update(&tree, &second);
    try std.testing.expectEqual(@as(usize, 1), backend_state.callCountOf(.attach_event));
    try std.testing.expectEqual(@as(usize, 0), backend_state.callCountOf(.detach_event));
    try std.testing.expectEqual(@as(usize, 1), backend_state.activeEventCount());

    try backend_state.fireEvent(leaf_id, "click");
    try std.testing.expectEqual(@as(u32, 1), counts.first);
    try std.testing.expectEqual(@as(u32, 1), counts.second);

    try reconciler.unmountTree(&tree);
    mounted = false;
    try std.testing.expectEqual(@as(usize, 0), backend_state.activeEventCount());
}
