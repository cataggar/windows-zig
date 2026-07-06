const std = @import("std");
const win = @import("win");
const win_collections = @import("win-collections");

const backend = @import("backend.zig");
const element = @import("element.zig");
const widgets_layout = @import("widgets_layout.zig");
const generated_attach_event = @import("reactor-generated-attach-event");
const generated_set_prop = @import("reactor-generated-set-prop");
const controls = @import("Microsoft.UI.Xaml.Controls");
const controls_primitives = @import("Microsoft.UI.Xaml.Controls.Primitives");
const foundation = @import("Windows.Foundation");
const ui_input = @import("Microsoft.UI.Input");
const xaml = @import("Microsoft.UI.Xaml");
const xaml_input = @import("Microsoft.UI.Xaml.Input");
const media = @import("Microsoft.UI.Xaml.Media");

const win_core = win.core;

const WidgetId = backend.WidgetId;
const Allocator = std.mem.Allocator;
const ObservableObjectVector = win_collections.IObservableVector(?*const anyopaque);

/// Real WinUI backend surface for the current reactor widget catalog:
/// Application, Window, Button, StackPanel, Grid, ScrollViewer, Border,
/// TextBlock, TextBox, Canvas, list, and navigation/dialog widgets, with
/// generated property/event dispatch wired for manifest-covered members plus
/// manual fallbacks for current attached-property / collection-property gaps.
pub const WinUIBackend = struct {
    allocator: Allocator,
    application: win_core.IInspectable,
    next_id: WidgetId = 1,
    nodes: std.AutoHashMapUnmanaged(WidgetId, Node) = .empty,
    root_order: std.ArrayListUnmanaged(WidgetId) = .empty,

    const ManagedItemsSource = struct {
        vector: *ObservableObjectVector,

        fn init(allocator: Allocator) !ManagedItemsSource {
            return .{
                .vector = try win_collections.createObservableVector(?*const anyopaque, allocator, &[_]?*const anyopaque{}),
            };
        }

        fn deinit(self: *ManagedItemsSource) void {
            self.vector.deinit();
            self.* = undefined;
        }

        fn object(self: *const ManagedItemsSource) ?*const anyopaque {
            return @ptrCast(self.vector);
        }

        fn insert(self: *ManagedItemsSource, index: usize, value: ?*const anyopaque) !void {
            const size: usize = @intCast(try self.vector.Size());
            if (index > size) return error.InvalidChildIndex;
            if (index == size) {
                try self.vector.Append(value);
                return;
            }
            try self.vector.InsertAt(@intCast(index), value);
        }

        fn removeAt(self: *ManagedItemsSource, index: usize) !void {
            try self.vector.RemoveAt(@intCast(index));
        }
    };

    const Node = struct {
        kind: element.WidgetKind,
        handle: win_core.IInspectable,
        parent: ?WidgetId,
        ref: ?*element.WidgetRef = null,
        children: std.ArrayListUnmanaged(WidgetId) = .empty,
        events: std.ArrayListUnmanaged(*EventEntry) = .empty,
        managed_items_source: ?ManagedItemsSource = null,
        uses_explicit_items_source: bool = false,

        fn deinit(self: *Node, allocator: Allocator) void {
            if (self.ref) |widget_ref| widget_ref.clear();
            if (self.managed_items_source) |*managed_items_source| {
                managed_items_source.deinit();
            }
            for (self.events.items) |entry| {
                entry.deinit(allocator);
                allocator.destroy(entry);
            }
            self.events.deinit(allocator);
            self.children.deinit(allocator);
            self.handle.deinit();
            self.* = undefined;
        }
    };

    const EventEntry = struct {
        allocator: Allocator,
        handler: element.EventHandler,
        payload: ?generated_attach_event.EventPayload = null,
        source: generated_attach_event.EventSource = .none,
        connection: generated_attach_event.EventConnection = .{},

        fn deinit(self: *EventEntry, allocator: Allocator) void {
            self.handler.deinit(allocator);
            self.* = undefined;
        }
    };

    const OwnedSetterValue = struct {
        value: generated_set_prop.SetterValue,
        owned_utf16: ?[]u16 = null,

        fn deinit(self: *OwnedSetterValue, allocator: Allocator) void {
            if (self.owned_utf16) |text| allocator.free(text);
            self.* = undefined;
        }
    };

    const ObjectVector_Vtbl = extern struct {
        base: win_core.IInspectable_Vtbl,
        GetAt: *const anyopaque,
        get_Size: *const anyopaque,
        GetView: *const anyopaque,
        IndexOf: *const anyopaque,
        SetAt: *const anyopaque,
        InsertAt: *const anyopaque,
        RemoveAt: *const anyopaque,
        Append: *const fn (this: *const ObjectVector, value: ?*const anyopaque) callconv(.winapi) win_core.HRESULT,
        RemoveAtEnd: *const anyopaque,
        Clear: *const fn (this: *const ObjectVector) callconv(.winapi) win_core.HRESULT,
    };

    const ObjectVector = extern struct {
        vtable: *const ObjectVector_Vtbl,

        fn Release(self: *const ObjectVector) callconv(.winapi) u32 {
            return self.vtable.base.base.Release(@ptrCast(@constCast(self)));
        }

        fn Append(self: *const ObjectVector, value: ?*const anyopaque) callconv(.winapi) win_core.HRESULT {
            return self.vtable.Append(self, value);
        }

        fn Clear(self: *const ObjectVector) callconv(.winapi) win_core.HRESULT {
            return self.vtable.Clear(self);
        }
    };

    const OwnedEventValue = struct {
        value: element.EventValue = .{ .unit = {} },
        owned_utf8: ?[]u8 = null,

        fn deinit(self: *OwnedEventValue, allocator: Allocator) void {
            if (self.owned_utf8) |text| allocator.free(text);
            self.* = undefined;
        }
    };

    pub fn init(allocator: Allocator, application: *xaml.Application) WinUIBackend {
        return .{
            .allocator = allocator,
            .application = .from(@ptrCast(application)),
        };
    }

    pub fn deinit(self: *WinUIBackend) void {
        while (self.root_order.items.len > 0) {
            const id = self.root_order.items[self.root_order.items.len - 1];
            self.unmountWidget(id) catch break;
        }

        var it = self.nodes.valueIterator();
        while (it.next()) |node| {
            node.deinit(self.allocator);
        }
        self.nodes.deinit(self.allocator);
        self.root_order.deinit(self.allocator);
        self.application.deinit();
        self.* = undefined;
    }

    pub fn activateWindows(self: *WinUIBackend) !void {
        var it = self.nodes.valueIterator();
        while (it.next()) |node| {
            if (node.kind != .window) continue;
            const window = try self.windowCom(node.handle);
            defer window.deinit();
            const iface: *const xaml.IWindow = @ptrCast(@alignCast(window.ptr));
            try win_core.hresult.ok(iface.Activate());
        }
    }

    pub fn firstWindowHandle(self: *WinUIBackend) !?*anyopaque {
        for (self.root_order.items) |id| {
            const node = self.nodes.get(id) orelse continue;
            if (node.kind != .window) continue;
            return self.windowHandleFrom(node.handle);
        }

        var it = self.nodes.valueIterator();
        while (it.next()) |node| {
            if (node.kind != .window) continue;
            return self.windowHandleFrom(node.handle);
        }
        return null;
    }

    pub fn showContentDialogAsync(self: *WinUIBackend, id: WidgetId) !win_core.IInspectable {
        const node = self.nodes.get(id) orelse return error.UnknownWidget;
        if (node.kind != .content_dialog) return error.UnsupportedWidgetKind;

        const dialog = try self.contentDialogCom(node.handle);
        defer dialog.deinit();
        const iface: *const controls.IContentDialog = @ptrCast(@alignCast(dialog.ptr));

        var operation_ptr: *anyopaque = undefined;
        try win_core.hresult.ok(iface.ShowAsync(&operation_ptr));
        return .from(@ptrCast(operation_ptr));
    }

    pub fn hideContentDialog(self: *WinUIBackend, id: WidgetId) !void {
        const node = self.nodes.get(id) orelse return error.UnknownWidget;
        if (node.kind != .content_dialog) return error.UnsupportedWidgetKind;

        const dialog = try self.contentDialogCom(node.handle);
        defer dialog.deinit();
        const iface: *const controls.IContentDialog = @ptrCast(@alignCast(dialog.ptr));
        try win_core.hresult.ok(iface.Hide());
    }

    pub fn showFlyout(self: *WinUIBackend, flyout_id: WidgetId, target_id: WidgetId) !void {
        const flyout_node = self.nodes.get(flyout_id) orelse return error.UnknownWidget;
        if (flyout_node.kind != .flyout) return error.UnsupportedWidgetKind;
        const target_node = self.nodes.get(target_id) orelse return error.UnknownWidget;

        const flyout = try self.flyoutBaseCom(flyout_node.handle);
        defer flyout.deinit();
        const flyout_iface: *const controls_primitives.IFlyoutBase = @ptrCast(@alignCast(flyout.ptr));

        const target_ui = try self.uiElementCom(target_node.handle);
        defer target_ui.deinit();
        const target_ptr: *xaml.FrameworkElement = @ptrCast(@alignCast(target_ui.ptr));

        try win_core.hresult.ok(flyout_iface.ShowAt(target_ptr));
    }

    pub fn hideFlyout(self: *WinUIBackend, id: WidgetId) !void {
        const node = self.nodes.get(id) orelse return error.UnknownWidget;
        if (node.kind != .flyout) return error.UnsupportedWidgetKind;

        const flyout = try self.flyoutBaseCom(node.handle);
        defer flyout.deinit();
        const iface: *const controls_primitives.IFlyoutBase = @ptrCast(@alignCast(flyout.ptr));
        try win_core.hresult.ok(iface.Hide());
    }

    pub fn mountWidget(self: *WinUIBackend, parent: ?WidgetId, index: usize, kind: element.WidgetKind) !WidgetId {
        const handle = try self.createHandle(kind);
        var node = Node{
            .kind = kind,
            .handle = handle,
            .parent = parent,
        };
        errdefer node.deinit(self.allocator);

        const id = self.next_id;
        self.next_id += 1;
        try self.nodes.put(self.allocator, id, node);
        errdefer {
            const removed = self.nodes.fetchRemove(id).?;
            var owned = removed.value;
            owned.deinit(self.allocator);
        }

        if (isManagedListWidget(kind)) {
            try self.initializeManagedItemsSource(id);
        }

        try self.insertChildRecord(parent, index, id);
        errdefer self.removeChildRecord(parent, id);

        try self.attachChild(parent, index, id);
        return id;
    }

    pub fn unmountWidget(self: *WinUIBackend, id: WidgetId) !void {
        var node = self.nodes.getPtr(id) orelse return error.UnknownWidget;

        while (node.children.items.len > 0) {
            const child_id = node.children.items[node.children.items.len - 1];
            try self.unmountWidget(child_id);
            node = self.nodes.getPtr(id) orelse return;
        }

        while (node.events.items.len > 0) {
            const entry = node.events.items[node.events.items.len - 1];
            try self.detachEvent(id, entry.handler.name);
            node = self.nodes.getPtr(id) orelse return;
        }

        try self.detachFromParent(id);

        const removed = self.nodes.fetchRemove(id) orelse return error.UnknownWidget;
        var owned = removed.value;
        owned.deinit(self.allocator);
    }

    pub fn reorderChildren(self: *WinUIBackend, parent: ?WidgetId, child_ids: []const WidgetId) !void {
        if (parent) |parent_id| {
            var parent_node = self.nodes.getPtr(parent_id) orelse return error.UnknownWidget;
            switch (parent_node.kind) {
                .application => {
                    try replaceChildList(&parent_node.children, self.allocator, child_ids);
                },
                .window => {
                    try replaceChildList(&parent_node.children, self.allocator, child_ids);
                    try self.refreshWindowContent(parent_node);
                },
                .scroll_viewer, .border => {
                    try replaceChildList(&parent_node.children, self.allocator, child_ids);
                    try self.refreshSingleChildContainer(parent_node);
                },
                .stack_panel, .grid, .canvas => {
                    const collection = try self.panelChildren(parent_node.handle);
                    defer collection.deinit();
                    const iface: *const controls.IUIElementCollection = @ptrCast(@alignCast(collection.ptr));

                    const current = try self.allocator.dupe(WidgetId, parent_node.children.items);
                    defer self.allocator.free(current);

                    for (child_ids, 0..) |desired_id, desired_index| {
                        if (desired_index < current.len and current[desired_index] == desired_id) continue;

                        const current_index = indexOfChild(current, desired_id) orelse return error.UnknownWidget;
                        try win_core.hresult.ok(iface.Move(@intCast(current_index), @intCast(desired_index)));
                        moveInPlace(current, current_index, desired_index);
                    }

                    try replaceChildList(&parent_node.children, self.allocator, child_ids);
                    try self.refreshStackPanelChildren(parent_node);
                },
                .content_dialog => {
                    try replaceChildList(&parent_node.children, self.allocator, child_ids);
                    try self.refreshContentDialogContent(parent_node);
                },
                .flyout => {
                    try replaceChildList(&parent_node.children, self.allocator, child_ids);
                    try self.refreshFlyoutContent(parent_node);
                },
                .navigation_view => {
                    try replaceChildList(&parent_node.children, self.allocator, child_ids);
                    try self.refreshNavigationView(parent_node);
                },
                .menu_bar => {
                    try replaceChildList(&parent_node.children, self.allocator, child_ids);
                    try self.refreshMenuBar(parent_node);
                },
                .list_view, .items_repeater => {
                    if (parent_node.uses_explicit_items_source) return error.ItemsSourceManagedExternally;
                    const managed_items_source = if (parent_node.managed_items_source) |*managed_items_source|
                        managed_items_source
                    else
                        return error.ManagedItemsSourceUnavailable;
                    const current = try self.allocator.dupe(WidgetId, parent_node.children.items);
                    defer self.allocator.free(current);

                    for (child_ids, 0..) |desired_id, desired_index| {
                        if (desired_index < current.len and current[desired_index] == desired_id) continue;

                        const current_index = indexOfChild(current, desired_id) orelse return error.UnknownWidget;
                        try managed_items_source.removeAt(current_index);
                        const child = self.nodes.get(desired_id) orelse return error.UnknownWidget;
                        try managed_items_source.insert(desired_index, inspectableAsObject(child.handle));
                        moveInPlace(current, current_index, desired_index);
                    }

                    try replaceChildList(&parent_node.children, self.allocator, child_ids);
                },
                else => return error.UnsupportedParentChild,
            }
            return;
        }

        try replaceChildList(&self.root_order, self.allocator, child_ids);
    }

    pub fn setProperty(self: *WinUIBackend, id: WidgetId, property: *const element.Property) !void {
        const node = self.nodes.getPtr(id) orelse return error.UnknownWidget;
        if (std.mem.eql(u8, property.name, element.WidgetRefPropertyName)) {
            const widget_ref = property.get(*element.WidgetRef) orelse return error.UnsupportedPropertyValue;
            if (node.ref) |existing| {
                if (existing != widget_ref) existing.clear();
            }
            node.ref = widget_ref;
            widget_ref.id = id;
            return;
        }

        const prior_explicit = node.uses_explicit_items_source;
        if (isItemsSourceProperty(node.kind, property.name)) {
            if (node.children.items.len != 0) return error.ItemsSourceManagedByChildren;
            node.uses_explicit_items_source = true;
        }
        errdefer node.uses_explicit_items_source = prior_explicit;

        if (try self.setManualProperty(id, property)) return;
        const widget_class = widgetClassName(node.kind) orelse return error.UnsupportedWidgetKind;
        var setter_value = try self.propertyToSetterValue(node.kind, property);
        defer setter_value.deinit(self.allocator);

        const applied = try generated_set_prop.dispatch(
            widget_class,
            property.name,
            node.handle.ptr,
            setter_value.value,
        );
        if (!applied) return error.UnsupportedProperty;
    }

    pub fn unsetProperty(self: *WinUIBackend, id: WidgetId, name: []const u8) !void {
        const node = self.nodes.getPtr(id) orelse return error.UnknownWidget;
        if (std.mem.eql(u8, name, element.WidgetRefPropertyName)) {
            if (node.ref) |widget_ref| widget_ref.clear();
            node.ref = null;
            return;
        }
        if (isItemsSourceProperty(node.kind, name)) {
            const prior_explicit = node.uses_explicit_items_source;
            node.uses_explicit_items_source = false;
            errdefer node.uses_explicit_items_source = prior_explicit;
            try self.applyManagedItemsSource(node);
            return;
        }
        if (try self.unsetManualProperty(node.kind, node.handle, name)) return;

        var value = if (std.mem.eql(u8, name, "Left") or std.mem.eql(u8, name, "Top"))
            OwnedSetterValue{ .value = .{ .f64 = std.math.nan(f64) } }
        else if (std.mem.eql(u8, name, "ZIndex"))
            OwnedSetterValue{ .value = .{ .i32 = 0 } }
        else switch (node.kind) {
            .window => if (std.mem.eql(u8, name, "Title"))
                try self.utf8SetterValue("")
            else
                return error.UnsupportedProperty,
            .button => if (std.mem.eql(u8, name, "Content"))
                try self.utf8SetterValue("")
            else
                return error.UnsupportedProperty,
            .text_block => if (std.mem.eql(u8, name, "Text"))
                try self.utf8SetterValue("")
            else
                return error.UnsupportedProperty,
            .content_dialog => if (std.mem.eql(u8, name, "Title") or
                std.mem.eql(u8, name, "PrimaryButtonText") or
                std.mem.eql(u8, name, "SecondaryButtonText") or
                std.mem.eql(u8, name, "CloseButtonText"))
                try self.utf8SetterValue("")
            else
                return error.UnsupportedProperty,
            .navigation_view_item => if (std.mem.eql(u8, name, "Content"))
                try self.utf8SetterValue("")
            else
                return error.UnsupportedProperty,
            .menu_bar_item => if (std.mem.eql(u8, name, "Title"))
                try self.utf8SetterValue("")
            else
                return error.UnsupportedProperty,
            .text_box => if (std.mem.eql(u8, name, "Text"))
                try self.utf8SetterValue("")
            else
                return error.UnsupportedProperty,
            .stack_panel => if (std.mem.eql(u8, name, "Orientation"))
                OwnedSetterValue{ .value = .{ .enum_i32 = @intFromEnum(controls.Orientation.Vertical) } }
            else if (std.mem.eql(u8, name, "Spacing"))
                OwnedSetterValue{ .value = .{ .f64 = 0.0 } }
            else
                return error.UnsupportedProperty,
            .grid, .scroll_viewer, .border, .list_view, .items_repeater => return error.UnsupportedProperty,
            else => return error.UnsupportedProperty,
        };
        defer value.deinit(self.allocator);

        const widget_class = widgetClassName(node.kind) orelse return error.UnsupportedWidgetKind;
        const applied = try generated_set_prop.dispatch(widget_class, name, node.handle.ptr, value.value);
        if (!applied) return error.UnsupportedProperty;
    }

    pub fn attachEvent(self: *WinUIBackend, id: WidgetId, handler: *const element.EventHandler) !void {
        const node = self.nodes.getPtr(id) orelse return error.UnknownWidget;
        const widget_class = widgetClassName(node.kind) orelse return error.UnsupportedWidgetKind;
        const connector = generated_attach_event.find(widget_class, handler.name) orelse
            return error.UnsupportedEvent;

        const entry = try self.allocator.create(EventEntry);
        errdefer self.allocator.destroy(entry);
        entry.* = .{
            .allocator = self.allocator,
            .handler = try handler.clone(self.allocator),
            .payload = connector.payload,
            .source = connector.source,
        };
        errdefer entry.deinit(self.allocator);

        const connected = try generated_attach_event.dispatchConnect(
            widget_class,
            entry.handler.name,
            node.handle.ptr,
            self.allocator,
            onEventInvoked,
            entry,
            &entry.connection,
        );
        if (!connected) return error.UnsupportedEvent;
        errdefer {
            _ = generated_attach_event.dispatchDisconnect(
                widget_class,
                entry.handler.name,
                node.handle.ptr,
                &entry.connection,
            ) catch {};
        }

        try node.events.append(self.allocator, entry);
    }

    pub fn detachEvent(self: *WinUIBackend, id: WidgetId, name: []const u8) !void {
        const node = self.nodes.getPtr(id) orelse return error.UnknownWidget;
        const event_index = findEventIndex(node.events.items, name) orelse return;
        const entry = node.events.orderedRemove(event_index);
        errdefer {
            node.events.insert(self.allocator, event_index, entry) catch {};
        }

        const widget_class = widgetClassName(node.kind) orelse return error.UnsupportedWidgetKind;
        const disconnected = try generated_attach_event.dispatchDisconnect(
            widget_class,
            entry.handler.name,
            node.handle.ptr,
            &entry.connection,
        );
        if (!disconnected) return error.UnsupportedEvent;

        entry.deinit(self.allocator);
        self.allocator.destroy(entry);
    }

    fn createHandle(self: *WinUIBackend, kind: element.WidgetKind) !win_core.IInspectable {
        return switch (kind) {
            .application => self.application.clone(),
            .window => ownInspectable(try createComposable(xaml.Window, xaml.IWindowFactory)),
            .button => ownInspectable(try createComposable(controls.Button, controls.IButtonFactory)),
            .canvas => ownInspectable(try createComposable(controls.Canvas, controls.ICanvasFactory)),
            .stack_panel => ownInspectable(try createComposable(controls.StackPanel, controls.IStackPanelFactory)),
            .grid => ownInspectable(try createComposable(controls.Grid, controls.IGridFactory)),
            .scroll_viewer => ownInspectable(try controls.ScrollViewer.activate()),
            .border => ownInspectable(try controls.Border.activate()),
            .text_block => ownInspectable(try controls.TextBlock.activate()),
            .text_box => ownInspectable(try createComposable(controls.TextBox, controls.ITextBoxFactory)),
            .content_dialog => ownInspectable(try createComposable(controls.ContentDialog, controls.IContentDialogFactory)),
            .flyout => ownInspectable(try createComposable(controls.Flyout, controls.IFlyoutFactory)),
            .navigation_view => ownInspectable(try createComposable(controls.NavigationView, controls.INavigationViewFactory)),
            .navigation_view_item => ownInspectable(try createComposable(controls.NavigationViewItem, controls.INavigationViewItemFactory)),
            .menu_bar => ownInspectable(try createComposable(controls.MenuBar, controls.IMenuBarFactory)),
            .menu_bar_item => ownInspectable(try createComposable(controls.MenuBarItem, controls.IMenuBarItemFactory)),
            .list_view => ownInspectable(try createComposable(controls.ListView, controls.IListViewFactory)),
            .items_repeater => ownInspectable(try createComposable(controls.ItemsRepeater, controls.IItemsRepeaterFactory)),
            else => error.UnsupportedWidgetKind,
        };
    }

    fn insertChildRecord(self: *WinUIBackend, parent: ?WidgetId, index: usize, id: WidgetId) !void {
        if (parent) |parent_id| {
            const parent_node = self.nodes.getPtr(parent_id) orelse return error.UnknownWidget;
            if (index > parent_node.children.items.len) return error.InvalidChildIndex;
            try parent_node.children.insert(self.allocator, index, id);
            return;
        }

        if (index > self.root_order.items.len) return error.InvalidChildIndex;
        try self.root_order.insert(self.allocator, index, id);
    }

    fn removeChildRecord(self: *WinUIBackend, parent: ?WidgetId, id: WidgetId) void {
        if (parent) |parent_id| {
            const parent_node = self.nodes.getPtr(parent_id) orelse return;
            removeChildId(&parent_node.children, id);
            return;
        }
        removeChildId(&self.root_order, id);
    }

    fn attachChild(self: *WinUIBackend, parent: ?WidgetId, index: usize, child_id: WidgetId) !void {
        if (parent == null) {
            const child = self.nodes.get(child_id) orelse return error.UnknownWidget;
            switch (child.kind) {
                .application, .window => return,
                else => return error.UnsupportedTopLevelWidget,
            }
        }

        const parent_id = parent.?;
        const parent_node = self.nodes.getPtr(parent_id) orelse return error.UnknownWidget;
        const child_node = self.nodes.get(child_id) orelse return error.UnknownWidget;

        switch (parent_node.kind) {
            .application => {
                if (child_node.kind != .window) return error.UnsupportedParentChild;
            },
            .window => {
                try self.setWindowContentHandle(parent_node, child_node.handle);
            },
            .scroll_viewer => {
                try self.setContentControlContentHandle(parent_node, child_node.handle);
            },
            .border => {
                try self.setBorderChildHandle(parent_node, child_node.handle);
            },
            .stack_panel, .grid, .canvas => {
                if (isOverlayWidget(child_node.kind)) return;
                if (child_node.kind == .navigation_view_item or child_node.kind == .menu_bar_item) {
                    return error.UnsupportedParentChild;
                }

                const collection = try self.panelChildren(parent_node.handle);
                defer collection.deinit();
                const iface: *const controls.IUIElementCollection = @ptrCast(@alignCast(collection.ptr));

                const child_ui = try self.uiElementCom(child_node.handle);
                defer child_ui.deinit();
                const child_ptr: *xaml.UIElement = @ptrCast(@alignCast(child_ui.ptr));

                if (index == parent_node.children.items.len - 1) {
                    try win_core.hresult.ok(iface.Append(child_ptr));
                } else {
                    try win_core.hresult.ok(iface.InsertAt(@intCast(index), child_ptr));
                }
            },
            .content_dialog => {
                if (isOverlayWidget(child_node.kind) or
                    child_node.kind == .navigation_view_item or
                    child_node.kind == .menu_bar_item)
                {
                    return error.UnsupportedParentChild;
                }
                try self.refreshContentDialogContent(parent_node);
            },
            .flyout => {
                if (isOverlayWidget(child_node.kind) or
                    child_node.kind == .navigation_view_item or
                    child_node.kind == .menu_bar_item)
                {
                    return error.UnsupportedParentChild;
                }
                try self.refreshFlyoutContent(parent_node);
            },
            .navigation_view => {
                if (child_node.kind != .navigation_view_item and isOverlayWidget(child_node.kind)) {
                    return error.UnsupportedParentChild;
                }
                if (child_node.kind == .menu_bar_item) return error.UnsupportedParentChild;
                try self.refreshNavigationView(parent_node);
            },
            .menu_bar => {
                if (child_node.kind != .menu_bar_item) return error.UnsupportedParentChild;
                try self.refreshMenuBar(parent_node);
            },
            .list_view, .items_repeater => {
                if (parent_node.uses_explicit_items_source) return error.ItemsSourceManagedExternally;
                if (parent_node.managed_items_source) |*managed_items_source| {
                    try managed_items_source.insert(index, inspectableAsObject(child_node.handle));
                } else {
                    return error.ManagedItemsSourceUnavailable;
                }
            },
            else => return error.UnsupportedParentChild,
        }
    }

    fn detachFromParent(self: *WinUIBackend, id: WidgetId) !void {
        const node = self.nodes.get(id) orelse return error.UnknownWidget;
        const parent_id = node.parent orelse {
            removeChildId(&self.root_order, id);
            return;
        };

        const parent_node = self.nodes.getPtr(parent_id) orelse return error.UnknownWidget;
        const child_index = indexOfChild(parent_node.children.items, id) orelse return error.UnknownWidget;

        switch (parent_node.kind) {
            .application => {},
            .window => {},
            .scroll_viewer => {},
            .border => {},
            .stack_panel, .grid, .canvas => {
                if (!isOverlayWidget(node.kind)) {
                    const visual_index = visualIndexOfPanelChild(self, parent_node, id) orelse return error.UnknownWidget;
                    const collection = try self.panelChildren(parent_node.handle);
                    defer collection.deinit();
                    const iface: *const controls.IUIElementCollection = @ptrCast(@alignCast(collection.ptr));
                    try win_core.hresult.ok(iface.RemoveAt(@intCast(visual_index)));
                }
            },
            .content_dialog => {},
            .flyout => {},
            .navigation_view => {},
            .menu_bar => {},
            .list_view, .items_repeater => {
                if (parent_node.uses_explicit_items_source) return error.ItemsSourceManagedExternally;
                if (parent_node.managed_items_source) |*managed_items_source| {
                    try managed_items_source.removeAt(child_index);
                } else {
                    return error.ManagedItemsSourceUnavailable;
                }
            },
            else => return error.UnsupportedParentChild,
        }

        _ = parent_node.children.orderedRemove(child_index);
        switch (parent_node.kind) {
            .window => try self.refreshWindowContent(parent_node),
            .scroll_viewer, .border => try self.refreshSingleChildContainer(parent_node),
            .content_dialog => try self.refreshContentDialogContent(parent_node),
            .flyout => try self.refreshFlyoutContent(parent_node),
            .navigation_view => try self.refreshNavigationView(parent_node),
            .menu_bar => try self.refreshMenuBar(parent_node),
            else => {},
        }
    }

    fn refreshWindowContent(self: *WinUIBackend, node: *Node) !void {
        if (node.children.items.len == 0) {
            try self.setWindowContent(node, null);
            return;
        }

        const child_id = node.children.items[node.children.items.len - 1];
        const child = self.nodes.get(child_id) orelse return error.UnknownWidget;
        try self.setWindowContentHandle(node, child.handle);
    }

    fn setWindowContentHandle(self: *WinUIBackend, node: *Node, handle: win_core.IInspectable) !void {
        const child_ui = try self.uiElementCom(handle);
        defer child_ui.deinit();
        const child_ptr: *xaml.UIElement = @ptrCast(@alignCast(child_ui.ptr));
        try self.setWindowContent(node, child_ptr);
    }

    fn setWindowContent(self: *WinUIBackend, node: *Node, value: ?*xaml.UIElement) !void {
        const window = try self.windowCom(node.handle);
        defer window.deinit();
        const iface: *const xaml.IWindow = @ptrCast(@alignCast(window.ptr));
        try win_core.hresult.ok(iface.put_Content(value));
    }

    fn refreshSingleChildContainer(self: *WinUIBackend, node: *Node) !void {
        if (node.children.items.len == 0) {
            switch (node.kind) {
                .scroll_viewer => try self.setContentControlContent(node, null),
                .border => try self.setBorderChild(node, null),
                else => return error.UnsupportedParentChild,
            }
            return;
        }

        const child_id = node.children.items[node.children.items.len - 1];
        const child = self.nodes.get(child_id) orelse return error.UnknownWidget;
        switch (node.kind) {
            .scroll_viewer => try self.setContentControlContentHandle(node, child.handle),
            .border => try self.setBorderChildHandle(node, child.handle),
            else => return error.UnsupportedParentChild,
        }
    }

    fn setContentControlContentHandle(self: *WinUIBackend, node: *Node, handle: win_core.IInspectable) !void {
        const child_ui = try self.uiElementCom(handle);
        defer child_ui.deinit();
        const child_ptr: *xaml.UIElement = @ptrCast(@alignCast(child_ui.ptr));
        try self.setContentControlContent(node, child_ptr);
    }

    fn setContentControlContent(self: *WinUIBackend, node: *Node, value: ?*xaml.UIElement) !void {
        const content_control = try self.contentControlCom(node.handle);
        defer content_control.deinit();
        const iface: *const controls.IContentControl = @ptrCast(@alignCast(content_control.ptr));
        try win_core.hresult.ok(iface.put_Content(if (value) |child|
            @as(?*const anyopaque, @ptrCast(child))
        else
            null));
    }

    fn setBorderChildHandle(self: *WinUIBackend, node: *Node, handle: win_core.IInspectable) !void {
        const child_ui = try self.uiElementCom(handle);
        defer child_ui.deinit();
        const child_ptr: *xaml.UIElement = @ptrCast(@alignCast(child_ui.ptr));
        try self.setBorderChild(node, child_ptr);
    }

    fn setBorderChild(self: *WinUIBackend, node: *Node, value: ?*xaml.UIElement) !void {
        const border = try self.borderCom(node.handle);
        defer border.deinit();
        const iface: *const controls.IBorder = @ptrCast(@alignCast(border.ptr));
        try win_core.hresult.ok(iface.put_Child(value));
    }

    fn initializeManagedItemsSource(self: *WinUIBackend, id: WidgetId) !void {
        const node = self.nodes.getPtr(id) orelse return error.UnknownWidget;
        if (!isManagedListWidget(node.kind) or node.managed_items_source != null) return;

        node.managed_items_source = try ManagedItemsSource.init(self.allocator);
        errdefer {
            if (node.managed_items_source) |*managed_items_source| {
                managed_items_source.deinit();
            }
            node.managed_items_source = null;
        }
        try self.applyManagedItemsSource(node);
    }

    fn applyManagedItemsSource(self: *WinUIBackend, node: *Node) !void {
        if (!isManagedListWidget(node.kind)) return;
        if (node.uses_explicit_items_source) return;
        const managed_items_source = node.managed_items_source orelse return error.ManagedItemsSourceUnavailable;
        try self.applyItemsSourceObject(node, managed_items_source.object());
    }

    fn applyItemsSourceObject(self: *WinUIBackend, node: *Node, value: ?*const anyopaque) !void {
        const widget_class = widgetClassName(node.kind) orelse return error.UnsupportedWidgetKind;
        const applied = try generated_set_prop.dispatch(
            widget_class,
            "ItemsSource",
            node.handle.ptr,
            .{ .object = value },
        );
        _ = self;
        if (!applied) return error.UnsupportedProperty;
    }

    fn setManualProperty(self: *WinUIBackend, id: WidgetId, property: *const element.Property) !bool {
        const node = self.nodes.get(id) orelse return error.UnknownWidget;

        switch (node.kind) {
            .button, .stack_panel, .grid, .scroll_viewer, .border, .text_block, .text_box, .canvas, .list_view, .items_repeater => {
                if (try self.setGridAttachedProperty(node.handle, property)) return true;
            },
            else => {},
        }

        switch (node.kind) {
            .grid => {
                if (std.mem.eql(u8, property.name, "RowDefinitions")) {
                    const tracks = property.get(widgets_layout.GridTracks) orelse return error.UnsupportedPropertyValue;
                    try self.setGridRowDefinitions(node.handle, tracks);
                    return true;
                }
                if (std.mem.eql(u8, property.name, "ColumnDefinitions")) {
                    const tracks = property.get(widgets_layout.GridTracks) orelse return error.UnsupportedPropertyValue;
                    try self.setGridColumnDefinitions(node.handle, tracks);
                    return true;
                }
            },
            .border => {
                if (std.mem.eql(u8, property.name, "BorderThickness")) {
                    const value = property.get(xaml.Thickness) orelse return error.UnsupportedPropertyValue;
                    const border = try self.borderCom(node.handle);
                    defer border.deinit();
                    const iface: *const controls.IBorder = @ptrCast(@alignCast(border.ptr));
                    try win_core.hresult.ok(iface.put_BorderThickness(value));
                    return true;
                }
                if (std.mem.eql(u8, property.name, "CornerRadius")) {
                    const value = property.get(xaml.CornerRadius) orelse return error.UnsupportedPropertyValue;
                    const border = try self.borderCom(node.handle);
                    defer border.deinit();
                    const iface: *const controls.IBorder = @ptrCast(@alignCast(border.ptr));
                    try win_core.hresult.ok(iface.put_CornerRadius(value));
                    return true;
                }
                if (std.mem.eql(u8, property.name, "Background")) {
                    const value = property.get(widgets_layout.Color) orelse return error.UnsupportedPropertyValue;
                    try self.setBorderBackground(node.handle, value);
                    return true;
                }
            },
            else => {},
        }

        return false;
    }

    fn unsetManualProperty(self: *WinUIBackend, kind: element.WidgetKind, handle: win_core.IInspectable, name: []const u8) !bool {
        switch (kind) {
            .button, .stack_panel, .grid, .scroll_viewer, .border, .text_block, .text_box, .canvas, .list_view, .items_repeater => {
                if (try self.clearGridAttachedProperty(handle, name)) return true;
            },
            else => {},
        }

        switch (kind) {
            .grid => {
                if (std.mem.eql(u8, name, "RowDefinitions")) {
                    try self.clearGridRowDefinitions(handle);
                    return true;
                }
                if (std.mem.eql(u8, name, "ColumnDefinitions")) {
                    try self.clearGridColumnDefinitions(handle);
                    return true;
                }
            },
            .border => {
                if (std.mem.eql(u8, name, "BorderThickness")) {
                    const border = try self.borderCom(handle);
                    defer border.deinit();
                    const iface: *const controls.IBorder = @ptrCast(@alignCast(border.ptr));
                    try win_core.hresult.ok(iface.put_BorderThickness(.{}));
                    return true;
                }
                if (std.mem.eql(u8, name, "CornerRadius")) {
                    const border = try self.borderCom(handle);
                    defer border.deinit();
                    const iface: *const controls.IBorder = @ptrCast(@alignCast(border.ptr));
                    try win_core.hresult.ok(iface.put_CornerRadius(.{}));
                    return true;
                }
                if (std.mem.eql(u8, name, "Background")) {
                    try self.clearBorderBackground(handle);
                    return true;
                }
            },
            else => {},
        }

        return false;
    }

    fn propertyToSetterValue(self: *WinUIBackend, kind: element.WidgetKind, property: *const element.Property) !OwnedSetterValue {
        if (std.mem.eql(u8, property.name, "Left") or std.mem.eql(u8, property.name, "Top")) {
            if (property.get(f64)) |value| {
                return .{ .value = .{ .f64 = value } };
            }
            if (property.get(f32)) |value| {
                return .{ .value = .{ .f64 = value } };
            }
            if (property.get(i32)) |value| {
                return .{ .value = .{ .f64 = @floatFromInt(value) } };
            }
            return error.UnsupportedPropertyValue;
        }

        if (std.mem.eql(u8, property.name, "ZIndex")) {
            if (property.get(i32)) |value| {
                return .{ .value = .{ .i32 = value } };
            }
            return error.UnsupportedPropertyValue;
        }

        switch (kind) {
            .window,
            .button,
            .text_block,
            .text_box,
            .content_dialog,
            .navigation_view_item,
            .menu_bar_item,
            => {
                if (property.get(*xaml.UIElement)) |value| {
                    return .{ .value = .{ .element = value } };
                }
                if (property.get(*const xaml.UIElement)) |value| {
                    return .{ .value = .{ .element = @constCast(value) } };
                }
                const text = property.get([]const u8) orelse return error.UnsupportedPropertyValue;
                return self.utf8SetterValue(text);
            },
            .flyout, .navigation_view => {
                if (property.get(*xaml.UIElement)) |value| {
                    return .{ .value = .{ .element = value } };
                }
                if (property.get(*const xaml.UIElement)) |value| {
                    return .{ .value = .{ .element = @constCast(value) } };
                }
                return error.UnsupportedPropertyValue;
            },
            .stack_panel => {
                if (std.mem.eql(u8, property.name, "Orientation")) {
                    if (property.get(i32)) |value| {
                        return .{ .value = .{ .enum_i32 = value } };
                    }
                    if (property.get(controls.Orientation)) |value| {
                        return .{ .value = .{ .enum_i32 = @intFromEnum(value) } };
                    }
                    return error.UnsupportedPropertyValue;
                }

                if (std.mem.eql(u8, property.name, "Spacing")) {
                    if (property.get(f64)) |value| {
                        return .{ .value = .{ .f64 = value } };
                    }
                    if (property.get(f32)) |value| {
                        return .{ .value = .{ .f64 = value } };
                    }
                    return error.UnsupportedPropertyValue;
                }

                return error.UnsupportedProperty;
            },
            .list_view, .items_repeater => {
                if (!std.mem.eql(u8, property.name, "ItemsSource")) return error.UnsupportedProperty;
                const source = property.get(?*const anyopaque) orelse return error.UnsupportedPropertyValue;
                return .{ .value = .{ .object = source } };
            },
            .grid, .scroll_viewer, .border => return error.UnsupportedProperty,
            else => return error.UnsupportedProperty,
        }
    }

    fn utf8SetterValue(self: *WinUIBackend, text: []const u8) !OwnedSetterValue {
        const wide = try std.unicode.utf8ToUtf16LeAlloc(self.allocator, text);
        return .{
            .value = .{ .string = wide },
            .owned_utf16 = wide,
        };
    }

    fn windowHandleFrom(_: *WinUIBackend, handle: win_core.IInspectable) !?*anyopaque {
        var raw: ?*anyopaque = null;
        try win_core.hresult.ok(handle.queryInterface(&xaml.IWindowNative_Vtbl.IID, &raw));
        const native: *const xaml.IWindowNative = @ptrCast(@alignCast(raw.?));
        defer _ = native.Release();

        var hwnd: ?*anyopaque = null;
        try win_core.hresult.ok(native.WindowHandle(&hwnd));
        return hwnd;
    }

    fn windowCom(_: *WinUIBackend, handle: win_core.IInspectable) !win_core.Com(xaml.IWindow_Vtbl) {
        return handle.cast(xaml.IWindow_Vtbl, &xaml.IWindow.IID);
    }

    fn uiElementCom(_: *WinUIBackend, handle: win_core.IInspectable) !win_core.Com(xaml.IUIElement_Vtbl) {
        return handle.cast(xaml.IUIElement_Vtbl, &xaml.IUIElement.IID);
    }

    fn frameworkElementCom(_: *WinUIBackend, handle: win_core.IInspectable) !win_core.Com(xaml.IFrameworkElement_Vtbl) {
        return handle.cast(xaml.IFrameworkElement_Vtbl, &xaml.IFrameworkElement.IID);
    }

    fn contentControlCom(_: *WinUIBackend, handle: win_core.IInspectable) !win_core.Com(controls.IContentControl_Vtbl) {
        return handle.cast(controls.IContentControl_Vtbl, &controls.IContentControl.IID);
    }

    fn borderCom(_: *WinUIBackend, handle: win_core.IInspectable) !win_core.Com(controls.IBorder_Vtbl) {
        return handle.cast(controls.IBorder_Vtbl, &controls.IBorder.IID);
    }

    fn gridCom(_: *WinUIBackend, handle: win_core.IInspectable) !win_core.Com(controls.IGrid_Vtbl) {
        return handle.cast(controls.IGrid_Vtbl, &controls.IGrid.IID);
    }

    fn panelChildren(self: *WinUIBackend, handle: win_core.IInspectable) !win_core.Com(controls.IUIElementCollection_Vtbl) {
        const panel = try handle.cast(controls.IPanel_Vtbl, &controls.IPanel.IID);
        defer panel.deinit();

        const iface: *const controls.IPanel = @ptrCast(@alignCast(panel.ptr));
        var children_ptr: *controls.IUIElementCollection = undefined;
        try win_core.hresult.ok(iface.get_Children(&children_ptr));
        _ = self;
        return .from(@ptrCast(children_ptr));
    }

    fn setGridAttachedProperty(self: *WinUIBackend, handle: win_core.IInspectable, property: *const element.Property) !bool {
        const value = propertyI32(property) orelse {
            if (isGridAttachedProperty(property.name)) return error.UnsupportedPropertyValue;
            return false;
        };

        const statics = try controls.Grid.statics();
        defer statics.deinit();
        const iface: *const controls.IGridStatics = @ptrCast(@alignCast(statics.ptr));

        const framework = try self.frameworkElementCom(handle);
        defer framework.deinit();
        const framework_ptr: *xaml.FrameworkElement = @ptrCast(@alignCast(framework.ptr));

        if (std.mem.eql(u8, property.name, "Grid.Row")) {
            try win_core.hresult.ok(iface.SetRow(framework_ptr, value));
            return true;
        }
        if (std.mem.eql(u8, property.name, "Grid.Column")) {
            try win_core.hresult.ok(iface.SetColumn(framework_ptr, value));
            return true;
        }
        if (std.mem.eql(u8, property.name, "Grid.RowSpan")) {
            try win_core.hresult.ok(iface.SetRowSpan(framework_ptr, value));
            return true;
        }
        if (std.mem.eql(u8, property.name, "Grid.ColumnSpan")) {
            try win_core.hresult.ok(iface.SetColumnSpan(framework_ptr, value));
            return true;
        }
        return false;
    }

    fn clearGridAttachedProperty(self: *WinUIBackend, handle: win_core.IInspectable, name: []const u8) !bool {
        if (!isGridAttachedProperty(name)) return false;

        const value: i32 = if (std.mem.eql(u8, name, "Grid.RowSpan") or std.mem.eql(u8, name, "Grid.ColumnSpan"))
            1
        else
            0;
        var property = try element.Property.init(self.allocator, name, value);
        defer property.deinit(self.allocator);
        return try self.setGridAttachedProperty(handle, &property);
    }

    fn setGridRowDefinitions(self: *WinUIBackend, handle: win_core.IInspectable, tracks: widgets_layout.GridTracks) !void {
        const grid = try self.gridCom(handle);
        defer grid.deinit();
        const iface: *const controls.IGrid = @ptrCast(@alignCast(grid.ptr));
        var raw: *controls.RowDefinitionCollection = undefined;
        try win_core.hresult.ok(iface.get_RowDefinitions(&raw));
        const collection_ref = ownInspectable(raw);
        defer collection_ref.deinit();
        const vector: *const controls.IRowDefinitionVector = @ptrCast(raw);
        var size: u32 = 0;
        try win_core.hresult.ok(vector.get_Size(&size));
        while (size > 0) : (size -= 1) {
            try win_core.hresult.ok(vector.RemoveAtEnd());
        }

        for (tracks.slice()) |track| {
            const row = try controls.RowDefinition.activate();
            const row_iface: *const controls.IRowDefinition = @ptrCast(row);
            defer _ = row_iface.Release();
            try win_core.hresult.ok(row_iface.put_Height(track.toXaml()));
            try win_core.hresult.ok(vector.Append(@ptrCast(row)));
        }
    }

    fn clearGridRowDefinitions(self: *WinUIBackend, handle: win_core.IInspectable) !void {
        try self.setGridRowDefinitions(handle, .{});
    }

    fn setGridColumnDefinitions(self: *WinUIBackend, handle: win_core.IInspectable, tracks: widgets_layout.GridTracks) !void {
        const grid = try self.gridCom(handle);
        defer grid.deinit();
        const iface: *const controls.IGrid = @ptrCast(@alignCast(grid.ptr));
        var raw: *controls.ColumnDefinitionCollection = undefined;
        try win_core.hresult.ok(iface.get_ColumnDefinitions(&raw));
        const collection_ref = ownInspectable(raw);
        defer collection_ref.deinit();
        const vector: *const controls.IColumnDefinitionVector = @ptrCast(raw);
        var size: u32 = 0;
        try win_core.hresult.ok(vector.get_Size(&size));
        while (size > 0) : (size -= 1) {
            try win_core.hresult.ok(vector.RemoveAtEnd());
        }

        for (tracks.slice()) |track| {
            const column = try controls.ColumnDefinition.activate();
            const column_iface: *const controls.IColumnDefinition = @ptrCast(column);
            defer _ = column_iface.Release();
            try win_core.hresult.ok(column_iface.put_Width(track.toXaml()));
            try win_core.hresult.ok(vector.Append(@ptrCast(column)));
        }
    }

    fn clearGridColumnDefinitions(self: *WinUIBackend, handle: win_core.IInspectable) !void {
        try self.setGridColumnDefinitions(handle, .{});
    }

    fn setBorderBackground(self: *WinUIBackend, handle: win_core.IInspectable, value: widgets_layout.Color) !void {
        const brush = try media.SolidColorBrush.activate();
        const brush_iface: *const media.ISolidColorBrush = @ptrCast(brush);
        defer _ = brush_iface.Release();
        try win_core.hresult.ok(brush_iface.put_Color(.{
            .A = value.a,
            .R = value.r,
            .G = value.g,
            .B = value.b,
        }));

        const brush_base = brush_iface.cast(media.IBrush) orelse return error.InterfaceCastFailed;
        defer _ = brush_base.Release();

        const border = try self.borderCom(handle);
        defer border.deinit();
        const iface: *const controls.IBorder = @ptrCast(@alignCast(border.ptr));
        try win_core.hresult.ok(iface.put_Background(@ptrCast(@constCast(brush_base))));
    }

    fn clearBorderBackground(self: *WinUIBackend, handle: win_core.IInspectable) !void {
        const border = try self.borderCom(handle);
        defer border.deinit();
        const iface: *const controls.IBorder = @ptrCast(@alignCast(border.ptr));
        try win_core.hresult.ok(iface.put_Background(null));
    }

    fn contentDialogCom(_: *WinUIBackend, handle: win_core.IInspectable) !win_core.Com(controls.IContentDialog_Vtbl) {
        return handle.cast(controls.IContentDialog_Vtbl, &controls.IContentDialog.IID);
    }

    fn flyoutCom(_: *WinUIBackend, handle: win_core.IInspectable) !win_core.Com(controls.IFlyout_Vtbl) {
        return handle.cast(controls.IFlyout_Vtbl, &controls.IFlyout.IID);
    }

    fn flyoutBaseCom(_: *WinUIBackend, handle: win_core.IInspectable) !win_core.Com(controls_primitives.IFlyoutBase_Vtbl) {
        return handle.cast(controls_primitives.IFlyoutBase_Vtbl, &controls_primitives.IFlyoutBase.IID);
    }

    fn navigationViewCom(_: *WinUIBackend, handle: win_core.IInspectable) !win_core.Com(controls.INavigationView_Vtbl) {
        return handle.cast(controls.INavigationView_Vtbl, &controls.INavigationView.IID);
    }

    fn menuBarCom(_: *WinUIBackend, handle: win_core.IInspectable) !win_core.Com(controls.IMenuBar_Vtbl) {
        return handle.cast(controls.IMenuBar_Vtbl, &controls.IMenuBar.IID);
    }

    fn refreshStackPanelChildren(self: *WinUIBackend, node: *Node) !void {
        const collection = try self.panelChildren(node.handle);
        defer collection.deinit();
        const iface: *const controls.IUIElementCollection = @ptrCast(@alignCast(collection.ptr));
        try win_core.hresult.ok(iface.Clear());

        for (node.children.items) |child_id| {
            const child = self.nodes.get(child_id) orelse return error.UnknownWidget;
            if (!isPanelVisualChild(child.kind)) continue;

            const child_ui = try self.uiElementCom(child.handle);
            defer child_ui.deinit();
            const child_ptr: *xaml.UIElement = @ptrCast(@alignCast(child_ui.ptr));
            try win_core.hresult.ok(iface.Append(child_ptr));
        }
    }

    fn refreshContentDialogContent(self: *WinUIBackend, node: *Node) !void {
        if (node.children.items.len == 0) {
            try self.setContentControlContent(node, null);
            return;
        }

        const handle = (self.nodes.get(node.children.items[node.children.items.len - 1]) orelse return error.UnknownWidget).handle;
        try self.setContentControlContentHandle(node, handle);
    }

    fn refreshFlyoutContent(self: *WinUIBackend, node: *Node) !void {
        const handle = if (node.children.items.len == 0)
            null
        else
            (self.nodes.get(node.children.items[node.children.items.len - 1]) orelse return error.UnknownWidget).handle;
        try self.setFlyoutContentHandle(node.handle, handle);
    }

    fn refreshNavigationView(self: *WinUIBackend, node: *Node) !void {
        const navigation_view = try self.navigationViewCom(node.handle);
        defer navigation_view.deinit();
        const iface: *const controls.INavigationView = @ptrCast(@alignCast(navigation_view.ptr));

        var items_raw: *anyopaque = undefined;
        try win_core.hresult.ok(iface.get_MenuItems(&items_raw));
        const items: *ObjectVector = @ptrCast(@alignCast(items_raw));
        defer _ = items.Release();
        try win_core.hresult.ok(items.Clear());

        var content_handle: ?win_core.IInspectable = null;
        for (node.children.items) |child_id| {
            const child = self.nodes.get(child_id) orelse return error.UnknownWidget;
            if (child.kind == .navigation_view_item) {
                try win_core.hresult.ok(items.Append(child.handle.ptr));
            } else {
                content_handle = child.handle;
            }
        }

        if (content_handle) |handle| {
            try self.setContentControlContentHandle(node, handle);
        } else {
            try self.setContentControlContent(node, null);
        }
    }

    fn refreshMenuBar(self: *WinUIBackend, node: *Node) !void {
        const menu_bar = try self.menuBarCom(node.handle);
        defer menu_bar.deinit();
        const iface: *const controls.IMenuBar = @ptrCast(@alignCast(menu_bar.ptr));

        var items_raw: *anyopaque = undefined;
        try win_core.hresult.ok(iface.get_Items(&items_raw));
        const items: *ObjectVector = @ptrCast(@alignCast(items_raw));
        defer _ = items.Release();
        try win_core.hresult.ok(items.Clear());

        for (node.children.items) |child_id| {
            const child = self.nodes.get(child_id) orelse return error.UnknownWidget;
            if (child.kind != .menu_bar_item) return error.UnsupportedParentChild;
            try win_core.hresult.ok(items.Append(child.handle.ptr));
        }
    }

    fn setFlyoutContentHandle(self: *WinUIBackend, parent_handle: win_core.IInspectable, child_handle: ?win_core.IInspectable) !void {
        const flyout = try self.flyoutCom(parent_handle);
        defer flyout.deinit();
        const iface: *const controls.IFlyout = @ptrCast(@alignCast(flyout.ptr));
        if (child_handle) |handle| {
            const child_ui = try self.uiElementCom(handle);
            defer child_ui.deinit();
            try win_core.hresult.ok(iface.put_Content(@ptrCast(@alignCast(child_ui.ptr))));
            return;
        }
        try win_core.hresult.ok(iface.put_Content(null));
    }
};

