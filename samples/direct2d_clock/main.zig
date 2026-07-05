//! Port of `crates/samples/windows/direct2d` — an animated clock rendered
//! through Direct2D on top of a D3D11 + DXGI swap chain.
//!
//! The sample intentionally keeps the original structure:
//!   * `D2D1CreateFactory` + `ID2D1Factory1`
//!   * `D3D11CreateDevice` + `IDXGISwapChain1`
//!   * `IUIAnimationManager` driving the clock-hand swing-in transition
//!   * classic Win32 message pump with `WM_PAINT` / resize / occlusion
//!
//! It is interactive (shows a window and keeps animating until closed), so
//! CI only compile-checks it via `zig build samples` / `zig build test`.

const std = @import("std");
const win = @import("win");
const win_sys = @import("win-sys");

const F = @import("Windows.Win32.Foundation");
const Com = @import("Windows.Win32.System.Com");
const D2D = @import("Windows.Win32.Graphics.Direct2D");
const D2D1C = @import("Windows.Win32.Graphics.Direct2D.Common");
const D3D = @import("Windows.Win32.Graphics.Direct3D");
const D3D11 = @import("Windows.Win32.Graphics.Direct3D11");
const Dxgi = @import("Windows.Win32.Graphics.Dxgi");
const DxgiCommon = @import("Windows.Win32.Graphics.Dxgi.Common");
const Gdi = @import("Windows.Win32.Graphics.Gdi");
const Perf = @import("Windows.Win32.System.Performance");
const SysInfo = @import("Windows.Win32.System.SystemInformation");
const Animation = @import("Windows.Win32.UI.Animation");

const core = win.core;
const hresult = core.hresult;

const sys = win_sys.project(.{
    .@"Windows.Win32.System.LibraryLoader" = .{"GetModuleHandleA"},
    .@"Windows.Win32.UI.WindowsAndMessaging" = .{
        "RegisterClassA",
        "CreateWindowExA",
        "DefWindowProcA",
        "GetMessageA",
        "PeekMessageA",
        "TranslateMessage",
        "DispatchMessageA",
        "PostQuitMessage",
        "LoadCursorW",
        "ShowWindow",
        "SetWindowLongPtrA",
        "GetWindowLongPtrA",
    },
});

const WAM = win_sys.index.@"Windows.Win32.UI.WindowsAndMessaging";

const CLSID_UIAnimationManager = core.GUID.parse(
    "4C1FC63A-695C-47E8-A339-1A194BE3D0B8",
);
const CLSID_UIAnimationTransitionLibrary = core.GUID.parse(
    "1D6322AD-AA85-4EF5-A828-86D71067D145",
);

// `winbindgen` still projects `D2D1_BITMAP_PROPERTIES1` as opaque today.
// Mirror the C layout locally so the sample can pass real bitmap options.
const BitmapProperties1 = extern struct {
    pixelFormat: D2D1C.D2D1_PIXEL_FORMAT,
    dpiX: f32,
    dpiY: f32,
    bitmapOptions: i32,
    colorContext: ?*anyopaque,
};

const ole32 = struct {
    extern "OLE32" fn CoInitializeEx(
        pv_reserved: ?*anyopaque,
        coinit: u32,
    ) callconv(.winapi) core.HRESULT;

    extern "OLE32" fn CoCreateInstance(
        clsid: *const core.GUID,
        outer: ?*anyopaque,
        clsctx: u32,
        iid: *const core.GUID,
        object: *?*anyopaque,
    ) callconv(.winapi) core.HRESULT;
};

const d2d1 = struct {
    extern "d2d1" fn D2D1CreateFactory(
        factory_type: D2D.D2D1_FACTORY_TYPE,
        iid: *const core.GUID,
        options: *const D2D.D2D1_FACTORY_OPTIONS,
        factory: *?*anyopaque,
    ) callconv(.winapi) core.HRESULT;
};

const d3d11_raw = struct {
    extern "d3d11" fn D3D11CreateDevice(
        adapter: ?*Dxgi.IDXGIAdapter,
        driver_type: D3D.D3D_DRIVER_TYPE,
        software: F.HMODULE,
        flags: D3D11.D3D11_CREATE_DEVICE_FLAG,
        feature_levels: ?*const D3D.D3D_FEATURE_LEVEL,
        feature_levels_count: u32,
        sdk_version: u32,
        device: *?*D3D11.ID3D11Device,
        feature_level: ?*D3D.D3D_FEATURE_LEVEL,
        immediate_context: ?*?*D3D11.ID3D11DeviceContext,
    ) callconv(.winapi) core.HRESULT;
};

const dxgi_raw = struct {
    extern "dxgi" fn CreateDXGIFactory1(
        iid: *const core.GUID,
        factory: *?*anyopaque,
    ) callconv(.winapi) core.HRESULT;
};

const Angles = struct {
    second: f32 = 0,
    minute: f32 = 0,
    hour: f32 = 0,

    fn now() Angles {
        var time: F.SYSTEMTIME = std.mem.zeroes(F.SYSTEMTIME);
        SysInfo.GetLocalTime(&time);

        const second =
            (@as(f32, @floatFromInt(time.wSecond)) +
                @as(f32, @floatFromInt(time.wMilliseconds)) / 1000.0) *
            6.0;
        const minute =
            @as(f32, @floatFromInt(time.wMinute)) * 6.0 +
            second / 60.0;
        const hour =
            @as(f32, @floatFromInt(time.wHour % 12)) * 30.0 +
            minute / 12.0;

        return .{
            .second = second,
            .minute = minute,
            .hour = hour,
        };
    }
};

