const std = @import("std");

const element = @import("element.zig");
const controls = @import("Microsoft.UI.Xaml.Controls");

pub const Allocator = element.Allocator;
pub const DefaultStackSpacing: f64 = 12.0;

/// Minimal WinUI-backed widget helpers layered on top of the generic
/// `WidgetBuilder` API.
///
/// Convention for future widget batches:
/// - helpers take the allocator first and return a built `Element`;
/// - helpers write the exact generated property/event names (`Text`,
///   `Content`, `Click`, `Orientation`, `Spacing`);
/// - helpers stay intentionally small, while the raw `*_builder` exports remain
///   available for cases that need additional props or custom wiring;
/// - borrowed `[]const u8` values are stored by reference today, so dynamic
///   text should live in stable storage (for example an arena allocation or a
///   `useRef` buffer) for as long as the element tree may read it.
pub fn text_block(allocator: Allocator, text: []const u8) element.Error!element.Element {
    var builder = element.text_block(allocator);
    defer builder.deinit();
    _ = try builder.prop("Text", text);
    return builder.build();
}

pub fn button(
    allocator: Allocator,
    content: []const u8,
    on_click: ?element.EventCallback,
) element.Error!element.Element {
    var builder = element.button(allocator);
    defer builder.deinit();
    _ = try builder.prop("Content", content);
    if (on_click) |callback| {
        _ = try builder.on("Click", callback);
    }
    return builder.build();
}

pub fn vstack(allocator: Allocator, children: anytype) element.Error!element.Element {
    return stackPanel(allocator, controls.Orientation.Vertical, children);
}

pub fn hstack(allocator: Allocator, children: anytype) element.Error!element.Element {
    return stackPanel(allocator, controls.Orientation.Horizontal, children);
}

fn stackPanel(
    allocator: Allocator,
    orientation: controls.Orientation,
    children: anytype,
) element.Error!element.Element {
    var builder = element.stack_panel(allocator);
    defer builder.deinit();
    _ = try (try builder.prop("Orientation", orientation)).prop("Spacing", DefaultStackSpacing);
    _ = try builder.childrenFrom(children);
    return builder.build();
}

test "text_block and button helpers create manifest-backed widget elements" {
    const Counter = struct {
        fn increment(raw: ?*anyopaque) void {
            const value: *usize = @ptrCast(@alignCast(raw.?));
            value.* += 1;
        }
    };

    var clicks: usize = 0;
    var title = try text_block(std.testing.allocator, "Count: 0");
    defer title.deinit(std.testing.allocator);

    var increment_button = try button(
        std.testing.allocator,
        "Increment",
        element.EventCallback.init(@ptrCast(&clicks), Counter.increment),
    );
    defer increment_button.deinit(std.testing.allocator);

    try std.testing.expect(title == .widget);
    try std.testing.expectEqual(element.WidgetKind.text_block, title.widget.kind);
    try std.testing.expectEqualStrings("Count: 0", title.widget.propertyValue([]const u8, "Text").?);

    try std.testing.expect(increment_button == .widget);
    try std.testing.expectEqual(element.WidgetKind.button, increment_button.widget.kind);
    try std.testing.expectEqualStrings(
        "Increment",
        increment_button.widget.propertyValue([]const u8, "Content").?,
    );
    increment_button.widget.event("Click").?.invoke();
    try std.testing.expectEqual(@as(usize, 1), clicks);
}

test "vstack and hstack create oriented stack panels with children" {
    var top = try text_block(std.testing.allocator, "top");
    defer top.deinit(std.testing.allocator);
    var bottom = try text_block(std.testing.allocator, "bottom");
    defer bottom.deinit(std.testing.allocator);

    var vertical = try vstack(std.testing.allocator, .{ &top, &bottom });
    defer vertical.deinit(std.testing.allocator);

    try std.testing.expect(vertical == .widget);
    try std.testing.expectEqual(element.WidgetKind.stack_panel, vertical.widget.kind);
    try std.testing.expectEqual(
        controls.Orientation.Vertical,
        vertical.widget.propertyValue(controls.Orientation, "Orientation").?,
    );
    try std.testing.expectEqual(DefaultStackSpacing, vertical.widget.propertyValue(f64, "Spacing").?);
    try std.testing.expectEqual(@as(usize, 2), vertical.widget.children.len);

    var left = try text_block(std.testing.allocator, "left");
    defer left.deinit(std.testing.allocator);
    var right = try text_block(std.testing.allocator, "right");
    defer right.deinit(std.testing.allocator);

    var horizontal = try hstack(std.testing.allocator, .{ &left, &right });
    defer horizontal.deinit(std.testing.allocator);

    try std.testing.expect(horizontal == .widget);
    try std.testing.expectEqual(element.WidgetKind.stack_panel, horizontal.widget.kind);
    try std.testing.expectEqual(
        controls.Orientation.Horizontal,
        horizontal.widget.propertyValue(controls.Orientation, "Orientation").?,
    );
    try std.testing.expectEqual(DefaultStackSpacing, horizontal.widget.propertyValue(f64, "Spacing").?);
    try std.testing.expectEqual(@as(usize, 2), horizontal.widget.children.len);
}