fn ownInspectable(ptr: anytype) win_core.IInspectable {
    return .from(@ptrCast(@alignCast(ptr)));
}

fn createComposable(comptime RuntimeClass: type, comptime Factory: type) !*RuntimeClass {
    const factory = try win_core.activationFactory(Factory.Vtbl, &Factory.IID, &RuntimeClass.NAME_W);
    defer factory.deinit();

    const factory_this: *const Factory = @ptrCast(@alignCast(factory.ptr));
    var inner: ?*const anyopaque = null;
    var instance: *RuntimeClass = undefined;
    try win_core.hresult.ok(factory_this.CreateInstance(null, &inner, &instance));
    return instance;
}

fn widgetClassName(kind: element.WidgetKind) ?[]const u8 {
    return switch (kind) {
        .application => "Microsoft.UI.Xaml.Application",
        .window => "Microsoft.UI.Xaml.Window",
        .button => "Microsoft.UI.Xaml.Controls.Button",
        .canvas => "Microsoft.UI.Xaml.Controls.Canvas",
        .stack_panel => "Microsoft.UI.Xaml.Controls.StackPanel",
        .grid => "Microsoft.UI.Xaml.Controls.Grid",
        .scroll_viewer => "Microsoft.UI.Xaml.Controls.ScrollViewer",
        .border => "Microsoft.UI.Xaml.Controls.Border",
        .text_block => "Microsoft.UI.Xaml.Controls.TextBlock",
        .text_box => "Microsoft.UI.Xaml.Controls.TextBox",
        .content_dialog => "Microsoft.UI.Xaml.Controls.ContentDialog",
        .flyout => "Microsoft.UI.Xaml.Controls.Flyout",
        .navigation_view => "Microsoft.UI.Xaml.Controls.NavigationView",
        .navigation_view_item => "Microsoft.UI.Xaml.Controls.NavigationViewItem",
        .menu_bar => "Microsoft.UI.Xaml.Controls.MenuBar",
        .menu_bar_item => "Microsoft.UI.Xaml.Controls.MenuBarItem",
        .list_view => "Microsoft.UI.Xaml.Controls.ListView",
        .items_repeater => "Microsoft.UI.Xaml.Controls.ItemsRepeater",
        else => null,
    };
}

