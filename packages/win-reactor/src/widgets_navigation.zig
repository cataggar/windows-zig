const std = @import("std");
const win = @import("win");

const context = @import("context.zig");
const element = @import("element.zig");
const render_cx = @import("render_cx.zig");
const winui_backend = @import("winui_backend.zig");
const controls = @import("Microsoft.UI.Xaml.Controls");

const win_core = win.core;
const win_future = win.future;

pub const Allocator = element.Allocator;
pub const WidgetRef = element.WidgetRef;
pub const WidgetRefPropertyName = element.WidgetRefPropertyName;
pub const ContentDialogResult = controls.ContentDialogResult;
pub const OverlayHostContext = context.Context(?*OverlayHost);

pub const overlay_host_context = OverlayHostContext{
    .default = null,
    .id = .{ .raw = 0 },
};

pub const ContentDialogOptions = struct {
    title: ?[]const u8 = null,
    primary_button_text: ?[]const u8 = null,
    secondary_button_text: ?[]const u8 = null,
    close_button_text: ?[]const u8 = null,
    ref: ?*WidgetRef = null,
};

pub const ContentDialogFuture = struct {
    operation: win_core.IInspectable,

    pub fn deinit(self: *@This()) void {
        self.operation.deinit();
        self.* = undefined;
    }

    pub fn wait(self: *@This(), allocator: std.mem.Allocator) win_future.Async.Error!ContentDialogResult {
        defer self.deinit();
        return win_future.Async.waitResult(ContentDialogResult, allocator, self.operation.ptr);
    }
};

pub const OverlayHost = struct {
    backend: *winui_backend.WinUIBackend,

    pub fn showContentDialogAsync(self: *OverlayHost, ref: *const WidgetRef) !ContentDialogFuture {
        return .{
            .operation = try self.backend.showContentDialogAsync(try resolveWidgetRef(ref)),
        };
    }

    pub fn hideContentDialog(self: *OverlayHost, ref: *const WidgetRef) !void {
        try self.backend.hideContentDialog(try resolveWidgetRef(ref));
    }

    pub fn showFlyout(self: *OverlayHost, flyout_ref: *const WidgetRef, anchor_ref: *const WidgetRef) !void {
        try self.backend.showFlyout(try resolveWidgetRef(flyout_ref), try resolveWidgetRef(anchor_ref));
    }

    pub fn hideFlyout(self: *OverlayHost, flyout_ref: *const WidgetRef) !void {
        try self.backend.hideFlyout(try resolveWidgetRef(flyout_ref));
    }
};

pub const ContentDialogHandle = struct {
    overlay_host: *OverlayHost,
    ref: *WidgetRef,

    pub fn showAsync(self: @This()) !ContentDialogFuture {
        return self.overlay_host.showContentDialogAsync(self.ref);
    }

    pub fn hide(self: @This()) !void {
        try self.overlay_host.hideContentDialog(self.ref);
    }
};

pub const FlyoutHandle = struct {
    overlay_host: *OverlayHost,
    ref: *WidgetRef,
    anchor_ref: *WidgetRef,

    pub fn show(self: @This()) !void {
        try self.overlay_host.showFlyout(self.ref, self.anchor_ref);
    }

    pub fn hide(self: @This()) !void {
        try self.overlay_host.hideFlyout(self.ref);
    }
};

pub fn with_ref(builder: anytype, ref: *WidgetRef) element.Error!@TypeOf(builder) {
    return try builder.prop(WidgetRefPropertyName, ref);
}

pub fn content_dialog(
    allocator: Allocator,
    options: ContentDialogOptions,
    content: anytype,
) element.Error!element.Element {
    var builder = element.content_dialog(allocator);
    defer builder.deinit();

    if (options.ref) |widget_ref| {
        _ = try with_ref(&builder, widget_ref);
    }
    if (options.title) |value| {
        _ = try builder.prop("Title", value);
    }
    if (options.primary_button_text) |value| {
        _ = try builder.prop("PrimaryButtonText", value);
    }
    if (options.secondary_button_text) |value| {
        _ = try builder.prop("SecondaryButtonText", value);
    }
    if (options.close_button_text) |value| {
        _ = try builder.prop("CloseButtonText", value);
    }
    _ = try builder.child(content);
    return builder.build();
}

pub fn flyout(
    allocator: Allocator,
    content: anytype,
    ref: ?*WidgetRef,
) element.Error!element.Element {
    var builder = element.flyout(allocator);
    defer builder.deinit();

    if (ref) |widget_ref| {
        _ = try with_ref(&builder, widget_ref);
    }
    _ = try builder.child(content);
    return builder.build();
}

pub fn navigation_view_item(allocator: Allocator, content: []const u8) element.Error!element.Element {
    var builder = element.navigation_view_item(allocator);
    defer builder.deinit();
    _ = try builder.prop("Content", content);
    return builder.build();
}

pub fn navigation_view(
    allocator: Allocator,
    menu_items: anytype,
    content: anytype,
) element.Error!element.Element {
    var builder = element.navigation_view(allocator);
    defer builder.deinit();
    _ = try builder.childrenFrom(menu_items);
    _ = try builder.child(content);
    return builder.build();
}

