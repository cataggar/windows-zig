const std = @import("std");
const box = @import("box.zig");
const context = @import("context.zig");
const render_cx = @import("render_cx.zig");

pub const Allocator = std.mem.Allocator;

/// Tree-construction errors: allocation failures, hook/context failures while
/// evaluating consumers, and a small amount of structural validation.
pub const Error = Allocator.Error || render_cx.Error || error{
    LeafCannotHaveChildren,
    WindowCannotHaveMultipleChildren,
};

pub const WidgetKind = enum {
    leaf,
    container,
    application,
    window,
    button,
    stack_panel,
    text_block,
    text_box,
};

pub fn widgetKindAllowsChildren(kind: WidgetKind) bool {
    return switch (kind) {
        .container, .application, .window, .stack_panel => true,
        .leaf, .button, .text_block, .text_box => false,
    };
}

/// Zero-argument event callback. Concrete WinUI event payloads arrive later;
/// for now the tree only needs stable callback identity plus an invocation
/// hook that tests can exercise.
pub const EventCallback = struct {
    userdata: ?*anyopaque = null,
    invoke_fn: *const fn (?*anyopaque) void = noop,

    pub fn init(userdata: ?*anyopaque, invoke_fn: *const fn (?*anyopaque) void) EventCallback {
        return .{
            .userdata = userdata,
            .invoke_fn = invoke_fn,
        };
    }

    pub fn fromFunction(comptime invoke_fn: *const fn () void) EventCallback {
        return .{
            .invoke_fn = &struct {
                fn call(_: ?*anyopaque) void {
                    invoke_fn();
                }
            }.call,
        };
    }

    pub fn invoke(self: *const EventCallback) void {
        self.invoke_fn(self.userdata);
    }

    pub fn eql(self: *const EventCallback, other: *const EventCallback) bool {
        return self.userdata == other.userdata and functionPtrEql(self.invoke_fn, other.invoke_fn);
    }

    fn noop(_: ?*anyopaque) void {}
};

pub const EventHandler = struct {
    name: []const u8,
    callback: EventCallback,

    pub fn init(allocator: Allocator, name: []const u8, callback: EventCallback) Allocator.Error!EventHandler {
        return .{
            .name = try dupString(allocator, name),
            .callback = callback,
        };
    }

    pub fn deinit(self: *EventHandler, allocator: Allocator) void {
        freeString(allocator, self.name);
        self.* = undefined;
    }

    pub fn clone(self: *const EventHandler, allocator: Allocator) Allocator.Error!EventHandler {
        return .{
            .name = try dupString(allocator, self.name),
            .callback = self.callback,
        };
    }

    pub fn invoke(self: *const EventHandler) void {
        self.callback.invoke();
    }

    pub fn eql(self: *const EventHandler, other: *const EventHandler) bool {
        return std.mem.eql(u8, self.name, other.name) and self.callback.eql(&other.callback);
    }
};

/// Generic pre-reconciler property slot. Code-generated widget setters can
/// translate strongly-typed builder calls into these name/value entries until
/// the concrete widget catalog lands.
pub const Property = struct {
    name: []const u8,
    value: box.ValueBox,

    pub fn init(allocator: Allocator, name: []const u8, value: anytype) Allocator.Error!Property {
        const owned_name = try dupString(allocator, name);
        errdefer freeString(allocator, owned_name);

        const value_box = switch (@typeInfo(@TypeOf(value))) {
            .pointer => |info| blk: {
                if (info.size == .slice and info.child == u8) {
                    break :blk try box.ValueBox.init(allocator, @as([]const u8, value));
                }
                if (info.size == .one and @typeInfo(info.child) == .array) {
                    const array_info = @typeInfo(info.child).array;
                    if (array_info.child == u8) {
                        if (array_info.sentinel() != null) {
                            break :blk try box.ValueBox.init(allocator, std.mem.span(value));
                        }
                        break :blk try box.ValueBox.init(allocator, value[0..]);
                    }
                }
                break :blk try box.ValueBox.init(allocator, value);
            },
            .array => |info| blk: {
                if (info.child == u8) {
                    break :blk try box.ValueBox.init(allocator, value[0..]);
                }
                break :blk try box.ValueBox.init(allocator, value);
            },
            else => try box.ValueBox.init(allocator, value),
        };

        return .{
            .name = owned_name,
            .value = value_box,
        };
    }

    pub fn deinit(self: *Property, allocator: Allocator) void {
        freeString(allocator, self.name);
        self.value.deinit(allocator);
        self.* = undefined;
    }

    pub fn clone(self: *const Property, allocator: Allocator) Allocator.Error!Property {
        const owned_name = try dupString(allocator, self.name);
        errdefer freeString(allocator, owned_name);

        return .{
            .name = owned_name,
            .value = try self.value.clone(allocator),
        };
    }

    pub fn get(self: *const Property, comptime T: type) ?T {
        if (!self.value.is(T)) return null;
        return self.value.getConst(T).*;
    }

    pub fn eql(self: *const Property, other: *const Property) bool {
        return std.mem.eql(u8, self.name, other.name) and self.value.eqlBox(&other.value);
    }
};

