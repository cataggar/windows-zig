//! Issue #4 hello-window spike: bootstrap the Windows App Runtime,
//! construct a real WinUI 3 `Application` + `Window` from Zig, and run a
//! plain Win32 message pump with no reactor engine involved.
//!
//! Run interactively:
//!   zig build run-hello-window
//!
//! Run with an auto-exit timer (useful for CLI verification):
//!   zig build run-hello-window -- --exit-after-ms 1500

const std = @import("std");
const win = @import("win");
const win_sys = @import("win-sys");
const surface = @import("surface.zig");

const core = win.core;

const sys = win_sys.project(.{
    .@"Windows.Win32.Foundation" = .{"FreeLibrary"},
    .@"Windows.Win32.System.LibraryLoader" = .{
        "LoadLibraryW",
        "GetProcAddress",
    },
    .@"Windows.Win32.UI.WindowsAndMessaging" = .{
        "KillTimer",
        "PostMessageW",
        "SetTimer",
    },
});

const WAM = win_sys.index.@"Windows.Win32.UI.WindowsAndMessaging";

const MddBootstrapInitializeOptions = i32;
const MddBootstrapInitializeOptions_OnNoMatch_ShowUI: MddBootstrapInitializeOptions = 8;
const MddBootstrapInitializeOptions_OnPackageIdentity_NOOP: MddBootstrapInitializeOptions = 16;
const WINDOWSAPPSDK_RELEASE_MAJORMINOR: u32 = 131072;
const WINDOWSAPPSDK_RELEASE_VERSION_TAG_W = [_]u16{0};
const WINDOWSAPPSDK_RUNTIME_VERSION_UINT64: u64 = 562949953486848;

const MddBootstrapInitialize2Fn = *const fn (
    majorminorversion: u32,
    versiontag: *const u16,
    minversion: PACKAGE_VERSION,
    options: MddBootstrapInitializeOptions,
) callconv(.winapi) core.HRESULT;

const MddBootstrapShutdownFn = *const fn () callconv(.winapi) void;

const PACKAGE_VERSION = extern struct {
    Anonymous: PACKAGE_VERSION_0,
};

const PACKAGE_VERSION_0 = extern union {
    Version: u64,
    Anonymous: PACKAGE_VERSION_0_0,
};

const PACKAGE_VERSION_0_0 = extern struct {
    Revision: u16,
    Build: u16,
    Minor: u16,
    Major: u16,
};

const Options = struct {
    exit_after_ms: ?u32 = null,
};

const ApplicationInitializationCallbackInvoke = fn (
    this: *anyopaque,
    params: *anyopaque,
) callconv(.winapi) core.HRESULT;

const IID_ApplicationInitializationCallback = core.GUID.parse("D8EEF1C9-1234-56F1-9963-45DD9C80A661");

const WindowLifetime = struct {
    application: core.IInspectable,
    window: core.IInspectable,
    button: core.IInspectable,
    text_block: core.IInspectable,
};

var g_lifetime: ?WindowLifetime = null;
var g_main_hwnd: ?*anyopaque = null;
var g_exit_after_ms: ?u32 = null;
var g_timer_id: ?usize = null;

fn releaseLifetime() void {
    if (g_lifetime) |lifetime| {
        lifetime.text_block.deinit();
        lifetime.button.deinit();
        lifetime.window.deinit();
        lifetime.application.deinit();
        g_lifetime = null;
    }
}

const BootstrapRuntime = struct {
    module: ?*anyopaque,
    shutdown: MddBootstrapShutdownFn,

    fn init() !BootstrapRuntime {
        var dll_name = std.unicode.utf8ToUtf16LeStringLiteral("Microsoft.WindowsAppRuntime.Bootstrap.dll").*;
        const module = sys.LoadLibraryW(&dll_name) orelse return error.LoadBootstrapDllFailed;
        errdefer _ = sys.FreeLibrary(module);

        var init_name = "MddBootstrapInitialize2".*;
        const init_raw = sys.GetProcAddress(module, &init_name) orelse return error.MissingBootstrapInitialize2;
        var shutdown_name = "MddBootstrapShutdown".*;
        const shutdown_raw = sys.GetProcAddress(module, &shutdown_name) orelse return error.MissingBootstrapShutdown;

        const init_fn: MddBootstrapInitialize2Fn = @ptrCast(@alignCast(init_raw));
        const shutdown_fn: MddBootstrapShutdownFn = @ptrCast(@alignCast(shutdown_raw));

        try core.hresult.ok(init_fn(
            WINDOWSAPPSDK_RELEASE_MAJORMINOR,
            &WINDOWSAPPSDK_RELEASE_VERSION_TAG_W[0],
            .{
                .Anonymous = .{
                    .Version = WINDOWSAPPSDK_RUNTIME_VERSION_UINT64,
                },
            },
            MddBootstrapInitializeOptions_OnNoMatch_ShowUI |
                MddBootstrapInitializeOptions_OnPackageIdentity_NOOP,
        ));

        return .{
            .module = module,
            .shutdown = shutdown_fn,
        };
    }

    fn deinit(self: *const BootstrapRuntime) void {
        self.shutdown();
        _ = sys.FreeLibrary(self.module);
    }
};

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
    const hr = factory_this.CreateInstance(null, &inner, &instance);
    if (hr < 0) {
        std.debug.print("CreateInstance failed for {s}: 0x{x}\n", .{
            @typeName(RuntimeClass),
            @as(u32, @bitCast(hr)),
        });
        try core.hresult.ok(hr);
    }
    return instance;
}