pub fn menu_bar_item(allocator: Allocator, title: []const u8) element.Error!element.Element {
    var builder = element.menu_bar_item(allocator);
    defer builder.deinit();
    _ = try builder.prop("Title", title);
    return builder.build();
}

pub fn menu_bar(allocator: Allocator, items: anytype) element.Error!element.Element {
    var builder = element.menu_bar(allocator);
    defer builder.deinit();
    _ = try builder.childrenFrom(items);
    return builder.build();
}

pub fn useOverlayHost(cx: *render_cx.RenderCx) render_cx.Error!*OverlayHost {
    return (try cx.useContext(?*OverlayHost, &overlay_host_context)).?;
}

pub fn useContentDialog(cx: *render_cx.RenderCx, ref: *WidgetRef) render_cx.Error!ContentDialogHandle {
    return .{
        .overlay_host = try useOverlayHost(cx),
        .ref = ref,
    };
}

pub fn useFlyout(
    cx: *render_cx.RenderCx,
    ref: *WidgetRef,
    anchor_ref: *WidgetRef,
) render_cx.Error!FlyoutHandle {
    return .{
        .overlay_host = try useOverlayHost(cx),
        .ref = ref,
        .anchor_ref = anchor_ref,
    };
}

fn resolveWidgetRef(ref: *const WidgetRef) !usize {
    return ref.id orelse error.WidgetNotMounted;
}

test "content_dialog helper stores dialog props child and widget ref" {
    var body_builder = element.text_block(std.testing.allocator);
    defer body_builder.deinit();
    _ = try body_builder.prop("Text", @as([]const u8, "Dialog body"));

    var body = try body_builder.build();
    defer body.deinit(std.testing.allocator);

    var dialog_ref: WidgetRef = .{};
    var dialog = try content_dialog(
        std.testing.allocator,
        .{
            .title = "Confirm",
            .primary_button_text = "OK",
            .secondary_button_text = "More",
            .close_button_text = "Cancel",
            .ref = &dialog_ref,
        },
        &body,
    );
    defer dialog.deinit(std.testing.allocator);

    try std.testing.expect(dialog == .widget);
    try std.testing.expectEqual(element.WidgetKind.content_dialog, dialog.widget.kind);
    try std.testing.expectEqualStrings("Confirm", dialog.widget.propertyValue([]const u8, "Title").?);
    try std.testing.expectEqualStrings(
        "OK",
        dialog.widget.propertyValue([]const u8, "PrimaryButtonText").?,
    );
    try std.testing.expectEqualStrings(
        "More",
        dialog.widget.propertyValue([]const u8, "SecondaryButtonText").?,
    );
    try std.testing.expectEqualStrings(
        "Cancel",
        dialog.widget.propertyValue([]const u8, "CloseButtonText").?,
    );
    try std.testing.expect(
        dialog.widget.propertyValue(*WidgetRef, WidgetRefPropertyName).? == &dialog_ref,
    );
    try std.testing.expectEqual(@as(usize, 1), dialog.widget.children.len);
    try std.testing.expectEqual(
        element.WidgetKind.text_block,
        dialog.widget.children[0].widget.kind,
    );
}

test "navigation_view and menu_bar helpers arrange their child widgets" {
    var item_one = try navigation_view_item(std.testing.allocator, "Home");
    defer item_one.deinit(std.testing.allocator);
    var item_two = try navigation_view_item(std.testing.allocator, "Settings");
    defer item_two.deinit(std.testing.allocator);

    var content_builder = element.text_block(std.testing.allocator);
    defer content_builder.deinit();
    _ = try content_builder.prop("Text", @as([]const u8, "Body"));
    var content = try content_builder.build();
    defer content.deinit(std.testing.allocator);

    var nav = try navigation_view(std.testing.allocator, .{ &item_one, &item_two }, &content);
    defer nav.deinit(std.testing.allocator);

    try std.testing.expect(nav == .widget);
    try std.testing.expectEqual(element.WidgetKind.navigation_view, nav.widget.kind);
    try std.testing.expectEqual(@as(usize, 3), nav.widget.children.len);
    try std.testing.expectEqual(
        element.WidgetKind.navigation_view_item,
        nav.widget.children[0].widget.kind,
    );
    try std.testing.expectEqual(
        element.WidgetKind.text_block,
        nav.widget.children[2].widget.kind,
    );

    var file_menu = try menu_bar_item(std.testing.allocator, "File");
    defer file_menu.deinit(std.testing.allocator);
    var help_menu = try menu_bar_item(std.testing.allocator, "Help");
    defer help_menu.deinit(std.testing.allocator);

    var bar = try menu_bar(std.testing.allocator, .{ &file_menu, &help_menu });
    defer bar.deinit(std.testing.allocator);

    try std.testing.expect(bar == .widget);
    try std.testing.expectEqual(element.WidgetKind.menu_bar, bar.widget.kind);
    try std.testing.expectEqual(@as(usize, 2), bar.widget.children.len);
    try std.testing.expectEqual(
        element.WidgetKind.menu_bar_item,
        bar.widget.children[0].widget.kind,
    );
    try std.testing.expectEqualStrings(
        "File",
        bar.widget.children[0].widget.propertyValue([]const u8, "Title").?,
    );
}