const App = struct {
    handle: F.HWND,
    factory: *const D2D.ID2D1Factory1,
    dxfactory: *const Dxgi.IDXGIFactory2,
    style: *const D2D.ID2D1StrokeStyle1,
    manager: *const Animation.IUIAnimationManager,
    variable: *const Animation.IUIAnimationVariable,

    target: ?*const D2D.ID2D1DeviceContext = null,
    swapchain: ?*const Dxgi.IDXGISwapChain1 = null,
    brush: ?*const D2D.ID2D1SolidColorBrush = null,
    shadow: ?*const D2D.ID2D1Effect = null,
    clock: ?*const D2D.ID2D1Bitmap1 = null,

    dpi: f32,
    visible: bool = false,
    occlusion: u32 = 0,
    frequency: i64,
    angles: Angles,

    fn init() !App {
        const factory = try createFactory();
        errdefer _ = factory.Release();

        const dxfactory = try createDxgiFactory(Dxgi.IDXGIFactory2);
        errdefer _ = dxfactory.Release();

        const style = try createStyle(factory);
        errdefer _ = style.Release();

        const manager = try coCreateInstance(
            Animation.IUIAnimationManager,
            &CLSID_UIAnimationManager,
        );
        errdefer _ = manager.Release();

        const transition = try createTransition();
        defer _ = transition.Release();

        var dpi: f32 = 0;
        var dpi_y: f32 = 0;
        _ = d2dFactoryBase(factory).GetDesktopDpi(&dpi, &dpi_y);

        var frequency: i64 = 0;
        if (!core.boolFromWin32(Perf.QueryPerformanceFrequency(&frequency))) {
            return error.QueryPerformanceFrequencyFailed;
        }

        var variable_opt: ?*Animation.IUIAnimationVariable = null;
        try hresult.ok(manager.CreateAnimationVariable(
            0.0,
            @ptrCast(&variable_opt),
        ));
        const variable = variable_opt orelse return error.NullAnimationVariable;
        errdefer _ = variable.Release();

        try hresult.ok(manager.ScheduleTransition(
            abiCast(Animation.IUIAnimationVariable, variable),
            abiCast(Animation.IUIAnimationTransition, transition),
            try getTime(frequency),
        ));

        return .{
            .handle = std.mem.zeroes(F.HWND),
            .factory = factory,
            .dxfactory = dxfactory,
            .style = style,
            .manager = manager,
            .variable = variable,
            .dpi = dpi,
            .frequency = frequency,
            .angles = Angles.now(),
        };
    }

    fn deinit(self: *App) void {
        if (self.occlusion != 0) {
            _ = self.dxfactory.UnregisterOcclusionStatus(self.occlusion);
            self.occlusion = 0;
        }

        self.releaseDevice();
        _ = self.variable.Release();
        _ = self.manager.Release();
        _ = self.style.Release();
        _ = self.dxfactory.Release();
        _ = self.factory.Release();
    }

    fn render(self: *App) !void {
        if (self.target == null) {
            const device = try createDevice();
            defer _ = device.Release();

            const target = try createRenderTarget(self.factory, device);
            errdefer _ = target.Release();
            _ = d2dRenderTarget(target).SetDpi(self.dpi, self.dpi);

            const swapchain = try createSwapchain(device, self.handle);
            errdefer _ = swapchain.Release();
            try createSwapchainBitmap(swapchain, target);

            const brush = try createBrush(target);
            errdefer _ = brush.Release();

            self.target = target;
            self.swapchain = swapchain;
            self.brush = brush;
            errdefer self.releaseDevice();

            try self.createDeviceSizeResources();
        }

        const target = self.target orelse return error.NoRenderTarget;
        const render_target = d2dRenderTarget(target);

        _ = render_target.BeginDraw();
        var tag1: u64 = 0;
        var tag2: u64 = 0;
        var end_draw_committed = false;
        defer if (!end_draw_committed) {
            _ = render_target.EndDraw(&tag1, &tag2);
        };

        try self.draw(target);
        try hresult.ok(render_target.EndDraw(&tag1, &tag2));
        end_draw_committed = true;

        const present_hr = self.present(1, @enumFromInt(0));
        if (present_hr != hresult.S_OK) {
            if (present_hr == F.DXGI_STATUS_OCCLUDED) {
                var cookie: u32 = 0;
                try hresult.ok(self.dxfactory.RegisterOcclusionStatusWindow(
                    self.handle,
                    WAM.WM_USER,
                    &cookie,
                ));
                self.occlusion = cookie;
                self.visible = false;
            } else {
                self.releaseDevice();
                return hresult.toError(present_hr);
            }
        }
    }

    fn draw(self: *App, target: *const D2D.ID2D1DeviceContext) !void {
        const clock = self.clock orelse return error.NoClockBitmap;
        const shadow = self.shadow orelse return error.NoShadowEffect;

        var update_result: Animation.UI_ANIMATION_UPDATE_RESULT =
            .UI_ANIMATION_UPDATE_NO_CHANGE;
        try hresult.ok(self.manager.Update(
            try getTime(self.frequency),
            &update_result,
        ));

        const render_target = d2dRenderTarget(target);
        var white = color(1.0, 1.0, 1.0, 1.0);
        _ = render_target.Clear(&white);

        var previous_opt: ?*D2D.ID2D1Image = null;
        _ = target.GetTarget(@ptrCast(&previous_opt));
        const previous = previous_opt orelse return error.NoPreviousTarget;
        defer _ = previous.Release();

        deviceContextSetTarget(target, bitmapImage(clock));
        var transparent = color(0.0, 0.0, 0.0, 0.0);
        _ = render_target.Clear(&transparent);
        try self.drawClock();
        deviceContextSetTarget(target, previous);

        var shadow_transform = matrixTranslation(5.0, 5.0);
        _ = render_target.SetTransform(&shadow_transform);

        var shadow_output_opt: ?*D2D.ID2D1Image = null;
        _ = shadow.GetOutput(@ptrCast(&shadow_output_opt));
        const shadow_output = shadow_output_opt orelse return error.NoShadowOutput;
        defer _ = shadow_output.Release();

        var shadow_rect: D2D1C.D2D_RECT_F = undefined;
        try hresult.ok(target.GetImageLocalBounds(shadow_output, &shadow_rect));
        const origin = point(0.0, 0.0);
        _ = target.DrawImage(
            shadow_output,
            @constCast(&origin),
            &shadow_rect,
            .D2D1_INTERPOLATION_MODE_LINEAR,
            .D2D1_COMPOSITE_MODE_SOURCE_OVER,
        );

        var identity = matrixIdentity();
        _ = render_target.SetTransform(&identity);
        var clock_rect: D2D1C.D2D_RECT_F = undefined;
        try hresult.ok(target.GetImageLocalBounds(bitmapImage(clock), &clock_rect));
        _ = target.DrawImage(
            bitmapImage(clock),
            @constCast(&origin),
            &clock_rect,
            .D2D1_INTERPOLATION_MODE_LINEAR,
            .D2D1_COMPOSITE_MODE_SOURCE_OVER,
        );
    }

    fn drawClock(self: *App) !void {
        const target = self.target orelse return error.NoRenderTarget;
        const brush = self.brush orelse return error.NoBrush;
        const render_target = d2dRenderTarget(target);

        var size: D2D1C.D2D_SIZE_F = undefined;
        _ = render_target.GetSize(&size);

        const radius = (@max(@min(size.width, size.height), 200.0) / 2.0) - 50.0;
        var translation = matrixTranslation(size.width / 2.0, size.height / 2.0);
        _ = render_target.SetTransform(&translation);

        var ellipse = D2D.D2D1_ELLIPSE{
            .point = point(0.0, 0.0),
            .radiusX = radius,
            .radiusY = radius,
        };
        _ = render_target.DrawEllipse(
            &ellipse,
            solidBrushBase(brush),
            radius / 20.0,
            strokeStyleBase(self.style),
        );

        var swing: f64 = 0.0;
        try hresult.ok(self.variable.GetValue(&swing));
        var angles = Angles.now();

        if (swing < 1.0) {
            if (self.angles.second > angles.second) angles.second += 360.0;
            if (self.angles.minute > angles.minute) angles.minute += 360.0;
            if (self.angles.hour > angles.hour) angles.hour += 360.0;

            const swing_f32: f32 = @floatCast(swing);
            angles.second *= swing_f32;
            angles.minute *= swing_f32;
            angles.hour *= swing_f32;
        }

        var transform = matrixMultiply(matrixRotation(angles.second), translation);
        _ = render_target.SetTransform(&transform);
        _ = render_target.DrawLine(
            point(0.0, 0.0),
            point(0.0, -(radius * 0.75)),
            solidBrushBase(brush),
            radius / 25.0,
            strokeStyleBase(self.style),
        );

        transform = matrixMultiply(matrixRotation(angles.minute), translation);
        _ = render_target.SetTransform(&transform);
        _ = render_target.DrawLine(
            point(0.0, 0.0),
            point(0.0, -(radius * 0.75)),
            solidBrushBase(brush),
            radius / 15.0,
            strokeStyleBase(self.style),
        );

        transform = matrixMultiply(matrixRotation(angles.hour), translation);
        _ = render_target.SetTransform(&transform);
        _ = render_target.DrawLine(
            point(0.0, 0.0),
            point(0.0, -(radius * 0.5)),
            solidBrushBase(brush),
            radius / 10.0,
            strokeStyleBase(self.style),
        );
    }

    fn createDeviceSizeResources(self: *App) !void {
        const target = self.target orelse return error.NoRenderTarget;
        if (self.shadow) |shadow| {
            _ = shadow.Release();
            self.shadow = null;
        }
        if (self.clock) |clock| {
            _ = clock.Release();
            self.clock = null;
        }

        const clock = try self.createClock(target);
        errdefer _ = clock.Release();

        const shadow = try createShadow(target, clock);
        errdefer _ = shadow.Release();

        self.clock = clock;
        self.shadow = shadow;
    }

    fn createClock(self: *const App, target: *const D2D.ID2D1DeviceContext) !*const D2D.ID2D1Bitmap1 {
        var size_f: D2D1C.D2D_SIZE_F = undefined;
        _ = d2dRenderTarget(target).GetSize(&size_f);

        const size_u = D2D1C.D2D_SIZE_U{
            .width = @intFromFloat(size_f.width * self.dpi / 96.0),
            .height = @intFromFloat(size_f.height * self.dpi / 96.0),
        };

        var props = BitmapProperties1{
            .pixelFormat = .{
                .format = @intFromEnum(DxgiCommon.DXGI_FORMAT.DXGI_FORMAT_B8G8R8A8_UNORM),
                .alphaMode = @intFromEnum(D2D1C.D2D1_ALPHA_MODE.D2D1_ALPHA_MODE_PREMULTIPLIED),
            },
            .dpiX = self.dpi,
            .dpiY = self.dpi,
            .bitmapOptions = @intFromEnum(D2D.D2D1_BITMAP_OPTIONS.D2D1_BITMAP_OPTIONS_TARGET),
            .colorContext = null,
        };

        var bitmap_opt: ?*D2D.ID2D1Bitmap1 = null;
        try hresult.ok(deviceContextCreateBitmap(
            target,
            size_u,
            null,
            0,
            &props,
            &bitmap_opt,
        ));
        return bitmap_opt orelse return error.NullClockBitmap;
    }

    fn resizeSwapchainBitmap(self: *App) !void {
        if (self.target) |target| {
            const swapchain = self.swapchain orelse return error.NoSwapChain;

            deviceContextSetTarget(target, null);
            const hr = dxgiSwapChainBase(swapchain).ResizeBuffers(
                0,
                0,
                0,
                .DXGI_FORMAT_UNKNOWN,
                0,
            );

            if (hr >= 0) {
                try createSwapchainBitmap(swapchain, target);
                try self.createDeviceSizeResources();
            } else {
                self.releaseDevice();
            }

            try self.render();
        }
    }

    fn messageHandler(
        self: *App,
        message: u32,
        wparam: usize,
        lparam: isize,
    ) isize {
        switch (message) {
            WAM.WM_PAINT => {
                var ps: Gdi.PAINTSTRUCT = std.mem.zeroes(Gdi.PAINTSTRUCT);
                _ = Gdi.BeginPaint(self.handle, &ps);
                self.render() catch |err| {
                    std.debug.print("direct2d-clock render failed: {}\n", .{err});
                };
                _ = Gdi.EndPaint(self.handle, &ps);
                return 0;
            },
            WAM.WM_SIZE => {
                if (wparam != WAM.SIZE_MINIMIZED) {
                    self.resizeSwapchainBitmap() catch |err| {
                        std.debug.print("direct2d-clock resize failed: {}\n", .{err});
                    };
                }
                return 0;
            },
            WAM.WM_DISPLAYCHANGE => {
                self.render() catch |err| {
                    std.debug.print("direct2d-clock redraw failed: {}\n", .{err});
                };
                return 0;
            },
            WAM.WM_USER => {
                if (self.present(0, .DXGI_PRESENT_TEST) == hresult.S_OK) {
                    _ = self.dxfactory.UnregisterOcclusionStatus(self.occlusion);
                    self.occlusion = 0;
                    self.visible = true;
                }
                return 0;
            },
            WAM.WM_ACTIVATE => {
                self.visible = @as(u16, @truncate(wparam >> 16)) == 0;
                return 0;
            },
            WAM.WM_DESTROY => {
                sys.PostQuitMessage(0);
                return 0;
            },
            else => return sys.DefWindowProcA(
                @ptrFromInt(@intFromPtr(self.handle.Value)),
                message,
                wparam,
                lparam,
            ),
        }
    }

    fn present(self: *const App, sync: u32, flags: Dxgi.DXGI_PRESENT) core.HRESULT {
        const swapchain = self.swapchain orelse return hresult.E_FAIL;
        return dxgiSwapChainBase(swapchain).Present(sync, flags);
    }

    fn releaseDevice(self: *App) void {
        if (self.target) |target| {
            _ = target.Release();
            self.target = null;
        }
        if (self.swapchain) |swapchain| {
            _ = swapchain.Release();
            self.swapchain = null;
        }
        self.releaseDeviceResources();
    }

    fn releaseDeviceResources(self: *App) void {
        if (self.brush) |brush| {
            _ = brush.Release();
            self.brush = null;
        }
        if (self.shadow) |shadow| {
            _ = shadow.Release();
            self.shadow = null;
        }
        if (self.clock) |clock| {
            _ = clock.Release();
            self.clock = null;
        }
    }
};

