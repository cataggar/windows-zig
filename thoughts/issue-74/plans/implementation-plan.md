# Issue #74 Implementation Plan

## Overview

Fix the real WinUI `TextBox` crash by merging `Microsoft.UI.Xaml.Controls.XamlControlsResources` into `Application.Resources.MergedDictionaries` during `win-reactor` app bootstrap, before the first reactor tree mount. Then re-enable real `.text_box` creation and validate with the dedicated `reactor_notepad` sample, the existing `--exit-after-ms` smoke pattern, window-title detection, and an Application Event Log crash scan.

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

## Desired End State

- `ReactorHost.start(...)` merges a `XamlControlsResources` instance into `Application.Resources.MergedDictionaries` before the first call to `mountInitial()`.
- `.text_box` once again creates a real WinUI `Microsoft.UI.Xaml.Controls.TextBox` instead of returning `error.NotYetSupported`.
- `samples/reactor_notepad` becomes the canonical in-tree TextBox validation sample and no longer documents the NotYetSupported stopgap.
- `reactor-selftest` includes the existing `--exit-after-ms 1500` smoke pattern for `reactor-notepad`, so TextBox stays covered by the same Windows-only smoke mechanism already used for `reactor-hello` and `reactor-counter`.
- A manual run of `zig build run-reactor-notepad -- --exit-after-ms 1500`:
  - opens a visible window whose title starts with `windows-zig reactor notepad`,
  - exits cleanly without a `0xC000027B` crash,
  - and produces no new `Application Error` events for `Microsoft.UI.Xaml.dll` in the Application log after the test start time.

### Key Discoveries

- The missing piece is **not** “emit `XamlControlsResources` somewhere in the repo”; the symbol already exists in generated bindings. The missing piece is “make the reactor-local curated WinUI surface expose the tiny ABI subset bootstrap actually needs” (`build.zig:195-239`; `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig:39523-39531`).
- The generated helper for `XamlControlsResources.activate()` is still affected by #54, so #74 should hand-author the local `activate()` helper instead of waiting on the emitter (`packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig:39527-39528`; `docs/windows-reactor-port.md:85-88`).
- #56 is relevant but not blocking: `MergedDictionaries` still falls back to `*anyopaque` in generated WinUI, but reactor already has established patterns for narrow raw collection consumers, so #74 can stay self-contained instead of taking #56 as a hard prerequisite (`docs/windows-reactor-port.md:89`; `packages/win-reactor/src/winui_backend.zig:123-145`).
- The historical “reactor_counter TextBox repro” from the issue body should be translated into today’s repo state as “use `reactor_notepad` for the live TextBox repro,” because that is the sample that still mounts the public `text_box(...)` API (`samples/reactor_notepad/main.zig:105-118`; `build.zig:1849-1854`).

## What We're NOT Doing

- We are **not** switching `win-reactor` wholesale from its curated WinUI surface to the full generated `packages/win/src/generated/` namespace files.
- We are **not** fixing issues #52-#56 globally in this issue. #74 should borrow the ABI details it needs and stay narrowly focused on bootstrapping theme resources for `TextBox`.
- We are **not** re-planning or implementing the broader emitter work for `Microsoft.UI.*` namespaces; sibling efforts already cover that.
- We are **not** broadening scope to unrelated runtime/lifetime problems such as the shutdown leak/crash tracked in #60.
- We are **not** adding permanent CI/Event-Viewer automation in this issue. Validation should follow the repo’s current split: build smoke in `build.zig`, plus manual `EnumWindows` / Application log checks.
- We are **not** reintroducing a `TextBox` into `reactor_counter` just to match the old repro text. `reactor_notepad` is already the dedicated TextBox sample and should remain the validation target.

## Implementation Approach

Use the generated WinUI files as an ABI reference source only, then backport the minimum required declarations into the reactor-local curated WinUI surface that `win-reactor` actually imports. Keep the fix self-contained:

1. **Fill the reactor-local binding gap**  
   Add the missing `ResourceDictionary` / `MergedDictionaries` / `XamlControlsResources` declarations directly under `packages/win-reactor/src/winui/`, sourcing IIDs and method order from the generated files but keeping the implementation in the curated modules.

2. **Avoid turning #56 into a prerequisite**  
   Do not wait for the emitter to hand back a typed `IVector<ResourceDictionary>`. Instead, add a narrow reactor-local merged-dictionary vector consumer that mirrors the `IVector` slot order from issue #10 and the raw collection pattern already used in `winui_backend.zig`. This gives bootstrap exactly one operation it needs: `Append(...)`.

3. **Run the resource merge before any widget mount**  
   The helper must run immediately after `Application` creation and before `WinUIBackend.init(...)` / `mountInitial()`, because the first `TextBox` can be created during the initial reactor tree mount.