/// Provider payload stored on `Element.provider`. The active render tree clones
/// this boxed value into the ambient `ContextStack` while descending into the
/// provider's child subtree.
pub const ContextProvision = struct {
    context_id: context.ContextId,
    value: box.ValueBox,

    pub fn init(allocator: Allocator, value_context: anytype, value: anytype) Error!ContextProvision {
        const T = @TypeOf(value_context.*.default);
        const coerced: T = value;
        return .{
            .context_id = value_context.id,
            .value = try box.ValueBox.init(allocator, coerced),
        };
    }

    pub fn deinit(self: *ContextProvision, allocator: Allocator) void {
        self.value.deinit(allocator);
        self.* = undefined;
    }

    pub fn clone(self: *const ContextProvision, allocator: Allocator) Allocator.Error!ContextProvision {
        return .{
            .context_id = self.context_id,
            .value = try self.value.clone(allocator),
        };
    }

    pub fn get(self: *const ContextProvision, comptime T: type) ?T {
        if (!self.value.is(T)) return null;
        return self.value.getConst(T).*;
    }

    pub fn eql(self: *const ContextProvision, other: *const ContextProvision) bool {
        return self.context_id.raw == other.context_id.raw and self.value.eqlBox(&other.value);
    }
};

pub const WidgetElement = struct {
    key: ?[]const u8 = null,
    kind: WidgetKind,
    props: []Property = &.{},
    events: []EventHandler = &.{},
    children: []Element = &.{},

    pub fn deinit(self: *WidgetElement, allocator: Allocator) void {
        if (self.key) |key| freeString(allocator, key);

        for (self.props) |*prop| {
            prop.deinit(allocator);
        }
        if (self.props.len > 0) allocator.free(self.props);

        for (self.events) |*event_handler| {
            event_handler.deinit(allocator);
        }
        if (self.events.len > 0) allocator.free(self.events);

        for (self.children) |*child| {
            child.deinit(allocator);
        }
        if (self.children.len > 0) allocator.free(self.children);

        self.* = undefined;
    }

    pub fn clone(self: *const WidgetElement, allocator: Allocator) Allocator.Error!WidgetElement {
        const key = try cloneOptionalString(allocator, self.key);
        errdefer if (key) |owned_key| freeString(allocator, owned_key);

        const props = try cloneProperties(allocator, self.props);
        errdefer {
            for (props) |*prop_entry| {
                prop_entry.deinit(allocator);
            }
            if (props.len > 0) allocator.free(props);
        }

        const events = try cloneEventHandlers(allocator, self.events);
        errdefer {
            for (events) |*event_handler| {
                event_handler.deinit(allocator);
            }
            if (events.len > 0) allocator.free(events);
        }

        const children = try cloneElements(allocator, self.children);
        errdefer {
            for (children) |*child_element| {
                child_element.deinit(allocator);
            }
            if (children.len > 0) allocator.free(children);
        }

        return .{
            .key = key,
            .kind = self.kind,
            .props = props,
            .events = events,
            .children = children,
        };
    }

    pub fn property(self: *const WidgetElement, name: []const u8) ?*const Property {
        for (self.props) |*prop| {
            if (std.mem.eql(u8, prop.name, name)) return prop;
        }
        return null;
    }

    pub fn propertyValue(self: *const WidgetElement, comptime T: type, name: []const u8) ?T {
        const prop = self.property(name) orelse return null;
        return prop.get(T);
    }

    pub fn event(self: *const WidgetElement, name: []const u8) ?*const EventHandler {
        for (self.events) |*event_handler| {
            if (std.mem.eql(u8, event_handler.name, name)) return event_handler;
        }
        return null;
    }
};

pub const ComponentElement = struct {
    key: ?[]const u8 = null,
    memoized: bool = false,
    name: []const u8,
    props: box.ValueBox,
    render_fn: *const fn (*const anyopaque, *render_cx.RenderCx) Error!Element,

    pub fn init(
        allocator: Allocator,
        name: []const u8,
        props: anytype,
        comptime render_fn: *const fn (*const @TypeOf(props), *render_cx.RenderCx) Error!Element,
    ) Error!ComponentElement {
        const Props = @TypeOf(props);
        const owned_name = try dupString(allocator, name);
        errdefer freeString(allocator, owned_name);
        return .{
            .name = owned_name,
            .props = try box.ValueBox.init(allocator, props),
            .render_fn = &struct {
                fn call(raw_props: *const anyopaque, cx: *render_cx.RenderCx) Error!Element {
                    const typed_props: *const Props = @ptrCast(@alignCast(raw_props));
                    return render_fn(typed_props, cx);
                }
            }.call,
        };
    }

    pub fn deinit(self: *ComponentElement, allocator: Allocator) void {
        if (self.key) |key| freeString(allocator, key);
        freeString(allocator, self.name);
        self.props.deinit(allocator);
        self.* = undefined;
    }

    pub fn clone(self: *const ComponentElement, allocator: Allocator) Allocator.Error!ComponentElement {
        const key = try cloneOptionalString(allocator, self.key);
        errdefer if (key) |owned_key| freeString(allocator, owned_key);

        const name = try dupString(allocator, self.name);
        errdefer freeString(allocator, name);

        const props = try self.props.clone(allocator);
        errdefer {
            var owned_props = props;
            owned_props.deinit(allocator);
        }

        return .{
            .key = key,
            .memoized = self.memoized,
            .name = name,
            .props = props,
            .render_fn = self.render_fn,
        };
    }

    pub fn render(self: *const ComponentElement, cx: *render_cx.RenderCx) Error!Element {
        return self.render_fn(self.props.rawConstPtr(), cx);
    }

    pub fn sameDefinition(self: *const ComponentElement, other: *const ComponentElement) bool {
        return functionPtrEql(self.render_fn, other.render_fn);
    }

    pub fn propsEqual(self: *const ComponentElement, other: *const ComponentElement) bool {
        return self.props.eqlBox(&other.props);
    }

    pub fn shouldUpdate(self: *const ComponentElement, other: *const ComponentElement) bool {
        if (!self.sameDefinition(other)) return true;
        if (other.memoized) {
            return !self.propsEqual(other);
        }
        return true;
    }
};

