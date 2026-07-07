//! Reactor-local COM aggregation helper (issue #74 Phase 1 spike).
//!
//! Implements the standard WinRT/COM "controlling outer" aggregation
//! pattern used internally by e.g. C++/WinRT's `winrt::implements<Derived,
//! ApplicationT<Derived>>` CRTP base: a caller-owned "outer" object is
//! passed as the `outer` parameter to a composable factory's
//! `CreateInstance(outer, &inner, &instance)`. The outer answers
//! `QueryInterface` first for its own authored extra interfaces (here, a
//! single stub `IXamlMetadataProvider`), then delegates everything else to
//! the aggregated inner object's private "non-delegating" `IUnknown`
//! (captured via the `inner` out-parameter).
//!
//! This is deliberately reactor-local rather than a generic `win-core`
//! primitive (see `thoughts/issue-74/plans/implementation-plan.md`,
//! "What We're NOT Doing"): it exists to give `Microsoft.UI.Xaml.Application`
//! a stub `IXamlMetadataProvider`, which WinUI's theme-resource loader
//! appears to require before `XamlControlsResources`/`ms-appx://` resource
//! loads can succeed. It is a throwaway probe vehicle for Phase 1; if the
//! probe confirms this unblocks resource loading, Phase 2 makes the wiring
//! permanent (this file itself can stay, just without the temporary
//! probe-only call sites in `app.zig`).

const std = @import("std");
const win = @import("win");
const win_core = win.core;

const GUID = win_core.GUID;
const HRESULT = win_core.HRESULT;
const HSTRING = win_core.HSTRING;
const hresult = win_core.hresult;
const IUnknown_Vtbl = win_core.IUnknown_Vtbl;
const IInspectable_Vtbl = win_core.IInspectable_Vtbl;
const IID_IUnknown = win_core.IID_IUnknown;
const IID_IInspectable = win_core.IID_IInspectable;

// ---- IXamlMetadataProvider ABI ---------------------------------------
//
// Confirmed directly from `vendor/winmd/Microsoft.UI.Xaml.winmd` via the
// existing `winbindgen` CLI (`zig build run -- Microsoft.UI.Xaml.Markup`),
// not guessed from public headers. See the Phase 1 findings in
// `thoughts/issue-74/plans/implementation-plan.md` for the exact command
// and emitted source this was cross-checked against. `IXamlMetadataProvider`
// is a standard WinRT interface (present in metadata); it is the
// compiler-generated *concrete implementation* class
// (`XamlControlsXamlMetaDataProvider`) that is genuinely absent from
// metadata — we don't need that class, only our own stub of the interface.

pub const IID_IXamlMetadataProvider = GUID.parse("A96251F0-2214-5D53-8746-CE99A2593CD7");

/// `Windows.UI.Xaml.Interop.TypeName` — cross-referenced by the WinUI3
/// metadata even under the `Microsoft.UI.*` namespaces.
pub const TypeName = extern struct {
    Name: HSTRING,
    Kind: i32,
};

/// `Microsoft.UI.Xaml.Markup.XmlnsDefinition`.
pub const XmlnsDefinition = extern struct {
    XmlNamespace: HSTRING,
    Namespace: HSTRING,
};

pub const IXamlMetadataProvider_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    GetXamlType: *const fn (this: *anyopaque, type_name: TypeName, result: *?*anyopaque) callconv(.winapi) HRESULT,
    GetXamlType_2: *const fn (this: *anyopaque, full_name: HSTRING, result: *?*anyopaque) callconv(.winapi) HRESULT,
    GetXmlnsDefinitions: *const fn (this: *anyopaque, result_size: *u32, result_ptr: *?[*]XmlnsDefinition) callconv(.winapi) HRESULT,
};

// ---- Stub IXamlMetadataProvider method bodies -------------------------
//
// Reactor has no XAML markup files (no `x:Bind`, no custom markup types),
// so these never need to resolve anything real. Returning a null
// `IXamlType`/empty definition list with `S_OK` matches how
// compiler-generated `App::GetXamlType` behaves for a type it doesn't
// recognize -- WinRT's metadata-provider chaining treats "not found" as
// "keep looking", not a hard error.

