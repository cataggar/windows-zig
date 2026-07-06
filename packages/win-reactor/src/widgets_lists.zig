const std = @import("std");
const win_collections = @import("win-collections");

const element = @import("element.zig");

pub const Allocator = element.Allocator;

pub fn observable_items_source(
    allocator: Allocator,
    values: anytype,
) win_collections.CollectionError!*win_collections.IObservableVector(ItemSourceElement(@TypeOf(values))) {
    const T = ItemSourceElement(@TypeOf(values));
    return win_collections.createObservableVector(T, allocator, itemSlice(values));
}

pub fn items_source(value: anytype) ?*const anyopaque {
    const T = @TypeOf(value);
    return switch (@typeInfo(T)) {
        .pointer => |info| blk: {
            comptime validateItemsSourcePointer(info.child, info.size);
            break :blk @as(?*const anyopaque, @ptrCast(value));
        },
        .optional => |info| switch (@typeInfo(info.child)) {
            .pointer => |child_info| blk: {
                comptime validateItemsSourcePointer(child_info.child, child_info.size);
                break :blk if (value) |ptr| @as(?*const anyopaque, @ptrCast(ptr)) else null;
            },
            else => @compileError("items_source expects a WinRT interface pointer or ?*const anyopaque"),
        },
        else => @compileError("items_source expects a WinRT interface pointer or ?*const anyopaque"),
    };
}

pub fn list_view(
    allocator: Allocator,
    children: anytype,
    on_selection_changed: ?element.EventCallback,
) element.Error!element.Element {
    var builder = element.list_view(allocator);
    defer builder.deinit();
    _ = try builder.childrenFrom(children);
    if (on_selection_changed) |callback| {
        _ = try builder.on("SelectionChanged", callback);
    }
    return builder.build();
}

pub fn list_view_from_source(
    allocator: Allocator,
    source: anytype,
    on_selection_changed: ?element.EventCallback,
) element.Error!element.Element {
    var builder = element.list_view(allocator);
    defer builder.deinit();
    _ = try builder.prop("ItemsSource", items_source(source));
    if (on_selection_changed) |callback| {
        _ = try builder.on("SelectionChanged", callback);
    }
    return builder.build();
}

pub fn items_repeater(allocator: Allocator, children: anytype) element.Error!element.Element {
    var builder = element.items_repeater(allocator);
    defer builder.deinit();
    _ = try builder.childrenFrom(children);
    return builder.build();
}

pub fn items_repeater_from_source(allocator: Allocator, source: anytype) element.Error!element.Element {
    var builder = element.items_repeater(allocator);
    defer builder.deinit();
    _ = try builder.prop("ItemsSource", items_source(source));
    return builder.build();
}

fn ItemSourceElement(comptime T: type) type {
    return switch (@typeInfo(T)) {
        .array => |info| info.child,
        .pointer => |info| blk: {
            if (info.size == .slice) break :blk info.child;
            if (info.size == .one and @typeInfo(info.child) == .@"struct" and @hasField(info.child, "items")) {
                break :blk @typeInfo(@FieldType(info.child, "items")).pointer.child;
            }
            @compileError("observable_items_source expects a slice, array, or *.items collection");
        },
        .@"struct" => blk: {
            if (@hasField(T, "items")) {
                break :blk @typeInfo(@FieldType(T, "items")).pointer.child;
            }
            @compileError("observable_items_source expects a slice, array, or .items collection");
        },
        else => @compileError("observable_items_source expects a slice, array, or .items collection"),
    };
}

fn itemSlice(values: anytype) []const ItemSourceElement(@TypeOf(values)) {
    const T = @TypeOf(values);
    return switch (@typeInfo(T)) {
        .array => values[0..],
        .pointer => |info| blk: {
            if (info.size == .slice) break :blk values;
            if (info.size == .one and @typeInfo(info.child) == .@"struct" and @hasField(info.child, "items")) {
                break :blk values.items;
            }
            @compileError("observable_items_source expects a slice, array, or *.items collection");
        },
        .@"struct" => blk: {
            if (@hasField(T, "items")) {
                break :blk values.items;
            }
            @compileError("observable_items_source expects a slice, array, or .items collection");
        },
        else => @compileError("observable_items_source expects a slice, array, or .items collection"),
    };
}