fn appFromWindow(hwnd: ?*anyopaque) ?*App {
    const raw = sys.GetWindowLongPtrA(hwnd, WAM.GWLP_USERDATA);
    if (raw == 0) return null;
    return @ptrFromInt(@as(usize, @intCast(raw)));
}

fn wndproc(
    hwnd: ?*anyopaque,
    message: u32,
    wparam: usize,
    lparam: isize,
) callconv(.winapi) isize {
    if (appFromWindow(hwnd)) |app| {
        switch (message) {
            WAM.WM_PAINT,
            WAM.WM_SIZE,
            WAM.WM_DISPLAYCHANGE,
            WAM.WM_USER,
            WAM.WM_ACTIVATE,
            WAM.WM_DESTROY,
            => return app.messageHandler(message, wparam, lparam),
            else => {},
        }
    }

    return sys.DefWindowProcA(hwnd, message, wparam, lparam);
}

pub fn main() !void {
    try hresult.ok(ole32.CoInitializeEx(
        null,
        0,
    ));
    defer Com.CoUninitialize();

    const instance = sys.GetModuleHandleA(null);
    if (instance == null) return error.GetModuleHandleFailed;

    var class_name = "zig-direct2d-clock".*;
    const class_name_ptr: ?[*:0]u8 = &class_name;

    var wc: win_sys.structs.WNDCLASSA = undefined;
    @memset(std.mem.asBytes(&wc), 0);
    wc.style = WAM.CS_HREDRAW | WAM.CS_VREDRAW;
    wc.lpfnWndProc = @ptrCast(&wndproc);
    wc.hInstance = .{ .Value = instance.? };
    const idc_arrow: ?[*:0]u16 = @ptrFromInt(@as(usize, WAM.IDC_ARROW));
    const cursor = sys.LoadCursorW(null, idc_arrow);
    if (cursor != null) wc.hCursor = .{ .Value = cursor.? };
    wc.lpszClassName = .{ .Value = @ptrCast(&class_name) };

    const atom = sys.RegisterClassA(&wc);
    if (atom == 0) return error.RegisterClassFailed;

    var title = "Direct2D Clock".*;
    const title_ptr: ?[*:0]u8 = &title;

    const hwnd = sys.CreateWindowExA(
        0,
        class_name_ptr,
        title_ptr,
        WAM.WS_OVERLAPPEDWINDOW,
        WAM.CW_USEDEFAULT,
        WAM.CW_USEDEFAULT,
        WAM.CW_USEDEFAULT,
        WAM.CW_USEDEFAULT,
        null,
        null,
        instance,
        null,
    );
    if (hwnd == null) return error.CreateWindowFailed;

    var app = try App.init();
    defer app.deinit();
    app.handle = .{ .Value = hwnd.? };

    _ = sys.SetWindowLongPtrA(hwnd, WAM.GWLP_USERDATA, @intCast(@intFromPtr(&app)));
    _ = sys.ShowWindow(hwnd, WAM.SW_SHOW);

    var message: win_sys.structs.MSG = undefined;
    @memset(std.mem.asBytes(&message), 0);

    var animating = true;
    while (true) {
        if (animating) {
            while (sys.PeekMessageA(&message, null, 0, 0, WAM.PM_REMOVE) != 0) {
                if (message.message == WAM.WM_QUIT) return;
                _ = sys.TranslateMessage(&message);
                _ = sys.DispatchMessageA(&message);
            }
        } else if (sys.GetMessageA(&message, null, 0, 0) != 0) {
            if (message.message == WAM.WM_QUIT) return;
            _ = sys.TranslateMessage(&message);
            _ = sys.DispatchMessageA(&message);
        } else {
            return;
        }

        animating = false;
        if (app.visible) {
            try app.render();
            animating = true;
        }
    }
}