pub const ProviderElement = struct {
    key: ?[]const u8 = null,
    provisions: []ContextProvision = &.{},
    child: *Element,

    pub fn deinit(self: *ProviderElement, allocator: Allocator) void {
        if (self.key) |key| freeString(allocator, key);

        for (self.provisions) |*provision| {
            provision.deinit(allocator);
        }
        if (self.provisions.len > 0) allocator.free(self.provisions);

        self.child.deinit(allocator);
        allocator.destroy(self.child);
        self.* = undefined;
    }

    pub fn clone(self: *const ProviderElement, allocator: Allocator) Allocator.Error!ProviderElement {
        const copied_child = try allocator.create(Element);
        copied_child.* = .empty;
        errdefer {
            copied_child.deinit(allocator);
            allocator.destroy(copied_child);
        }
        copied_child.* = try self.child.clone(allocator);

        const key = try cloneOptionalString(allocator, self.key);
        errdefer if (key) |owned_key| freeString(allocator, owned_key);

        return .{
            .key = key,
            .provisions = try cloneProvisions(allocator, self.provisions),
            .child = copied_child,
        };
    }

    pub fn appendProvision(self: *ProviderElement, allocator: Allocator, provision: ContextProvision) Allocator.Error!void {
        const old_provisions = self.provisions;
        var new_provisions = try allocator.alloc(ContextProvision, old_provisions.len + 1);
        if (old_provisions.len > 0) {
            @memcpy(new_provisions[0..old_provisions.len], old_provisions);
            allocator.free(old_provisions);
        }
        new_provisions[old_provisions.len] = provision;
        self.provisions = new_provisions;
    }

    pub fn pushToContextStack(self: *const ProviderElement, stack: *context.ContextStack) Error!usize {
        const mark = stack.mark();
        errdefer stack.popToMark(mark);

        for (self.provisions) |*provision| {
            try stack.pushBox(provision.context_id, &provision.value);
        }
        return mark;
    }
};

pub const GroupElement = struct {
    key: ?[]const u8 = null,
    children: []Element = &.{},

    pub fn deinit(self: *GroupElement, allocator: Allocator) void {
        if (self.key) |key| freeString(allocator, key);
        for (self.children) |*child| {
            child.deinit(allocator);
        }
        if (self.children.len > 0) allocator.free(self.children);
        self.* = undefined;
    }

    pub fn clone(self: *const GroupElement, allocator: Allocator) Allocator.Error!GroupElement {
        const key = try cloneOptionalString(allocator, self.key);
        errdefer if (key) |owned_key| freeString(allocator, owned_key);

        return .{
            .key = key,
            .children = try cloneElements(allocator, self.children),
        };
    }
};

pub const Visitor = struct {
    userdata: ?*anyopaque = null,
    visit_fn: *const fn (?*anyopaque, *render_cx.RenderCx, *const Element) Error!void = noop,

    pub fn init(
        userdata: ?*anyopaque,
        visit_fn: *const fn (?*anyopaque, *render_cx.RenderCx, *const Element) Error!void,
    ) Visitor {
        return .{
            .userdata = userdata,
            .visit_fn = visit_fn,
        };
    }

    pub fn visit(self: *const Visitor, cx: *render_cx.RenderCx, element: *const Element) Error!void {
        try self.visit_fn(self.userdata, cx, element);
    }

    fn noop(_: ?*anyopaque, _: *render_cx.RenderCx, _: *const Element) Error!void {}
};