fn isAllowedItemsSourcePointer(comptime Child: type, comptime size: std.builtin.Type.Pointer.Size) bool {
    if (size != .one) return false;
    if (Child == anyopaque) return true;
    return canHaveDecls(Child) and @hasDecl(Child, "QueryInterface");
}

fn validateItemsSourcePointer(comptime Child: type, comptime size: std.builtin.Type.Pointer.Size) void {
    if (!isAllowedItemsSourcePointer(Child, size)) {
        @compileError("items_source expects a WinRT interface pointer or ?*const anyopaque");
    }
}

fn canHaveDecls(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"enum", .@"union", .@"opaque" => true,
        else => false,
    };
}

test "child-driven list helpers build keyed list widgets" {
    const Counter = struct {
        fn changed(raw: ?*anyopaque) void {
            const count: *usize = @ptrCast(@alignCast(raw.?));
            count.* += 1;
        }
    };

    var first_builder = element.leaf(std.testing.allocator);
    defer first_builder.deinit();
    var first = try first_builder.build();
    defer first.deinit(std.testing.allocator);
    var second_builder = element.leaf(std.testing.allocator);
    defer second_builder.deinit();
    var second = try second_builder.build();
    defer second.deinit(std.testing.allocator);

    var changes: usize = 0;
    var list = try list_view(
        std.testing.allocator,
        .{ &first, &second },
        element.EventCallback.init(@ptrCast(&changes), Counter.changed),
    );
    defer list.deinit(std.testing.allocator);

    try std.testing.expect(list == .widget);
    try std.testing.expectEqual(element.WidgetKind.list_view, list.widget.kind);
    try std.testing.expectEqual(@as(usize, 2), list.widget.children.len);
    list.widget.event("SelectionChanged").?.invoke();
    try std.testing.expectEqual(@as(usize, 1), changes);

    var third_builder = element.leaf(std.testing.allocator);
    defer third_builder.deinit();
    var third = try third_builder.build();
    defer third.deinit(std.testing.allocator);
    var fourth_builder = element.leaf(std.testing.allocator);
    defer fourth_builder.deinit();
    var fourth = try fourth_builder.build();
    defer fourth.deinit(std.testing.allocator);

    var repeater = try items_repeater(std.testing.allocator, .{ &third, &fourth });
    defer repeater.deinit(std.testing.allocator);

    try std.testing.expect(repeater == .widget);
    try std.testing.expectEqual(element.WidgetKind.items_repeater, repeater.widget.kind);
    try std.testing.expectEqual(@as(usize, 2), repeater.widget.children.len);
}

test "source-driven list helpers accept observable vectors from zig collections" {
    var array_list: std.ArrayList(i32) = try .initCapacity(std.testing.allocator, 0);
    defer array_list.deinit(std.testing.allocator);
    try array_list.append(std.testing.allocator, 1);
    try array_list.append(std.testing.allocator, 2);

    const source = try observable_items_source(std.testing.allocator, array_list);
    defer source.deinit();

    var list = try list_view_from_source(std.testing.allocator, source, null);
    defer list.deinit(std.testing.allocator);
    try std.testing.expectEqual(
        @as(?*const anyopaque, @ptrCast(source)),
        list.widget.propertyValue(?*const anyopaque, "ItemsSource").?,
    );

    var repeater = try items_repeater_from_source(std.testing.allocator, source);
    defer repeater.deinit(std.testing.allocator);
    try std.testing.expectEqual(
        @as(?*const anyopaque, @ptrCast(source)),
        repeater.widget.propertyValue(?*const anyopaque, "ItemsSource").?,
    );
}