fn getTime(frequency: i64) !f64 {
    var time: i64 = 0;
    if (!core.boolFromWin32(Perf.QueryPerformanceCounter(&time))) {
        return error.QueryPerformanceCounterFailed;
    }
    return @as(f64, @floatFromInt(time)) / @as(f64, @floatFromInt(frequency));
}

fn createFactory() !*const D2D.ID2D1Factory1 {
    var options = std.mem.zeroes(D2D.D2D1_FACTORY_OPTIONS);
    if (@import("builtin").mode == .Debug) {
        options.debugLevel =
            @intFromEnum(D2D.D2D1_DEBUG_LEVEL.D2D1_DEBUG_LEVEL_INFORMATION);
    }

    var raw: ?*anyopaque = null;
    try hresult.ok(d2d1.D2D1CreateFactory(
        .D2D1_FACTORY_TYPE_SINGLE_THREADED,
        &D2D.ID2D1Factory1.IID,
        &options,
        &raw,
    ));
    return @ptrCast(@alignCast(raw orelse return error.NullD2DFactory));
}

fn createStyle(factory: *const D2D.ID2D1Factory1) !*const D2D.ID2D1StrokeStyle1 {
    var props = std.mem.zeroes(D2D.D2D1_STROKE_STYLE_PROPERTIES1);
    props.startCap = @intFromEnum(D2D.D2D1_CAP_STYLE.D2D1_CAP_STYLE_ROUND);
    props.endCap = @intFromEnum(D2D.D2D1_CAP_STYLE.D2D1_CAP_STYLE_TRIANGLE);

    var style_opt: ?*D2D.ID2D1StrokeStyle1 = null;
    var dummy_dash: f32 = 0.0;
    try hresult.ok(factory.CreateStrokeStyle(
        &props,
        &dummy_dash,
        0,
        @ptrCast(&style_opt),
    ));
    return style_opt orelse return error.NullStrokeStyle;
}