fn isManagedListWidget(kind: element.WidgetKind) bool {
    return switch (kind) {
        .list_view, .items_repeater => true,
        else => false,
    };
}

fn isItemsSourceProperty(kind: element.WidgetKind, name: []const u8) bool {
    return isManagedListWidget(kind) and std.mem.eql(u8, name, "ItemsSource");
}

fn inspectableAsObject(handle: win_core.IInspectable) ?*const anyopaque {
    return @ptrCast(handle.ptr);
}

fn isGridAttachedProperty(name: []const u8) bool {
    return std.mem.eql(u8, name, "Grid.Row") or
        std.mem.eql(u8, name, "Grid.Column") or
        std.mem.eql(u8, name, "Grid.RowSpan") or
        std.mem.eql(u8, name, "Grid.ColumnSpan");
}

fn propertyI32(property: *const element.Property) ?i32 {
    if (property.get(i32)) |value| return value;
    if (property.get(i16)) |value| return value;
    if (property.get(i8)) |value| return value;
    if (property.get(u32)) |value| return std.math.cast(i32, value);
    if (property.get(u16)) |value| return value;
    if (property.get(u8)) |value| return value;
    return null;
}

fn isOverlayWidget(kind: element.WidgetKind) bool {
    return switch (kind) {
        .content_dialog, .flyout => true,
        else => false,
    };
}