/// Pure-data render tree returned by hook-driven components and later diffed by
/// the reconciler. Widget children are stored inline, provider children are
/// boxed so the tagged union stays a fixed size, and components carry a typed
/// render callback plus boxed props for #14's future component-instance table.
pub const Element = union(enum) {
    widget: WidgetElement,
    component: ComponentElement,
    provider: ProviderElement,
    group: GroupElement,
    empty,

    pub fn deinit(self: *Element, allocator: Allocator) void {
        switch (self.*) {
            .widget => |*widget| widget.deinit(allocator),
            .component => |*component_element| component_element.deinit(allocator),
            .provider => |*provider_element| provider_element.deinit(allocator),
            .group => |*group_element| group_element.deinit(allocator),
            .empty => {},
        }
        self.* = undefined;
    }

    pub fn clone(self: *const Element, allocator: Allocator) Allocator.Error!Element {
        return switch (self.*) {
            .widget => |widget| .{ .widget = try widget.clone(allocator) },
            .component => |component_element| .{ .component = try component_element.clone(allocator) },
            .provider => |provider_element| .{ .provider = try provider_element.clone(allocator) },
            .group => |group_element| .{ .group = try group_element.clone(allocator) },
            .empty => .empty,
        };
    }

    pub fn key(self: *const Element) ?[]const u8 {
        return switch (self.*) {
            .widget => |widget| widget.key,
            .component => |component_element| component_element.key,
            .provider => |provider_element| provider_element.key,
            .group => |group_element| group_element.key,
            .empty => null,
        };
    }

    pub fn kindName(self: *const Element) []const u8 {
        return switch (self.*) {
            .widget => |widget| @tagName(widget.kind),
            .component => "component",
            .provider => "provider",
            .group => "group",
            .empty => "empty",
        };
    }

    pub fn kindMatches(self: *const Element, other: *const Element) bool {
        return switch (self.*) {
            .widget => |widget| switch (other.*) {
                .widget => |other_widget| widget.kind == other_widget.kind,
                else => false,
            },
            .component => |component_element| switch (other.*) {
                .component => |other_component| component_element.sameDefinition(&other_component),
                else => false,
            },
            .provider => other.* == .provider,
            .group => other.* == .group,
            .empty => other.* == .empty,
        };
    }

    pub fn canUpdate(self: *const Element, other: *const Element) bool {
        return optionalStringEql(self.key(), other.key()) and self.kindMatches(other);
    }

    pub fn setKey(self: *Element, allocator: Allocator, new_key: []const u8) Allocator.Error!void {
        const owned_key = try dupString(allocator, new_key);
        switch (self.*) {
            .widget => |*widget| {
                if (widget.key) |existing| freeString(allocator, existing);
                widget.key = owned_key;
            },
            .component => |*component_element| {
                if (component_element.key) |existing| freeString(allocator, existing);
                component_element.key = owned_key;
            },
            .provider => |*provider_element| {
                if (provider_element.key) |existing| freeString(allocator, existing);
                provider_element.key = owned_key;
            },
            .group => |*group_element| {
                if (group_element.key) |existing| freeString(allocator, existing);
                group_element.key = owned_key;
            },
            .empty => freeString(allocator, owned_key),
        }
    }

    /// Tree walk that wires provider nodes into the currently attached
    /// `RenderCx` context stack. The reconciler can reuse this push/pop policy
    /// when it later renders child components with their own `RenderCx`
    /// instances.
    pub fn walk(self: *const Element, cx: *render_cx.RenderCx, visitor: Visitor) Error!void {
        try visitor.visit(cx, self);

        switch (self.*) {
            .widget => |widget| {
                for (widget.children) |*child| {
                    try child.walk(cx, visitor);
                }
            },
            .component => {},
            .provider => |provider_element| {
                if (cx.contextStack()) |stack| {
                    const mark = try provider_element.pushToContextStack(stack);
                    defer stack.popToMark(mark);
                    try provider_element.child.walk(cx, visitor);
                } else {
                    try provider_element.child.walk(cx, visitor);
                }
            },
            .group => |group_element| {
                for (group_element.children) |*child| {
                    try child.walk(cx, visitor);
                }
            },
            .empty => {},
        }
    }
};

pub fn component(
    allocator: Allocator,
    name: []const u8,
    props: anytype,
    comptime render_fn: *const fn (*const @TypeOf(props), *render_cx.RenderCx) Error!Element,
) Error!Element {
    return .{
        .component = try ComponentElement.init(allocator, name, props, render_fn),
    };
}

pub fn memo(
    allocator: Allocator,
    name: []const u8,
    props: anytype,
    comptime render_fn: *const fn (*const @TypeOf(props), *render_cx.RenderCx) Error!Element,
) Error!Element {
    var result = try component(allocator, name, props, render_fn);
    result.component.memoized = true;
    return result;
}

pub fn group(allocator: Allocator, children: anytype) Error!Element {
    return .{
        .group = .{
            .children = try collectElements(allocator, children),
        },
    };
}

/// Wrap `child` in a provider. If `child` is already a provider, the new
/// context is folded into the same provider node, matching the Rust port:
/// later repeated `.provide()` calls on the same element shadow earlier ones.
pub fn provide(allocator: Allocator, child: anytype, value_context: anytype, value: anytype) Error!Element {
    var converted_child = try intoElement(allocator, child);
    errdefer converted_child.deinit(allocator);

    var provision = try ContextProvision.init(allocator, value_context, value);
    errdefer provision.deinit(allocator);

    switch (converted_child) {
        .provider => |*provider| {
            try provider.appendProvision(allocator, provision);
            return converted_child;
        },
        else => {
            const owned_child = try allocator.create(Element);
            errdefer {
                owned_child.deinit(allocator);
                allocator.destroy(owned_child);
            }
            owned_child.* = converted_child;

            const provisions = try allocator.alloc(ContextProvision, 1);
            provisions[0] = provision;

            return .{
                .provider = .{
                    .provisions = provisions,
                    .child = owned_child,
                },
            };
        },
    }
}

/// Generic Zig equivalent of Rust's `.into()`: pass a pointer to a builder or
/// `Element` to transfer ownership and reset the source. Use `clone()` first if
/// you need to reuse a named value in multiple places.
pub fn intoElement(allocator: Allocator, value: anytype) Error!Element {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .pointer => |info| {
            if (info.size == .one and info.child == Element) {
                const moved = value.*;
                value.* = .empty;
                return moved;
            }

            if (info.size == .one and @hasDecl(info.child, "build") and @hasDecl(info.child, "deinit")) {
                return value.build();
            }
        },
        else => {},
    }

    _ = allocator;
    @compileError(
        "type " ++ @typeName(T) ++
            " cannot be converted into win-reactor Element by value; pass a pointer to transfer ownership or call clone() explicitly",
    );
}

