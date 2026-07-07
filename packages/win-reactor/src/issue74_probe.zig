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
const controls = @import("Microsoft.UI.Xaml.Controls");

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

/// Narrow `IVector<ResourceDictionary>` consumer -- only `Append` is
/// exercised here, but every slot must be declared in the real order
/// (`packages/win-collections/src/interfaces.zig:298-312`) since vtable
/// layout is offset-based, not name-based.
const IVectorResourceDictionary_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    GetAt: *const fn (this: *anyopaque, index: u32, result: *?*anyopaque) callconv(.winapi) HRESULT,
    get_Size: *const fn (this: *anyopaque, result: *u32) callconv(.winapi) HRESULT,
    GetView: *const fn (this: *anyopaque, result: *?*anyopaque) callconv(.winapi) HRESULT,
    IndexOf: *const fn (this: *anyopaque, value: ?*anyopaque, index: *u32, result: *BOOL) callconv(.winapi) HRESULT,
    SetAt: *const fn (this: *anyopaque, index: u32, value: ?*anyopaque) callconv(.winapi) HRESULT,
    InsertAt: *const fn (this: *anyopaque, index: u32, value: ?*anyopaque) callconv(.winapi) HRESULT,
    RemoveAt: *const fn (this: *anyopaque, index: u32) callconv(.winapi) HRESULT,
    Append: *const fn (this: *anyopaque, value: ?*anyopaque) callconv(.winapi) HRESULT,
    RemoveAtEnd: *const fn (this: *anyopaque) callconv(.winapi) HRESULT,
    Clear: *const fn (this: *anyopaque) callconv(.winapi) HRESULT,
    GetMany: *const fn (this: *anyopaque, start_index: u32, items_size: u32, items_ptr: [*]?*anyopaque, result: *u32) callconv(.winapi) HRESULT,
    ReplaceAll: *const fn (this: *anyopaque, items_size: u32, items_ptr: [*]const ?*anyopaque) callconv(.winapi) HRESULT,
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

// ---- Speculative probe: is XamlControlsXamlMetaDataProvider directly
// activatable, and does it expose the real IXamlMetadataProvider? -------
// The original investigation claimed this compiler-generated-looking type
// was absent from metadata, but that check only looked at the *emitted
// bundle* (packages/win/src/generated/), not the full vendored .winmd via
// `winbindgen --list` / `winbindgen <namespace>`. It IS present there. If
// it's directly activatable and really implements IXamlMetadataProvider,
// our stub could delegate to it instead of always returning "not found" --
// which may be what real apps' compiler-generated providers actually do
// under the hood (see microsoft/microsoft-ui-xaml#7606 comment thread: "it
// is good enough to just fall through to the WinUI provided provider").

const xaml_controls_metadata_provider_name_w = std.unicode.utf8ToUtf16LeStringLiteral("Microsoft.UI.Xaml.XamlTypeInfo.XamlControlsXamlMetaDataProvider").*;

const IActivationFactory_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    ActivateInstance: *const fn (this: *anyopaque, instance: *?*anyopaque) callconv(.winapi) HRESULT,
};

