const std = @import("std");
const win = @import("win");

const backend = @import("backend.zig");
const element = @import("element.zig");
const generated_attach_event = @import("reactor-generated-attach-event");
const generated_set_prop = @import("reactor-generated-set-prop");
const controls = @import("Microsoft.UI.Xaml.Controls");
const controls_primitives = @import("Microsoft.UI.Xaml.Controls.Primitives");
const xaml = @import("Microsoft.UI.Xaml");

const win_core = win.core;

const WidgetId = backend.WidgetId;
const Allocator = std.mem.Allocator;

/// Initial real WinUI backend surface: Application, Window, Button,
/// StackPanel, TextBlock, TextBox, and the first navigation/dialog
/// controls, with generated property/event dispatch wired for the
/// manifest-covered subset.
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
        ref: ?*element.WidgetRef = null,
        children: std.ArrayListUnmanaged(WidgetId) = .empty,
        events: std.ArrayListUnmanaged(*EventEntry) = .empty,

        fn deinit(self: *Node, allocator: Allocator) void {
            if (self.ref) |widget_ref| widget_ref.clear();
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
            .content_dialog => ownInspectable(try createComposable(controls.ContentDialog, controls.IContentDialogFactory)),
            .flyout => ownInspectable(try createComposable(controls.Flyout, controls.IFlyoutFactory)),
            .navigation_view => ownInspectable(try createComposable(controls.NavigationView, controls.INavigationViewFactory)),
            .navigation_view_item => ownInspectable(try createComposable(controls.NavigationViewItem, controls.INavigationViewItemFactory)),
            .menu_bar => ownInspectable(try createComposable(controls.MenuBar, controls.IMenuBarFactory)),
            .menu_bar_item => ownInspectable(try createComposable(controls.MenuBarItem, controls.IMenuBarItemFactory)),
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
                if (isOverlayWidget(child_node.kind)) return;
                if (child_node.kind == .navigation_view_item or child_node.kind == .menu_bar_item) {
                    return error.UnsupportedParentChild;
                }
                _ = index;
                try self.refreshStackPanelChildren(parent_node);
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
            else => return error.UnsupportedParentChild,
        }

        _ = parent_node.children.orderedRemove(child_index);
        switch (parent_node.kind) {
            .window => try self.refreshWindowContent(parent_node),
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

    fn propertyToSetterValue(self: *WinUIBackend, kind: element.WidgetKind, property: *const element.Property) !OwnedSetterValue {
        switch (kind) {
            .window,
            .button,
            .text_block,
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
        const handle = if (node.children.items.len == 0)
            null
        else
            (self.nodes.get(node.children.items[node.children.items.len - 1]) orelse return error.UnknownWidget).handle;
        try self.setContentControlContentHandle(node.handle, handle);
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

        try self.setContentControlContentHandle(node.handle, content_handle);
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

    fn setContentControlContentHandle(self: *WinUIBackend, parent_handle: win_core.IInspectable, child_handle: ?win_core.IInspectable) !void {
        const content_control = try parent_handle.cast(controls.IContentControl_Vtbl, &controls.IContentControl.IID);
        defer content_control.deinit();
        const iface: *const controls.IContentControl = @ptrCast(@alignCast(content_control.ptr));

        if (child_handle) |handle| {
            const child_ui = try self.uiElementCom(handle);
            defer child_ui.deinit();
            try win_core.hresult.ok(iface.put_Content(@ptrCast(child_ui.ptr)));
            return;
        }

        try win_core.hresult.ok(iface.put_Content(null));
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
        .stack_panel => "Microsoft.UI.Xaml.Controls.StackPanel",
        .text_block => "Microsoft.UI.Xaml.Controls.TextBlock",
        .text_box => "Microsoft.UI.Xaml.Controls.TextBox",
        .content_dialog => "Microsoft.UI.Xaml.Controls.ContentDialog",
        .flyout => "Microsoft.UI.Xaml.Controls.Flyout",
        .navigation_view => "Microsoft.UI.Xaml.Controls.NavigationView",
        .navigation_view_item => "Microsoft.UI.Xaml.Controls.NavigationViewItem",
        .menu_bar => "Microsoft.UI.Xaml.Controls.MenuBar",
        .menu_bar_item => "Microsoft.UI.Xaml.Controls.MenuBarItem",
        else => null,
    };
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