pub fn collectElements(allocator: Allocator, values: anytype) Error![]Element {
    var items: std.ArrayListUnmanaged(Element) = .empty;
    errdefer {
        for (items.items) |*item| {
            item.deinit(allocator);
        }
        items.deinit(allocator);
    }

    try appendElementInputs(&items, allocator, values);
    return try items.toOwnedSlice(allocator);
}

pub fn WidgetBuilder(comptime kind: WidgetKind) type {
    return struct {
        allocator: Allocator,
        key: ?[]const u8 = null,
        props: std.ArrayListUnmanaged(Property) = .empty,
        events: std.ArrayListUnmanaged(EventHandler) = .empty,
        children: std.ArrayListUnmanaged(Element) = .empty,

        pub fn init(allocator: Allocator) @This() {
            return .{ .allocator = allocator };
        }

        pub fn deinit(self: *@This()) void {
            if (self.key) |key| freeString(self.allocator, key);

            for (self.props.items) |*prop_entry| {
                prop_entry.deinit(self.allocator);
            }
            self.props.deinit(self.allocator);

            for (self.events.items) |*event_handler| {
                event_handler.deinit(self.allocator);
            }
            self.events.deinit(self.allocator);

            for (self.children.items) |*child_element| {
                child_element.deinit(self.allocator);
            }
            self.children.deinit(self.allocator);

            self.* = undefined;
        }

        pub fn clone(self: *const @This()) Allocator.Error!@This() {
            const key = try cloneOptionalString(self.allocator, self.key);
            errdefer if (key) |owned_key| freeString(self.allocator, owned_key);

            var props = try clonePropertyList(self.allocator, self.props.items);
            errdefer {
                for (props.items) |*prop_entry| {
                    prop_entry.deinit(self.allocator);
                }
                props.deinit(self.allocator);
            }

            var events = try cloneEventList(self.allocator, self.events.items);
            errdefer {
                for (events.items) |*event_handler| {
                    event_handler.deinit(self.allocator);
                }
                events.deinit(self.allocator);
            }

            var children = try cloneElementList(self.allocator, self.children.items);
            errdefer {
                for (children.items) |*child_element| {
                    child_element.deinit(self.allocator);
                }
                children.deinit(self.allocator);
            }

            return .{
                .allocator = self.allocator,
                .key = key,
                .props = props,
                .events = events,
                .children = children,
            };
        }

        pub fn withKey(self: *@This(), key: []const u8) Allocator.Error!*@This() {
            const owned_key = try dupString(self.allocator, key);
            if (self.key) |existing| freeString(self.allocator, existing);
            self.key = owned_key;
            return self;
        }

        pub fn prop(self: *@This(), name: []const u8, value: anytype) Error!*@This() {
            var property = try Property.init(self.allocator, name, value);
            errdefer property.deinit(self.allocator);
            try self.props.append(self.allocator, property);
            return self;
        }

        pub fn on(self: *@This(), name: []const u8, callback: EventCallback) Error!*@This() {
            var event_handler = try EventHandler.init(self.allocator, name, callback);
            errdefer event_handler.deinit(self.allocator);
            try self.events.append(self.allocator, event_handler);
            return self;
        }

        pub fn child(self: *@This(), value: anytype) Error!*@This() {
            comptime {
                switch (kind) {
                    .leaf, .button, .text_block, .text_box => {
                        @compileError("this widget builder cannot accept children");
                    },
                    else => {},
                }
            }

            try self.children.append(self.allocator, try intoElement(self.allocator, value));
            return self;
        }

        pub fn childrenFrom(self: *@This(), values: anytype) Error!*@This() {
            comptime {
                switch (kind) {
                    .leaf, .button, .text_block, .text_box => {
                        @compileError("this widget builder cannot accept children");
                    },
                    else => {},
                }
            }

            const owned_children = try collectElements(self.allocator, values);
            errdefer {
                for (owned_children) |*child_element| {
                    child_element.deinit(self.allocator);
                }
                if (owned_children.len > 0) self.allocator.free(owned_children);
            }

            try self.children.appendSlice(self.allocator, owned_children);
            if (owned_children.len > 0) self.allocator.free(owned_children);
            return self;
        }

        pub fn build(self: *@This()) Error!Element {
            if (!widgetKindAllowsChildren(kind) and self.children.items.len != 0) {
                return error.LeafCannotHaveChildren;
            }
            if (kind == .window and self.children.items.len > 1) {
                return error.WindowCannotHaveMultipleChildren;
            }

            const allocator = self.allocator;
            const key = self.key;

            const props = try self.props.toOwnedSlice(allocator);
            errdefer {
                for (props) |*prop_entry| {
                    prop_entry.deinit(allocator);
                }
                if (props.len > 0) allocator.free(props);
            }

            const events = try self.events.toOwnedSlice(allocator);
            errdefer {
                for (events) |*event_handler| {
                    event_handler.deinit(allocator);
                }
                if (events.len > 0) allocator.free(events);
            }

            const children = try self.children.toOwnedSlice(allocator);
            errdefer {
                for (children) |*child_element| {
                    child_element.deinit(allocator);
                }
                if (children.len > 0) allocator.free(children);
            }

            self.* = .{ .allocator = allocator };

            return .{
                .widget = .{
                    .key = key,
                    .kind = kind,
                    .props = props,
                    .events = events,
                    .children = children,
                },
            };
        }
    };
}

