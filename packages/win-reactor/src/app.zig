const std = @import("std");
const win = @import("win");
const win_sys = @import("win-sys");

const element = @import("element.zig");
const render_cx = @import("render_cx.zig");
const reconciler = @import("reconciler.zig");
const backend = @import("backend.zig");
const winui_backend = @import("winui_backend.zig");
const winui_dispatcher = @import("winui_dispatcher.zig");
const xaml = @import("Microsoft.UI.Xaml");

const win_core = win.core;

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
const DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2: isize = -4;
const ERROR_ACCESS_DENIED: u32 = 5;

const MddBootstrapInitialize2Fn = *const fn (
    majorminorversion: u32,
    versiontag: *const u16,
    minversion: PACKAGE_VERSION,
    options: MddBootstrapInitializeOptions,
) callconv(.winapi) win_core.HRESULT;

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

const ApplicationInitializationCallbackInvoke = fn (
    this: *anyopaque,
    params: *anyopaque,
) callconv(.winapi) win_core.HRESULT;

const IID_ApplicationInitializationCallback = win_core.GUID.parse("D8EEF1C9-1234-56F1-9963-45DD9C80A661");

extern "user32" fn SetProcessDpiAwarenessContext(value: isize) callconv(.winapi) win_core.BOOL;
extern "kernel32" fn GetLastError() callconv(.winapi) u32;

pub const RootRenderFn = *const fn (cx: *render_cx.RenderCx) element.Error!element.Element;

pub const App = struct {
    allocator: std.mem.Allocator,
    exit_after_ms: ?u32 = null,

    pub fn init(allocator: std.mem.Allocator) App {
        return .{ .allocator = allocator };
    }

    pub fn run(self: *const App, comptime root_render: RootRenderFn) !void {
        return self.render(root_render);
    }

    pub fn render(self: *const App, comptime root_render: RootRenderFn) !void {
        try initAppPlatform();
        defer win_core.winrt.RoUninitialize();

        var bootstrap = try BootstrapRuntime.init();
        defer bootstrap.deinit();

        const app_statics = try xaml.Application.statics();
        defer app_statics.deinit();

        const app_statics_this: *const xaml.IApplicationStatics = @ptrCast(@alignCast(app_statics.ptr));

        const Host = ReactorHost(root_render);
        const Callback = win_core.Delegate(
            ApplicationInitializationCallbackInvoke,
            IID_ApplicationInitializationCallback,
        );
        const StartContext = struct {
            allocator: std.mem.Allocator,
            exit_after_ms: ?u32,
            launch_error: *?anyerror,

            fn onInitialized(this: *anyopaque, _: *anyopaque) callconv(.winapi) win_core.HRESULT {
                const raw = Callback.userData(this) orelse return win_core.hresult.S_OK;
                const ctx: *@This() = @ptrCast(@alignCast(raw));

                Host.start(ctx.allocator, ctx.exit_after_ms) catch |err| {
                    ctx.launch_error.* = err;
                    std.debug.print("win-reactor: app initialization failed: {}\n", .{err});
                    std.process.exit(1);
                };
                return win_core.hresult.S_OK;
            }
        };

        var launch_error: ?anyerror = null;
        var start_context = StartContext{
            .allocator = self.allocator,
            .exit_after_ms = self.exit_after_ms,
            .launch_error = &launch_error,
        };

        const callback = try Callback.create(self.allocator, &StartContext.onInitialized, &start_context);
        defer _ = Callback.release(callback);

        try win_core.hresult.ok(app_statics_this.Start(callback));
        if (launch_error) |err| return err;
    }
};

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

        try win_core.hresult.ok(init_fn(
            WINDOWSAPPSDK_RELEASE_MAJORMINOR,
            &WINDOWSAPPSDK_RELEASE_VERSION_TAG_W[0],
            .{ .Anonymous = .{ .Version = WINDOWSAPPSDK_RUNTIME_VERSION_UINT64 } },
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

fn ReactorHost(comptime root_render: RootRenderFn) type {
    return struct {
        allocator: std.mem.Allocator,
        backend_impl: winui_backend.WinUIBackend,
        reconciler_impl: reconciler.Reconciler,
        dispatcher: ?winui_dispatcher.WinUIDispatcher = null,
        tree: ?reconciler.Tree = null,
        pending_before_dispatcher: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        render_scheduled: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

        fn start(allocator: std.mem.Allocator, exit_after_ms: ?u32) !void {
            const application = try createComposable(xaml.Application, xaml.IApplicationFactory);
            const self = try allocator.create(@This());
            errdefer allocator.destroy(self);

            self.allocator = allocator;
            self.backend_impl = winui_backend.WinUIBackend.init(allocator, application);
            self.reconciler_impl = reconciler.Reconciler.init(
                allocator,
                backend.Backend.from(&self.backend_impl),
                render_cx.RequestRerender.init(self, requestRerender),
            );
            self.dispatcher = null;
            self.tree = null;
            self.pending_before_dispatcher = std.atomic.Value(bool).init(false);
            self.render_scheduled = std.atomic.Value(bool).init(false);

            try self.mountInitial();

            self.dispatcher = try winui_dispatcher.WinUIDispatcher.forCurrentThread();
            if (self.pending_before_dispatcher.swap(false, .acq_rel)) {
                try self.scheduleRerender();
            }

            try self.backend_impl.activateWindows();
            try configureAutoExit(&self.backend_impl, exit_after_ms);

            // WinUI owns teardown after Application.Start returns; explicitly
            // releasing the final refs still crashes during shutdown, so keep
            // the host alive until process exit.
        }

        fn mountInitial(self: *@This()) !void {
            var root = try self.buildRoot();
            defer root.deinit(self.allocator);
            self.tree = try self.reconciler_impl.mount(&root);
        }

        fn buildRoot(self: *@This()) !element.Element {
            const RootProps = struct {};
            return element.component(
                self.allocator,
                "winui_root",
                RootProps{},
                struct {
                    fn render(_: *const RootProps, cx: *render_cx.RenderCx) element.Error!element.Element {
                        return root_render(cx);
                    }
                }.render,
            );
        }

        fn rerenderNow(self: *@This()) !void {
            var root = try self.buildRoot();
            defer root.deinit(self.allocator);
            try self.reconciler_impl.reconcile(&self.tree, &root);
        }

        fn requestRerender(user_data: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(user_data.?));
            if (self.dispatcher == null) {
                self.pending_before_dispatcher.store(true, .release);
                return;
            }

            if (self.render_scheduled.swap(true, .acq_rel)) return;
            self.scheduleRerender() catch {
                self.render_scheduled.store(false, .release);
            };
        }

        fn scheduleRerender(self: *@This()) !void {
            const marshaller = self.dispatcher.?.marshaller();
            try marshaller.dispatch(self, performScheduledRerender);
        }

        fn performScheduledRerender(user_data: ?*anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(user_data.?));
            self.render_scheduled.store(false, .release);
            self.rerenderNow() catch |err| {
                std.debug.print("win-reactor: rerender failed: {}\n", .{err});
                std.process.exit(1);
            };
        }
    };
}