fn createTransition() !*const Animation.IUIAnimationTransition {
    const library = try coCreateInstance(
        Animation.IUIAnimationTransitionLibrary,
        &CLSID_UIAnimationTransitionLibrary,
    );
    defer _ = library.Release();

    var transition_opt: ?*Animation.IUIAnimationTransition = null;
    try hresult.ok(library.CreateAccelerateDecelerateTransition(
        5.0,
        1.0,
        0.2,
        0.8,
        @ptrCast(&transition_opt),
    ));
    return transition_opt orelse return error.NullTransition;
}

fn createDeviceWithType(driver_type: D3D.D3D_DRIVER_TYPE) !*const D3D11.ID3D11Device {
    var flags: u32 =
        @intFromEnum(D3D11.D3D11_CREATE_DEVICE_FLAG.D3D11_CREATE_DEVICE_BGRA_SUPPORT);
    if (@import("builtin").mode == .Debug) {
        flags |= @intFromEnum(
            D3D11.D3D11_CREATE_DEVICE_FLAG.D3D11_CREATE_DEVICE_DEBUG,
        );
    }

    var device_opt: ?*D3D11.ID3D11Device = null;
    const feature_levels = [_]D3D.D3D_FEATURE_LEVEL{
        .D3D_FEATURE_LEVEL_11_1,
        .D3D_FEATURE_LEVEL_11_0,
        .D3D_FEATURE_LEVEL_10_1,
        .D3D_FEATURE_LEVEL_10_0,
        .D3D_FEATURE_LEVEL_9_3,
        .D3D_FEATURE_LEVEL_9_2,
        .D3D_FEATURE_LEVEL_9_1,
    };
    var achieved_level: D3D.D3D_FEATURE_LEVEL = .D3D_FEATURE_LEVEL_9_1;
    var immediate_context: ?*D3D11.ID3D11DeviceContext = null;
    defer {
        if (immediate_context) |ctx| _ = ctx.Release();
    }

    const hr = d3d11_raw.D3D11CreateDevice(
        null,
        driver_type,
        std.mem.zeroes(F.HMODULE),
        @enumFromInt(flags),
        &feature_levels[0],
        @intCast(feature_levels.len),
        D3D11.D3D11_SDK_VERSION,
        &device_opt,
        &achieved_level,
        &immediate_context,
    );
    try hresult.ok(hr);
    return device_opt orelse return error.NullD3DDevice;
}