fn okStep(name: []const u8, hr: core.HRESULT) !void {
    if (hr < 0) {
        std.debug.print("{s} failed: 0x{x}\n", .{ name, @as(u32, @bitCast(hr)) });
    }
    try core.hresult.ok(hr);
}

fn onApplicationInitialized(_: *anyopaque, _: *anyopaque) callconv(.winapi) core.HRESULT {
    setupWindow() catch |err| {
        std.debug.print("hello-window setup failed: {}\n", .{err});
        std.process.exit(1);
    };
    return core.hresult.S_OK;
}

fn onAutoCloseTimer(_: ?*anyopaque, _: u32, id: usize, _: u32) callconv(.winapi) void {
    if (g_timer_id == id) {
        _ = sys.KillTimer(null, id);
        g_timer_id = null;
    }
    if (g_main_hwnd) |hwnd| {
        _ = sys.PostMessageW(hwnd, WAM.WM_CLOSE, 0, 0);
    }
}

fn setupWindow() !void {
    const application = try createComposable(surface.Application, surface.IApplicationFactory);
    errdefer ownInspectable(application).deinit();

    const window = try createComposable(surface.Window, surface.IWindowFactory);
    errdefer ownInspectable(window).deinit();
    const window_iface: *const surface.IWindow = @ptrCast(window);
    try okStep("Window.put_Title", window_iface.put_TitleFromUtf16(core.utf16Lit("Hello WinUI 3 from Zig")));

    const button = try createComposable(surface.Button, surface.IButtonFactory);
    errdefer ownInspectable(button).deinit();
    const button_iface: *const surface.IButton = @ptrCast(button);
    const button_ui = button_iface.cast(surface.IUIElement) orelse return error.ButtonMissingUIElement;
    defer _ = button_ui.Release();

    const text_block = try core.activateInstance(surface.ITextBlock, &surface.TextBlock.NAME_W);
    errdefer ownInspectable(text_block).deinit();
    const text_iface: *const surface.ITextBlock = @ptrCast(text_block);
    try okStep("TextBlock.put_Text", text_iface.put_TextFromUtf16(core.utf16Lit("Hello from Zig + WinUI 3")));

    const text_ui = text_iface.cast(surface.IUIElement) orelse return error.TextBlockMissingUIElement;
    defer _ = text_ui.Release();

    try okStep("Window.put_Content", window_iface.put_Content(asRuntimeClass(surface.UIElement, text_ui)));
    try okStep("Window.Activate", window_iface.Activate());

    const window_native = try ownInspectable(window).cast(surface.IWindowNative_Vtbl, &surface.IID_IWindowNative);
    defer window_native.deinit();
    var hwnd: ?*anyopaque = null;
    try core.hresult.ok(window_native.vtbl().WindowHandle(window_native.ptr, &hwnd));
    g_main_hwnd = hwnd orelse return error.MissingWindowHandle;

    if (g_exit_after_ms) |ms| {
        const timer_proc: ?*const anyopaque = @ptrCast(&onAutoCloseTimer);
        const id = sys.SetTimer(null, 1, ms, timer_proc);
        if (id == 0) return error.SetTimerFailed;
        g_timer_id = id;
    }

    g_lifetime = .{
        .application = ownInspectable(application),
        .window = ownInspectable(window),
        .button = ownInspectable(button),
        .text_block = ownInspectable(text_block),
    };

    std.debug.print(
        "hello-window: activated hwnd=0x{x}, bootstrap={d}.0, min-runtime=2.0.1.0\n",
        .{ @intFromPtr(g_main_hwnd.?), WINDOWSAPPSDK_RELEASE_MAJORMINOR >> 16 },
    );
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const options = try parseArgs(args);
    g_exit_after_ms = options.exit_after_ms;
    defer {
        if (g_timer_id) |id| {
            _ = sys.KillTimer(null, id);
        }
        g_main_hwnd = null;
        g_exit_after_ms = null;
        g_timer_id = null;
    }

    try core.roInitialize(.single_threaded);
    defer core.winrt.RoUninitialize();

    var bootstrap = try BootstrapRuntime.init();
    defer bootstrap.deinit();
    // Retained WinUI refs must be released on the original STA/UI thread
    // after `Application.Start()` unwinds, but before bootstrap / WinRT
    // teardown begins.
    defer releaseLifetime();

    const app_statics = try core.activationFactory(
        surface.IApplicationStatics.Vtbl,
        &surface.IApplicationStatics.IID,
        &surface.Application.NAME_W,
    );
    defer app_statics.deinit();

    const app_statics_this: *const surface.IApplicationStatics = @ptrCast(@alignCast(app_statics.ptr));
    const Callback = core.Delegate(
        ApplicationInitializationCallbackInvoke,
        IID_ApplicationInitializationCallback,
    );
    const callback = try Callback.create(std.heap.page_allocator, &onApplicationInitialized, null);
    defer _ = Callback.release(callback);

    try core.hresult.ok(app_statics_this.Start(callback));
}

fn parseArgs(args: []const []const u8) !Options {
    var options: Options = .{};

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--exit-after-ms")) {
            i += 1;
            if (i >= args.len) return error.MissingExitAfterValue;
            options.exit_after_ms = try std.fmt.parseUnsigned(u32, args[i], 10);
        } else if (std.mem.startsWith(u8, args[i], "--exit-after-ms=")) {
            options.exit_after_ms = try std.fmt.parseUnsigned(
                u32,
                args[i]["--exit-after-ms=".len..],
                10,
            );
        } else {
            return error.UnknownArgument;
        }
    }

    return options;
}
