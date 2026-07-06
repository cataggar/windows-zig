const std = @import("std");

const element = @import("element.zig");
const widgets = @import("widgets.zig");
const xaml = @import("Microsoft.UI.Xaml");
const controls = @import("Microsoft.UI.Xaml.Controls");

pub const Allocator = element.Allocator;
pub const DefaultStackSpacing: f64 = widgets.DefaultStackSpacing;
pub const MaxGridTracks: usize = 16;

pub const GridUnit = enum {
    auto,
    pixel,
    star,
};

pub const GridTrack = struct {
    value: f64 = 1.0,
    unit: GridUnit = .star,

    pub fn auto() @This() {
        return .{
            .value = 1.0,
            .unit = .auto,
        };
    }

    pub fn pixels(value: f64) @This() {
        return .{
            .value = value,
            .unit = .pixel,
        };
    }

    pub fn star(value: f64) @This() {
        return .{
            .value = value,
            .unit = .star,
        };
    }

    pub fn toXaml(self: @This()) xaml.GridLength {
        const unit: xaml.GridUnitType = switch (self.unit) {
            .auto => .Auto,
            .pixel => .Pixel,
            .star => .Star,
        };
        return .{
            .Value = self.value,
            .GridUnitType = @intFromEnum(unit),
        };
    }
};

pub const GridTracks = struct {
    items: [MaxGridTracks]GridTrack = [_]GridTrack{.{ .value = 0, .unit = .pixel }} ** MaxGridTracks,
    len: u8 = 0,

    pub fn init(values: anytype) @This() {
        var tracks: @This() = .{};
        appendGridTracks(&tracks, values);
        return tracks;
    }

    pub fn slice(self: *const @This()) []const GridTrack {
        return self.items[0..self.len];
    }

    fn append(self: *@This(), track: GridTrack) void {
        const index: usize = self.len;
        std.debug.assert(index < MaxGridTracks);
        self.items[index] = track;
        self.len += 1;
    }
};

pub const Color = struct {
    a: u8 = 0xff,
    r: u8,
    g: u8,
    b: u8,

    pub fn rgb(r: u8, g: u8, b: u8) @This() {
        return .{
            .r = r,
            .g = g,
            .b = b,
        };
    }

    pub fn argb(a: u8, r: u8, g: u8, b: u8) @This() {
        return .{
            .a = a,
            .r = r,
            .g = g,
            .b = b,
        };
    }
};

pub const GridOptions = struct {
    row_definitions: ?GridTracks = null,
    column_definitions: ?GridTracks = null,
};

pub const BorderOptions = struct {
    border_thickness: ?xaml.Thickness = null,
    corner_radius: ?xaml.CornerRadius = null,
    background: ?Color = null,
};

pub fn uniform_thickness(all: f64) xaml.Thickness {
    return .{
        .Left = all,
        .Top = all,
        .Right = all,
        .Bottom = all,
    };
}

pub fn uniform_corner_radius(all: f64) xaml.CornerRadius {
    return .{
        .TopLeft = all,
        .TopRight = all,
        .BottomRight = all,
        .BottomLeft = all,
    };
}

pub fn vstack_spaced(allocator: Allocator, spacing: f64, children: anytype) element.Error!element.Element {
    return stackPanel(allocator, controls.Orientation.Vertical, spacing, children);
}

pub fn hstack_spaced(allocator: Allocator, spacing: f64, children: anytype) element.Error!element.Element {
    return stackPanel(allocator, controls.Orientation.Horizontal, spacing, children);
}

/// Grid child placement currently uses the raw builder escape hatch:
/// attach `Grid.Row`, `Grid.Column`, `Grid.RowSpan`, or `Grid.ColumnSpan`
/// via `.prop(...)` on the child widget builder.
pub fn grid(allocator: Allocator, options: GridOptions, children: anytype) element.Error!element.Element {
    var builder = element.grid(allocator);
    defer builder.deinit();
    if (options.row_definitions) |tracks| {
        _ = try builder.prop("RowDefinitions", tracks);
    }
    if (options.column_definitions) |tracks| {
        _ = try builder.prop("ColumnDefinitions", tracks);
    }
    _ = try builder.childrenFrom(children);
    return builder.build();
}

pub fn scroll_viewer(allocator: Allocator, child: anytype) element.Error!element.Element {
    var builder = element.scroll_viewer(allocator);
    defer builder.deinit();
    _ = try builder.child(child);
    return builder.build();
}

pub fn border(allocator: Allocator, options: BorderOptions, child: anytype) element.Error!element.Element {
    var builder = element.border(allocator);
    defer builder.deinit();
    if (options.border_thickness) |value| {
        _ = try builder.prop("BorderThickness", value);
    }
    if (options.corner_radius) |value| {
        _ = try builder.prop("CornerRadius", value);
    }
    if (options.background) |value| {
        _ = try builder.prop("Background", value);
    }
    _ = try builder.child(child);
    return builder.build();
}

fn stackPanel(
    allocator: Allocator,
    orientation: controls.Orientation,
    spacing: f64,
    children: anytype,
) element.Error!element.Element {
    var builder = element.stack_panel(allocator);
    defer builder.deinit();
    _ = try (try builder.prop("Orientation", orientation)).prop("Spacing", spacing);
    _ = try builder.childrenFrom(children);
    return builder.build();
}