fn isPanelVisualChild(kind: element.WidgetKind) bool {
    return switch (kind) {
        .navigation_view_item, .menu_bar_item => false,
        else => !isOverlayWidget(kind),
    };
}

fn visualIndexOfPanelChild(self: *const WinUIBackend, parent_node: *const WinUIBackend.Node, id: WidgetId) ?usize {
    var visual_index: usize = 0;
    for (parent_node.children.items) |child_id| {
        const child = self.nodes.get(child_id) orelse continue;
        if (child_id == id) return if (isPanelVisualChild(child.kind)) visual_index else 0;
        if (isPanelVisualChild(child.kind)) visual_index += 1;
    }
    return null;
}

fn expectObjectVectorEqual(
    vector: *ObservableObjectVector,
    expected: []const ?*const anyopaque,
) !void {
    try std.testing.expectEqual(@as(u32, @intCast(expected.len)), try vector.Size());
    for (expected, 0..) |expected_item, index| {
        var actual = try vector.GetAt(@intCast(index));
        defer win_collections.releaseValue(?*const anyopaque, &actual);
        try std.testing.expectEqual(expected_item, actual);
    }
}

test "managed items source mirrors incremental insertions and removals" {
    var source = try WinUIBackend.ManagedItemsSource.init(std.testing.allocator);
    defer source.deinit();

    const item_a = try win_collections.createVector(i32, std.testing.allocator, &[_]i32{1});
    defer item_a.deinit();
    const item_b = try win_collections.createVector(i32, std.testing.allocator, &[_]i32{2});
    defer item_b.deinit();
    const item_c = try win_collections.createVector(i32, std.testing.allocator, &[_]i32{3});
    defer item_c.deinit();

    const object_a = @as(?*const anyopaque, @ptrCast(item_a));
    const object_b = @as(?*const anyopaque, @ptrCast(item_b));
    const object_c = @as(?*const anyopaque, @ptrCast(item_c));

    try source.insert(0, object_a);
    try source.insert(1, object_b);
    try source.insert(1, object_c);
    try expectObjectVectorEqual(source.vector, &[_]?*const anyopaque{ object_a, object_c, object_b });

    try source.removeAt(1);
    try expectObjectVectorEqual(source.vector, &[_]?*const anyopaque{ object_a, object_b });
}

