const std = @import("std");

const element = @import("element.zig");

pub const Allocator = element.Allocator;

pub fn text_box(
    allocator: Allocator,
    text: []const u8,
    on_text_changed: ?element.EventCallback,
) element.Error!element.Element {
    var builder = element.text_box(allocator);
    defer builder.deinit();
    _ = try builder.prop("Text", text);
    if (on_text_changed) |callback| {
        _ = try builder.on("TextChanged", callback);
    }
    return builder.build();
}

pub fn check_box(
    allocator: Allocator,
    content: []const u8,
    is_checked: bool,
    on_checked: ?element.EventCallback,
    on_unchecked: ?element.EventCallback,
) element.Error!element.Element {
    var builder = element.check_box(allocator);
    defer builder.deinit();
    _ = try (try builder.prop("Content", content)).prop("IsChecked", is_checked);
    if (on_checked) |callback| {
        _ = try builder.on("Checked", callback);
    }
    if (on_unchecked) |callback| {
        _ = try builder.on("Unchecked", callback);
    }
    return builder.build();
}

pub fn slider(
    allocator: Allocator,
    value: f64,
    minimum: f64,
    maximum: f64,
    on_value_changed: ?element.EventCallback,
) element.Error!element.Element {
    var builder = element.slider(allocator);
    defer builder.deinit();
    _ = try (try (try builder.prop("Value", value)).prop("Minimum", minimum)).prop("Maximum", maximum);
    if (on_value_changed) |callback| {
        _ = try builder.on("ValueChanged", callback);
    }
    return builder.build();
}

pub fn combo_box(
    allocator: Allocator,
    items: []const []const u8,
    selected_index: i32,
    on_selection_changed: ?element.EventCallback,
) element.Error!element.Element {
    var builder = element.combo_box(allocator);
    defer builder.deinit();
    _ = try (try builder.prop("ItemsSource", items)).prop("SelectedIndex", selected_index);
    if (on_selection_changed) |callback| {
        _ = try builder.on("SelectionChanged", callback);
    }
    return builder.build();
}

pub fn toggle_switch(
    allocator: Allocator,
    is_on: bool,
    on_toggled: ?element.EventCallback,
) element.Error!element.Element {
    var builder = element.toggle_switch(allocator);
    defer builder.deinit();
    _ = try builder.prop("IsOn", is_on);
    if (on_toggled) |callback| {
        _ = try builder.on("Toggled", callback);
    }
    return builder.build();
}

pub fn radio_button(
    allocator: Allocator,
    content: []const u8,
    is_checked: bool,
    on_checked: ?element.EventCallback,
) element.Error!element.Element {
    var builder = element.radio_button(allocator);
    defer builder.deinit();
    _ = try (try builder.prop("Content", content)).prop("IsChecked", is_checked);
    if (on_checked) |callback| {
        _ = try builder.on("Checked", callback);
    }
    return builder.build();
}