fn createDevice() !*const D3D11.ID3D11Device {
    const hardware = createDeviceWithType(.D3D_DRIVER_TYPE_HARDWARE);
    return hardware catch |err| {
        if (hresult.last_hresult == Dxgi.DXGI_ERROR_UNSUPPORTED) {
            return createDeviceWithType(.D3D_DRIVER_TYPE_WARP);
        }
        return err;
    };
}

fn createRenderTarget(
    factory: *const D2D.ID2D1Factory1,
    device: *const D3D11.ID3D11Device,
) !*const D2D.ID2D1DeviceContext {
    const dxgi_device = device.cast(Dxgi.IDXGIDevice) orelse
        return error.NoDxgiDevice;
    defer _ = dxgi_device.Release();

    var d2d_device_opt: ?*D2D.ID2D1Device = null;
    try hresult.ok(factory.CreateDevice(
        @ptrCast(@constCast(dxgi_device)),
        @ptrCast(&d2d_device_opt),
    ));
    const d2d_device = d2d_device_opt orelse return error.NullD2DDevice;
    defer _ = d2d_device.Release();

    var target_opt: ?*D2D.ID2D1DeviceContext = null;
    try hresult.ok(d2d_device.CreateDeviceContext(
        .D2D1_DEVICE_CONTEXT_OPTIONS_NONE,
        @ptrCast(&target_opt),
    ));
    const target = target_opt orelse return error.NullDeviceContext;
    _ = target.SetUnitMode(.D2D1_UNIT_MODE_DIPS);
    return target;
}

fn createDxgiFactory(comptime T: type) !*const T {
    var raw: ?*anyopaque = null;
    try hresult.ok(dxgi_raw.CreateDXGIFactory1(
        &T.IID,
        &raw,
    ));
    return @ptrCast(@alignCast(raw orelse return error.NullDxgiFactory));
}

fn createSwapchainBitmap(
    swapchain: *const Dxgi.IDXGISwapChain1,
    target: *const D2D.ID2D1DeviceContext,
) !void {
    var surface_raw: ?*anyopaque = null;
    try hresult.ok(dxgiSwapChainBase(swapchain).GetBuffer(
        0,
        @constCast(&Dxgi.IDXGISurface.IID),
        @ptrCast(&surface_raw),
    ));
    const surface: *const Dxgi.IDXGISurface =
        @ptrCast(@alignCast(surface_raw orelse return error.NullDxgiSurface));
    defer _ = surface.Release();

    var props = BitmapProperties1{
        .pixelFormat = .{
            .format = @intFromEnum(DxgiCommon.DXGI_FORMAT.DXGI_FORMAT_B8G8R8A8_UNORM),
            .alphaMode = @intFromEnum(D2D1C.D2D1_ALPHA_MODE.D2D1_ALPHA_MODE_IGNORE),
        },
        .dpiX = 96.0,
        .dpiY = 96.0,
        .bitmapOptions = @intFromEnum(D2D.D2D1_BITMAP_OPTIONS.D2D1_BITMAP_OPTIONS_TARGET) |
            @intFromEnum(D2D.D2D1_BITMAP_OPTIONS.D2D1_BITMAP_OPTIONS_CANNOT_DRAW),
        .colorContext = null,
    };

    var bitmap_opt: ?*D2D.ID2D1Bitmap1 = null;
    try hresult.ok(target.CreateBitmapFromDxgiSurface(
        @ptrCast(@constCast(surface)),
        @ptrCast(&props),
        @ptrCast(&bitmap_opt),
    ));
    const bitmap = bitmap_opt orelse return error.NullSwapchainBitmap;
    defer _ = bitmap.Release();

    _ = target.SetTarget(bitmapImage(bitmap));
}