fn onEventInvoked(user_data: ?*anyopaque, sender: ?*const anyopaque, args: ?*const anyopaque) callconv(.winapi) win_core.HRESULT {
    const raw = user_data orelse return win_core.hresult.S_OK;
    const entry: *WinUIBackend.EventEntry = @ptrCast(@alignCast(raw));

    if (std.mem.eql(u8, entry.handler.name, "PointerPressed")) {
        capturePointerFromEvent(sender, args);
    }

    var value: WinUIBackend.OwnedEventValue = extractEventValue(entry, sender, args) catch .{};
    defer value.deinit(entry.allocator);
    entry.handler.invokeValue(value.value);

    if (std.mem.eql(u8, entry.handler.name, "PointerReleased")) {
        releasePointerFromEvent(sender, args);
    }

    return win_core.hresult.S_OK;
}

fn extractEventValue(
    entry: *const WinUIBackend.EventEntry,
    sender: ?*const anyopaque,
    args: ?*const anyopaque,
) !WinUIBackend.OwnedEventValue {
    const payload = entry.payload orelse return .{};
    return switch (payload) {
        .unit => .{},
        .string => switch (entry.source) {
            .sender_property => |name| try extractSenderStringProperty(entry.allocator, sender, name),
            else => .{},
        },
        .pointer => .{
            .value = .{
                .pointer = try extractPointerEventInfo(sender, args),
            },
        },
        else => .{},
    };
}

