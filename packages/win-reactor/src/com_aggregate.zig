//! Reactor-local COM aggregation helper (issue #74 Phase 1/2 spike).
//!
//! Implements the standard WinRT/COM "controlling outer" aggregation
//! pattern used internally by e.g. C++/WinRT's `winrt::implements<Derived,
//! ApplicationT<Derived>>` CRTP base: a caller-owned "outer" object is
//! passed as the `outer` parameter to a composable factory's
//! `CreateInstance(outer, &inner, &instance)`. The outer answers
//! `QueryInterface` first for its own authored extra interfaces (here, an
//! `IXamlMetadataProvider` that delegates to the real framework provider,
//! see below), then delegates everything else to the aggregated inner
//! object's private "non-delegating" `IUnknown` (captured via the `inner`
//! out-parameter).
//!
//! This is deliberately reactor-local rather than a generic `win-core`
//! primitive (see `thoughts/issue-74/plans/implementation-plan.md`,
//! "What We're NOT Doing"): it exists to give `Microsoft.UI.Xaml.Application`
//! a working `IXamlMetadataProvider`, which WinUI's theme-resource loader
//! requires before `XamlControlsResources`/`ms-appx://` resource loads can
//! succeed.

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
// and emitted source this was cross-checked against.

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

// ---- Real XamlControlsXamlMetaDataProvider (framework-provided) --------
//
// The original issue #74 investigation assumed
// `Microsoft.UI.Xaml.XamlTypeInfo.XamlControlsXamlMetaDataProvider` was
// absent from metadata and therefore that a hand-authored stub was the
// only option. That check only looked at the currently-*emitted bundle*
// (`packages/win/src/generated/`), not the full vendored `.winmd` via the
// `winbindgen` CLI directly. It is present, is a plain default-activatable
// WinRT class, and really implements `IXamlMetadataProvider` -- confirmed
// empirically via `zig build run-reactor-hello -- --exit-after-ms 2000`
// (see the Phase 1 results in the plan doc). Rather than stubbing
// "not found" for everything, `Outer` activates one instance of this real
// provider once and delegates every `IXamlMetadataProvider` call to it,
// matching how real (compiler-generated) app metadata providers are
// documented to "fall through to the WinUI provided provider" for types
// they don't own (see microsoft/microsoft-ui-xaml#7606).

const xaml_controls_metadata_provider_name_w = std.unicode.utf8ToUtf16LeStringLiteral(
    "Microsoft.UI.Xaml.XamlTypeInfo.XamlControlsXamlMetaDataProvider",
).*;

const IActivationFactory_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    ActivateInstance: *const fn (this: *anyopaque, instance: *?*anyopaque) callconv(.winapi) HRESULT,
};

// `IXamlControlsXamlMetaDataProviderStatics.Initialize()` -- real
// compiler-generated provider chains typically call something like this
// once at startup. IID confirmed via `zig build run --
// Microsoft.UI.Xaml.XamlTypeInfo`.
const IID_IXamlControlsXamlMetaDataProviderStatics = GUID.parse("2D7EB3FD-ECDB-5084-B7E0-12F9598381EF");

const IXamlControlsXamlMetaDataProviderStatics_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    Initialize: *const fn (this: *anyopaque) callconv(.winapi) HRESULT,
};

fn initializeRealProviderStatics() void {
    const factory = win_core.activationFactory(
        IActivationFactory_Vtbl,
        &IID_IXamlControlsXamlMetaDataProviderStatics,
        &xaml_controls_metadata_provider_name_w,
    ) catch |err| {
        std.debug.print("com_aggregate: XamlControlsXamlMetaDataProviderStatics activationFactory FAILED {} (hresult 0x{X:0>8})\n", .{ err, @as(u32, @bitCast(hresult.last_hresult)) });
        return;
    };
    defer factory.deinit();
    const statics_this: *const IXamlControlsXamlMetaDataProviderStatics_Vtbl = @as(*const *const IXamlControlsXamlMetaDataProviderStatics_Vtbl, @ptrCast(@alignCast(factory.ptr))).*;
    const hr = statics_this.Initialize(factory.ptr);
    std.debug.print("com_aggregate: XamlControlsXamlMetaDataProviderStatics.Initialize hresult 0x{X:0>8}\n", .{@as(u32, @bitCast(hr))});
}