test "text input helpers create manifest-backed input widget elements" {
    const EventCounters = struct {
        text_changed: usize = 0,
        checked: usize = 0,
        unchecked: usize = 0,
        slider_changed: usize = 0,
        selection_changed: usize = 0,
        toggled: usize = 0,
        radio_checked: usize = 0,

        fn bumpTextChanged(raw: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.text_changed += 1;
        }

        fn bumpChecked(raw: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.checked += 1;
        }

        fn bumpUnchecked(raw: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.unchecked += 1;
        }

        fn bumpSliderChanged(raw: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.slider_changed += 1;
        }

        fn bumpSelectionChanged(raw: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.selection_changed += 1;
        }

        fn bumpToggled(raw: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.toggled += 1;
        }

        fn bumpRadioChecked(raw: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.radio_checked += 1;
        }
    };

    var counters: EventCounters = .{};
    const items = [_][]const u8{ "Alpha", "Beta", "Gamma" };

    var name = try text_box(
        std.testing.allocator,
        "Hello",
        element.EventCallback.init(@ptrCast(&counters), EventCounters.bumpTextChanged),
    );
    defer name.deinit(std.testing.allocator);

    var accepted = try check_box(
        std.testing.allocator,
        "Accepted",
        true,
        element.EventCallback.init(@ptrCast(&counters), EventCounters.bumpChecked),
        element.EventCallback.init(@ptrCast(&counters), EventCounters.bumpUnchecked),
    );
    defer accepted.deinit(std.testing.allocator);

    var amount = try slider(
        std.testing.allocator,
        25.0,
        0.0,
        100.0,
        element.EventCallback.init(@ptrCast(&counters), EventCounters.bumpSliderChanged),
    );
    defer amount.deinit(std.testing.allocator);

    var picker = try combo_box(
        std.testing.allocator,
        items[0..],
        1,
        element.EventCallback.init(@ptrCast(&counters), EventCounters.bumpSelectionChanged),
    );
    defer picker.deinit(std.testing.allocator);

    var enabled = try toggle_switch(
        std.testing.allocator,
        true,
        element.EventCallback.init(@ptrCast(&counters), EventCounters.bumpToggled),
    );
    defer enabled.deinit(std.testing.allocator);

    var mode = try radio_button(
        std.testing.allocator,
        "Advanced",
        false,
        element.EventCallback.init(@ptrCast(&counters), EventCounters.bumpRadioChecked),
    );
    defer mode.deinit(std.testing.allocator);

    try std.testing.expectEqual(element.WidgetKind.text_box, name.widget.kind);
    try std.testing.expectEqualStrings("Hello", name.widget.propertyValue([]const u8, "Text").?);
    name.widget.event("TextChanged").?.invoke();
    try std.testing.expectEqual(@as(usize, 1), counters.text_changed);

    try std.testing.expectEqual(element.WidgetKind.check_box, accepted.widget.kind);
    try std.testing.expectEqualStrings("Accepted", accepted.widget.propertyValue([]const u8, "Content").?);
    try std.testing.expectEqual(true, accepted.widget.propertyValue(bool, "IsChecked").?);
    accepted.widget.event("Checked").?.invoke();
    accepted.widget.event("Unchecked").?.invoke();
    try std.testing.expectEqual(@as(usize, 1), counters.checked);
    try std.testing.expectEqual(@as(usize, 1), counters.unchecked);

    try std.testing.expectEqual(element.WidgetKind.slider, amount.widget.kind);
    try std.testing.expectEqual(@as(f64, 25.0), amount.widget.propertyValue(f64, "Value").?);
    try std.testing.expectEqual(@as(f64, 0.0), amount.widget.propertyValue(f64, "Minimum").?);
    try std.testing.expectEqual(@as(f64, 100.0), amount.widget.propertyValue(f64, "Maximum").?);
    amount.widget.event("ValueChanged").?.invoke();
    try std.testing.expectEqual(@as(usize, 1), counters.slider_changed);

    try std.testing.expectEqual(element.WidgetKind.combo_box, picker.widget.kind);
    try std.testing.expectEqual(@as(i32, 1), picker.widget.propertyValue(i32, "SelectedIndex").?);
    const stored_items = picker.widget.propertyValue([]const []const u8, "ItemsSource").?;
    try std.testing.expectEqual(@as(usize, 3), stored_items.len);
    try std.testing.expectEqualStrings("Alpha", stored_items[0]);
    picker.widget.event("SelectionChanged").?.invoke();
    try std.testing.expectEqual(@as(usize, 1), counters.selection_changed);

    try std.testing.expectEqual(element.WidgetKind.toggle_switch, enabled.widget.kind);
    try std.testing.expectEqual(true, enabled.widget.propertyValue(bool, "IsOn").?);
    enabled.widget.event("Toggled").?.invoke();
    try std.testing.expectEqual(@as(usize, 1), counters.toggled);

    try std.testing.expectEqual(element.WidgetKind.radio_button, mode.widget.kind);
    try std.testing.expectEqualStrings("Advanced", mode.widget.propertyValue([]const u8, "Content").?);
    try std.testing.expectEqual(false, mode.widget.propertyValue(bool, "IsChecked").?);
    mode.widget.event("Checked").?.invoke();
    try std.testing.expectEqual(@as(usize, 1), counters.radio_checked);
}
