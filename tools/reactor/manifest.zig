//! Typed loader and lookup helpers for the reactor widget manifest.

const std = @import("std");

const schema = @import("schema.zig");

pub const AttachedPropertyInit = schema.AttachedPropertyInit;
pub const Event = schema.Event;
pub const EventInit = schema.EventInit;
pub const EventPayload = schema.EventPayload;
pub const EventSource = schema.EventSource;
pub const PropInit = schema.PropInit;
pub const Property = schema.Property;
pub const SetterKind = schema.SetterKind;
pub const ValueKind = schema.ValueKind;
pub const Widget = schema.Widget;
pub const WidgetMetaInit = schema.WidgetMetaInit;

pub const raw_widgets = @import("widget_manifest.zig").raw_widgets;

pub const Manifest = struct {
    arena: std.heap.ArenaAllocator,
    widgets: []Widget,

    pub fn deinit(self: *Manifest) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

pub fn load(allocator: std.mem.Allocator) !Manifest {
    return loadFromRaw(allocator, raw_widgets);
}

pub fn loadFromRaw(allocator: std.mem.Allocator, comptime raw: anytype) !Manifest {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const a = arena.allocator();

    const fields = std.meta.fields(@TypeOf(raw));
    const widgets = try a.alloc(Widget, fields.len);
    var initialized: usize = 0;

    inline for (fields) |field| {
        const class_name = field.name;
        const section = @field(raw, class_name);
        validateWidgetSection(@TypeOf(section), class_name);
        const split = splitClassName(class_name);
        const meta = if (@hasField(@TypeOf(section), "meta"))
            @field(section, "meta")
        else
            schema.WidgetMetaInit{};
        const props = if (@hasField(@TypeOf(section), "props"))
            try loadProps(a, @field(section, "props"))
        else
            try loadProps(a, .{});
        const events = if (@hasField(@TypeOf(section), "events"))
            try loadEvents(a, @field(section, "events"))
        else
            try loadEvents(a, .{});

        widgets[initialized] = .{
            .class_name = class_name,
            .namespace = split.namespace,
            .short_name = split.short_name,
            .widget_name = meta.widget_name orelse split.short_name,
            .handle_name = meta.handle_name orelse split.short_name,
            .props = props,
            .events = events,
        };
        initialized += 1;
    }

    return .{
        .arena = arena,
        .widgets = widgets,
    };
}

pub fn findWidget(widgets: []const Widget, class_name: []const u8) ?*const Widget {
    for (widgets) |*widget| {
        if (std.mem.eql(u8, widget.class_name, class_name)) {
            return widget;
        }
    }
    return null;
}

pub fn findProp(widget: *const Widget, name: []const u8) ?*const Property {
    for (widget.props) |*prop| {
        if (std.mem.eql(u8, prop.name, name)) {
            return prop;
        }
    }
    return null;
}

pub fn findEvent(widget: *const Widget, name: []const u8) ?*const Event {
    for (widget.events) |*event| {
        if (std.mem.eql(u8, event.name, name)) {
            return event;
        }
    }
    return null;
}

fn loadProps(allocator: std.mem.Allocator, comptime raw: anytype) ![]Property {
    const fields = std.meta.fields(@TypeOf(raw));
    const out = try allocator.alloc(Property, fields.len);

    inline for (fields, 0..) |field, i| {
        const init: schema.PropInit = @field(raw, field.name);
        out[i] = .{
            .name = field.name,
            .winrt_name = init.winrt_name orelse field.name,
            .field = if (init.field) |name|
                name
            else
                try snakeCaseAlloc(allocator, field.name),
            .value = init.value,
            .setter = if (init.attached != null and init.setter == null)
                .attached
            else
                init.setter,
            .winrt_type = init.winrt_type,
            .attached = init.attached,
            .manual = init.manual,
        };
    }

    return out;
}

fn loadEvents(allocator: std.mem.Allocator, comptime raw: anytype) ![]Event {
    const fields = std.meta.fields(@TypeOf(raw));
    const out = try allocator.alloc(Event, fields.len);

    inline for (fields, 0..) |field, i| {
        const init: schema.EventInit = @field(raw, field.name);
        out[i] = .{
            .name = field.name,
            .winrt_name = init.winrt_name orelse field.name,
            .field = if (init.field) |name|
                name
            else
                try eventFieldNameAlloc(allocator, field.name),
            .delegate = init.delegate,
            .payload = init.payload,
            .source = init.source orelse .none,
            .manual = init.manual,
        };
    }

    return out;
}

fn validateWidgetSection(comptime T: type, comptime class_name: []const u8) void {
    inline for (std.meta.fields(T)) |field| {
        comptime {
            if (!std.mem.eql(u8, field.name, "meta") and
                !std.mem.eql(u8, field.name, "props") and
                !std.mem.eql(u8, field.name, "events"))
            {
                @compileError(std.fmt.comptimePrint(
                    "widget manifest section '{s}' contains unknown key '{s}' (expected meta, props, or events)",
                    .{ class_name, field.name },
                ));
            }
        }
    }
}

fn splitClassName(class_name: []const u8) struct {
    namespace: []const u8,
    short_name: []const u8,
} {
    const index = std.mem.lastIndexOfScalar(u8, class_name, '.') orelse unreachable;

    return .{
        .namespace = class_name[0..index],
        .short_name = class_name[index + 1 ..],
    };
}

fn snakeCaseAlloc(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    const buf = try allocator.alloc(u8, name.len * 2);
    var out_len: usize = 0;

    for (name, 0..) |ch, i| {
        if (std.ascii.isUpper(ch) and i > 0) {
            buf[out_len] = '_';
            out_len += 1;
        }

        buf[out_len] = std.ascii.toLower(ch);
        out_len += 1;
    }

    return buf[0..out_len];
}

fn eventFieldNameAlloc(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    const buf = try allocator.alloc(u8, name.len * 2 + 3);
    buf[0] = 'o';
    buf[1] = 'n';
    buf[2] = '_';
    var out_len: usize = 3;

    for (name, 0..) |ch, i| {
        if (std.ascii.isUpper(ch) and i > 0) {
            buf[out_len] = '_';
            out_len += 1;
        }

        buf[out_len] = std.ascii.toLower(ch);
        out_len += 1;
    }

    return buf[0..out_len];
}

test "production manifest covers the committed widget set" {
    var manifest = try load(std.testing.allocator);
    defer manifest.deinit();

    try std.testing.expectEqual(@as(usize, 23), manifest.widgets.len);

    const application = findWidget(manifest.widgets, "Microsoft.UI.Xaml.Application") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 0), application.props.len);
    try std.testing.expectEqual(@as(usize, 0), application.events.len);

    const window = findWidget(manifest.widgets, "Microsoft.UI.Xaml.Window") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("Microsoft.UI.Xaml", window.namespace);
    try std.testing.expectEqualStrings("Window", window.short_name);
    const title = findProp(window, "Title") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("title", title.field);
    try std.testing.expect(title.value.? == .string);

    const text_block = findWidget(manifest.widgets, "Microsoft.UI.Xaml.Controls.TextBlock") orelse return error.TestUnexpectedResult;
    const text = findProp(text_block, "Text") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("text", text.field);
    try std.testing.expect(text.value.? == .string);
    const text_block_left = findProp(text_block, "Left") orelse return error.TestUnexpectedResult;
    try std.testing.expect(text_block_left.setter.? == .attached);

    const text_box = findWidget(manifest.widgets, "Microsoft.UI.Xaml.Controls.TextBox") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 8), text_box.props.len);
    try std.testing.expectEqual(@as(usize, 4), text_box.events.len);
    const text_box_text = findProp(text_box, "Text") orelse return error.TestUnexpectedResult;
    try std.testing.expect(text_box_text.value.? == .string);
    const text_changed = findEvent(text_box, "TextChanged") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("on_text_changed", text_changed.field);
    try std.testing.expect(text_changed.payload.? == .string);
    switch (text_changed.source) {
        .sender_property => |name| try std.testing.expectEqualStrings("Text", name),
        else => return error.TestUnexpectedResult,
    }
    const text_box_pointer_moved = findEvent(text_box, "PointerMoved") orelse return error.TestUnexpectedResult;
    try std.testing.expect(text_box_pointer_moved.payload.? == .pointer);

    const check_box = findWidget(manifest.widgets, "Microsoft.UI.Xaml.Controls.CheckBox") orelse return error.TestUnexpectedResult;
    const is_checked = findProp(check_box, "IsChecked") orelse return error.TestUnexpectedResult;
    try std.testing.expect(is_checked.value.? == .bool);
    try std.testing.expect(is_checked.setter.? == .boxed_reference);
    const unchecked = findEvent(check_box, "Unchecked") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("on_unchecked", unchecked.field);
    try std.testing.expect(unchecked.payload.? == .unit);

    const slider = findWidget(manifest.widgets, "Microsoft.UI.Xaml.Controls.Slider") orelse return error.TestUnexpectedResult;
    const value = findProp(slider, "Value") orelse return error.TestUnexpectedResult;
    try std.testing.expect(value.value.? == .f64);
    const value_changed = findEvent(slider, "ValueChanged") orelse return error.TestUnexpectedResult;
    switch (value_changed.source) {
        .args_property => |name| try std.testing.expectEqualStrings("NewValue", name),
        else => return error.TestUnexpectedResult,
    }

    const combo_box = findWidget(manifest.widgets, "Microsoft.UI.Xaml.Controls.ComboBox") orelse return error.TestUnexpectedResult;
    const items_source = findProp(combo_box, "ItemsSource") orelse return error.TestUnexpectedResult;
    try std.testing.expect(items_source.value.? == .string_list);
    const selected_index = findProp(combo_box, "SelectedIndex") orelse return error.TestUnexpectedResult;
    try std.testing.expect(selected_index.value.? == .i32);

    const toggle_switch = findWidget(manifest.widgets, "Microsoft.UI.Xaml.Controls.ToggleSwitch") orelse return error.TestUnexpectedResult;
    const is_on = findProp(toggle_switch, "IsOn") orelse return error.TestUnexpectedResult;
    try std.testing.expect(is_on.value.? == .bool);
    const toggled = findEvent(toggle_switch, "Toggled") orelse return error.TestUnexpectedResult;
    switch (toggled.source) {
        .sender_property => |name| try std.testing.expectEqualStrings("IsOn", name),
        else => return error.TestUnexpectedResult,
    }

    const radio_button = findWidget(manifest.widgets, "Microsoft.UI.Xaml.Controls.RadioButton") orelse return error.TestUnexpectedResult;
    const radio_checked = findProp(radio_button, "IsChecked") orelse return error.TestUnexpectedResult;
    try std.testing.expect(radio_checked.value.? == .bool);
    try std.testing.expect(radio_checked.setter.? == .boxed_reference);

    const button = findWidget(manifest.widgets, "Microsoft.UI.Xaml.Controls.Button") orelse return error.TestUnexpectedResult;
    const content = findProp(button, "Content") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("content", content.field);
    try std.testing.expect(content.value.? == .string);
    try std.testing.expect(content.setter.? == .text_block);
    const click = findEvent(button, "Click") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("on_click", click.field);
    try std.testing.expect(click.payload.? == .unit);
    switch (click.source) {
        .none => {},
        else => return error.TestUnexpectedResult,
    }
    const pointer_pressed = findEvent(button, "PointerPressed") orelse return error.TestUnexpectedResult;
    try std.testing.expect(pointer_pressed.payload.? == .pointer);

    const stack_panel = findWidget(manifest.widgets, "Microsoft.UI.Xaml.Controls.StackPanel") orelse return error.TestUnexpectedResult;
    const orientation = findProp(stack_panel, "Orientation") orelse return error.TestUnexpectedResult;
    try std.testing.expect(orientation.value.? == .enum_i32);
    const spacing = findProp(stack_panel, "Spacing") orelse return error.TestUnexpectedResult;
    try std.testing.expect(spacing.value.? == .f64);
    const stack_left = findProp(stack_panel, "Left") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("Microsoft.UI.Xaml.Controls.Canvas", stack_left.attached.?.owner);

    const canvas = findWidget(manifest.widgets, "Microsoft.UI.Xaml.Controls.Canvas") orelse return error.TestUnexpectedResult;
    const canvas_top = findProp(canvas, "Top") orelse return error.TestUnexpectedResult;
    try std.testing.expect(canvas_top.value.? == .f64);
    const canvas_z = findProp(canvas, "ZIndex") orelse return error.TestUnexpectedResult;
    try std.testing.expect(canvas_z.value.? == .i32);
    const canvas_pointer_released = findEvent(canvas, "PointerReleased") orelse return error.TestUnexpectedResult;
    try std.testing.expect(canvas_pointer_released.payload.? == .pointer);
    const grid = findWidget(manifest.widgets, "Microsoft.UI.Xaml.Controls.Grid") orelse return error.TestUnexpectedResult;
    const row_definitions = findProp(grid, "RowDefinitions") orelse return error.TestUnexpectedResult;
    try std.testing.expect(row_definitions.manual);
    const column_definitions = findProp(grid, "ColumnDefinitions") orelse return error.TestUnexpectedResult;
    try std.testing.expect(column_definitions.manual);
    const grid_row = findProp(grid, "Grid.Row") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("Row", grid_row.winrt_name);
    try std.testing.expectEqualStrings("grid_row", grid_row.field);
    try std.testing.expect(grid_row.setter.? == .attached);
    try std.testing.expectEqualStrings("Microsoft.UI.Xaml.Controls.Grid", grid_row.attached.?.owner);
    try std.testing.expectEqualStrings("SetRow", grid_row.attached.?.setter);
    const grid_column_span = findProp(grid, "Grid.ColumnSpan") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("ColumnSpan", grid_column_span.winrt_name);
    try std.testing.expectEqualStrings("grid_column_span", grid_column_span.field);
    try std.testing.expect(grid_column_span.value.? == .i32);

    const scroll_viewer = findWidget(manifest.widgets, "Microsoft.UI.Xaml.Controls.ScrollViewer") orelse return error.TestUnexpectedResult;
    const content_prop = findProp(scroll_viewer, "Content") orelse return error.TestUnexpectedResult;
    try std.testing.expect(content_prop.value.? == .element);

    const border = findWidget(manifest.widgets, "Microsoft.UI.Xaml.Controls.Border") orelse return error.TestUnexpectedResult;
    const child = findProp(border, "Child") orelse return error.TestUnexpectedResult;
    try std.testing.expect(child.value.? == .element);
    try std.testing.expect((findProp(border, "BorderThickness") orelse return error.TestUnexpectedResult).manual);
    try std.testing.expect((findProp(border, "CornerRadius") orelse return error.TestUnexpectedResult).manual);
    try std.testing.expect((findProp(border, "Background") orelse return error.TestUnexpectedResult).manual);

    const content_dialog = findWidget(manifest.widgets, "Microsoft.UI.Xaml.Controls.ContentDialog") orelse return error.TestUnexpectedResult;
    const title_prop = findProp(content_dialog, "Title") orelse return error.TestUnexpectedResult;
    try std.testing.expect(title_prop.value.? == .string);
    try std.testing.expect(title_prop.setter.? == .text_block);
    const primary_button_text = findProp(content_dialog, "PrimaryButtonText") orelse return error.TestUnexpectedResult;
    try std.testing.expect(primary_button_text.value.? == .string);

    const flyout = findWidget(manifest.widgets, "Microsoft.UI.Xaml.Controls.Flyout") orelse return error.TestUnexpectedResult;
    const flyout_content = findProp(flyout, "Content") orelse return error.TestUnexpectedResult;
    try std.testing.expect(flyout_content.value.? == .element);

    const navigation_view = findWidget(manifest.widgets, "Microsoft.UI.Xaml.Controls.NavigationView") orelse return error.TestUnexpectedResult;
    const navigation_view_content = findProp(navigation_view, "Content") orelse return error.TestUnexpectedResult;
    try std.testing.expect(navigation_view_content.value.? == .element);

    const navigation_view_item = findWidget(manifest.widgets, "Microsoft.UI.Xaml.Controls.NavigationViewItem") orelse return error.TestUnexpectedResult;
    const navigation_item_content = findProp(navigation_view_item, "Content") orelse return error.TestUnexpectedResult;
    try std.testing.expect(navigation_item_content.value.? == .string);
    try std.testing.expect(navigation_item_content.setter.? == .text_block);

    const menu_bar_item = findWidget(manifest.widgets, "Microsoft.UI.Xaml.Controls.MenuBarItem") orelse return error.TestUnexpectedResult;
    const menu_bar_title = findProp(menu_bar_item, "Title") orelse return error.TestUnexpectedResult;
    try std.testing.expect(menu_bar_title.value.? == .string);

    const list_view = findWidget(manifest.widgets, "Microsoft.UI.Xaml.Controls.ListView") orelse return error.TestUnexpectedResult;
    const list_view_items_source = findProp(list_view, "ItemsSource") orelse return error.TestUnexpectedResult;
    try std.testing.expect(list_view_items_source.value.? == .object);
    const selection_changed = findEvent(list_view, "SelectionChanged") orelse return error.TestUnexpectedResult;
    try std.testing.expect(selection_changed.payload.? == .unit);

    const items_repeater = findWidget(manifest.widgets, "Microsoft.UI.Xaml.Controls.ItemsRepeater") orelse return error.TestUnexpectedResult;
    const repeater_items_source = findProp(items_repeater, "ItemsSource") orelse return error.TestUnexpectedResult;
    try std.testing.expect(repeater_items_source.value.? == .object);
}

