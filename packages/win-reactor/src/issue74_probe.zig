//! THROWAWAY Phase 1 probe code for issue #74 -- see
//! `thoughts/issue-74/plans/implementation-plan.md`. Not wired into any
//! production path; only `app.zig`'s temporary
//! `issue74_use_aggregated_application` toggle calls into this. Delete this
//! file once Phase 1's decision gate is resolved and Phase 2 (or
//! Phase 2-Fallback) has its own permanent implementation.
//!
//! Re-runs the `Application.Resources` / `XamlControlsResources` probes
//! from the investigation recorded in the plan, against whichever
//! `Application` pointer the caller hands in (aggregated or not), and
//! prints results to stderr so a manual `zig build run-reactor-hello --
//! --exit-after-ms 1500` run can be inspected.

const std = @import("std");
const win = @import("win");
const win_core = win.core;
const xaml = @import("Microsoft.UI.Xaml");

const GUID = win_core.GUID;
const HRESULT = win_core.HRESULT;
const BOOL = win_core.BOOL;
const IInspectable_Vtbl = win_core.IInspectable_Vtbl;
const hresult = win_core.hresult;

// ---- Minimal ad-hoc ABI, just enough for this probe ----------------------
// Sourced from `packages/win/src/generated/Microsoft.UI.Xaml.zig` /
// `Microsoft.UI.Xaml.Controls.zig` (see citations in the plan doc). Not
// wired into the shared curated `winui/` surface yet -- that's Phase 2/3
// work once the resource-loading strategy is confirmed.

const IID_IResourceDictionary = GUID.parse("1B690975-A710-5783-A6E1-15836F6186C2");

const IResourceDictionary_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_Source: *const fn (this: *anyopaque, result: *?*anyopaque) callconv(.winapi) HRESULT,
    put_Source: *const fn (this: *anyopaque, value: *anyopaque) callconv(.winapi) HRESULT,
    get_MergedDictionaries: *const fn (this: *anyopaque, result: *?*anyopaque) callconv(.winapi) HRESULT,
    get_ThemeDictionaries: *const fn (this: *anyopaque, result: *?*anyopaque) callconv(.winapi) HRESULT,
};

const IID_IXamlControlsResources = GUID.parse("918CA043-F42C-5805-861B-62D6D1D0C162");

const IXamlControlsResources = extern struct {
    vtable: *const IXamlControlsResources_Vtbl,
    pub const IID = IID_IXamlControlsResources;
};

const IXamlControlsResources_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    get_UseCompactResources: *const fn (this: *anyopaque, result: *BOOL) callconv(.winapi) HRESULT,
    put_UseCompactResources: *const fn (this: *anyopaque, value: BOOL) callconv(.winapi) HRESULT,
};

const xaml_controls_resources_name_w = std.unicode.utf8ToUtf16LeStringLiteral("Microsoft.UI.Xaml.Controls.XamlControlsResources").*;

/// Hand-authored `activate()` bypassing the known #54 emitter bug (which
/// passes the `_Vtbl` type instead of the interface handle type to
/// `win_core.activateInstance`).
fn activateXamlControlsResources() !*IXamlControlsResources {
    return win_core.activateInstance(IXamlControlsResources, &xaml_controls_resources_name_w);
}

const IUnknown_Vtbl = win_core.IUnknown_Vtbl;
const com_aggregate = @import("com_aggregate.zig");

fn logHr(label: []const u8, hr: HRESULT) void {
    if (hresult.succeeded(hr)) {
        std.debug.print("issue74_probe: {s}: S_OK (0x{X:0>8})\n", .{ label, @as(u32, @bitCast(hr)) });
    } else {
        std.debug.print("issue74_probe: {s}: FAILED 0x{X:0>8}\n", .{ label, @as(u32, @bitCast(hr)) });
    }
}

/// Run the full probe battery against `application` and print results
/// prefixed with `stage` (e.g. "post-construct", "post-mount",
/// "post-activate"), matching the multi-point sampling the original
/// (non-aggregated) investigation used.
pub fn runProbes(application: *xaml.Application, stage: []const u8) void {
    std.debug.print("issue74_probe: ---- stage: {s} ----\n", .{stage});

    const app_this: *const xaml.IApplication = @ptrCast(@alignCast(application));

    // Validity check: confirm the aggregation is actually wired up (our
    // stub IXamlMetadataProvider must be reachable via QI), so a FAILED
    // XamlControlsResources probe below can't be misread as a false
    // negative from broken aggregation plumbing.
    var xmp_raw: ?*anyopaque = null;
    const qi_hr = app_this.QueryInterface(&com_aggregate.IID_IXamlMetadataProvider, &xmp_raw);
    logHr("QueryInterface(IID_IXamlMetadataProvider)", qi_hr);
    if (hresult.succeeded(qi_hr)) {
        const unk: *const IUnknown_Vtbl = @as(*const *const IUnknown_Vtbl, @ptrCast(@alignCast(xmp_raw.?))).*;
        _ = unk.Release(xmp_raw.?);
    }

    var resources: *xaml.ResourceDictionary = undefined;
    const get_resources_hr = app_this.vtable.get_Resources(app_this, &resources);
    logHr("get_Resources", get_resources_hr);

    if (hresult.succeeded(get_resources_hr)) {
        const rd_this: *anyopaque = @ptrCast(resources);
        const rd_vtbl: *const IResourceDictionary_Vtbl = @as(*const *const IResourceDictionary_Vtbl, @ptrCast(@alignCast(rd_this))).*;
        var merged: ?*anyopaque = null;
        const merged_hr = rd_vtbl.get_MergedDictionaries(rd_this, &merged);
        logHr("get_MergedDictionaries", merged_hr);
    }

    if (activateXamlControlsResources()) |xcr| {
        std.debug.print("issue74_probe: XamlControlsResources.activate: S_OK\n", .{});
        _ = xcr.vtable.base.base.Release(@ptrCast(xcr));
    } else |err| {
        std.debug.print("issue74_probe: XamlControlsResources.activate: FAILED {} (hresult 0x{X:0>8})\n", .{ err, @as(u32, @bitCast(hresult.last_hresult)) });
    }
}
