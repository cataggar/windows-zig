const std = @import("std");
const element = @import("element.zig");

pub const WidgetId = usize;

/// Abstract widget host that the reconciler drives. `mountWidget` inserts a
/// new widget at `index` under `parent` (`null` = root list), `unmountWidget`
/// removes that widget and destroys its whole descendant subtree, and
/// `reorderChildren` rewrites the direct child order under `parent` to exactly
/// match `children`.
pub const Backend = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        mount_widget: *const fn (
            ptr: *anyopaque,
            parent: ?WidgetId,
            index: usize,
            kind: element.WidgetKind,
        ) anyerror!WidgetId,
        unmount_widget: *const fn (ptr: *anyopaque, id: WidgetId) anyerror!void,
        reorder_children: *const fn (
            ptr: *anyopaque,
            parent: ?WidgetId,
            children: []const WidgetId,
        ) anyerror!void,
        set_property: *const fn (
            ptr: *anyopaque,
            id: WidgetId,
            property: *const element.Property,
        ) anyerror!void,
        unset_property: *const fn (
            ptr: *anyopaque,
            id: WidgetId,
            name: []const u8,
        ) anyerror!void,
        attach_event: *const fn (
            ptr: *anyopaque,
            id: WidgetId,
            handler: *const element.EventHandler,
        ) anyerror!void,
        detach_event: *const fn (
            ptr: *anyopaque,
            id: WidgetId,
            name: []const u8,
        ) anyerror!void,
    };

    pub fn init(ptr: *anyopaque, vtable: *const VTable) Backend {
        return .{
            .ptr = ptr,
            .vtable = vtable,
        };
    }

    /// Build a `Backend` from a concrete `*T`. `T` must expose `pub` methods
    /// named:
    /// `mountWidget`, `unmountWidget`, `reorderChildren`, `setProperty`,
    /// `unsetProperty`, `attachEvent`, and `detachEvent`.
    pub fn from(implementation: anytype) Backend {
        const Ptr = @TypeOf(implementation);
        const ptr_info = @typeInfo(Ptr);
        if (ptr_info != .pointer or ptr_info.pointer.size != .one) {
            @compileError("Backend.from expects a single-item pointer");
        }

        const T = ptr_info.pointer.child;
        return .{
            .ptr = @ptrCast(implementation),
            .vtable = &struct {
                fn selfFrom(raw: *anyopaque) *T {
                    return @ptrCast(@alignCast(raw));
                }

                fn mountWidgetThunk(
                    raw: *anyopaque,
                    parent: ?WidgetId,
                    index: usize,
                    kind: element.WidgetKind,
                ) anyerror!WidgetId {
                    return selfFrom(raw).mountWidget(parent, index, kind);
                }

                fn unmountWidgetThunk(raw: *anyopaque, id: WidgetId) anyerror!void {
                    return selfFrom(raw).unmountWidget(id);
                }

                fn reorderChildrenThunk(
                    raw: *anyopaque,
                    parent: ?WidgetId,
                    children: []const WidgetId,
                ) anyerror!void {
                    return selfFrom(raw).reorderChildren(parent, children);
                }

                fn setPropertyThunk(
                    raw: *anyopaque,
                    id: WidgetId,
                    property: *const element.Property,
                ) anyerror!void {
                    return selfFrom(raw).setProperty(id, property);
                }

                fn unsetPropertyThunk(
                    raw: *anyopaque,
                    id: WidgetId,
                    name: []const u8,
                ) anyerror!void {
                    return selfFrom(raw).unsetProperty(id, name);
                }

                fn attachEventThunk(
                    raw: *anyopaque,
                    id: WidgetId,
                    handler: *const element.EventHandler,
                ) anyerror!void {
                    return selfFrom(raw).attachEvent(id, handler);
                }

                fn detachEventThunk(
                    raw: *anyopaque,
                    id: WidgetId,
                    name: []const u8,
                ) anyerror!void {
                    return selfFrom(raw).detachEvent(id, name);
                }

                const value = VTable{
                    .mount_widget = mountWidgetThunk,
                    .unmount_widget = unmountWidgetThunk,
                    .reorder_children = reorderChildrenThunk,
                    .set_property = setPropertyThunk,
                    .unset_property = unsetPropertyThunk,
                    .attach_event = attachEventThunk,
                    .detach_event = detachEventThunk,
                };
            }.value,
        };
    }

    pub fn mountWidget(
        self: Backend,
        parent: ?WidgetId,
        index: usize,
        kind: element.WidgetKind,
    ) anyerror!WidgetId {
        return self.vtable.mount_widget(self.ptr, parent, index, kind);
    }

    pub fn unmountWidget(self: Backend, id: WidgetId) anyerror!void {
        return self.vtable.unmount_widget(self.ptr, id);
    }

    pub fn reorderChildren(
        self: Backend,
        parent: ?WidgetId,
        children: []const WidgetId,
    ) anyerror!void {
        return self.vtable.reorder_children(self.ptr, parent, children);
    }

    pub fn setProperty(
        self: Backend,
        id: WidgetId,
        property: *const element.Property,
    ) anyerror!void {
        return self.vtable.set_property(self.ptr, id, property);
    }

    pub fn unsetProperty(self: Backend, id: WidgetId, name: []const u8) anyerror!void {
        return self.vtable.unset_property(self.ptr, id, name);
    }

    pub fn attachEvent(
        self: Backend,
        id: WidgetId,
        handler: *const element.EventHandler,
    ) anyerror!void {
        return self.vtable.attach_event(self.ptr, id, handler);
    }

    pub fn detachEvent(self: Backend, id: WidgetId, name: []const u8) anyerror!void {
        return self.vtable.detach_event(self.ptr, id, name);
    }
};