fn appendGridTracks(list: *GridTracks, values: anytype) void {
    const T = @TypeOf(values);
    switch (@typeInfo(T)) {
        .@"struct" => |info| {
            if (info.is_tuple) {
                inline for (info.fields) |field| {
                    appendGridTracks(list, @field(values, field.name));
                }
                return;
            }
        },
        .array => {
            for (values) |value| {
                appendGridTracks(list, value);
            }
            return;
        },
        .pointer => |info| {
            if (info.size == .slice) {
                for (values) |value| {
                    appendGridTracks(list, value);
                }
                return;
            }
        },
        else => {},
    }

    list.append(coerceGridTrack(values));
}

fn coerceGridTrack(value: anytype) GridTrack {
    return switch (@TypeOf(value)) {
        GridTrack => value,
        else => @compileError("grid definitions must contain win-reactor GridTrack values"),
    };
}

test "grid helper stores manual row and column definitions" {
    const rows = GridTracks.init(.{
        GridTrack.auto(),
        GridTrack.star(1),
    });
    const columns = GridTracks.init(.{
        GridTrack.star(2),
        GridTrack.pixels(96),
    });

    var left = try widgets.text_block(std.testing.allocator, "left");
    defer left.deinit(std.testing.allocator);
    var right = try widgets.text_block(std.testing.allocator, "right");
    defer right.deinit(std.testing.allocator);

    var layout = try grid(
        std.testing.allocator,
        .{
            .row_definitions = rows,
            .column_definitions = columns,
        },
        .{ &left, &right },
    );
    defer layout.deinit(std.testing.allocator);

    try std.testing.expect(layout == .widget);
    try std.testing.expectEqual(element.WidgetKind.grid, layout.widget.kind);
    try std.testing.expectEqual(rows, layout.widget.propertyValue(GridTracks, "RowDefinitions").?);
    try std.testing.expectEqual(columns, layout.widget.propertyValue(GridTracks, "ColumnDefinitions").?);
    try std.testing.expectEqual(@as(usize, 2), layout.widget.children.len);
}

test "scroll viewer and border helpers create single-child layout widgets" {
    var content = try widgets.text_block(std.testing.allocator, "content");
    defer content.deinit(std.testing.allocator);

    const background = Color.rgb(0x20, 0x30, 0x40);
    const thickness = uniform_thickness(2);
    const radius = uniform_corner_radius(8);

    var bordered = try border(
        std.testing.allocator,
        .{
            .border_thickness = thickness,
            .corner_radius = radius,
            .background = background,
        },
        &content,
    );
    defer bordered.deinit(std.testing.allocator);

    try std.testing.expect(bordered == .widget);
    try std.testing.expectEqual(element.WidgetKind.border, bordered.widget.kind);
    try std.testing.expectEqual(thickness, bordered.widget.propertyValue(xaml.Thickness, "BorderThickness").?);
    try std.testing.expectEqual(radius, bordered.widget.propertyValue(xaml.CornerRadius, "CornerRadius").?);
    try std.testing.expectEqual(background, bordered.widget.propertyValue(Color, "Background").?);
    try std.testing.expectEqual(@as(usize, 1), bordered.widget.children.len);

    var scroller = try scroll_viewer(std.testing.allocator, &bordered);
    defer scroller.deinit(std.testing.allocator);

    try std.testing.expect(scroller == .widget);
    try std.testing.expectEqual(element.WidgetKind.scroll_viewer, scroller.widget.kind);
    try std.testing.expectEqual(@as(usize, 1), scroller.widget.children.len);
}

test "spaced stack helpers override the default spacing" {
    var top = try widgets.text_block(std.testing.allocator, "top");
    defer top.deinit(std.testing.allocator);
    var bottom = try widgets.text_block(std.testing.allocator, "bottom");
    defer bottom.deinit(std.testing.allocator);

    var vertical = try vstack_spaced(std.testing.allocator, 24, .{ &top, &bottom });
    defer vertical.deinit(std.testing.allocator);

    try std.testing.expect(vertical == .widget);
    try std.testing.expectEqual(element.WidgetKind.stack_panel, vertical.widget.kind);
    try std.testing.expectEqual(
        controls.Orientation.Vertical,
        vertical.widget.propertyValue(controls.Orientation, "Orientation").?,
    );
    try std.testing.expectEqual(@as(f64, 24), vertical.widget.propertyValue(f64, "Spacing").?);

    var left = try widgets.text_block(std.testing.allocator, "left");
    defer left.deinit(std.testing.allocator);
    var right = try widgets.text_block(std.testing.allocator, "right");
    defer right.deinit(std.testing.allocator);

    var horizontal = try hstack_spaced(std.testing.allocator, 6, .{ &left, &right });
    defer horizontal.deinit(std.testing.allocator);

    try std.testing.expect(horizontal == .widget);
    try std.testing.expectEqual(element.WidgetKind.stack_panel, horizontal.widget.kind);
    try std.testing.expectEqual(
        controls.Orientation.Horizontal,
        horizontal.widget.propertyValue(controls.Orientation, "Orientation").?,
    );
    try std.testing.expectEqual(@as(f64, 6), horizontal.widget.propertyValue(f64, "Spacing").?);
}