fn stubGetXamlType(_: *anyopaque, _: TypeName, result: *?*anyopaque) callconv(.winapi) HRESULT {
    result.* = null;
    return hresult.S_OK;
}

fn stubGetXamlType2(_: *anyopaque, _: HSTRING, result: *?*anyopaque) callconv(.winapi) HRESULT {
    result.* = null;
    return hresult.S_OK;
}

fn stubGetXmlnsDefinitions(_: *anyopaque, result_size: *u32, result_ptr: *?[*]XmlnsDefinition) callconv(.winapi) HRESULT {
    result_size.* = 0;
    result_ptr.* = null;
    return hresult.S_OK;
}

// ---- Outer aggregation object -------------------------------------------

/// Per-instance layout: the vtable pointer must be the first field (COM
/// ABI contract -- an object pointer IS a pointer to its vtable pointer).
/// `inner` is the captured non-delegating `IUnknown`/`IInspectable` of the
/// aggregated instance, populated by `createAggregated` immediately after
/// `CreateInstance` returns; it is `null` only during that brief
/// construction window (any earlier `QueryInterface` call would be a
/// caller bug, hence the `@panic` in `innerUnknown` rather than quietly
/// misbehaving).
const Outer = extern struct {
    vtable: *const IXamlMetadataProvider_Vtbl,
    refcount: u32,
    allocator_ptr: *anyopaque,
    allocator_vtable: *const std.mem.Allocator.VTable,
    inner: ?*const anyopaque,
};

const outer_vtbl: IXamlMetadataProvider_Vtbl = .{
    .base = .{
        .base = .{
            .QueryInterface = outerQueryInterface,
            .AddRef = outerAddRef,
            .Release = outerRelease,
        },
        .GetIids = outerGetIids,
        .GetRuntimeClassName = outerGetRuntimeClassName,
        .GetTrustLevel = outerGetTrustLevel,
    },
    .GetXamlType = stubGetXamlType,
    .GetXamlType_2 = stubGetXamlType2,
    .GetXmlnsDefinitions = stubGetXmlnsDefinitions,
};

fn innerUnknown(self: *Outer) *const IUnknown_Vtbl {
    // The `inner` non-delegating pointer is itself a vtable-first COM
    // object; its `QueryInterface`/`AddRef`/`Release` operate independently
    // of the identity delegation `Outer` provides for `IUnknown`/
    // `IInspectable` -- that independence is the entire point of
    // "non-delegating" in the aggregation contract.
    const raw = self.inner orelse @panic("com_aggregate: inner not yet captured");
    return @as(*const *const IUnknown_Vtbl, @ptrCast(@alignCast(raw))).*;
}

fn outerQueryInterface(this: *anyopaque, riid: *const GUID, out: *?*anyopaque) callconv(.winapi) HRESULT {
    if (@intFromPtr(riid) == 0 or @intFromPtr(out) == 0) return hresult.E_POINTER;
    const self: *Outer = @ptrCast(@alignCast(this));

    if (std.meta.eql(riid.*, IID_IUnknown) or std.meta.eql(riid.*, IID_IInspectable)) {
        _ = outerAddRef(this);
        out.* = this;
        return hresult.S_OK;
    }
    if (std.meta.eql(riid.*, IID_IXamlMetadataProvider)) {
        _ = outerAddRef(this);
        out.* = this;
        return hresult.S_OK;
    }

    // Anything else: delegate to the aggregated inner object's private
    // non-delegating `IUnknown`. Per the standard aggregation contract, the
    // interface pointer handed back here has its OWN `IUnknown` identity
    // wired back to this outer -- `Application` supports composable
    // aggregation the same way any XAML-compiler-generated `App :
    // ApplicationT<App>` subclass relies on it via `winrt::implements`.
    const inner_raw = self.inner.?;
    return innerUnknown(self).QueryInterface(@constCast(inner_raw), riid, out);
}