4. **Re-enable TextBox only after bootstrap is in place**  
   The backend already has the `ITextBoxFactory` plumbing and the public `text_box(...)` API. Once theme resources are present, the actual code change is just to stop returning `error.NotYetSupported` and restore real `TextBox` construction.

5. **Validate with the sample that still mounts TextBox today**  
   Make `reactor_notepad` the authoritative repro/smoke target, wire it into `reactor-selftest`, and keep the manual Event Viewer scan outside the build system.

## Phase 1: Expand the reactor-local WinUI binding surface

### Overview

Backfill the small ABI surface missing from `packages/win-reactor/src/winui/` so app bootstrap can access `Application.Resources.MergedDictionaries` and construct `XamlControlsResources` without relying on the broken generated helper.

### Changes Required

#### 1. Add `ResourceDictionary` collection access to the curated XAML surface
**Files**:
- `packages/win-reactor/src/winui/Microsoft.UI.Xaml.zig`
- reference source: `packages/win/src/generated/Microsoft.UI.Xaml.zig`

**Changes**:
- Replace the current opaque `ResourceDictionary` placeholder with a minimal ABI-accurate definition:
  - `IResourceDictionary_Vtbl`
  - `IResourceDictionary`
  - `ResourceDictionary`
- Add a narrow merged-dictionary vector consumer that follows the `IVector` slot order from issue #10 but only exposes the operations bootstrap needs (`Append`, and the usual COM lifetime methods).
- Declare `IResourceDictionary.get_MergedDictionaries(...)` to return that narrow vector type directly, so `app.zig` does not need to reason about a raw `**anyopaque`.
- Keep the scope narrow: this is not a full projection of `ResourceDictionary`; it only needs to cover `QueryInterface`/`AddRef`/`Release` plus `MergedDictionaries`.

#### 2. Add a local `XamlControlsResources` activation surface
**Files**:
- `packages/win-reactor/src/winui/Microsoft.UI.Xaml.Controls.zig`
- reference source: `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig`

**Changes**:
- Add `IXamlControlsResources_Vtbl`, `IXamlControlsResources`, and `XamlControlsResources`.
- Hand-author `XamlControlsResources.activate()` using the same pattern already used for `TextBlock`, `ScrollViewer`, and `ToggleSwitch` in the curated controls file, so it calls `win_core.activateInstance(IXamlControlsResources, &NAME_W)` instead of depending on the known-broken generated helper.
- Keep the local surface minimal: #74 only needs activation and an interface IID; it does not need the full statics/property set.

#### 3. Sync the starter WinUI manifest comment/allowlist
**File**: `tools/bindings/src/winui.txt`

**Changes**:
- Add `Microsoft.UI.Xaml.Controls.XamlControlsResources` to the starter allowlist so the file no longer misleads future issue-#74 readers into thinking the type was never emitted.
- Treat this as a documentation-consistency update only. Do **not** make the functional fix depend on rerouting reactor to the generated WinUI bundle.

### Success Criteria

- `win-reactor` can compile against local curated definitions for:
  - `xaml.IResourceDictionary`
  - the merged-dictionary vector consumer
  - `controls.XamlControlsResources.activate()`
- No code in `win-reactor` needs to import the full generated `Microsoft.UI.Xaml*` modules directly.
- The new local helper surfaces are obviously sourced from the generated ABI, but they do not require #52-#56 to land first.

---

## Phase 2: Merge `XamlControlsResources` during app bootstrap

### Overview

Insert a one-time bootstrap step that merges WinUI’s default control resources into the app-wide resource dictionary before the first reactor widget tree is mounted.

### Changes Required

#### 1. Add a bootstrap helper in `app.zig`
**File**: `packages/win-reactor/src/app.zig`

**Changes**:
- Import `Microsoft.UI.Xaml.Controls` alongside the existing `Microsoft.UI.Xaml` import.
- Add a helper such as `ensureControlThemeResources(application: *xaml.Application) !void`.
- Inside that helper:
  1. reinterpret the runtime class pointer as `*const xaml.IApplication`,
  2. call `get_Resources(...)` to obtain the app-wide `ResourceDictionary`,
  3. call `get_MergedDictionaries(...)` to obtain the merged-dictionary vector,
  4. activate one `controls.XamlControlsResources`,
  5. append it to the vector,
  6. release temporary interface refs after the append succeeds.

#### 2. Invoke the helper in the only safe place
**File**: `packages/win-reactor/src/app.zig`

**Changes**:
- Call `ensureControlThemeResources(application)` immediately after:
  - `const application = try createComposable(xaml.Application, xaml.IApplicationFactory);`
- Do this **before**:
  - `self.backend_impl = winui_backend.WinUIBackend.init(...)`
  - `try self.mountInitial();`