/// Activate the real framework provider and QI it for `IXamlMetadataProvider`.
/// Returns `null` (rather than propagating the error) if anything about this
/// fails, so `Outer` can gracefully fall back to its own "not found" stub
/// instead of making aggregated `Application` construction itself fail.
fn activateRealProvider() ?*anyopaque {
    initializeRealProviderStatics();

    const factory = win_core.activationFactory(
        IActivationFactory_Vtbl,
        &win_core.IID_IActivationFactory,
        &xaml_controls_metadata_provider_name_w,
    ) catch return null;
    defer factory.deinit();

    var instance_raw: ?*anyopaque = null;
    if (!hresult.succeeded(factory.vtbl().ActivateInstance(factory.ptr, &instance_raw))) return null;
    const instance = instance_raw orelse return null;
    const inst_unk: *const IUnknown_Vtbl = @as(*const *const IUnknown_Vtbl, @ptrCast(@alignCast(instance))).*;
    defer _ = inst_unk.Release(instance);

    var provider_raw: ?*anyopaque = null;
    if (!hresult.succeeded(inst_unk.QueryInterface(instance, &IID_IXamlMetadataProvider, &provider_raw))) return null;
    return provider_raw;
}

fn realProviderVtbl(provider: *anyopaque) *const IXamlMetadataProvider_Vtbl {
    return @as(*const *const IXamlMetadataProvider_Vtbl, @ptrCast(@alignCast(provider))).*;
}

// ---- IXamlMetadataProvider method bodies -------------------------------
//
// Delegate to the real framework provider (`Outer.real_provider`) when one
// was successfully activated; otherwise fall back to "not found" (`S_OK`
// with a null/empty result -- matches how compiler-generated
// `App::GetXamlType` behaves for a type it doesn't recognize, since WinRT's
// metadata-provider chaining treats "not found" as "keep looking", not a
// hard error).

fn delegatingGetXamlType(this: *anyopaque, type_name: TypeName, result: *?*anyopaque) callconv(.winapi) HRESULT {
    const self: *Outer = @ptrCast(@alignCast(this));
    if (self.real_provider) |provider| {
        return realProviderVtbl(provider).GetXamlType(provider, type_name, result);
    }
    result.* = null;
    return hresult.S_OK;
}

fn delegatingGetXamlType2(this: *anyopaque, full_name: HSTRING, result: *?*anyopaque) callconv(.winapi) HRESULT {
    const self: *Outer = @ptrCast(@alignCast(this));
    if (self.real_provider) |provider| {
        return realProviderVtbl(provider).GetXamlType_2(provider, full_name, result);
    }
    result.* = null;
    return hresult.S_OK;
}

fn delegatingGetXmlnsDefinitions(this: *anyopaque, result_size: *u32, result_ptr: *?[*]XmlnsDefinition) callconv(.winapi) HRESULT {
    const self: *Outer = @ptrCast(@alignCast(this));
    if (self.real_provider) |provider| {
        return realProviderVtbl(provider).GetXmlnsDefinitions(provider, result_size, result_ptr);
    }
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
    /// The real framework `IXamlMetadataProvider`, if `activateRealProvider`
    /// succeeded (see above); `null` means fall back to "not found" stubs.
    real_provider: ?*anyopaque,
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
    .GetXamlType = delegatingGetXamlType,
    .GetXamlType_2 = delegatingGetXamlType2,
    .GetXmlnsDefinitions = delegatingGetXmlnsDefinitions,
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
        if (self.real_provider) |provider| {
            const provider_unk: *const IUnknown_Vtbl = @as(*const *const IUnknown_Vtbl, @ptrCast(@alignCast(provider))).*;
            _ = provider_unk.Release(provider);
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
        .real_provider = activateRealProvider(),
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
