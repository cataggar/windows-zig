const std = @import("std");
const win = @import("win");
const win_collections = @import("win-collections");

const backend = @import("backend.zig");
const element = @import("element.zig");
const generated_attach_event = @import("reactor-generated-attach-event");
const generated_set_prop = @import("reactor-generated-set-prop");
const controls = @import("Microsoft.UI.Xaml.Controls");
const xaml = @import("Microsoft.UI.Xaml");

const win_core = win.core;

const WidgetId = backend.WidgetId;
const Allocator = std.mem.Allocator;
const ObservableObjectVector = win_collections.IObservableVector(?*const anyopaque);

/// Initial real WinUI backend surface: Application, Window, Button,
/// StackPanel, TextBlock, and TextBox runtime objects, with generated
/// property/event dispatch wired only for the manifest-covered subset.
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
        children: std.ArrayListUnmanaged(WidgetId) = .empty,
        events: std.ArrayListUnmanaged(*EventEntry) = .empty,
        managed_items_source: ?ManagedItemsSource = null,
        uses_explicit_items_source: bool = false,

        fn deinit(self: *Node, allocator: Allocator) void {
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
        handler: element.EventHandler,
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
                .stack_panel => {
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
        const prior_explicit = node.uses_explicit_items_source;
        if (isItemsSourceProperty(node.kind, property.name)) {
            if (node.children.items.len != 0) return error.ItemsSourceManagedByChildren;
            node.uses_explicit_items_source = true;
        }
        errdefer node.uses_explicit_items_source = prior_explicit;

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
        if (isItemsSourceProperty(node.kind, name)) {
            const prior_explicit = node.uses_explicit_items_source;
            node.uses_explicit_items_source = false;
            errdefer node.uses_explicit_items_source = prior_explicit;
            try self.applyManagedItemsSource(node);
            return;
        }

        var value = switch (node.kind) {
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
            .stack_panel => if (std.mem.eql(u8, name, "Orientation"))
                OwnedSetterValue{ .value = .{ .enum_i32 = @intFromEnum(controls.Orientation.Vertical) } }
            else if (std.mem.eql(u8, name, "Spacing"))
                OwnedSetterValue{ .value = .{ .f64 = 0.0 } }
            else
                return error.UnsupportedProperty,
            .list_view, .items_repeater => return error.UnsupportedProperty,
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

        const entry = try self.allocator.create(EventEntry);
        errdefer self.allocator.destroy(entry);
        entry.* = .{
            .handler = try handler.clone(self.allocator),
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
            .stack_panel => ownInspectable(try createComposable(controls.StackPanel, controls.IStackPanelFactory)),
            .text_block => ownInspectable(try controls.TextBlock.activate()),
            .text_box => ownInspectable(try createComposable(controls.TextBox, controls.ITextBoxFactory)),
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
            .stack_panel => {
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
            .stack_panel => {
                const collection = try self.panelChildren(parent_node.handle);
                defer collection.deinit();
                const iface: *const controls.IUIElementCollection = @ptrCast(@alignCast(collection.ptr));
                try win_core.hresult.ok(iface.RemoveAt(@intCast(child_index)));
            },
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
        if (parent_node.kind == .window) {
            try self.refreshWindowContent(parent_node);
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

    fn propertyToSetterValue(self: *WinUIBackend, kind: element.WidgetKind, property: *const element.Property) !OwnedSetterValue {
        switch (kind) {
            .window, .button, .text_block => {
                const text = property.get([]const u8) orelse return error.UnsupportedPropertyValue;
                return self.utf8SetterValue(text);
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

    fn panelChildren(self: *WinUIBackend, handle: win_core.IInspectable) !win_core.Com(controls.IUIElementCollection_Vtbl) {
        const panel = try handle.cast(controls.IPanel_Vtbl, &controls.IPanel.IID);
        defer panel.deinit();

        const iface: *const controls.IPanel = @ptrCast(@alignCast(panel.ptr));
        var children_ptr: *controls.IUIElementCollection = undefined;
        try win_core.hresult.ok(iface.get_Children(&children_ptr));
        _ = self;
        return .from(@ptrCast(children_ptr));
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
        .stack_panel => "Microsoft.UI.Xaml.Controls.StackPanel",
        .text_block => "Microsoft.UI.Xaml.Controls.TextBlock",
        .text_box => "Microsoft.UI.Xaml.Controls.TextBox",
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

fn onEventInvoked(user_data: ?*anyopaque, _: ?*const anyopaque, _: ?*const anyopaque) callconv(.winapi) win_core.HRESULT {
    const raw = user_data orelse return win_core.hresult.S_OK;
    const entry: *WinUIBackend.EventEntry = @ptrCast(@alignCast(raw));
    entry.handler.invoke();
    return win_core.hresult.S_OK;
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