fn createSwapchain(
    device: *const D3D11.ID3D11Device,
    window: F.HWND,
) !*const Dxgi.IDXGISwapChain1 {
    const factory = try getDxgiFactory(device);
    defer _ = factory.Release();

    var props = std.mem.zeroes(Dxgi.DXGI_SWAP_CHAIN_DESC1);
    props.Format = @intFromEnum(DxgiCommon.DXGI_FORMAT.DXGI_FORMAT_B8G8R8A8_UNORM);
    props.SampleDesc = .{ .Count = 1, .Quality = 0 };
    props.BufferUsage =
        @intFromEnum(Dxgi.DXGI_USAGE.DXGI_USAGE_RENDER_TARGET_OUTPUT);
    props.BufferCount = 2;
    props.SwapEffect =
        @intFromEnum(Dxgi.DXGI_SWAP_EFFECT.DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL);

    var swapchain_opt: ?*Dxgi.IDXGISwapChain1 = null;
    var fullscreen_desc = std.mem.zeroes(Dxgi.DXGI_SWAP_CHAIN_FULLSCREEN_DESC);
    fullscreen_desc.Windowed = 1;
    try hresult.ok(factoryCreateSwapChainForHwnd(
        factory,
        abiCast(Com.IUnknown, device),
        window,
        &props,
        &fullscreen_desc,
        null,
        &swapchain_opt,
    ));
    return swapchain_opt orelse return error.NullSwapChain;
}

fn createBrush(target: *const D2D.ID2D1DeviceContext) !*const D2D.ID2D1SolidColorBrush {
    var orange = color(0.92, 0.38, 0.208, 1.0);
    var props = D2D.D2D1_BRUSH_PROPERTIES{
        .opacity = 0.8,
        .transform = matrixIdentity(),
    };

    var brush_opt: ?*D2D.ID2D1SolidColorBrush = null;
    try hresult.ok(d2dRenderTarget(target).CreateSolidColorBrush(
        &orange,
        &props,
        @ptrCast(&brush_opt),
    ));
    return brush_opt orelse return error.NullBrush;
}

fn createShadow(
    target: *const D2D.ID2D1DeviceContext,
    clock: *const D2D.ID2D1Bitmap1,
) !*const D2D.ID2D1Effect {
    var shadow_opt: ?*D2D.ID2D1Effect = null;
    try hresult.ok(target.CreateEffect(
        @constCast(&D2D.CLSID_D2D1Shadow),
        @ptrCast(&shadow_opt),
    ));
    const shadow = shadow_opt orelse return error.NullShadowEffect;
    _ = shadow.SetInput(0, bitmapImage(clock), core.boolToWin32(true));
    return shadow;
}

fn getDxgiFactory(device: *const D3D11.ID3D11Device) !*const Dxgi.IDXGIFactory2 {
    const dxgi_device = device.cast(Dxgi.IDXGIDevice) orelse
        return error.NoDxgiDevice;
    defer _ = dxgi_device.Release();

    var adapter_opt: ?*Dxgi.IDXGIAdapter = null;
    try hresult.ok(dxgi_device.GetAdapter(@ptrCast(&adapter_opt)));
    const adapter = adapter_opt orelse return error.NullDxgiAdapter;
    defer _ = adapter.Release();

    const dxgi_object = abiCast(Dxgi.IDXGIObject, adapter);

    var raw: ?*anyopaque = null;
    try hresult.ok(dxgi_object.GetParent(
        @constCast(&Dxgi.IDXGIFactory2.IID),
        @ptrCast(&raw),
    ));
    return @ptrCast(@alignCast(raw orelse return error.NullDxgiFactory));
}

fn coCreateInstance(comptime T: type, clsid: *const core.GUID) !*const T {
    var raw: ?*anyopaque = null;
    try hresult.ok(ole32.CoCreateInstance(
        clsid,
        null,
        0x17,
        &T.IID,
        &raw,
    ));
    return @ptrCast(@alignCast(raw orelse return error.NullComObject));
}

fn d2dFactoryBase(factory: *const D2D.ID2D1Factory1) *D2D.ID2D1Factory {
    return abiCast(D2D.ID2D1Factory, factory);
}

fn d2dRenderTarget(target: *const D2D.ID2D1DeviceContext) *D2D.ID2D1RenderTarget {
    return abiCast(D2D.ID2D1RenderTarget, target);
}