test "loader derives defaults and preserves advanced overrides" {
    const fixture = .{
        .@"Microsoft.UI.Xaml.Controls.ToggleSwitch" = .{
            .meta = schema.WidgetMetaInit{
                .widget_name = "SwitchWidget",
            },
            .props = .{
                .IsOn = schema.PropInit{
                    .value = .bool,
                },
                .Row = schema.PropInit{
                    .value = .i32,
                    .attached = .{
                        .owner = "Microsoft.UI.Xaml.Controls.Grid",
                        .setter = "SetRow",
                    },
                    .manual = true,
                },
            },
            .events = .{
                .Toggled = schema.EventInit{
                    .payload = .bool,
                    .source = .{
                        .sender_property = "IsOn",
                    },
                },
                .Checked = schema.EventInit{
                    .source = .{
                        .paired_bool = "Unchecked",
                    },
                },
            },
        },
    };

    var loaded = try loadFromRaw(std.testing.allocator, fixture);
    defer loaded.deinit();
    try std.testing.expectEqual(@as(usize, 1), loaded.widgets.len);

    const widget = &loaded.widgets[0];
    try std.testing.expectEqualStrings("Microsoft.UI.Xaml.Controls", widget.namespace);
    try std.testing.expectEqualStrings("ToggleSwitch", widget.short_name);
    try std.testing.expectEqualStrings("SwitchWidget", widget.widget_name);
    try std.testing.expectEqualStrings("ToggleSwitch", widget.handle_name);

    const is_on = &widget.props[0];
    try std.testing.expectEqualStrings("is_on", is_on.field);
    try std.testing.expect(is_on.value.? == .bool);

    const row = &widget.props[1];
    try std.testing.expectEqualStrings("row", row.field);
    try std.testing.expect(row.setter.? == .attached);
    try std.testing.expectEqualStrings("Microsoft.UI.Xaml.Controls.Grid", row.attached.?.owner);
    try std.testing.expectEqualStrings("SetRow", row.attached.?.setter);
    try std.testing.expect(row.manual);

    const toggled = &widget.events[0];
    try std.testing.expectEqualStrings("on_toggled", toggled.field);
    try std.testing.expect(toggled.payload.? == .bool);
    switch (toggled.source) {
        .sender_property => |name| try std.testing.expectEqualStrings("IsOn", name),
        else => return error.TestUnexpectedResult,
    }

    const checked = &widget.events[1];
    try std.testing.expectEqualStrings("on_checked", checked.field);
    switch (checked.source) {
        .paired_bool => |name| try std.testing.expectEqualStrings("Unchecked", name),
        else => return error.TestUnexpectedResult,
    }
}

test "loader preserves owner-qualified attached property overrides" {
    const fixture = .{
        .@"Microsoft.UI.Xaml.Controls.Button" = .{
            .props = .{
                .@"Grid.Row" = schema.PropInit{
                    .winrt_name = "Row",
                    .field = "grid_row",
                    .value = .i32,
                    .attached = .{
                        .owner = "Microsoft.UI.Xaml.Controls.Grid",
                        .setter = "SetRow",
                    },
                },
            },
        },
    };

    var loaded = try loadFromRaw(std.testing.allocator, fixture);
    defer loaded.deinit();

    const widget = findWidget(loaded.widgets, "Microsoft.UI.Xaml.Controls.Button") orelse return error.TestUnexpectedResult;
    const row = findProp(widget, "Grid.Row") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("Grid.Row", row.name);
    try std.testing.expectEqualStrings("Row", row.winrt_name);
    try std.testing.expectEqualStrings("grid_row", row.field);
    try std.testing.expect(row.setter.? == .attached);
    try std.testing.expectEqualStrings("Microsoft.UI.Xaml.Controls.Grid", row.attached.?.owner);
    try std.testing.expectEqualStrings("SetRow", row.attached.?.setter);
}