fn extractSenderStringProperty(
    allocator: Allocator,
    sender: ?*const anyopaque,
    name: []const u8,
) !WinUIBackend.OwnedEventValue {
    if (!std.mem.eql(u8, name, "Text")) {
        return .{
            .value = .{ .string = "" },
        };
    }

    const text_box = queryInterfaceOwnedRaw(sender, controls.ITextBox) orelse {
        return .{
            .value = .{ .string = "" },
        };
    };
    defer _ = text_box.Release();

    var text = try text_box.get_TextOwned();
    defer text.deinit();

    const utf8 = try std.unicode.utf16LeToUtf8Alloc(allocator, text.slice());
    return .{
        .value = .{ .string = utf8 },
        .owned_utf8 = utf8,
    };
}

fn extractPointerEventInfo(
    sender: ?*const anyopaque,
    args: ?*const anyopaque,
) !element.PointerEventInfo {
    var info: element.PointerEventInfo = .{};

    const raw_args = args orelse return info;
    const element_iface = queryInterfaceOwnedRaw(sender, xaml.IUIElement) orelse return info;
    defer _ = element_iface.Release();

    const routed: *const xaml_input.PointerRoutedEventArgs = @ptrCast(@alignCast(raw_args));
    var point_ptr: *ui_input.PointerPoint = undefined;
    try win_core.hresult.ok(routed.GetCurrentPoint(@ptrCast(@constCast(element_iface)), &point_ptr));
    defer _ = point_ptr.Release();

    var position: foundation.Point = .{};
    try win_core.hresult.ok(point_ptr.get_Position(&position));
    info.x = position.X;
    info.y = position.Y;

    var props: *ui_input.PointerPointProperties = undefined;
    try win_core.hresult.ok(point_ptr.get_Properties(&props));
    defer _ = props.Release();

    var left: foundation.BOOL = 0;
    var right: foundation.BOOL = 0;
    var middle: foundation.BOOL = 0;
    try win_core.hresult.ok(props.get_IsLeftButtonPressed(&left));
    try win_core.hresult.ok(props.get_IsRightButtonPressed(&right));
    try win_core.hresult.ok(props.get_IsMiddleButtonPressed(&middle));

    info.is_left_button_pressed = win_core.boolFromWin32(left);
    info.is_right_button_pressed = win_core.boolFromWin32(right);
    info.is_middle_button_pressed = win_core.boolFromWin32(middle);
    return info;
}

