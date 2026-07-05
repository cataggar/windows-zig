const std = @import("std");
const backend = @import("backend.zig");
const element = @import("element.zig");

pub const Allocator = std.mem.Allocator;
pub const Backend = backend.Backend;
pub const WidgetId = backend.WidgetId;

const empty_widget_ids = [_]WidgetId{};

pub const RecordingBackend = struct {
    allocator: Allocator,
    next_id: WidgetId = 1,
    calls: std.ArrayListUnmanaged(Call) = .empty,
    widgets: std.ArrayListUnmanaged(?WidgetState) = .empty,
    root_children: std.ArrayListUnmanaged(WidgetId) = .empty,

    pub const WidgetState = struct {
        parent: ?WidgetId,
        kind: element.WidgetKind,
        props: std.ArrayListUnmanaged(element.Property) = .empty,
        events: std.ArrayListUnmanaged(element.EventHandler) = .empty,
        children: std.ArrayListUnmanaged(WidgetId) = .empty,

        fn deinit(self: *WidgetState, allocator: Allocator) void {
            for (self.props.items) |*prop| {
                prop.deinit(allocator);
            }
            self.props.deinit(allocator);

            for (self.events.items) |*event_handler| {
                event_handler.deinit(allocator);
            }
            self.events.deinit(allocator);

            self.children.deinit(allocator);
            self.* = undefined;
        }

        pub fn property(self: *const WidgetState, name: []const u8) ?*const element.Property {
            for (self.props.items) |*prop| {
                if (std.mem.eql(u8, prop.name, name)) return prop;
            }
            return null;
        }

        pub fn event(self: *const WidgetState, name: []const u8) ?*const element.EventHandler {
            for (self.events.items) |*handler| {
                if (std.mem.eql(u8, handler.name, name)) return handler;
            }
            return null;
        }
    };

    pub const Call = union(enum) {
        mount_widget: struct {
            parent: ?WidgetId,
            index: usize,
            kind: element.WidgetKind,
            id: WidgetId,
        },
        unmount_widget: WidgetId,
        reorder_children: struct {
            parent: ?WidgetId,
            children: []WidgetId,
        },
        set_property: struct {
            id: WidgetId,
            property: element.Property,
        },
        unset_property: struct {
            id: WidgetId,
            name: []const u8,
        },
        attach_event: struct {
            id: WidgetId,
            handler: element.EventHandler,
        },
        detach_event: struct {
            id: WidgetId,
            name: []const u8,
        },

        fn deinit(self: *Call, allocator: Allocator) void {
            switch (self.*) {
                .reorder_children => |*reorder| {
                    if (reorder.children.len > 0) allocator.free(reorder.children);
                },
                .set_property => |*set_property| {
                    set_property.property.deinit(allocator);
                },
                .unset_property => |*unset_property| {
                    if (unset_property.name.len > 0) allocator.free(unset_property.name);
                },
                .attach_event => |*attach_event| {
                    attach_event.handler.deinit(allocator);
                },
                .detach_event => |*detach_event| {
                    if (detach_event.name.len > 0) allocator.free(detach_event.name);
                },
                else => {},
            }
            self.* = undefined;
        }
    };

    pub fn init(allocator: Allocator) RecordingBackend {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *RecordingBackend) void {
        self.clearCalls();
        self.calls.deinit(self.allocator);

        while (self.root_children.items.len > 0) {
            const id = popWidgetId(&self.root_children);
            self.destroyWidgetRecursive(id);
        }

        for (self.widgets.items, 0..) |maybe_widget, index| {
            if (maybe_widget != null) {
                self.destroyWidgetRecursive(index + 1);
            }
        }

        self.root_children.deinit(self.allocator);
        self.widgets.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn asBackend(self: *RecordingBackend) Backend {
        return Backend.from(self);
    }

    pub fn clearCalls(self: *RecordingBackend) void {
        for (self.calls.items) |*call| {
            call.deinit(self.allocator);
        }
        self.calls.clearRetainingCapacity();
    }

    pub fn callsSlice(self: *const RecordingBackend) []const Call {
        return self.calls.items;
    }

    pub fn callCountOf(self: *const RecordingBackend, comptime tag: std.meta.Tag(Call)) usize {
        var count: usize = 0;
        for (self.calls.items) |call| {
            if (std.meta.activeTag(call) == tag) count += 1;
        }
        return count;
    }

    pub fn mountCallCount(self: *const RecordingBackend) usize {
        return self.callCountOf(.mount_widget);
    }

    pub fn unmountCallCount(self: *const RecordingBackend) usize {
        return self.callCountOf(.unmount_widget);
    }

    pub fn widgetState(self: *const RecordingBackend, id: WidgetId) ?*const WidgetState {
        return self.widgetConst(id);
    }

    pub fn rootChildren(self: *const RecordingBackend) []const WidgetId {
        return self.root_children.items;
    }

    pub fn childrenOf(self: *const RecordingBackend, parent: ?WidgetId) []const WidgetId {
        if (parent) |parent_id| {
            const widget = self.widgetConst(parent_id) orelse return &empty_widget_ids;
            return widget.children.items;
        }
        return self.root_children.items;
    }

    pub fn widgetIdAt(self: *const RecordingBackend, parent: ?WidgetId, index: usize) ?WidgetId {
        const children = self.childrenOf(parent);
        if (index >= children.len) return null;
        return children[index];
    }

    pub fn liveWidgetCount(self: *const RecordingBackend) usize {
        var count: usize = 0;
        for (self.widgets.items) |maybe_widget| {
            if (maybe_widget != null) count += 1;
        }
        return count;
    }

    pub fn activeEventCount(self: *const RecordingBackend) usize {
        var count: usize = 0;
        for (self.widgets.items) |maybe_widget| {
            if (maybe_widget) |widget| {
                count += widget.events.items.len;
            }
        }
        return count;
    }

    pub fn kindOf(self: *const RecordingBackend, id: WidgetId) ?element.WidgetKind {
        const widget = self.widgetConst(id) orelse return null;
        return widget.kind;
    }

    pub fn wasMounted(
        self: *const RecordingBackend,
        parent: ?WidgetId,
        index: usize,
        kind: element.WidgetKind,
    ) bool {
        return self.mountedId(parent, index, kind) != null;
    }

    pub fn mountedId(
        self: *const RecordingBackend,
        parent: ?WidgetId,
        index: usize,
        kind: element.WidgetKind,
    ) ?WidgetId {
        for (self.calls.items) |call| {
            switch (call) {
                .mount_widget => |mount| {
                    if (mount.parent == parent and mount.index == index and mount.kind == kind) {
                        return mount.id;
                    }
                },
                else => {},
            }
        }
        return null;
    }

    pub fn propertyValue(
        self: *const RecordingBackend,
        comptime T: type,
        id: WidgetId,
        name: []const u8,
    ) ?T {
        const widget = self.widgetConst(id) orelse return null;
        const property = widget.property(name) orelse return null;
        return property.get(T);
    }

    pub fn sawPropertySet(
        self: *const RecordingBackend,
        comptime T: type,
        id: WidgetId,
        name: []const u8,
        expected: T,
    ) bool {
        for (self.calls.items) |call| {
            switch (call) {
                .set_property => |set_property| {
                    if (set_property.id != id) continue;
                    if (!std.mem.eql(u8, set_property.property.name, name)) continue;
                    const value = set_property.property.get(T) orelse continue;
                    if (std.meta.eql(value, expected)) return true;
                },
                else => {},
            }
        }
        return false;
    }

    pub fn hasEventHandler(self: *const RecordingBackend, id: WidgetId, name: []const u8) bool {
        const widget = self.widgetConst(id) orelse return false;
        return widget.event(name) != null;
    }

    pub fn fireEvent(
        self: *const RecordingBackend,
        id: WidgetId,
        name: []const u8,
    ) error{ UnknownWidget, UnknownEvent }!void {
        const widget = self.widgetConst(id) orelse return error.UnknownWidget;
        const handler = widget.event(name) orelse return error.UnknownEvent;
        handler.invoke();
    }

    pub fn mountWidget(
        self: *RecordingBackend,
        parent: ?WidgetId,
        index: usize,
        kind: element.WidgetKind,
    ) anyerror!WidgetId {
        const id = self.next_id;
        self.next_id += 1;

        try self.widgets.append(self.allocator, .{
            .parent = parent,
            .kind = kind,
        });
        try self.insertChild(parent, index, id);
        try self.calls.append(self.allocator, .{
            .mount_widget = .{
                .parent = parent,
                .index = index,
                .kind = kind,
                .id = id,
            },
        });
        return id;
    }

    pub fn unmountWidget(self: *RecordingBackend, id: WidgetId) anyerror!void {
        const widget = self.widgetConst(id) orelse return error.UnknownWidget;
        try self.calls.append(self.allocator, .{ .unmount_widget = id });
        self.removeChild(widget.parent, id);
        self.destroyWidgetRecursive(id);
    }

    pub fn reorderChildren(
        self: *RecordingBackend,
        parent: ?WidgetId,
        children: []const WidgetId,
    ) anyerror!void {
        const list = try self.childListMut(parent);
        list.clearRetainingCapacity();
        try list.appendSlice(self.allocator, children);
        try self.calls.append(self.allocator, .{
            .reorder_children = .{
                .parent = parent,
                .children = try self.allocator.dupe(WidgetId, children),
            },
        });
    }

    pub fn setProperty(
        self: *RecordingBackend,
        id: WidgetId,
        property: *const element.Property,
    ) anyerror!void {
        const widget = self.widgetMut(id) orelse return error.UnknownWidget;
        const state_property = try property.clone(self.allocator);
        if (findPropertyIndex(widget.props.items, property.name)) |property_index| {
            widget.props.items[property_index].deinit(self.allocator);
            widget.props.items[property_index] = state_property;
        } else {
            try widget.props.append(self.allocator, state_property);
        }

        try self.calls.append(self.allocator, .{
            .set_property = .{
                .id = id,
                .property = try property.clone(self.allocator),
            },
        });
    }

    pub fn unsetProperty(self: *RecordingBackend, id: WidgetId, name: []const u8) anyerror!void {
        const widget = self.widgetMut(id) orelse return error.UnknownWidget;
        if (findPropertyIndex(widget.props.items, name)) |property_index| {
            var removed = widget.props.orderedRemove(property_index);
            removed.deinit(self.allocator);
        }

        try self.calls.append(self.allocator, .{
            .unset_property = .{
                .id = id,
                .name = try self.allocator.dupe(u8, name),
            },
        });
    }

    pub fn attachEvent(
        self: *RecordingBackend,
        id: WidgetId,
        handler: *const element.EventHandler,
    ) anyerror!void {
        const widget = self.widgetMut(id) orelse return error.UnknownWidget;
        const state_handler = try handler.clone(self.allocator);
        if (findEventIndex(widget.events.items, handler.name)) |event_index| {
            widget.events.items[event_index].deinit(self.allocator);
            widget.events.items[event_index] = state_handler;
        } else {
            try widget.events.append(self.allocator, state_handler);
        }

        try self.calls.append(self.allocator, .{
            .attach_event = .{
                .id = id,
                .handler = try handler.clone(self.allocator),
            },
        });
    }

    pub fn detachEvent(self: *RecordingBackend, id: WidgetId, name: []const u8) anyerror!void {
        const widget = self.widgetMut(id) orelse return error.UnknownWidget;
        if (findEventIndex(widget.events.items, name)) |event_index| {
            var removed = widget.events.orderedRemove(event_index);
            removed.deinit(self.allocator);
        }

        try self.calls.append(self.allocator, .{
            .detach_event = .{
                .id = id,
                .name = try self.allocator.dupe(u8, name),
            },
        });
    }

    fn widgetConst(self: *const RecordingBackend, id: WidgetId) ?*const WidgetState {
        if (id == 0 or id > self.widgets.items.len) return null;
        const slot = &self.widgets.items[id - 1];
        if (slot.*) |*widget| return widget;
        return null;
    }

    fn widgetMut(self: *RecordingBackend, id: WidgetId) ?*WidgetState {
        if (id == 0 or id > self.widgets.items.len) return null;
        const slot = &self.widgets.items[id - 1];
        if (slot.*) |*widget| return widget;
        return null;
    }

    fn childListMut(self: *RecordingBackend, parent: ?WidgetId) anyerror!*std.ArrayListUnmanaged(WidgetId) {
        if (parent) |parent_id| {
            const widget = self.widgetMut(parent_id) orelse return error.UnknownWidget;
            return &widget.children;
        }
        return &self.root_children;
    }

    fn insertChild(
        self: *RecordingBackend,
        parent: ?WidgetId,
        index: usize,
        id: WidgetId,
    ) anyerror!void {
        const list = try self.childListMut(parent);
        if (index > list.items.len) return error.InvalidChildIndex;
        try list.insert(self.allocator, index, id);
    }

    fn removeChild(self: *RecordingBackend, parent: ?WidgetId, id: WidgetId) void {
        if (parent) |parent_id| {
            if (self.widgetMut(parent_id)) |widget| {
                removeWidgetId(&widget.children, id);
            }
            return;
        }
        removeWidgetId(&self.root_children, id);
    }

    fn destroyWidgetRecursive(self: *RecordingBackend, id: WidgetId) void {
        const widget = self.widgetMut(id) orelse return;

        while (widget.children.items.len > 0) {
            const child_id = popWidgetId(&widget.children);
            self.destroyWidgetRecursive(child_id);
        }

        widget.deinit(self.allocator);
        self.widgets.items[id - 1] = null;
    }
};

fn popWidgetId(list: *std.ArrayListUnmanaged(WidgetId)) WidgetId {
    const last_index = list.items.len - 1;
    const id = list.items[last_index];
    list.items = list.items[0..last_index];
    return id;
}

fn removeWidgetId(list: *std.ArrayListUnmanaged(WidgetId), id: WidgetId) void {
    for (list.items, 0..) |existing, index| {
        if (existing == id) {
            _ = list.orderedRemove(index);
            return;
        }
    }
}

fn findPropertyIndex(properties: []const element.Property, name: []const u8) ?usize {
    for (properties, 0..) |property, index| {
        if (std.mem.eql(u8, property.name, name)) return index;
    }
    return null;
}

fn findEventIndex(events: []const element.EventHandler, name: []const u8) ?usize {
    for (events, 0..) |handler, index| {
        if (std.mem.eql(u8, handler.name, name)) return index;
    }
    return null;
}

test "RecordingBackend helpers reflect live widget state" {
    const Callbacks = struct {
        fn increment(raw: ?*anyopaque) void {
            const clicks: *u32 = @ptrCast(@alignCast(raw.?));
            clicks.* += 1;
        }
    };

    var backend_state = RecordingBackend.init(std.testing.allocator);
    defer backend_state.deinit();

    const root = try backend_state.mountWidget(null, 0, .container);
    const first = try backend_state.mountWidget(root, 0, .leaf);
    const second = try backend_state.mountWidget(root, 1, .leaf);

    var text = try element.Property.init(std.testing.allocator, "text", @as([]const u8, "hello"));
    defer text.deinit(std.testing.allocator);
    try backend_state.setProperty(first, &text);

    var clicks: u32 = 0;
    var click_handler = try element.EventHandler.init(
        std.testing.allocator,
        "click",
        element.EventCallback.init(@ptrCast(&clicks), Callbacks.increment),
    );
    defer click_handler.deinit(std.testing.allocator);
    try backend_state.attachEvent(second, &click_handler);

    try std.testing.expectEqual(@as(usize, 3), backend_state.mountCallCount());
    try std.testing.expect(backend_state.wasMounted(null, 0, .container));
    try std.testing.expectEqualSlices(WidgetId, &[_]WidgetId{ first, second }, backend_state.childrenOf(root));
    try std.testing.expectEqualStrings("hello", backend_state.propertyValue([]const u8, first, "text").?);
    try std.testing.expectEqual(@as(?WidgetId, second), backend_state.widgetIdAt(root, 1));
    try std.testing.expectEqual(@as(usize, 1), backend_state.activeEventCount());

    try backend_state.fireEvent(second, "click");
    try std.testing.expectEqual(@as(u32, 1), clicks);

    try backend_state.reorderChildren(root, &[_]WidgetId{ second, first });
    try std.testing.expectEqualSlices(WidgetId, &[_]WidgetId{ second, first }, backend_state.childrenOf(root));

    try backend_state.unmountWidget(root);
    try std.testing.expectEqual(@as(usize, 0), backend_state.liveWidgetCount());
    try std.testing.expectEqual(@as(usize, 0), backend_state.activeEventCount());
}