pub const LeafBuilder = WidgetBuilder(.leaf);
pub const ContainerBuilder = WidgetBuilder(.container);
pub const ApplicationBuilder = WidgetBuilder(.application);
pub const WindowBuilder = WidgetBuilder(.window);
pub const ButtonBuilder = WidgetBuilder(.button);
pub const StackPanelBuilder = WidgetBuilder(.stack_panel);
pub const TextBlockBuilder = WidgetBuilder(.text_block);
pub const TextBoxBuilder = WidgetBuilder(.text_box);

pub fn leaf(allocator: Allocator) LeafBuilder {
    return LeafBuilder.init(allocator);
}

pub fn container(allocator: Allocator) ContainerBuilder {
    return ContainerBuilder.init(allocator);
}

pub fn application(allocator: Allocator) ApplicationBuilder {
    return ApplicationBuilder.init(allocator);
}

pub fn window(allocator: Allocator) WindowBuilder {
    return WindowBuilder.init(allocator);
}

pub fn button(allocator: Allocator) ButtonBuilder {
    return ButtonBuilder.init(allocator);
}

pub fn stack_panel(allocator: Allocator) StackPanelBuilder {
    return StackPanelBuilder.init(allocator);
}

pub fn text_block(allocator: Allocator) TextBlockBuilder {
    return TextBlockBuilder.init(allocator);
}

pub fn text_box(allocator: Allocator) TextBoxBuilder {
    return TextBoxBuilder.init(allocator);
}

fn appendElementInputs(items: *std.ArrayListUnmanaged(Element), allocator: Allocator, values: anytype) Error!void {
    const T = @TypeOf(values);
    switch (@typeInfo(T)) {
        .@"struct" => |info| {
            if (info.is_tuple) {
                inline for (info.fields) |field| {
                    try appendElementInputs(items, allocator, @field(values, field.name));
                }
                return;
            }
        },
        .array => {
            for (values) |value| {
                try items.append(allocator, try intoElement(allocator, value));
            }
            return;
        },
        .pointer => |info| {
            if (info.size == .slice) {
                for (values) |value| {
                    try items.append(allocator, try intoElement(allocator, value));
                }
                return;
            }
        },
        else => {},
    }

    try items.append(allocator, try intoElement(allocator, values));
}

fn dupString(allocator: Allocator, value: []const u8) Allocator.Error![]const u8 {
    return try allocator.dupe(u8, value);
}

fn freeString(allocator: Allocator, value: []const u8) void {
    if (value.len > 0) allocator.free(value);
}

fn cloneOptionalString(allocator: Allocator, value: ?[]const u8) Allocator.Error!?[]const u8 {
    return if (value) |owned| try dupString(allocator, owned) else null;
}

fn cloneProperties(allocator: Allocator, source: []const Property) Allocator.Error![]Property {
    var list = try clonePropertyList(allocator, source);
    errdefer {
        for (list.items) |*prop_entry| {
            prop_entry.deinit(allocator);
        }
        list.deinit(allocator);
    }
    return try list.toOwnedSlice(allocator);
}

fn cloneEventHandlers(allocator: Allocator, source: []const EventHandler) Allocator.Error![]EventHandler {
    var list = try cloneEventList(allocator, source);
    errdefer {
        for (list.items) |*event_handler| {
            event_handler.deinit(allocator);
        }
        list.deinit(allocator);
    }
    return try list.toOwnedSlice(allocator);
}

fn cloneElements(allocator: Allocator, source: []const Element) Allocator.Error![]Element {
    var list = try cloneElementList(allocator, source);
    errdefer {
        for (list.items) |*child_element| {
            child_element.deinit(allocator);
        }
        list.deinit(allocator);
    }
    return try list.toOwnedSlice(allocator);
}

fn cloneProvisions(allocator: Allocator, source: []const ContextProvision) Allocator.Error![]ContextProvision {
    var list = try cloneProvisionList(allocator, source);
    errdefer {
        for (list.items) |*provision| {
            provision.deinit(allocator);
        }
        list.deinit(allocator);
    }
    return try list.toOwnedSlice(allocator);
}

fn clonePropertyList(
    allocator: Allocator,
    source: []const Property,
) Allocator.Error!std.ArrayListUnmanaged(Property) {
    var list: std.ArrayListUnmanaged(Property) = .empty;
    errdefer {
        for (list.items) |*prop_entry| {
            prop_entry.deinit(allocator);
        }
        list.deinit(allocator);
    }

    for (source) |*prop_entry| {
        try list.append(allocator, try prop_entry.clone(allocator));
    }
    return list;
}

fn cloneEventList(
    allocator: Allocator,
    source: []const EventHandler,
) Allocator.Error!std.ArrayListUnmanaged(EventHandler) {
    var list: std.ArrayListUnmanaged(EventHandler) = .empty;
    errdefer {
        for (list.items) |*event_handler| {
            event_handler.deinit(allocator);
        }
        list.deinit(allocator);
    }

    for (source) |*event_handler| {
        try list.append(allocator, try event_handler.clone(allocator));
    }
    return list;
}