fn capturePointerFromEvent(sender: ?*const anyopaque, args: ?*const anyopaque) void {
    const element_iface = queryInterfaceOwnedRaw(sender, xaml.IUIElement) orelse return;
    defer _ = element_iface.Release();

    const raw_args = args orelse return;
    const routed: *const xaml_input.PointerRoutedEventArgs = @ptrCast(@alignCast(raw_args));
    var pointer: *xaml_input.Pointer = undefined;
    if (routed.get_Pointer(&pointer) < 0) return;
    defer _ = pointer.Release();

    var captured: foundation.BOOL = 0;
    _ = element_iface.CapturePointer(pointer, &captured);
}

fn releasePointerFromEvent(sender: ?*const anyopaque, args: ?*const anyopaque) void {
    const element_iface = queryInterfaceOwnedRaw(sender, xaml.IUIElement) orelse return;
    defer _ = element_iface.Release();

    const raw_args = args orelse {
        _ = element_iface.ReleasePointerCaptures();
        return;
    };
    const routed: *const xaml_input.PointerRoutedEventArgs = @ptrCast(@alignCast(raw_args));
    var pointer: *xaml_input.Pointer = undefined;
    if (routed.get_Pointer(&pointer) < 0) {
        _ = element_iface.ReleasePointerCaptures();
        return;
    }
    defer _ = pointer.Release();

    _ = element_iface.ReleasePointerCapture(pointer);
}

