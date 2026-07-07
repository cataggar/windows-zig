# Issue #74 Implementation Plan

## Overview

Fix the real WinUI `TextBox` crash. The original approach (merge `Microsoft.UI.Xaml.Controls.XamlControlsResources` into `Application.Resources.MergedDictionaries` before the first reactor tree mount) turned out to be unreachable in the current bare-`Application` host — see "2026-07-06 investigation findings" and "follow-up research" below. The plan has been updated (2026-07-06, resumed) to build a reactor-local COM aggregation helper that gives `Application` a stub `IXamlMetadataProvider`, re-probe whether that unblocks `XamlControlsResources`, and fall back to vendoring `themeresources.xaml` directly if it doesn't. Then re-enable real `.text_box` creation and validate with the dedicated `reactor_notepad` sample, the existing `--exit-after-ms` smoke pattern, window-title detection, and an Application Event Log crash scan. See "Updated Plan (2026-07-06, resumed)" below for the current phase breakdown; the sections above it are the historical investigation record that motivated this update.

## Current State Analysis

- `App.render(...)` starts WinUI, and `ReactorHost.start(...)` creates a bare `Application`, initializes the backend, mounts the first tree, activates windows, and optionally arms `--exit-after-ms`; there is no bootstrap hook that merges theme resources before `mountInitial()` runs (`packages/win-reactor/src/app.zig:89-134,188-215`).
- `win-reactor` does **not** consume `packages/win/src/generated/Microsoft.UI.Xaml*.zig` directly. `build.zig` wires `@import("Microsoft.UI.Xaml")` and `@import("Microsoft.UI.Xaml.Controls")` to the hand-curated reactor-local modules under `packages/win-reactor/src/winui/` (`build.zig:195-239`).
- The reactor-local XAML surface exposes `Application.Resources`, but `ResourceDictionary` is only an opaque runtime class today, so there is no typed `MergedDictionaries` path in the code reactor actually builds against (`packages/win-reactor/src/winui/Microsoft.UI.Xaml.zig:60,164-165,219-224`).
- The generated WinUI surface already contains the raw ABI facts this fix needs: `IResourceDictionary.get_MergedDictionaries(...)` exists (`packages/win/src/generated/Microsoft.UI.Xaml.zig:4109-4112`), and `XamlControlsResources` is emitted (`packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig:39523-39531`).
- The generated `XamlControlsResources.activate()` helper is **not** directly trustworthy for this fix because it still hits the known #54 emitter bug and passes `_Vtbl` instead of the interface handle type to `win_core.activateInstance(...)` (`packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig:39527-39528`; `docs/windows-reactor-port.md:85-88`).
- `tools/bindings/src/winui.txt` only lists `Application`, `Window`, `Button`, and `TextBlock` (`tools/bindings/src/winui.txt:5-8`), but the actual `zig build bindings` path bundles full `Microsoft.UI.Xaml` and `Microsoft.UI.Xaml.Controls` namespace files into `packages/win/src/generated/` (`build.zig:934-961`). That file is stale documentation, not the functional gate for #74.
- The public `text_box(...)` API is still exported (`packages/win-reactor/src/widgets_text_input.zig:7`, `packages/win-reactor/src/root.zig:80`), and the local WinUI control bindings still include `ITextBoxFactory` / `TextBox` (`packages/win-reactor/src/winui/Microsoft.UI.Xaml.Controls.zig:507-532`). The current block is the backend descope at `.text_box => error.NotYetSupported` (`packages/win-reactor/src/winui_backend.zig:590`).
- The current in-tree sample that actually mounts `reactor.text_box(...)` is `reactor_notepad`, and it still documents the issue-#74 `error.NotYetSupported` stopgap (`samples/reactor_notepad/main.zig:3-7,105-118`; `docs/windows-reactor.md:493-495,635-636`). `reactor_counter` no longer mounts a real `TextBox`, so it is no longer the best live validation target.
- The repo already has two useful collection precedents:
  - issue #10’s `win-collections` consumer wrapper proves the `IVector` ABI layout and `Append`/`Size` calling pattern are already tested (`packages/win-collections/src/interfaces.zig:287-400`; `packages/win-collections/src/tests.zig:182-232`).
  - `winui_backend.zig` already hand-authors a narrow raw `ObjectVector` consumer when the generated surface is too weak to use directly (`packages/win-reactor/src/winui_backend.zig:123-145`).
- The documented WinUI emitter follow-ups still matter, but only as context. #52-#55 explain why reactor continues to use a curated WinUI surface, and #56 explains why some collection properties still degrade to `*anyopaque` instead of a clean concrete type (`docs/windows-reactor-port.md:85-89`).

## 2026-07-06 investigation findings (blocking)

Temporary runtime probes were added to `packages/win-reactor/src/app.zig` and exercised with:

```powershell
zig build run-reactor-hello -- --exit-after-ms 1500
```

Those probes materially changed the diagnosis for this issue:

- `Application.Resources` / `Application.put_Resources(...)` are **not** usable immediately after `Application` construction, even when the call happens inside the `Application.Start(...)` callback. Right after `createComposable(xaml.Application, xaml.IApplicationFactory)`, both calls returned `0x8000FFFF` (`E_UNEXPECTED`). The same `get_Resources(...)` and `get_MergedDictionaries(...)` calls only started returning `S_OK` **after** `mountInitial()` had already created the first reactor tree. This matches upstream WinUI app-model notes: `Application.Resources` is backed by the thread's `DXamlCore` / core-app handle and is only valid once XAML core initialization has reached that point (`docs/design-notes/app-model.md` in `microsoft/microsoft-ui-xaml`). In other words, the original Phase 2 requirement to merge resources *before* `mountInitial()` is not achievable in the current bare-`Application` host.

- The curated ABI surface was **not** the active culprit for the `Application.Resources` failure. The `IApplication.get_Resources(...)` and `IResourceDictionary.get_MergedDictionaries(...)` slots were cross-checked against `packages/win/src/generated/Microsoft.UI.Xaml.zig`, and the exact same calls began returning `S_OK` after mount without any IID/vtable changes.

- `XamlControlsResources` still cannot be constructed in the current host, even after the app reaches the UI thread and a window has been activated. The probe observed `0x80004005` (`E_FAIL`) from `IActivationFactory::ActivateInstance("Microsoft.UI.Xaml.Controls.XamlControlsResources")`:
  - immediately after `Application` creation,
  - after `mountInitial()`,
  - after `activateWindows()`,
  - and on a later dispatcher callback.

- A plain `ResourceDictionary.Source = Uri("ms-appx:///Microsoft.UI.Xaml.Controls/Themes/themeresources.xaml")` probe also returned `0x80004005` at those same post-mount stages. That matters because upstream WinUI source shows `XamlControlsResources::UpdateSource()` does exactly that `Source(uri)` assignment and then immediately looks up the `"Default"` theme dictionary (`controls/dev/dll/XamlControlsResources.cpp` in `microsoft/microsoft-ui-xaml`). So the constructor failure is not just "the wrong helper signature" — the underlying MUX theme-resource URI load is failing in this host.