fn initAppPlatform() !void {
    if (SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2) == 0) {
        const last_error = GetLastError();
        if (last_error != ERROR_ACCESS_DENIED) {
            return error.SetProcessDpiAwarenessContextFailed;
        }
    }

    const hr = win_core.winrt.RoInitialize(.single_threaded);
    if (hr == win_core.RPC_E_CHANGED_MODE) {
        return error.AppRequiresSingleThreadedApartment;
    }
    try win_core.hresult.ok(hr);
}

var g_main_hwnd: ?*anyopaque = null;
var g_timer_id: ?usize = null;

fn configureAutoExit(backend_impl: *winui_backend.WinUIBackend, exit_after_ms: ?u32) !void {
    g_main_hwnd = null;
    g_timer_id = null;
    const ms = exit_after_ms orelse return;
    g_main_hwnd = try backend_impl.firstWindowHandle() orelse return error.NoWindowMounted;
    g_timer_id = sys.SetTimer(null, 0, ms, onAutoCloseTimer);
    if (g_timer_id == null) return error.SetTimerFailed;
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

fn createComposable(comptime RuntimeClass: type, comptime Factory: type) !*RuntimeClass {
    const factory = try win_core.activationFactory(Factory.Vtbl, &Factory.IID, &RuntimeClass.NAME_W);
    defer factory.deinit();

    const factory_this: *const Factory = @ptrCast(@alignCast(factory.ptr));
    var inner: ?*const anyopaque = null;
    var instance: *RuntimeClass = undefined;
    try win_core.hresult.ok(factory_this.CreateInstance(null, &inner, &instance));
    return instance;
}