fn queryInterfaceOwnedRaw(raw: ?*const anyopaque, comptime T: type) ?*const T {
    const ptr = raw orelse return null;
    const unknown = @as(*const *const win_core.IUnknown_Vtbl, @ptrCast(@alignCast(ptr))).*;
    var out: ?*anyopaque = null;
    if (unknown.QueryInterface(@ptrCast(@constCast(ptr)), &T.IID, &out) < 0) return null;
    return @ptrCast(@alignCast(out.?));
}

fn findEventIndex(entries: []*WinUIBackend.EventEntry, name: []const u8) ?usize {
    for (entries, 0..) |entry, index| {
        if (std.mem.eql(u8, entry.handler.name, name)) return index;
    }
    return null;
}

fn indexOfChild(items: []const WidgetId, id: WidgetId) ?usize {
    for (items, 0..) |item, index| {
        if (item == id) return index;
    }
    return null;
}

fn removeChildId(list: *std.ArrayListUnmanaged(WidgetId), id: WidgetId) void {
    const index = indexOfChild(list.items, id) orelse return;
    _ = list.orderedRemove(index);
}

fn replaceChildList(list: *std.ArrayListUnmanaged(WidgetId), allocator: Allocator, child_ids: []const WidgetId) !void {
    list.clearRetainingCapacity();
    try list.appendSlice(allocator, child_ids);
}

fn moveInPlace(items: []WidgetId, from: usize, to: usize) void {
    if (from == to) return;
    const value = items[from];
    if (from > to) {
        std.mem.copyBackwards(WidgetId, items[to + 1 .. from + 1], items[to..from]);
    } else {
        std.mem.copyForwards(WidgetId, items[from..to], items[from + 1 .. to + 1]);
    }
    items[to] = value;
}