- Upstream WinUI desktop app-model docs say that supporting `Microsoft.UI.Xaml.Controls.dll` in desktop apps requires **both**:
  1. app-level `IXamlMetadataProvider` wiring that includes `Microsoft.UI.Xaml.XamlTypeInfo.XamlControlsXamlMetaDataProvider`, and
  2. a `XamlControlsResources` instance in `Application.Resources`.

  See `docs/design-notes/desktop-app-walkthrough.md` and `docs/design-notes/app-model.md` in `microsoft/microsoft-ui-xaml`. `win-reactor` currently creates a bare `Microsoft.UI.Xaml.Application` runtime object, not an app-defined `Application` subclass with XAML-generated metadata-provider plumbing, so sequencing changes alone cannot satisfy those requirements.

### Impact on the original plan

The original Phase 2 assumption — "merge `XamlControlsResources` into `Application.Resources.MergedDictionaries` before `mountInitial()`" — is invalid for the current host model. `Application.Resources` is unavailable until after the first mount, and the `XamlControlsResources` constructor then fails anyway because the underlying `ms-appx:///Microsoft.UI.Xaml.Controls/Themes/themeresources.xaml` load fails in the bare reactor app.

### What would unblock this issue

A real fix now appears to require a larger bootstrap / app-model change than issue #74 originally scoped:

- either introduce a proper WinUI desktop-style `Application` subclass that implements / hosts `IXamlMetadataProvider` (including `XamlControlsXamlMetaDataProvider`) plus a resource-loading story equivalent to `App.xaml`,
- or find a separate, reliable non-`ms-appx` way to load the WinUI theme dictionaries in unpackaged reactor apps.

## 2026-07-06 follow-up research (still blocking, scope confirmed larger than #74)

Further research (public C++/WinRT unpackaged WinUI3 samples/docs) corroborates and sharpens the above:

- The standard C++/WinRT `App::App()` pattern is:
  ```cpp
  App::App() {
      InitializeComponent(); // loads compiler-generated App.xaml via Application::LoadComponent
      auto resources = Resources();
      Controls::XamlControlsResources xamlControlsResources;
      resources.MergedDictionaries().Append(xamlControlsResources);
  }
  ```
  `InitializeComponent()` is generated by the MSBuild/XAML compiler from the project's `App.xaml` and, critically, wires the app's `IXamlMetadataProvider` implementation (which itself chains to a compiler-generated `XamlTypeInfo.g.h` that merges `Microsoft.UI.Xaml.XamlTypeInfo.XamlControlsXamlMetaDataProvider`). Reactor's bare Zig `Application` has no equivalent step, which is consistent with `XamlControlsResources` activation failing with `0x80004005` in every bootstrap position tried.
- `Microsoft.UI.Xaml.XamlTypeInfo.XamlControlsXamlMetaDataProvider` is **not** a WinRT type projected anywhere in `packages/win/src/generated/` (confirmed via repo-wide search for `XamlTypeInfo`/`XamlControlsXamlMetaDataProvider`/`IXamlMetadataProvider` — zero matches). It is not a metadata-only WinRT activatable class shipped in the Windows App SDK `.winmd`; it is emitted per-project by the XAML compiler from `generic.xaml`/`App.xaml`, so there is no existing binding to simply activate — reactor would have to hand-author an equivalent.
- `packages/win-reactor/src/app.zig:321-330`'s `createComposable(...)` currently calls `factory_this.CreateInstance(null, &inner, &instance)` — i.e. it creates `Application` **without COM aggregation** (`outer = null`). Exposing an additional interface like `IXamlMetadataProvider` on the `Application` object requires real COM aggregation: passing a caller-owned outer `IUnknown` into `CreateInstance` so the outer can answer `QueryInterface` for interfaces the base class doesn't implement (a well-defined but nontrivial COM pattern — outer owns the refcount and `IUnknown`, delegates unrecognized `QueryInterface` calls to the inner object's non-delegating `IUnknown`, and the inner's `IUnknown` delegates back out to the outer for aggregation-aware ref-counting).

### Recommended next steps (for whoever picks this up)