fn cloneElementList(
    allocator: Allocator,
    source: []const Element,
) Allocator.Error!std.ArrayListUnmanaged(Element) {
    var list: std.ArrayListUnmanaged(Element) = .empty;
    errdefer {
        for (list.items) |*child_element| {
            child_element.deinit(allocator);
        }
        list.deinit(allocator);
    }

    for (source) |*child_element| {
        try list.append(allocator, try child_element.clone(allocator));
    }
    return list;
}

fn cloneProvisionList(
    allocator: Allocator,
    source: []const ContextProvision,
) Allocator.Error!std.ArrayListUnmanaged(ContextProvision) {
    var list: std.ArrayListUnmanaged(ContextProvision) = .empty;
    errdefer {
        for (list.items) |*provision| {
            provision.deinit(allocator);
        }
        list.deinit(allocator);
    }

    for (source) |*provision| {
        try list.append(allocator, try provision.clone(allocator));
    }
    return list;
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

fn functionPtrEql(lhs: anytype, rhs: @TypeOf(lhs)) bool {
    return @intFromPtr(lhs) == @intFromPtr(rhs);
}

test "widget builders convert into element trees with props, children, and handlers" {
    const Counter = struct {
        fn increment(raw: ?*anyopaque) void {
            const value: *u32 = @ptrCast(@alignCast(raw.?));
            value.* += 1;
        }
    };

    var clicks: u32 = 0;
    var title_builder = leaf(std.testing.allocator);
    _ = try (try title_builder.withKey("title")).prop("text", @as([]const u8, "hello"));
    defer title_builder.deinit();

    var button_builder = leaf(std.testing.allocator);
    _ = try (try (try button_builder.withKey("button")).prop("role", @as([]const u8, "primary")))
        .on("click", EventCallback.init(@ptrCast(&clicks), Counter.increment));
    defer button_builder.deinit();

    var root_builder = container(std.testing.allocator);
    _ = try (try (try root_builder.withKey("root")).prop("spacing", @as(f32, 8))).child(&title_builder);
    _ = try root_builder.child(&button_builder);
    defer root_builder.deinit();

    var root = try root_builder.build();
    defer root.deinit(std.testing.allocator);

    try std.testing.expect(root == .widget);
    try std.testing.expectEqual(WidgetKind.container, root.widget.kind);
    try std.testing.expectEqualStrings("root", root.key().?);
    try std.testing.expectEqual(@as(f32, 8), root.widget.propertyValue(f32, "spacing").?);
    try std.testing.expectEqual(@as(usize, 2), root.widget.children.len);

    const title = &root.widget.children[0];
    try std.testing.expect(title.* == .widget);
    try std.testing.expectEqual(WidgetKind.leaf, title.widget.kind);
    try std.testing.expectEqualStrings("hello", title.widget.propertyValue([]const u8, "text").?);

    const button_el = &root.widget.children[1];
    try std.testing.expect(button_el.* == .widget);
    try std.testing.expectEqualStrings("primary", button_el.widget.propertyValue([]const u8, "role").?);
    button_el.widget.event("click").?.invoke();
    try std.testing.expectEqual(@as(u32, 1), clicks);
}

test "provide folds multiple context values into one provider node" {
    const ThemeContext = context.Context([]const u8);
    const ScaleContext = context.Context(f32);

    const theme = ThemeContext.init("light");
    const scale = ScaleContext.init(1);

    var leaf_builder = leaf(std.testing.allocator);
    _ = try leaf_builder.prop("id", @as(u32, 1));
    defer leaf_builder.deinit();

    var dark_leaf = try intoElement(std.testing.allocator, &leaf_builder);
    defer dark_leaf.deinit(std.testing.allocator);

    var dark_provider = try provide(
        std.testing.allocator,
        &dark_leaf,
        &theme,
        @as([]const u8, "dark"),
    );
    defer dark_provider.deinit(std.testing.allocator);

    var provided = try provide(
        std.testing.allocator,
        &dark_provider,
        &scale,
        @as(f32, 1.5),
    );
    defer provided.deinit(std.testing.allocator);

    try std.testing.expect(provided == .provider);
    try std.testing.expectEqual(@as(usize, 2), provided.provider.provisions.len);
    try std.testing.expectEqualStrings("dark", provided.provider.provisions[0].get([]const u8).?);
    try std.testing.expectEqual(@as(f32, 1.5), provided.provider.provisions[1].get(f32).?);
    try std.testing.expect(provided.provider.child.* == .widget);
}

test "element clone supports safe explicit reuse of named elements" {
    var named_builder = leaf(std.testing.allocator);
    _ = try named_builder.prop("text", @as([]const u8, "shared"));
    defer named_builder.deinit();

    var named = try intoElement(std.testing.allocator, &named_builder);
    defer named.deinit(std.testing.allocator);

    var clone_a = try named.clone(std.testing.allocator);
    defer clone_a.deinit(std.testing.allocator);
    var clone_b = try named.clone(std.testing.allocator);
    defer clone_b.deinit(std.testing.allocator);

    var wrapped = try group(std.testing.allocator, .{
        &clone_a,
        &clone_b,
    });
    defer wrapped.deinit(std.testing.allocator);

    try std.testing.expect(wrapped == .group);
    try std.testing.expectEqual(@as(usize, 2), wrapped.group.children.len);
    try std.testing.expectEqualStrings("shared", named.widget.propertyValue([]const u8, "text").?);
    try std.testing.expectEqualStrings("shared", wrapped.group.children[0].widget.propertyValue([]const u8, "text").?);
    try std.testing.expectEqualStrings("shared", wrapped.group.children[1].widget.propertyValue([]const u8, "text").?);
}

test "memoized components compare props while plain components always rerender" {
    const Props = struct {
        value: i32,
    };

    const Render = struct {
        fn call(_: *const Props, _: *render_cx.RenderCx) Error!Element {
            return .empty;
        }
    };

    var plain_old = try component(std.testing.allocator, "counter", Props{ .value = 1 }, Render.call);
    defer plain_old.deinit(std.testing.allocator);
    var plain_new = try component(std.testing.allocator, "counter", Props{ .value = 1 }, Render.call);
    defer plain_new.deinit(std.testing.allocator);
    try std.testing.expect(plain_old.component.shouldUpdate(&plain_new.component));

    var memo_old = try memo(std.testing.allocator, "counter", Props{ .value = 1 }, Render.call);
    defer memo_old.deinit(std.testing.allocator);
    var memo_same = try memo(std.testing.allocator, "counter", Props{ .value = 1 }, Render.call);
    defer memo_same.deinit(std.testing.allocator);
    try std.testing.expect(!memo_old.component.shouldUpdate(&memo_same.component));

    var memo_changed = try memo(std.testing.allocator, "counter", Props{ .value = 2 }, Render.call);
    defer memo_changed.deinit(std.testing.allocator);
    try std.testing.expect(memo_old.component.shouldUpdate(&memo_changed.component));
}

test "provider walk scopes ambient context for nested consumer components" {
    const ThemeContext = context.Context([]const u8);
    const theme = ThemeContext.init("light");

    const ConsumerProps = struct {
        label: []const u8,
        theme: *const context.Context([]const u8),
    };

    const RenderConsumer = struct {
        fn call(props: *const ConsumerProps, cx: *render_cx.RenderCx) Error!Element {
            const theme_value = try cx.useContext([]const u8, props.theme);
            var builder = leaf(cx.getAllocator());
            _ = try (try builder.prop("label", props.label)).prop("theme", theme_value);
            return builder.build();
        }
    };

    const VisitConsumers = struct {
        const State = struct {
            values: [3][]const u8 = undefined,
            count: usize = 0,
            saw_non_widget: bool = false,
        };

        fn call(raw: ?*anyopaque, cx: *render_cx.RenderCx, element: *const Element) Error!void {
            const state: *State = @ptrCast(@alignCast(raw.?));
            switch (element.*) {
                .component => |component_element| {
                    var rendered = try component_element.render(cx);
                    defer rendered.deinit(cx.getAllocator());

                    if (rendered != .widget) {
                        state.saw_non_widget = true;
                        return;
                    }
                    state.values[state.count] = rendered.widget.propertyValue([]const u8, "theme").?;
                    state.count += 1;
                },
                else => {},
            }
        }
    };

    var outer_consumer = try component(
        std.testing.allocator,
        "consumer",
        ConsumerProps{ .label = "outer", .theme = &theme },
        RenderConsumer.call,
    );
    defer outer_consumer.deinit(std.testing.allocator);

    var inner_consumer = try component(
        std.testing.allocator,
        "consumer",
        ConsumerProps{ .label = "inner", .theme = &theme },
        RenderConsumer.call,
    );
    defer inner_consumer.deinit(std.testing.allocator);

    var inner_provider = try provide(
        std.testing.allocator,
        &inner_consumer,
        &theme,
        @as([]const u8, "high-contrast"),
    );
    defer inner_provider.deinit(std.testing.allocator);

    var trailing_consumer = try component(
        std.testing.allocator,
        "consumer",
        ConsumerProps{ .label = "after-inner", .theme = &theme },
        RenderConsumer.call,
    );
    defer trailing_consumer.deinit(std.testing.allocator);

    var tree_builder = container(std.testing.allocator);
    _ = try tree_builder.childrenFrom(.{
        &outer_consumer,
        &inner_provider,
        &trailing_consumer,
    });
    defer tree_builder.deinit();

    var tree = try tree_builder.build();
    defer tree.deinit(std.testing.allocator);

    var provided_tree = try provide(
        std.testing.allocator,
        &tree,
        &theme,
        @as([]const u8, "dark"),
    );
    defer provided_tree.deinit(std.testing.allocator);

    var stack = context.ContextStack.init(std.testing.allocator);
    defer stack.deinit();

    var cx = render_cx.RenderCx.init(std.testing.allocator, render_cx.RequestRerender.none());
    defer cx.deinit();
    cx.setContextStack(&stack);

    var state = VisitConsumers.State{};
    const visitor = Visitor.init(@ptrCast(&state), VisitConsumers.call);

    cx.beginRender();
    try provided_tree.walk(&cx, visitor);
    try cx.finishRender();

    try std.testing.expectEqual(@as(usize, 3), state.count);
    try std.testing.expect(!state.saw_non_widget);
    try std.testing.expectEqualStrings("dark", state.values[0]);
    try std.testing.expectEqualStrings("high-contrast", state.values[1]);
    try std.testing.expectEqualStrings("dark", state.values[2]);

    var read_contexts = cx.takeReadContexts();
    defer read_contexts.deinit(std.testing.allocator);
    try std.testing.expect(read_contexts.contains(theme.id));
}
