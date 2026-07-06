//! Compile-only canary for the minimal WinUI 3 surface tracked by issue #3.
//!
//! Directly importing the whole checked-in `packages/win/src/generated`
//! WinUI namespace snapshots currently fails because unrelated emitter gaps
//! leave undeclared `CoreWebView2*`, `IResourceManager`, and other emitter
//! gaps behind (tracked in #53 and #54).
//! This sample therefore isolates the exact emitted signatures needed for
//! Application/Window/Button/TextBlock in `surface.zig`, so we can still
//! prove the minimal four-type surface type-checks end-to-end while the
//! broader namespace issues are tracked separately. Remaining `*anyopaque`
//! fallbacks are catalogued in #55 and #56.

const std = @import("std");
const win = @import("win");
const surface = @import("surface.zig");

const core = win.core;

fn ownInspectable(ptr: anytype) core.IInspectable {
    return .{ .ptr = @ptrCast(@alignCast(ptr)) };
}

fn asRuntimeClass(comptime RuntimeClass: type, ptr: anytype) *RuntimeClass {
    return @ptrCast(@alignCast(@constCast(ptr)));
}

fn createComposable(comptime RuntimeClass: type, comptime Factory: type) !*RuntimeClass {
    const factory = try core.activationFactory(Factory.Vtbl, &Factory.IID, &RuntimeClass.NAME_W);
    defer factory.deinit();

    const factory_this: *const Factory = @ptrCast(@alignCast(factory.ptr));
    var inner: ?*const anyopaque = null;
    var instance: *RuntimeClass = undefined;
    try core.hresult.ok(factory_this.CreateInstance(null, &inner, &instance));
    return instance;
}

fn typecheckMinimalSurface() !void {
    const application = try createComposable(surface.Application, surface.IApplicationFactory);
    defer ownInspectable(application).deinit();
    const app_iface: *const surface.IApplication = @ptrCast(application);

    var resources: *surface.ResourceDictionary = undefined;
    try core.hresult.ok(app_iface.get_Resources(&resources));
    try core.hresult.ok(app_iface.put_RequestedTheme(.Light));

    const window = try createComposable(surface.Window, surface.IWindowFactory);
    defer ownInspectable(window).deinit();
    const window_iface: *const surface.IWindow = @ptrCast(window);
    try core.hresult.ok(window_iface.put_TitleFromUtf16(core.utf16Lit("WinUI 3 minimal surface")));

    const button = try createComposable(surface.Button, surface.IButtonFactory);
    defer ownInspectable(button).deinit();
    const button_iface: *const surface.IButton = @ptrCast(button);

    var flyout: *surface.FlyoutBase = undefined;
    try core.hresult.ok(button_iface.get_Flyout(&flyout));

    const text_block = try core.activateInstance(surface.ITextBlock, &surface.TextBlock.NAME_W);
    defer ownInspectable(text_block).deinit();
    const text_iface: *const surface.ITextBlock = @ptrCast(text_block);
    try core.hresult.ok(text_iface.put_TextFromUtf16(core.utf16Lit("Hello from Zig")));
    try core.hresult.ok(text_iface.put_TextWrapping(.Wrap));

    const button_ui = button_iface.cast(surface.IUIElement) orelse return error.ButtonMissingUIElement;
    defer _ = button_ui.Release();
    const text_ui = text_iface.cast(surface.IUIElement) orelse return error.TextBlockMissingUIElement;
    defer _ = text_ui.Release();

    try core.hresult.ok(window_iface.put_Content(asRuntimeClass(surface.UIElement, text_ui)));
    try core.hresult.ok(window_iface.SetTitleBar(asRuntimeClass(surface.UIElement, button_ui)));
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len == 0) {
        try typecheckMinimalSurface();
    }
}