fn probeXamlControlsXamlMetaDataProvider() void {
    const factory = win_core.activationFactory(IActivationFactory_Vtbl, &win_core.IID_IActivationFactory, &xaml_controls_metadata_provider_name_w) catch |err| {
        std.debug.print("issue74_probe: XamlControlsXamlMetaDataProvider activationFactory: FAILED {} (hresult 0x{X:0>8})\n", .{ err, @as(u32, @bitCast(hresult.last_hresult)) });
        return;
    };
    defer factory.deinit();

    var instance_raw: ?*anyopaque = null;
    const activate_hr = factory.vtbl().ActivateInstance(factory.ptr, &instance_raw);
    logHr("XamlControlsXamlMetaDataProvider ActivateInstance", activate_hr);
    if (!hresult.succeeded(activate_hr)) return;
    defer {
        const unk: *const IUnknown_Vtbl = @as(*const *const IUnknown_Vtbl, @ptrCast(@alignCast(instance_raw.?))).*;
        _ = unk.Release(instance_raw.?);
    }

    var xmp_raw: ?*anyopaque = null;
    const inst_unk: *const IUnknown_Vtbl = @as(*const *const IUnknown_Vtbl, @ptrCast(@alignCast(instance_raw.?))).*;
    const qi_hr = inst_unk.QueryInterface(instance_raw.?, &com_aggregate.IID_IXamlMetadataProvider, &xmp_raw);
    logHr("XamlControlsXamlMetaDataProvider -> QI(IID_IXamlMetadataProvider)", qi_hr);
    if (hresult.succeeded(qi_hr)) {
        const xmp_unk: *const IUnknown_Vtbl = @as(*const *const IUnknown_Vtbl, @ptrCast(@alignCast(xmp_raw.?))).*;
        _ = xmp_unk.Release(xmp_raw.?);
    }
}

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
    probeXamlControlsXamlMetaDataProvider();

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
    if (!hresult.succeeded(get_resources_hr)) return;

    const rd_this: *anyopaque = @ptrCast(resources);
    const rd_vtbl: *const IResourceDictionary_Vtbl = @as(*const *const IResourceDictionary_Vtbl, @ptrCast(@alignCast(rd_this))).*;
    var merged_raw: ?*anyopaque = null;
    const merged_hr = rd_vtbl.get_MergedDictionaries(rd_this, &merged_raw);
    logHr("get_MergedDictionaries", merged_hr);
    if (!hresult.succeeded(merged_hr)) return;

    if (merged_dictionaries_populated) return; // only merge once, at the first stage Resources is available
    merged_dictionaries_populated = true;

    const xcr = activateXamlControlsResources() catch |err| {
        std.debug.print("issue74_probe: XamlControlsResources.activate: FAILED {} (hresult 0x{X:0>8})\n", .{ err, @as(u32, @bitCast(hresult.last_hresult)) });
        return;
    };
    logHr("XamlControlsResources.activate", hresult.S_OK);

    const merged_this = merged_raw.?;
    const merged_vtbl: *const IVectorResourceDictionary_Vtbl = @as(*const *const IVectorResourceDictionary_Vtbl, @ptrCast(@alignCast(merged_this))).*;
    const append_hr = merged_vtbl.Append(merged_this, @ptrCast(xcr));
    logHr("MergedDictionaries.Append(XamlControlsResources)", append_hr);
    // Append (per normal WinRT collection semantics) takes its own
    // reference; release our own activation reference now that the vector
    // holds one. This is the real Phase-2 usage pattern (activate once,
    // merge once, then normal refcounting) rather than the earlier
    // probe-only activate+immediately-release-without-merging pattern.
    _ = xcr.vtable.base.base.Release(@ptrCast(xcr));

    // The critical validation: does constructing a REAL TextBox now avoid
    // the original issue #74 0xC000027B crash? Construct one directly
    // (bypassing the full reactor element tree, which has its own
    // mount-ordering problem the real Phase 2/3 work still needs to
    // solve -- see the plan doc) and immediately tear it down.
    const tb_factory = win_core.activationFactory(
        controls.ITextBoxFactory.Vtbl,
        &controls.ITextBoxFactory.IID,
        &controls.TextBox.NAME_W,
    ) catch |err| {
        std.debug.print("issue74_probe: TextBox activationFactory: FAILED {} (hresult 0x{X:0>8})\n", .{ err, @as(u32, @bitCast(hresult.last_hresult)) });
        return;
    };
    defer tb_factory.deinit();
    const tb_factory_this: *const controls.ITextBoxFactory = @ptrCast(@alignCast(tb_factory.ptr));
    var tb_inner: ?*const anyopaque = null;
    var tb_instance: *controls.TextBox = undefined;
    const tb_hr = tb_factory_this.CreateInstance(null, &tb_inner, &tb_instance);
    logHr("TextBox CreateInstance (real construction, the original #74 repro)", tb_hr);
    if (hresult.succeeded(tb_hr)) {
        _ = tb_instance.vtable.base.base.Release(@ptrCast(tb_instance));
        std.debug.print("issue74_probe: TextBox construction+release completed WITHOUT crashing.\n", .{});
    }
    // Append (per normal WinRT collection semantics) takes its own
    // reference; release our own activation reference now that the vector
    // holds one. This is the real Phase-2 usage pattern (activate once,
    // merge once, then normal refcounting) rather than the earlier
    // probe-only activate+immediately-release-without-merging pattern.
    _ = xcr.vtable.base.base.Release(@ptrCast(xcr));
}

var merged_dictionaries_populated = false;
