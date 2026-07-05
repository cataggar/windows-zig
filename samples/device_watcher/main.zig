//! Port of `crates/samples/windows/samples/examples/device_watcher.rs`.
//!
//! Exercises the full cross-namespace WinRT event-sugar path:
//!
//!   * `DeviceInformation.statics3().CreateWatcher()` creates a
//!     `DeviceWatcher`.
//!   * `IDeviceWatcher.addAdded` wires a Zig callback through
//!     `win_core.Delegate` into
//!     `Windows.Foundation.TypedEventHandler<DeviceWatcher, DeviceInformation>`.
//!   * `IDeviceWatcher.addEnumerationCompleted` does the same for the
//!     `TypedEventHandler<DeviceWatcher, object>` completion event.
//!   * A Win32 event handle lets the sample wait until enumeration
//!     completes instead of sleeping for a fixed duration.
//!
//! Build: `zig build`
//! Run:   `zig build run-device-watcher`

const std = @import("std");
const win = @import("win");
const win_sys = @import("win-sys");

const core = win.core;
const HRESULT = core.HRESULT;

const Devices = win.WinRT.Devices.Enumeration;
const Foundation = win.WinRT.Foundation;

const kernel32 = win_sys.project(.{
    .@"Windows.Win32.System.Threading" = .{
        "CreateEventW",
        "SetEvent",
        "WaitForSingleObject",
    },
    .@"Windows.Win32.Foundation" = .{"CloseHandle"},
});

const WAIT_OBJECT_0: u32 = 0x0;
const WAIT_TIMEOUT: u32 = 0x102;

const AddedHandler = Foundation.TypedEventHandler__G2__Windows_Devices_Enumeration_DeviceWatcher__Windows_Devices_Enumeration_DeviceInformation;
const CompletedHandler = Foundation.TypedEventHandler__G2__Windows_Devices_Enumeration_DeviceWatcher__object;

const Context = struct {
    done_event: ?*anyopaque,
    device_count: u32 = 0,
};

fn onDeviceAdded(
    this: *const AddedHandler,
    _: *Devices.DeviceWatcher,
    args: *Devices.DeviceInformation,
) callconv(.winapi) HRESULT {
    const D = core.Delegate(@TypeOf(onDeviceAdded), AddedHandler.IID);
    const ctx_raw = D.userData(@ptrCast(@constCast(this))) orelse return core.hresult.S_OK;
    const ctx: *Context = @ptrCast(@alignCast(ctx_raw));
    ctx.device_count += 1;

    const info: *const Devices.IDeviceInformation = @ptrCast(@alignCast(args));
    var name: core.HSTRING = null;
    const hr = info.get_Name(&name);
    if (hr < 0) return hr;
    var owned = core.Hstring.fromRaw(name);
    defer owned.deinit();

    var utf8_buf: [512]u8 = undefined;
    const n = std.unicode.utf16LeToUtf8(&utf8_buf, owned.slice()) catch {
        std.debug.print("<device name too long>\n", .{});
        return core.hresult.S_OK;
    };
    std.debug.print("{s}\n", .{utf8_buf[0..n]});
    return core.hresult.S_OK;
}

fn onEnumerationCompleted(
    this: *const CompletedHandler,
    _: *Devices.DeviceWatcher,
    _: ?*const anyopaque,
) callconv(.winapi) HRESULT {
    const D = core.Delegate(@TypeOf(onEnumerationCompleted), CompletedHandler.IID);
    const ctx_raw = D.userData(@ptrCast(@constCast(this))) orelse return core.hresult.S_OK;
    const ctx: *Context = @ptrCast(@alignCast(ctx_raw));

    std.debug.print("done!\n", .{});
    if (ctx.done_event) |done_event| {
        _ = kernel32.SetEvent(done_event);
    }
    return core.hresult.S_OK;
}

pub fn main() !void {
    try core.roInitialize(.multi_threaded);
    defer core.winrt.RoUninitialize();

    // The no-filter `CreateWatcher()` overload lives on
    // `IDeviceInformationStatics`, which the generated class facade
    // currently exposes as `.Statics3`.
    const statics = try Devices.DeviceInformation.statics3();
    defer statics.deinit();

    const statics_this: *const Devices.IDeviceInformationStatics =
        @ptrCast(@alignCast(statics.ptr));

    var watcher: *Devices.IDeviceWatcher = undefined;
    try core.hresult.ok(statics_this.CreateWatcher(@ptrCast(&watcher)));
    defer _ = watcher.Release();

    const done_event = kernel32.CreateEventW(null, 1, 0, null);
    if (done_event == null) return error.CreateEventFailed;
    defer _ = kernel32.CloseHandle(done_event);

    const allocator = std.heap.page_allocator;
    var ctx: Context = .{ .done_event = done_event };

    const added_token = try watcher.addAdded(allocator, &onDeviceAdded, &ctx);
    defer watcher.removeAdded(added_token) catch {};

    const completed_token = try watcher.addEnumerationCompleted(
        allocator,
        &onEnumerationCompleted,
        &ctx,
    );
    defer watcher.removeEnumerationCompleted(completed_token) catch {};

    try core.hresult.ok(watcher.Start());
    defer _ = watcher.Stop();

    std.debug.print("Enumerating devices...\n", .{});
    switch (kernel32.WaitForSingleObject(done_event, 10_000)) {
        WAIT_OBJECT_0 => {},
        WAIT_TIMEOUT => return error.EnumerationTimedOut,
        else => return error.WaitFailed,
    }

    std.debug.print("Enumerated {d} device(s).\n", .{ctx.device_count});
}