fn dxgiSwapChainBase(swapchain: *const Dxgi.IDXGISwapChain1) *Dxgi.IDXGISwapChain {
    return abiCast(Dxgi.IDXGISwapChain, swapchain);
}

fn solidBrushBase(brush: *const D2D.ID2D1SolidColorBrush) *D2D.ID2D1Brush {
    return abiCast(D2D.ID2D1Brush, brush);
}

fn strokeStyleBase(style: *const D2D.ID2D1StrokeStyle1) *D2D.ID2D1StrokeStyle {
    return abiCast(D2D.ID2D1StrokeStyle, style);
}

fn bitmapImage(bitmap: *const D2D.ID2D1Bitmap1) *D2D.ID2D1Image {
    return abiCast(D2D.ID2D1Image, bitmap);
}

fn deviceContextSetTarget(
    target: *const D2D.ID2D1DeviceContext,
    image: ?*D2D.ID2D1Image,
) void {
    const Fn = *const fn (
        *const D2D.ID2D1DeviceContext,
        ?*D2D.ID2D1Image,
    ) callconv(.winapi) void;
    const call: Fn = @ptrCast(target.vtable.SetTarget);
    call(target, image);
}

fn deviceContextCreateBitmap(
    target: *const D2D.ID2D1DeviceContext,
    size: D2D1C.D2D_SIZE_U,
    source_data: ?*const anyopaque,
    pitch: u32,
    properties: *const BitmapProperties1,
    bitmap: *?*D2D.ID2D1Bitmap1,
) core.HRESULT {
    const Fn = *const fn (
        *const D2D.ID2D1DeviceContext,
        D2D1C.D2D_SIZE_U,
        ?*const anyopaque,
        u32,
        *const BitmapProperties1,
        *?*D2D.ID2D1Bitmap1,
    ) callconv(.winapi) core.HRESULT;
    const call: Fn = @ptrCast(target.vtable.CreateBitmap);
    return call(target, size, source_data, pitch, properties, bitmap);
}

fn factoryCreateSwapChainForHwnd(
    factory: *const Dxgi.IDXGIFactory2,
    device: *Com.IUnknown,
    window: F.HWND,
    desc: *const Dxgi.DXGI_SWAP_CHAIN_DESC1,
    fullscreen_desc: ?*const Dxgi.DXGI_SWAP_CHAIN_FULLSCREEN_DESC,
    restrict_output: ?*Dxgi.IDXGIOutput,
    swapchain: *?*Dxgi.IDXGISwapChain1,
) core.HRESULT {
    const Fn = *const fn (
        *const Dxgi.IDXGIFactory2,
        *Com.IUnknown,
        F.HWND,
        *const Dxgi.DXGI_SWAP_CHAIN_DESC1,
        ?*const Dxgi.DXGI_SWAP_CHAIN_FULLSCREEN_DESC,
        ?*Dxgi.IDXGIOutput,
        *?*Dxgi.IDXGISwapChain1,
    ) callconv(.winapi) core.HRESULT;
    const call: Fn = @ptrCast(factory.vtable.CreateSwapChainForHwnd);
    return call(factory, device, window, desc, fullscreen_desc, restrict_output, swapchain);
}

fn abiCast(comptime T: type, ptr: anytype) *T {
    return @ptrCast(@constCast(ptr));
}

fn point(x: f32, y: f32) D2D1C.D2D_POINT_2F {
    return .{ .x = x, .y = y };
}

fn color(r: f32, g: f32, b: f32, a: f32) D2D1C.D2D1_COLOR_F {
    return .{
        .r = r,
        .g = g,
        .b = b,
        .a = a,
    };
}

fn matrixIdentity() D2D1C.D2D_MATRIX_3X2_F {
    return matrix(1.0, 0.0, 0.0, 1.0, 0.0, 0.0);
}

fn matrixTranslation(x: f32, y: f32) D2D1C.D2D_MATRIX_3X2_F {
    return matrix(1.0, 0.0, 0.0, 1.0, x, y);
}

fn matrixRotation(angle_degrees: f32) D2D1C.D2D_MATRIX_3X2_F {
    const radians = angle_degrees * std.math.pi / 180.0;
    const s = std.math.sin(radians);
    const c = std.math.cos(radians);
    return matrix(c, s, -s, c, 0.0, 0.0);
}

fn matrixMultiply(
    left: D2D1C.D2D_MATRIX_3X2_F,
    right: D2D1C.D2D_MATRIX_3X2_F,
) D2D1C.D2D_MATRIX_3X2_F {
    const a = left.Anonymous.m;
    const b = right.Anonymous.m;
    return matrix(
        a[0] * b[0] + a[1] * b[2],
        a[0] * b[1] + a[1] * b[3],
        a[2] * b[0] + a[3] * b[2],
        a[2] * b[1] + a[3] * b[3],
        a[4] * b[0] + a[5] * b[2] + b[4],
        a[4] * b[1] + a[5] * b[3] + b[5],
    );
}

fn matrix(
    m11: f32,
    m12: f32,
    m21: f32,
    m22: f32,
    dx: f32,
    dy: f32,
) D2D1C.D2D_MATRIX_3X2_F {
    return .{
        .Anonymous = .{
            .m = .{ m11, m12, m21, m22, dx, dy },
        },
    };
}