That ordering is the core correctness rule for #74: the first `TextBox` construction must see a resource dictionary whose `MergedDictionaries` already contains `XamlControlsResources`.

### Success Criteria

- The bootstrap path still follows the existing `RoInitialize` → `MddBootstrapInitialize2` → `Application.Start` sequence.
- The new resource-merge helper runs exactly once per app start, before any reactor widget handle can be created.
- Existing non-TextBox samples continue to use the same app bootstrap path and remain behaviorally unchanged.

---

## Phase 3: Re-enable `TextBox` and validate with the live sample

### Overview

Remove the backend descope, update the sample/docs that still describe the crash workaround, and make the dedicated TextBox sample part of the existing WinUI smoke pattern.

### Changes Required

#### 1. Re-enable backend construction
**File**: `packages/win-reactor/src/winui_backend.zig`

**Changes**:
- Replace:
  - `.text_box => error.NotYetSupported,`
- with the same construction path already used by other composable controls:
  - `ownInspectable(try createComposable(controls.TextBox, controls.ITextBoxFactory))`

No public API redesign is needed here; the `text_box(...)` builder and TextChanged wiring already exist.

#### 2. Remove stale NotYetSupported documentation
**Files**:
- `samples/reactor_notepad/main.zig`
- `docs/windows-reactor.md`

**Changes**:
- Remove the comments that still say the sample exits with `error.NotYetSupported`.
- Update the sample header to advertise the same timed smoke form used elsewhere, e.g. `zig build run-reactor-notepad -- --exit-after-ms 1500`.
- Update the widget surface docs so `text_box` is no longer described as blocked by issue #74.

#### 3. Extend the existing smoke target to include the real TextBox sample
**File**: `build.zig`

**Changes**:
- Add `reactor-notepad` to the Windows-only `reactor-selftest` smoke condition that already runs `reactor-hello` and `reactor-counter` with `--exit-after-ms 1500`.
- Keep the implementation pattern identical to the current smoke steps: run the installed executable, rely on `stage-winui-runtime`, and use the auto-exit timer to keep the check non-interactive.

### Success Criteria

- `.text_box` no longer returns `error.NotYetSupported`.
- `reactor_notepad` is the explicit live sample for TextBox regressions.
- `reactor-selftest` now exercises at least one WinUI app that really constructs a `TextBox`.
- The user-facing docs no longer describe the old issue-#74 workaround as the current state.

## Success Criteria

- `packages/win-reactor/src/app.zig` merges `XamlControlsResources` before `mountInitial()`.
- `packages/win-reactor/src/winui_backend.zig` constructs a real `TextBox` again.
- `samples/reactor_notepad` and `docs/windows-reactor.md` no longer mention the NotYetSupported stopgap.
- `zig build reactor-selftest --summary all` passes with `reactor-notepad` included in the Windows-only smoke set.
- A manual `zig build run-reactor-notepad -- --exit-after-ms 1500` run opens a visible notepad window and exits without a new `Microsoft.UI.Xaml.dll` / `0xc000027b` Application Error event.

## Testing Strategy

### Targeted build/test commands

- `zig build reactor-selftest --summary all`  
  Targeted existing repo step that runs `win-reactor` tests, builds reactor samples, and smoke-tests selected WinUI apps (`build.zig:321-322`).

- `zig build run-reactor-notepad -- --exit-after-ms 1500`  
  Dedicated live TextBox repro/validation command once `.text_box` is re-enabled.

### Manual validation steps

1. In PowerShell, capture a start timestamp:

   ```powershell
   $start = Get-Date
   ```

2. Launch the TextBox sample with the same auto-exit style used elsewhere:

   ```powershell
   zig build run-reactor-notepad -- --exit-after-ms 1500
   ```

3. While the sample is running (or from a second shell), verify window creation with the repo’s existing `EnumWindows` sample:

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

- #74 should **not** wait for #52-#55. The local curated binding route avoids those broader generator/import blockers.
- #56 is relevant because `MergedDictionaries` still degrades to `*anyopaque` in generated WinUI, but it should be handled here with a narrow reactor-local consumer shim rather than by making issue #56 a prerequisite.

## References

- Issue #74 — Reactor: real TextBox crashes with `0xC000027B` in `Microsoft.UI.Xaml.dll` (unpackaged app resource gap)  
  <https://github.com/cataggar/windows-zig/issues/74>

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

- Reactor bootstrap and smoke references:
  - `packages/win-reactor/src/app.zig`
  - `packages/win-reactor/src/winui_backend.zig`
  - `samples/reactor_notepad/main.zig`
  - `build.zig`
  - `docs/windows-reactor-port.md`
  - `docs/windows-reactor.md`