fn outerAddRef(this: *anyopaque) callconv(.winapi) u32 {
    const self: *Outer = @ptrCast(@alignCast(this));
    return @atomicRmw(u32, &self.refcount, .Add, 1, .acq_rel) + 1;
}

fn outerRelease(this: *anyopaque) callconv(.winapi) u32 {
    const self: *Outer = @ptrCast(@alignCast(this));
    const prev = @atomicRmw(u32, &self.refcount, .Sub, 1, .acq_rel);
    if (prev == 1) {
        if (self.inner) |inner_raw| {
            _ = innerUnknown(self).Release(@constCast(inner_raw));
        }
        const allocator: std.mem.Allocator = .{
            .ptr = self.allocator_ptr,
            .vtable = self.allocator_vtable,
        };
        allocator.destroy(self);
    }
    return prev - 1;
}

fn outerGetIids(_: *anyopaque, count: *u32, values: *?[*]GUID) callconv(.winapi) HRESULT {
    if (@intFromPtr(count) == 0 or @intFromPtr(values) == 0) return hresult.E_POINTER;
    count.* = 0;
    values.* = null;
    return hresult.S_OK;
}

fn outerGetRuntimeClassName(_: *anyopaque, value: *HSTRING) callconv(.winapi) HRESULT {
    if (@intFromPtr(value) == 0) return hresult.E_POINTER;
    value.* = null;
    return hresult.S_OK;
}

fn outerGetTrustLevel(_: *anyopaque, value: *i32) callconv(.winapi) HRESULT {
    if (@intFromPtr(value) == 0) return hresult.E_POINTER;
    value.* = 0; // BaseTrust
    return hresult.S_OK;
}

/// Construct `RuntimeClass` (via `Factory`) aggregated behind a stub
/// `IXamlMetadataProvider`, and return it viewed through `iid` (e.g.
/// `&xaml.IApplication.IID`), cast to `*RuntimeClass` to match the shape
/// `app.zig`'s existing `createComposable` returns.
///
/// The returned pointer is obtained via `QueryInterface` on the outer's own
/// identity rather than trusting the factory's `result` out-parameter,
/// since composable factories are free to leave `result` pointing at a
/// non-aggregation-aware default interface (or `null`) once `outer` is
/// non-null -- the outer's own `QueryInterface` is the only pointer
/// guaranteed to answer correctly for every interface once aggregation is
/// involved.
///
/// Note on lifetime: mirrors `app.zig`'s existing relaxed teardown model
/// ("WinUI owns teardown after `Application.Start` returns; explicitly
/// releasing the final refs still crashes during shutdown, so keep the
/// host alive until process exit") -- the `Outer` allocation deliberately
/// leaks for the lifetime of the process, same as the plain
/// `createComposable` path.
pub fn createAggregated(
    allocator: std.mem.Allocator,
    comptime RuntimeClass: type,
    comptime Factory: type,
    iid: *const GUID,
) !*RuntimeClass {
    const outer = try allocator.create(Outer);
    errdefer allocator.destroy(outer);
    outer.* = .{
        .vtable = &outer_vtbl,
        .refcount = 1,
        .allocator_ptr = allocator.ptr,
        .allocator_vtable = allocator.vtable,
        .inner = null,
    };

    const factory = try win_core.activationFactory(Factory.Vtbl, &Factory.IID, &RuntimeClass.NAME_W);
    defer factory.deinit();
    const factory_this: *const Factory = @ptrCast(@alignCast(factory.ptr));

    var inner_raw: ?*const anyopaque = null;
    var instance_raw: *RuntimeClass = undefined;
    const hr = factory_this.CreateInstance(@ptrCast(outer), &inner_raw, &instance_raw);
    try hresult.ok(hr);
    outer.inner = inner_raw orelse return error.AggregationDidNotReturnInner;

    var out: ?*anyopaque = null;
    try hresult.ok(outerQueryInterface(@ptrCast(outer), iid, &out));
    return @ptrCast(@alignCast(out.?));
}