1. Implement a minimal reactor-local COM aggregation helper: an "outer" `IUnknown`/`IInspectable` Zig struct that reactor's `Application` creation can supply as the `outer` parameter to `CreateInstance`, exposing a hand-rolled `IXamlMetadataProvider` (stub `GetXamlType`/`GetXamlUserType`/`GetXmlnsDefinitions` implementations are likely sufficient since reactor doesn't use `x:Bind` or custom XAML markup types — the interface just needs to **exist** on the object).
2. Re-run the `Application.Resources` / `XamlControlsResources` activation probes from this investigation with that aggregated `Application` to confirm whether exposing `IXamlMetadataProvder` alone unblocks `0x80004005`, or whether additional wiring (e.g. `Application.MainWindow`/`Window.Content` established before merge) is also required.
3. If this works, wire the aggregation permanently into `createComposable`/`app.zig`, re-enable `TextBox`, and follow the rest of this plan's original Phase 3 (sample/docs updates, `reactor-selftest` wiring).
4. If exposing a stub `IXamlMetadataProvider` does *not* unblock the failure, the next thing to try is bypassing `ms-appx://` entirely: obtain the actual `themeresources.xaml` markup text (e.g. vendored from the Windows App SDK NuGet package's `Microsoft.UI.Xaml.Controls` source/resources) and load it directly via `Microsoft.UI.Xaml.Markup.XamlReader.Load(...)` instead of `ResourceDictionary.Source = ms-appx://...`, to sidestep package-identity-dependent URI resolution altogether.
5. Given the increased scope (real COM aggregation is new reactor infrastructure, not just an app.zig tweak), consider tracking this as its own follow-up issue/plan rather than folding it into #74's original phases, so it can be scoped, reviewed, and time-boxed independently.

**Status: paused here at user's request (2026-07-06).** No working runtime fix has been found yet; `TextBox` remains `error.NotYetSupported`. PR #80 stays a draft with this document as the record of investigation to date.

Until one of those exists, `.text_box` should remain `error.NotYetSupported`.

---

## Updated Plan (2026-07-06, resumed)

The sections below supersede the original Phase 1-3 plan that used to follow this point (that plan assumed `Application.Resources` could be populated before `mountInitial()`, which the investigation above disproved). Scope decisions confirmed with @cataggar for this update:

- Pursue both fallback strategies from the investigation, as sequential phases with an explicit decision gate: try the COM-aggregation + stub `IXamlMetadataProvider` route first; only build the `themeresources.xaml`-vendoring fallback if that route fails to unblock `XamlControlsResources`.
- Keep the COM aggregation helper in this same #74 plan/PR rather than splitting it into a separate issue — it's still new reusable infrastructure, but tracking it separately isn't worth the coordination overhead for this fix.

### Additional Key Discoveries (this update)

- `packages/win-core/src/root.zig` already has two precedents for hand-authoring COM/WinRT objects, and neither one currently supports COM aggregation:
  - `Delegate(VtblInvokeFn, iid)` (`packages/win-core/src/root.zig:387-451`) — single-method callback objects (`IUnknown` + one IID + `IAgileObject`), used for WinRT event handlers.
  - `MultiInterfaceObject(State, options, interfaces)` (`packages/win-core/src/root.zig:563-...`, documented in `docs/multi-method-authoring.md`) — multi-interface authored objects with their own identity/state, used for `IVector<T>`-style consumer wrappers. It always creates a **new independent object identity**; it has no notion of an "outer" controlling `IUnknown` or of delegating to a pre-existing WinRT-activated inner object. It is not a drop-in fit for aggregation, but its `qiFn`/refcount/`IInspectable` (`GetIids`/`GetRuntimeClassName`/`GetTrustLevel`) plumbing is a solid template to copy from.
- `createComposable(RuntimeClass, Factory)` in `packages/win-reactor/src/app.zig:321-330` calls `factory_this.CreateInstance(null, &inner, &instance)` — the `outer` parameter is already part of the ABI (every composable WinRT factory's `CreateInstance(this, outer, inner, instance)` takes it), reactor just always passes `null` today. Real aggregation only requires passing a real outer `IUnknown`/`IInspectable` pointer here and capturing the `inner` non-delegating `IUnknown` that comes back.
- `Microsoft.UI.Xaml.winmd` is already vendored in this worktree (`vendor/winmd/Microsoft.UI.Xaml.winmd`, fetched via `zig build fetch-winui-metadata`), so the exact `IXamlMetadataProvider` IID and method order (if the type is present in the metadata at all, even if `winbindgen` currently emits nothing for it) can be looked up directly from that file using the existing `winmd`/`tools/bindings` tooling instead of guessing from public C++/WinRT headers.
- `microsoft/microsoft-ui-xaml` (the open-source WinUI/MUX repo, source of `themeresources.xaml`/`generic.xaml`) is MIT-licensed (confirmed via its GitHub `LICENSE` file). That means, unlike the proprietary WindowsAppSDK NuGet binaries in `vendor/winmd/README.md`'s "fetched-on-demand" table, a vendored copy of the actual XAML resource markup text from that repo could be **committed to git** under a new `vendor/` subdirectory with a README citing the exact source path/commit/license, following the same documented-provenance convention `vendor/winmd/README.md` already uses for its MIT-licensed rows — no build-time fetch/proprietary-license gitignore needed for this fallback path.
- The vendored `Microsoft.UI.Xaml.winmd`/`Microsoft.UI.Text.winmd` pair is pinned at WinUI/WindowsAppSDK version `2.2.1` (`vendor/winmd/README.md`); if the fallback path is needed, the vendored `themeresources.xaml` source should come from the `microsoft-ui-xaml` tag/branch matching that same release so the resource keys line up with the binary `Microsoft.UI.Xaml.dll` actually loaded at runtime.

## Desired End State

- `win-core` gains a small COM-aggregation helper (name/shape decided during Phase 1) that reactor's `Application` creation uses to expose a stub `IXamlMetadataProvider` alongside the real `IApplication`/`IInspectable` faces.
- `ReactorHost.start(...)` merges a working `XamlControlsResources`-equivalent resource dictionary into `Application.Resources.MergedDictionaries` at whatever point Phase 1's probes show is the earliest safe point relative to `mountInitial()`, using either the aggregation route (Phase 2) or the vendored-`themeresources.xaml` route (Phase 2-Fallback) — whichever Phase 1 determines actually works.
- `.text_box` once again creates a real WinUI `Microsoft.UI.Xaml.Controls.TextBox` instead of returning `error.NotYetSupported`.
- `samples/reactor_notepad` becomes the canonical in-tree TextBox validation sample and no longer documents the `NotYetSupported` stopgap.
- `reactor-selftest` includes the existing `--exit-after-ms 1500` smoke pattern for `reactor-notepad`, so TextBox stays covered by the same Windows-only smoke mechanism already used for `reactor-hello` and `reactor-counter`.
- A manual run of `zig build run-reactor-notepad -- --exit-after-ms 1500`:
  - opens a visible window whose title starts with `windows-zig reactor notepad`,
  - exits cleanly without a `0xC000027B` crash,
  - and produces no new `Application Error` events for `Microsoft.UI.Xaml.dll` in the Application log after the test start time.

### Key Discoveries

- The missing piece is **not** "emit `XamlControlsResources` somewhere in the repo"; the symbol already exists in generated bindings. The missing piece is the app-model wiring (`IXamlMetadataProvider`) that WinUI's theme-resource loader silently depends on, which the XAML compiler normally generates for free and which reactor's bare `Application` never gets.
- The generated helper for `XamlControlsResources.activate()` is still affected by #54, so this plan should hand-author any local `activate()`-style helper instead of waiting on the emitter (`packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig:39527-39528`; `docs/windows-reactor-port.md:85-88`).
- #56 is relevant but not blocking: `MergedDictionaries` still falls back to `*anyopaque` in generated WinUI, but reactor already has established patterns for narrow raw collection consumers (`packages/win-reactor/src/winui_backend.zig:123-145`), so this issue can stay self-contained instead of taking #56 as a hard prerequisite.
- `reactor_notepad` is the correct live repro/validation target (translated from the issue body's older "reactor_counter TextBox repro" wording), because it's the sample that still mounts the public `text_box(...)` API (`samples/reactor_notepad/main.zig:105-118`; `build.zig:1849-1854`).

## What We're NOT Doing

- We are **not** switching `win-reactor` wholesale from its curated WinUI surface to the full generated `packages/win/src/generated/` namespace files.
- We are **not** fixing issues #52-#56 globally in this issue. This issue should borrow the ABI details it needs and stay narrowly focused on unblocking `TextBox`.
- We are **not** re-planning or implementing the broader emitter work for `Microsoft.UI.*` namespaces; sibling efforts already cover that.
- We are **not** broadening scope to unrelated runtime/lifetime problems such as the shutdown leak/crash tracked in #60.
- We are **not** adding permanent CI/Event-Viewer automation in this issue. Validation should follow the repo's current split: build smoke in `build.zig`, plus manual `EnumWindows` / Application log checks.
- We are **not** reintroducing a `TextBox` into `reactor_counter` just to match the old repro text. `reactor_notepad` is already the dedicated TextBox sample and should remain the validation target.
- We are **not** building a fully general-purpose, reusable-for-any-runtime-class COM aggregation framework. Scope the helper to what `Application` needs (one stub extra interface); generalize later only if another issue actually needs it.
- We are **not** splitting the COM aggregation helper into a separate issue/PR — per user decision, it stays Phase 1 of this same #74 plan.
- We are **not** implementing `x:Bind` / custom XAML markup type support in the stub `IXamlMetadataProvider` — reactor doesn't use XAML markup files, so `GetXamlType`/`GetXamlUserType`/`GetXmlnsDefinitions` only need to exist and return "not found" style results, not actually resolve types.

## Implementation Approach

1. **Build the minimum COM aggregation helper reactor needs, and validate it against the real blocker before writing any more code around it.** Phase 1 is a spike with a hard decision gate: it must end with a definitive answer to "does an aggregated `Application` with a stub `IXamlMetadataProvider` make `XamlControlsResources` activation (or an equivalent theme-resource load) succeed?" before Phase 2 work starts.
2. **Do not assume the original bootstrap ordering still holds.** Because `Application.Resources` was only observed to become queryable after `mountInitial()` ran, Phase 1's probes must also pin down the earliest point after aggregated construction that `Resources`/`MergedDictionaries` become usable, and whether that's early enough relative to when the first `TextBox` widget would actually be constructed during the initial reactor mount.
3. **Only build the `themeresources.xaml`-vendoring fallback if Phase 1 proves it's needed.** Don't speculatively implement both resource-loading strategies; Phase 1's findings pick exactly one of Phase 2 / Phase 2-Fallback to implement.
4. **Re-enable `TextBox` only after a resource-loading strategy is confirmed working end-to-end**, i.e., after a real `TextBox` has been constructed and rendered without crashing in a throwaway probe, not just after `XamlControlsResources.ActivateInstance` stops returning `E_FAIL`.
5. **Validate with the sample that still mounts TextBox today.** Make `reactor_notepad` the authoritative repro/smoke target, wire it into `reactor-selftest`, and keep the manual Event Viewer scan outside the build system (consistent with existing repo convention for `reactor-hello`/`reactor-counter`).

## Phase 1: COM aggregation helper + stub `IXamlMetadataProvider`, probe the real blocker

### Overview

Add a reactor-usable COM aggregation primitive, use it to give a real `Application` instance a stub `IXamlMetadataProvider`, and re-run the `Application.Resources`/`XamlControlsResources` probes from the investigation against that aggregated instance. This phase's deliverable is an answer, not a permanent feature — the temporary probe code added here can be thrown away once the answer is known (permanent wiring happens in Phase 2 or Phase 2-Fallback).

### Changes Required

#### 1. Look up `IXamlMetadataProvider`'s real ABI shape
**Files**:
- `vendor/winmd/Microsoft.UI.Xaml.winmd` (read-only source of truth)
- `packages/winmd/src/` / `tools/bindings/src/` (existing tooling to query it)

**Changes**:
- Use the existing `winmd` parsing package (the same one `winbindgen` uses) to check whether `Microsoft.UI.Xaml.Markup.IXamlMetadataProvider` (or wherever it actually lives in the metadata) is present, and if so, record its IID and exact method order/signatures (`GetXamlType` overloads, `GetXmlnsDefinitions`, etc.).
- If the interface is genuinely absent from the metadata (as the earlier repo-wide source search suggested), fall back to the publicly documented C++/WinRT `IXamlMetadataProvider` ABI (3 methods: `GetXamlType(TypeName)`, `GetXamlType(hstring fullName)` or equivalent overload, `GetXmlnsDefinitions()`), and pin the IID from public Windows SDK headers (`xamlom.h`/`Windows.UI.Xaml.Markup.h`-equivalent for Microsoft.UI.Xaml).
- Document whichever source was used (metadata vs. public header) directly in the code comment next to the new vtable, since this is exactly the kind of ABI fact future issues will want to cross-check.

#### 2. Add a reactor-local (or `win-core`) COM aggregation helper
**Files**:
- New file, e.g. `packages/win-reactor/src/com_aggregate.zig` (keep it reactor-local first; only promote to `win-core` later if a second consumer shows up — this matches the "we're not building a general framework" scope decision above)

**Changes**:
- Model the object shape on `Delegate`/`MultiInterfaceObject`'s existing pattern in `packages/win-core/src/root.zig` (per-instance vtable-pointer-first struct, atomic refcount, allocator-aware teardown).
- Implement the standard WinRT/COM aggregation contract:
  - An "outer" object that owns the controlling `IUnknown`/`IInspectable` identity and answers `QueryInterface` first for its own authored interfaces (just `IXamlMetadataProvider` for now), then delegates anything else to the inner object's **non-delegating** `IUnknown` (obtained from the `inner` out-parameter of `CreateInstance(outer, &inner, &instance)`).
  - The inner object's non-delegating `AddRef`/`Release`/`QueryInterface` must be reachable through that captured `inner` pointer distinctly from the identity `instance` pointer WinRT hands back — do not conflate the two.
  - Stub `GetXamlType`/`GetXamlUserType`/`GetXmlnsDefinitions` implementations that return "not found"/empty results (`E_NOTIMPL` or empty array, whichever the real interface's contract expects for "no custom types") — reactor has no XAML markup files, so these never need to resolve anything real.
- Provide a single entry point along the lines of `pub fn createAggregatedApplication(allocator) !*xaml.Application` that:
  1. builds the outer aggregation object,
  2. calls the `Application` factory's `CreateInstance` with that outer object as the `outer` parameter,
  3. stores the captured inner non-delegating `IUnknown` on the outer object for later delegation,
  4. returns the same `*xaml.Application` identity pointer `createComposable` returns today, so callers in `app.zig` don't need to change shape.

#### 3. Temporary probe wiring in `app.zig`
**File**: `packages/win-reactor/src/app.zig`

**Changes**:
- Swap the plain `createComposable(xaml.Application, xaml.IApplicationFactory)` call for the new aggregated constructor, gated behind a temporary flag/build option so this can be backed out cleanly if Phase 1 fails.
- Re-run the exact probes from the investigation (`Application.Resources`/`put_Resources`, `get_MergedDictionaries`, `XamlControlsResources` activation, `ResourceDictionary.Source = ms-appx://...`) at each of: immediately after aggregated construction, after `mountInitial()`, after `activateWindows()`, and on a later dispatcher callback — using `zig build run-reactor-hello -- --exit-after-ms 1500` as the throwaway harness, same as the original investigation.
- Record results directly in this plan document (a new "Phase 1 results" subsection) once probes are complete.

### Phase 1 progress — item 1 result (2026-07-07)

`IXamlMetadataProvider` **is** present in the vendored metadata — confirmed by running `zig build run -- Microsoft.UI.Xaml.Markup` (the existing `winbindgen` CLI, see `packages/winbindgen/src/main.zig:14`) and grepping the emitted source. This is the standard WinRT interface itself, distinct from the compiler-generated concrete `XamlControlsXamlMetaDataProvider` class (which is genuinely absent, as the earlier investigation found — but this plan only needs to author a stub *implementation* of the interface, not obtain that generated class). Confirmed ABI:

```zig
pub const IID_IXamlMetadataProvider: GUID = .{
    .data1 = 0xA96251F0, .data2 = 0x2214, .data3 = 0x5D53,
    .data4 = .{ 0x87, 0x46, 0xCE, 0x99, 0xA2, 0x59, 0x3C, 0xD7 },
};

pub const IXamlMetadataProvider_Vtbl = extern struct {
    base: IInspectable_Vtbl,
    GetXamlType: *const fn (this: *const IXamlMetadataProvider, p0: TypeName, result: **IXamlType) callconv(.winapi) HRESULT,
    GetXamlType_2: *const fn (this: *const IXamlMetadataProvider, p0: HSTRING, result: **IXamlType) callconv(.winapi) HRESULT,
    GetXmlnsDefinitions: *const fn (this: *const IXamlMetadataProvider, result_size: *u32, result_ptr: *[*]XmlnsDefinition) callconv(.winapi) HRESULT,
};

// from Windows.UI.Xaml.Interop (cross-referenced by the WinUI3 metadata)
pub const TypeName = extern struct { Name: HSTRING, Kind: i32 };

// from Microsoft.UI.Xaml.Markup
pub const XmlnsDefinition = extern struct { XmlNamespace: HSTRING, Namespace: HSTRING };
// IXamlType IID: d24219df-7ec9-57f1-a27b-6af251d9c5bc (only needed as an opaque out-pointer for the stub — never populated, since a stub returns "not found")
```

Stub contract (matches how compiler-generated `App::GetXamlType` behaves for unrecognized types): `GetXamlType`/`GetXamlType_2` set `result.* = null` and return `S_OK` (not an error — WinRT's metadata-provider chaining treats a null result as "this provider doesn't know this type, keep looking", not a hard failure). `GetXmlnsDefinitions` sets `result_size.* = 0` and `result_ptr.* = null`  (empty array) and returns `S_OK`.

### Success Criteria

- The aggregation helper compiles and a real `Application` instance can be constructed through it without crashing or hanging.
- `QueryInterface` for `IID_IXamlMetadataProvider` against the aggregated `Application` instance succeeds (`S_OK`) — this alone proves the aggregation wiring itself is correct, independent of whether it fixes the resource-loading problem.
- A definitive yes/no answer is recorded for: "does exposing `IXamlMetadataProvider` alone unblock `XamlControlsResources` activation / theme-resource loading?"
- A definitive answer is recorded for: "what is the earliest point after aggregated `Application` construction that `Application.Resources`/`MergedDictionaries` are queryable, and is that early enough to run before the first `TextBox` widget would be constructed during `mountInitial()`?"

### Phase 1 results (2026-07-07) — DECISION: aggregation alone is insufficient, proceed to Phase 2-Fallback

Implemented and ran the full Phase 1 spike:

- `packages/win-reactor/src/com_aggregate.zig` — the COM aggregation helper (`createAggregated`), implementing the standard "controlling outer" pattern: builds an outer object exposing a stub `IXamlMetadataProvider` (ABI from the "item 1 result" above), passes it as `outer` to `IApplicationFactory.CreateInstance`, captures the returned non-delegating `inner` pointer, and re-derives the `*Application`-shaped identity via `QueryInterface(IID_IApplication)` on the outer (rather than trusting the factory's `result` out-param, which composable factories are free to leave non-aggregation-aware).
- `packages/win-reactor/src/issue74_probe.zig` — throwaway probe harness with hand-authored minimal ABI for `IResourceDictionary.get_MergedDictionaries` and a `#54`-safe `XamlControlsResources.activate()` (calls `win_core.activateInstance(IXamlControlsResources, &NAME_W)` directly, sourcing the interface's IID from `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig:4499`).
- `packages/win-reactor/src/app.zig` — temporary `issue74_use_aggregated_application = true` toggle swaps `createComposable` for `com_aggregate.createAggregated`, with `issue74_probe.runProbes(application, stage)` called at `"post-construct"`, `"post-mount"`, and `"post-activate"`.

Ran via `zig build run-reactor-hello -- --exit-after-ms 2000`. Output (full):

```
issue74_probe: ---- stage: post-construct ----
issue74_probe: QueryInterface(IID_IXamlMetadataProvider): S_OK (0x00000000)
issue74_probe: get_Resources: FAILED 0x8000FFFF
issue74_probe: XamlControlsResources.activate: FAILED error.Fail (hresult 0x80004005)
issue74_probe: ---- stage: post-mount ----
issue74_probe: QueryInterface(IID_IXamlMetadataProvider): S_OK (0x00000000)
issue74_probe: get_Resources: S_OK (0x00000000)
issue74_probe: get_MergedDictionaries: S_OK (0x00000000)
issue74_probe: XamlControlsResources.activate: FAILED error.Fail (hresult 0x80004005)
issue74_probe: ---- stage: post-activate ----
issue74_probe: QueryInterface(IID_IXamlMetadataProvider): S_OK (0x00000000)
issue74_probe: get_Resources: S_OK (0x00000000)
issue74_probe: get_MergedDictionaries: S_OK (0x00000000)
issue74_probe: XamlControlsResources.activate: FAILED error.Fail (hresult 0x80004005)
```

**Answers to the two questions this phase had to resolve:**

1. **Does exposing `IXamlMetadataProvider` alone unblock `XamlControlsResources` activation? NO.** `QueryInterface(IID_IXamlMetadataProvider)` against the aggregated `Application` succeeds (`S_OK`) at every stage — proving the aggregation plumbing itself is correct, so this is a real negative result, not a broken-probe false negative. Despite that, `XamlControlsResources.activate()` fails with the exact same `0x80004005` (`E_FAIL`) at every stage, identical to the non-aggregated baseline from the original investigation. Whatever WinUI's theme-resource loader needs beyond `IXamlMetadataProvider` (a working `Application.Resources.MergedDictionaries` on the compiler-generated `App.xaml` path, package-identity-dependent `ms-appx://` resolution, or something else entirely) is not satisfied merely by the interface existing on the object.
2. **Earliest safe point for `Resources`/`MergedDictionaries`?** Unchanged from the original investigation: still `E_UNEXPECTED` (`0x8000FFFF`) immediately post-construct, still `S_OK` post-mount onward. Aggregation did not change this timing either.

**Decision: skip Phase 2, proceed directly to Phase 2-Fallback** (vendor `themeresources.xaml`, load via `XamlReader.Load`, bypass `ms-appx://` entirely). Phase 2 as originally scoped (merge `XamlControlsResources` after confirming aggregation unblocks it) is not applicable given this result.

**Implementation Note**: Paused here for manual confirmation before proceeding to Phase 2-Fallback, per this phase's decision gate.

### MAJOR UPDATE (2026-07-07, same session) — the "Phase 2-Fallback" conclusion above was premature; real fix found

Before starting Phase 2-Fallback's vendoring work, external research turned up [microsoft/microsoft-ui-xaml#7606](https://github.com/microsoft/microsoft-ui-xaml/issues/7606) ("XamlControlsResources causes crash when used from plain win32 desktop app") — the exact same failure, reported against a plain unpackaged C++/WinRT app. Key quote from a comment on that issue: instantiating `XamlControlsResources` requires an `IXamlMetadataProvider` implementation, and a hand-authored one is "good enough to just fall through to the WinUI provided provider" for a basic window/controls to show.

That phrase ("fall through to the WinUI provided provider") prompted re-checking whether `Microsoft.UI.Xaml.XamlTypeInfo.XamlControlsXamlMetaDataProvider` is really absent from metadata, since the original investigation's check only searched the **emitted bundle** (`packages/win/src/generated/`) — not the full vendored `.winmd` via the `winbindgen` CLI directly. It is NOT absent:

```
zig build run -- Microsoft.UI.Xaml.XamlTypeInfo
```

emits a full `XamlControlsXamlMetaDataProvider` / `IXamlControlsXamlMetaDataProvider` / `IXamlControlsXamlMetaDataProviderStatics` definition. Empirically confirmed via the probe harness that it is a plain default-activatable WinRT class (`IActivationFactory.ActivateInstance` → `S_OK`) and that the resulting instance really implements `IID_IXamlMetadataProvider` (`QueryInterface` → `S_OK`).

**Fix**: `com_aggregate.zig`'s `Outer` now activates one instance of this real framework provider (`activateRealProvider()`) and delegates every `IXamlMetadataProvider` method to it (`delegatingGetXamlType`/`delegatingGetXamlType2`/`delegatingGetXmlnsDefinitions`), falling back to the old "not found" stub only if activation fails for some reason. Re-ran the exact same probe:

```
issue74_probe: ---- stage: post-construct ----
issue74_probe: XamlControlsXamlMetaDataProvider ActivateInstance: S_OK (0x00000000)
issue74_probe: XamlControlsXamlMetaDataProvider -> QI(IID_IXamlMetadataProvider): S_OK (0x00000000)
issue74_probe: QueryInterface(IID_IXamlMetadataProvider): S_OK (0x00000000)
issue74_probe: get_Resources: FAILED 0x8000FFFF
issue74_probe: XamlControlsResources.activate: S_OK
issue74_probe: ---- stage: post-mount ----
...
issue74_probe: XamlControlsResources.activate: S_OK
issue74_probe: ---- stage: post-activate ----
...
issue74_probe: XamlControlsResources.activate: S_OK
```

**`XamlControlsResources.activate()` now succeeds (`S_OK`) at every stage.** This confirms the real fix is "aggregate `Application` behind an `IXamlMetadataProvider` that delegates to the real, already-shipped `XamlControlsXamlMetaDataProvider` framework class" — no XAML vendoring needed at all. **Phase 2-Fallback is not needed; revert to (a corrected) Phase 2.**

**New wrinkle found**: with this change, the probe run now hits a *new*, different crash — a segfault inside `Microsoft.UI.Xaml.dll` during process teardown (after the `--exit-after-ms` timer closes the window, inside `RoUninitialize()`), not the original startup `0xC000027B`. The probe's repeated activate-then-immediately-release of a throwaway `XamlControlsResources` instance at all three stages (without ever merging it into `Application.Resources`) is a likely culprit and does not reflect how the real Phase 2 implementation will use it (merge once, keep it alive, same "leak until process exit" pattern `app.zig` already uses for `Application` itself). Next step: implement the real merge (single `XamlControlsResources` instance appended to `Application.Resources.MergedDictionaries`, never explicitly released) and re-check whether the shutdown crash persists.

### Follow-up (same session): real merge implemented; core #74 bug confirmed fixed; separate shutdown-time issue found

Changed `issue74_probe.zig` to do the real (not throwaway) usage pattern: activate exactly one `XamlControlsResources`, `Append` it into `MergedDictionaries` (only once, guarded by a `merged_dictionaries_populated` flag, at the first stage `Resources` is queryable), then release only *our* activation reference (the vector holds its own, per normal WinRT collection semantics) rather than leaking or repeatedly churning instances.

**The core issue #74 bug is fixed.** With the real provider delegation (previous section) plus this real merge, added a direct validation to the probe: construct a real `Microsoft.UI.Xaml.Controls.TextBox` via plain `CreateInstance(null, ...)` (the exact construction path `winui_backend.zig`'s `.text_box` case uses) immediately after the merge, then release it. Output:

```
issue74_probe: MergedDictionaries.Append(XamlControlsResources): S_OK (0x00000000)
issue74_probe: TextBox CreateInstance (real construction, the original #74 repro): S_OK (0x00000000)
issue74_probe: TextBox construction+release completed WITHOUT crashing.
```

No `0xC000027B` crash. This is the exact repro from the issue body (`TextBox` construction crashing the process) and it no longer crashes.

**A separate, new shutdown-time issue was found, and it is NOT specific to `TextBox`.** Once the real merge is in place (regardless of whether a `TextBox` is ever constructed — confirmed via bisection, see below), the process no longer exits cleanly with `--exit-after-ms`:

- Before this session's fix (bare `Application`, no working theme resources): `zig build run-reactor-hello -- --exit-after-ms 2000` on **unmodified `main`** exits with code `0` (verified in a separate, unmodified worktree at `C:\Users\cataggar\ms\windows-zig`).
- After the real merge lands (`Outer` delegating to `XamlControlsXamlMetaDataProvider`, `XamlControlsResources` appended to `MergedDictionaries`): the same command now exits with code `116`, with **no stack trace** and **no crash message** printed — a debug print placed directly around `IApplicationStatics.Start(callback)` in `app.zig` never fires, meaning execution never returns from `Start(...)` at all; something terminates the process from within the blocking WinUI message pump itself (possibly a fail-fast/telemetry-driven termination internal to `Microsoft.WindowsAppRuntime`/`Microsoft.UI.Xaml.dll`, not a normal Zig-catchable access violation).
- **Bisected**: this reproduces identically whether or not the probe's `TextBox` construction+release test runs at all (removing it from the probe still produces the same exit code `116`). So this is triggered by **the resource merge itself** (or possibly the aggregation + real-provider-delegation it depends on), not by constructing a `TextBox`.
- This is a distinct failure mode from the original bug: no crash dump, no `Microsoft.UI.Xaml.dll` stack frames, a different (and unexplained) exit code, and it happens at/after shutdown rather than at `TextBox` construction time. It is consistent with the *class* of problem the plan's own "What We're NOT Doing" section already excludes as out of scope — the pre-existing "shutdown leak/crash" tracked in issue #60 — but whether it is literally the same root cause as #60 has not been confirmed.

**Current state of the worktree**: `packages/win-reactor/src/winui_backend.zig`'s `.text_box` case has been left as `error.NotYetSupported` (reverted after validating it works, since Phase 3's permanent re-enable should wait until the shutdown issue is understood/resolved or explicitly deferred). `packages/win-reactor/src/issue74_probe.zig` retains the working merge + the throwaway `TextBox` construction validation (both gated behind the temporary `issue74_use_aggregated_application` toggle in `app.zig`, unchanged). `zig build test --summary all`: 178/178 steps, 218/220 tests (2 skipped, expected) — the pre-existing package test suite doesn't exercise this runtime path, so it stays green regardless.

**Recommendation for whoever continues:** the `IXamlMetadataProvider`-delegation approach is confirmed correct and should become the permanent Phase 2 implementation (wire `com_aggregate.zig` permanently into `app.zig`, backfill the small `IResourceDictionary`/`XamlControlsResources` ABI into the shared curated `winui/` surface instead of `issue74_probe.zig`'s ad-hoc copy, per the original Phase 2 changes-required list above). Before re-enabling `TextBox` permanently (Phase 3), the new shutdown-time exit-116 issue needs investigation: bisect further (does merging *any* `ResourceDictionary.MergedDictionaries` entry trigger it, or specifically `XamlControlsResources`? does it happen without the aggregation/real-provider delegation, e.g. by merging an empty custom `ResourceDictionary` instead? does `--exit-after-ms`'s `WM_CLOSE`-driven shutdown path matter, or does it reproduce on a normal user-initiated window close too?), and cross-reference against #60's own investigation notes once found.

---

## Phase 2: Wire aggregation permanently and merge theme resources (only if Phase 1 succeeds)

### Overview

If Phase 1 confirms that an aggregated `Application` with a stub `IXamlMetadataProvider` allows `XamlControlsResources` (or an equivalent resource dictionary) to activate successfully, make that wiring permanent and merge it into `Application.Resources.MergedDictionaries` at the timing Phase 1 determined is safe.

### Changes Required

#### 1. Make aggregated `Application` construction permanent
**File**: `packages/win-reactor/src/app.zig`

**Changes**:
- Replace the temporary probe-gated construction from Phase 1 with the aggregated constructor unconditionally.
- Remove the throwaway probe code, keeping only the parts that are now load-bearing (the resource merge itself).

#### 2. Merge `XamlControlsResources` at the confirmed-safe point
**File**: `packages/win-reactor/src/app.zig`

**Changes**:
- Add a bootstrap helper (e.g. `ensureControlThemeResources(application: *xaml.Application) !void`) that: obtains `Application.Resources`, obtains `MergedDictionaries`, activates one `XamlControlsResources` instance (hand-authored `activate()` per the #54 workaround already used elsewhere in the curated surface), appends it, and releases temporary refs.
- Call it at the point Phase 1's probes showed is both valid (`S_OK`, not `E_UNEXPECTED`) and early enough relative to the first possible `TextBox` construction. If Phase 1 shows `Resources` genuinely isn't queryable early enough to run before `mountInitial()`, this phase must also change `ReactorHost.start(...)`'s sequencing (e.g., deferring real `TextBox` construction for widgets present in the very first mount to a follow-up dispatcher tick after the merge completes) rather than silently accepting a race.

#### 3. Backfill the reactor-local WinUI binding surface needed for the merge
**Files**:
- `packages/win-reactor/src/winui/Microsoft.UI.Xaml.zig`
- `packages/win-reactor/src/winui/Microsoft.UI.Xaml.Controls.zig`

**Changes**:
- Add a minimal ABI-accurate `IResourceDictionary`/`ResourceDictionary` definition (`QueryInterface`/`AddRef`/`Release` + `get_MergedDictionaries`), sourcing IIDs/method order from `packages/win/src/generated/Microsoft.UI.Xaml.zig`.
- Add a narrow merged-dictionary vector consumer exposing just `Append` (mirroring the `IVector` slot order already proven in `packages/win-collections/src/interfaces.zig:287-400`).
- Add `IXamlControlsResources`/`XamlControlsResources` with a hand-authored `activate()` that calls `win_core.activateInstance(...)` directly (bypassing the known-broken generated helper, per #54).

### Success Criteria

- `packages/win-reactor/src/app.zig` merges a working theme-resource dictionary into `Application.Resources.MergedDictionaries` before any `TextBox` can be constructed.
- A throwaway `TextBox` construction + `Window.Content` assignment in a probe build renders without the `0xC000027B` crash.

**Implementation Note**: Pause here for manual confirmation before proceeding to Phase 3.

---

## Phase 2-Fallback: Vendor `themeresources.xaml` and bypass `ms-appx://` (only if Phase 1 shows aggregation is insufficient)

### Overview

If Phase 1 shows that exposing `IXamlMetadataProvider` alone does not unblock the `E_FAIL`/`0x80004005` theme-resource load, bypass `ms-appx://` resolution entirely by vendoring the actual resource markup and loading it via `XamlReader.Load(...)`.

### Changes Required

#### 1. Vendor the MIT-licensed theme resource markup
**Files**:
- New `vendor/winui-resources/` directory + README (mirroring `vendor/winmd/README.md`'s documented-provenance style)

**Changes**:
- From the `microsoft/microsoft-ui-xaml` GitHub repo, at the tag/branch matching the vendored `Microsoft.UI.Xaml.winmd` version (`2.2.1`, per `vendor/winmd/README.md`), locate and copy `themeresources.xaml` (and any dictionaries it directly `<ResourceDictionary.MergedDictionaries>`-merges that `TextBox`'s default style actually needs — focus visuals, placeholder-text brushes, etc.; not necessarily the full control set).
- Commit these files directly to git (MIT license permits it), with a README documenting the exact source repo path, commit/tag, and license, following the same table format `vendor/winmd/README.md` uses for its MIT-licensed rows.
- Confirm via a text diff/scan that the vendored XAML doesn't reference any `ms-appx://` URIs itself that would reintroduce the same resolution failure one level down (some theme dictionaries merge sibling files by `ms-appx://` `Source` URI); if it does, either vendor those sibling files too and rewrite the merge to load them the same way, or point them at absolute file paths under the app's own install directory.

#### 2. Embed or load the vendored XAML at runtime
**Files**:
- `packages/win-reactor/src/app.zig` (or a new `packages/win-reactor/src/theme_resources.zig`)

**Changes**:
- Embed the vendored XAML text via `@embedFile(...)` (avoids needing to ship/locate a loose file next to the installed exe).
- Add the minimal `Microsoft.UI.Xaml.Markup.XamlReader` binding needed (`IXamlReaderStatics.Load(xamlText) -> IInspectable`) to the curated WinUI surface.
- Call `XamlReader.Load(...)` with the embedded text, `cast` the result to `IResourceDictionary`, and append it to `Application.Resources.MergedDictionaries` using the same merged-dictionary vector consumer built in Phase 2 (item 3) / Phase 1's ABI lookup.

### Success Criteria

- The vendored resource dictionary loads via `XamlReader.Load(...)` without error, independent of `ms-appx://`/package-identity resolution.
- A throwaway `TextBox` construction + `Window.Content` assignment in a probe build renders without the `0xC000027B` crash.

**Implementation Note**: Pause here for manual confirmation before proceeding to Phase 3.

---

## Phase 3: Re-enable `TextBox` and validate with the live sample

### Overview

Remove the backend descope, update the sample/docs that still describe the crash workaround, and make the dedicated TextBox sample part of the existing WinUI smoke pattern. This phase is identical regardless of whether Phase 2 or Phase 2-Fallback was the one actually implemented.

### Changes Required

#### 1. Re-enable backend construction
**File**: `packages/win-reactor/src/winui_backend.zig`

**Changes**:
- Replace `.text_box => error.NotYetSupported,` (line 590) with the same construction path already used by other composable controls: `.text_box => ownInspectable(try createComposable(controls.TextBox, controls.ITextBoxFactory)),`.

No public API redesign is needed here; the `text_box(...)` builder and `TextChanged` wiring already exist.

#### 2. Remove stale `NotYetSupported` documentation
**Files**:
- `samples/reactor_notepad/main.zig` (header comment, lines 1-7)
- `docs/windows-reactor.md` (lines 493-495, 636)

**Changes**:
- Remove the comments that still say the sample exits with `error.NotYetSupported`.
- Update the sample header to advertise the same timed-smoke form used elsewhere, e.g. `zig build run-reactor-notepad -- --exit-after-ms 1500`.
- Update the widget surface docs so `text_box` is no longer described as blocked by issue #74.

#### 3. Extend the existing smoke condition to include the real TextBox sample
**File**: `build.zig:1985-1986`

**Changes**:
- Change the smoke condition from `std.mem.eql(u8, s.name, "reactor-hello") or std.mem.eql(u8, s.name, "reactor-counter")` to also include `or std.mem.eql(u8, s.name, "reactor-notepad")`, so `reactor-selftest` runs `zig build run-reactor-notepad -- --exit-after-ms 1500` the same way it already does for the other two samples.

### Success Criteria

- `.text_box` no longer returns `error.NotYetSupported`.
- `reactor_notepad` is the explicit live sample for TextBox regressions.
- `reactor-selftest` now exercises at least one WinUI app that really constructs a `TextBox`.
- The user-facing docs no longer describe the old issue-#74 workaround as the current state.

## Success Criteria

- `packages/win-reactor/src/app.zig` merges a working theme-resource dictionary before the first `TextBox` can be constructed (via whichever of Phase 2 / Phase 2-Fallback Phase 1 selected).
- `packages/win-reactor/src/winui_backend.zig` constructs a real `TextBox` again.
- `samples/reactor_notepad` and `docs/windows-reactor.md` no longer mention the `NotYetSupported` stopgap.
- `zig build reactor-selftest --summary all` passes with `reactor-notepad` included in the Windows-only smoke set.
- A manual `zig build run-reactor-notepad -- --exit-after-ms 1500` run opens a visible notepad window and exits without a new `Microsoft.UI.Xaml.dll` / `0xc000027b` Application Error event.

## Testing Strategy

### Targeted build/test commands

- `zig build test --summary all` — full repository validation per repo convention, run at least once after Phase 1's `win-core`/reactor-local aggregation code lands.
- `zig build reactor-selftest --summary all` — targeted existing repo step that runs `win-reactor` tests, builds reactor samples, and smoke-tests selected WinUI apps (`build.zig:321-322`).
- `zig build run-reactor-hello -- --exit-after-ms 1500` — the throwaway probe harness for Phase 1's investigation.
- `zig build run-reactor-notepad -- --exit-after-ms 1500` — dedicated live TextBox repro/validation command once `.text_box` is re-enabled (Phase 3).

### Manual validation steps

1. In PowerShell, capture a start timestamp:

   ```powershell
   $start = Get-Date
   ```

2. Launch the TextBox sample with the same auto-exit style used elsewhere:

   ```powershell
   zig build run-reactor-notepad -- --exit-after-ms 1500
   ```

3. While the sample is running (or from a second shell), verify window creation with the repo's existing `EnumWindows` sample:

   ```powershell
   zig build enum-windows
   .\zig-out\bin\enum-windows.exe | Select-String 'windows-zig reactor notepad'
   ```

   Expected result: at least one visible top-level window title starting with `windows-zig reactor notepad`.

4. After the sample exits, scan the Application log for new `Application Error` crash events since `$start`:

   ```powershell
   Get-WinEvent -FilterHashtable @{
     LogName = 'Application'
     ProviderName = 'Application Error'
     StartTime = $start
   } | Where-Object {
     $_.Message -match 'Microsoft\.UI\.Xaml\.dll' -or
     $_.Message -match '0xc000027b'
   }
   ```

   Expected result: no events from this run.

5. Run one existing non-TextBox smoke sample as a sanity regression if needed:

   ```powershell
   zig build run-reactor-counter -- --exit-after-ms 1500
   ```

### Dependency note on #52-#56

- This issue should **not** wait for #52-#55. The local curated binding route avoids those broader generator/import blockers.
- #56 is relevant because `MergedDictionaries` still degrades to `*anyopaque` in generated WinUI, but it should be handled here with a narrow reactor-local consumer shim rather than by making issue #56 a prerequisite.

## References

- Issue #74 — Reactor: real TextBox crashes with `0xC000027B` in `Microsoft.UI.Xaml.dll` (unpackaged app resource gap)
  <https://github.com/cataggar/windows-zig/issues/74>

- PR #80 — Plan: fix real TextBox crash via XamlControlsResources merge (#74) — draft, holds this document
  <https://github.com/cataggar/windows-zig/pull/80>

- Issue #21 — Widget batch: text & basic input controls
  <https://github.com/cataggar/windows-zig/issues/21>

- PR #71 — Widget batch: text & basic input controls
  <https://github.com/cataggar/windows-zig/pull/71>

- Issue #10 — Port windows-collections -> win-collections package
  <https://github.com/cataggar/windows-zig/issues/10>

- Issue #52 — winbindgen bundle emits empty Microsoft.UI dependency namespaces
  <https://github.com/cataggar/windows-zig/issues/52>

- Issue #53 — winbindgen emits undeclared IResourceManager/CoreWebView2 identifiers in WinUI namespaces
  <https://github.com/cataggar/windows-zig/issues/53>

- Issue #54 — Generated WinRT `activate()` helper passes `_Vtbl` type to `win_core.activateInstance`
  <https://github.com/cataggar/windows-zig/issues/54>

- Issue #55 — Composable WinUI runtime classes do not get `Factory/factory()` helpers
  <https://github.com/cataggar/windows-zig/issues/55>

- Issue #56 — WinUI event and collection members still fall back to `*anyopaque`
  <https://github.com/cataggar/windows-zig/issues/56>

- Issue #60 — shutdown leak/crash (explicitly out of scope for this issue)
  <https://github.com/cataggar/windows-zig/issues/60>

- `docs/multi-method-authoring.md` — `win-core.MultiInterfaceObject` pattern this plan's aggregation helper borrows plumbing from.
- `microsoft/microsoft-ui-xaml` (MIT-licensed) — source of `themeresources.xaml`/`generic.xaml` for the Phase 2-Fallback vendoring route.
  <https://github.com/microsoft/microsoft-ui-xaml>

- Reactor bootstrap and smoke references:
  - `packages/win-reactor/src/app.zig`
  - `packages/win-reactor/src/winui_backend.zig`
  - `packages/win-core/src/root.zig` (`Delegate`, `MultiInterfaceObject`)
  - `samples/reactor_notepad/main.zig`
  - `build.zig`
  - `docs/windows-reactor-port.md`
  - `docs/windows-reactor.md`
  - `vendor/winmd/README.md`
