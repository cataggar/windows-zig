const std = @import("std");
const win = @import("win");

const backend = @import("backend.zig");
const element = @import("element.zig");
const generated_attach_event = @import("reactor-generated-attach-event");
const generated_set_prop = @import("reactor-generated-set-prop");
const controls = @import("Microsoft.UI.Xaml.Controls");
const win_collections = @import("win-collections");
const xaml = @import("Microsoft.UI.Xaml");

const win_core = win.core;

const WidgetId = backend.WidgetId;
const Allocator = std.mem.Allocator;

/// Real WinUI backend surface covering the seeded text, button, layout,
/// and basic input widgets, with generated property/event dispatch wired
/// to the current manifest.
pub const WinUIBackend = struct {
    allocator: Allocator,
    application: win_core.IInspectable,
    next_id: WidgetId = 1,
    nodes: std.AutoHashMapUnmanaged(WidgetId, Node) = .empty,
    root_order: std.ArrayListUnmanaged(WidgetId) = .empty,

    const Node = struct {
        kind: element.WidgetKind,
        handle: win_core.IInspectable,
        parent: ?WidgetId,
        children: std.ArrayListUnmanaged(WidgetId) = .empty,
        events: std.ArrayListUnmanaged(*EventEntry) = .empty,

        fn deinit(self: *Node, allocator: Allocator) void {
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
        owned_inspectable: ?win_core.IInspectable = null,

        fn deinit(self: *OwnedSetterValue, allocator: Allocator) void {
            if (self.owned_utf16) |text| allocator.free(text);
            if (self.owned_inspectable) |owned| {
                var inspectable = owned;
                inspectable.deinit();
            }
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
                else => return error.UnsupportedParentChild,
            }
            return;
        }

        try replaceChildList(&self.root_order, self.allocator, child_ids);
    }

    pub fn setProperty(self: *WinUIBackend, id: WidgetId, property: *const element.Property) !void {
        const node = self.nodes.get(id) orelse return error.UnknownWidget;
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
        const node = self.nodes.get(id) orelse return error.UnknownWidget;
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
            .text_box => if (std.mem.eql(u8, name, "Text"))
                try self.utf8SetterValue("")
            else
                return error.UnsupportedProperty,
            .check_box => if (std.mem.eql(u8, name, "Content"))
                try self.utf8SetterValue("")
            else if (std.mem.eql(u8, name, "IsChecked"))
                OwnedSetterValue{ .value = .{ .bool = false } }
            else
                return error.UnsupportedProperty,
            .slider => if (std.mem.eql(u8, name, "Value") or std.mem.eql(u8, name, "Minimum"))
                OwnedSetterValue{ .value = .{ .f64 = 0.0 } }
            else if (std.mem.eql(u8, name, "Maximum"))
                OwnedSetterValue{ .value = .{ .f64 = 100.0 } }
            else
                return error.UnsupportedProperty,
            .combo_box => if (std.mem.eql(u8, name, "ItemsSource"))
                try self.stringListSetterValue(&[_][]const u8{})
            else if (std.mem.eql(u8, name, "SelectedIndex"))
                OwnedSetterValue{ .value = .{ .i32 = -1 } }
            else
                return error.UnsupportedProperty,
            .toggle_switch => if (std.mem.eql(u8, name, "IsOn"))
                OwnedSetterValue{ .value = .{ .bool = false } }
            else
                return error.UnsupportedProperty,
            .radio_button => if (std.mem.eql(u8, name, "Content"))
                try self.utf8SetterValue("")
            else if (std.mem.eql(u8, name, "IsChecked"))
                OwnedSetterValue{ .value = .{ .bool = false } }
            else
                return error.UnsupportedProperty,
            .stack_panel => if (std.mem.eql(u8, name, "Orientation"))
                OwnedSetterValue{ .value = .{ .enum_i32 = @intFromEnum(controls.Orientation.Vertical) } }
            else if (std.mem.eql(u8, name, "Spacing"))
                OwnedSetterValue{ .value = .{ .f64 = 0.0 } }
            else
                return error.UnsupportedProperty,
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
            .check_box => ownInspectable(try createComposable(controls.CheckBox, controls.ICheckBoxFactory)),
            .slider => ownInspectable(try createComposable(controls.Slider, controls.ISliderFactory)),
            .combo_box => ownInspectable(try createComposable(controls.ComboBox, controls.IComboBoxFactory)),
            .toggle_switch => ownInspectable(try controls.ToggleSwitch.activate()),
            .radio_button => ownInspectable(try createComposable(controls.RadioButton, controls.IRadioButtonFactory)),
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
            .window, .button, .text_block, .text_box => {
                const text = property.get([]const u8) orelse return error.UnsupportedPropertyValue;
                return self.utf8SetterValue(text);
            },
            .check_box, .radio_button => {
                if (std.mem.eql(u8, property.name, "Content")) {
                    const text = property.get([]const u8) orelse return error.UnsupportedPropertyValue;
                    return self.utf8SetterValue(text);
                }
                if (std.mem.eql(u8, property.name, "IsChecked")) {
                    const value = property.get(bool) orelse return error.UnsupportedPropertyValue;
                    return .{ .value = .{ .bool = value } };
                }
                return error.UnsupportedProperty;
            },
            .slider => {
                if (std.mem.eql(u8, property.name, "Value") or
                    std.mem.eql(u8, property.name, "Minimum") or
                    std.mem.eql(u8, property.name, "Maximum"))
                {
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
            .combo_box => {
                if (std.mem.eql(u8, property.name, "ItemsSource")) {
                    const items = property.get([]const []const u8) orelse return error.UnsupportedPropertyValue;
                    return self.stringListSetterValue(items);
                }
                if (std.mem.eql(u8, property.name, "SelectedIndex")) {
                    const value = property.get(i32) orelse return error.UnsupportedPropertyValue;
                    return .{ .value = .{ .i32 = value } };
                }
                return error.UnsupportedProperty;
            },
            .toggle_switch => {
                if (std.mem.eql(u8, property.name, "IsOn")) {
                    const value = property.get(bool) orelse return error.UnsupportedPropertyValue;
                    return .{ .value = .{ .bool = value } };
                }
                return error.UnsupportedProperty;
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

    fn stringListSetterValue(self: *WinUIBackend, items: []const []const u8) !OwnedSetterValue {
        var strings = try std.ArrayList(win_core.Hstring).initCapacity(self.allocator, items.len);
        defer {
            for (strings.items) |*item| item.deinit();
            strings.deinit(self.allocator);
        }

        for (items) |item| {
            try strings.append(self.allocator, try win_core.Hstring.createUtf8(self.allocator, item));
        }

        const vector = try win_collections.createVector(win_core.Hstring, self.allocator, strings.items);
        return .{
            .value = .{ .string_list = @ptrCast(vector) },
            .owned_inspectable = .from(@ptrCast(vector)),
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
        .check_box => "Microsoft.UI.Xaml.Controls.CheckBox",
        .slider => "Microsoft.UI.Xaml.Controls.Slider",
        .combo_box => "Microsoft.UI.Xaml.Controls.ComboBox",
        .toggle_switch => "Microsoft.UI.Xaml.Controls.ToggleSwitch",
        .radio_button => "Microsoft.UI.Xaml.Controls.RadioButton",
        else => null,
    };
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
