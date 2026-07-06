# Issue #52 Implementation Plan

## Overview

`winbindgen bundle` is emitting empty `Microsoft.UI.*` dependency modules because the CLI only stages and selects `Microsoft.UI.Xaml.winmd` / `Microsoft.UI.Text.winmd`, while several referenced WinUI dependency namespaces actually live in a separate `Microsoft.UI.winmd`. Fixing issue #52 requires both (1) teaching the fetch/select pipeline about that metadata file and (2) making the generated WinUI dependency manifest represent a compilable transitive namespace set instead of only the starter roots' direct imports.

## Current State Analysis

- `tools/fetch-winui-metadata/main.zig:25-43` is hard-coded to a single NuGet package (`microsoft.windowsappsdk.winui` version `2.2.1`) and extracts only `metadata/Microsoft.UI.Xaml.winmd` and `metadata/Microsoft.UI.Text.winmd`.
- `vendor/winmd/README.md:32-56` documents only those two fetched WinUI metadata files and says `zig build fetch-winui-metadata` extracts only those two paths.
- `packages/winbindgen/src/main.zig:38-60` defines only `winui_xaml` and `winui_text` fetched metadata sources, and routes every `Microsoft.UI.*` namespace except `Microsoft.UI.Text.*` to `Microsoft.UI.Xaml.winmd`.
- `packages/winbindgen/src/main.zig:148,518` iterates only `.winrt`, `.win32`, `.wdk`, `.winui_xaml`, and `.winui_text` when listing namespaces and grouping bundle inputs by metadata source.
- `packages/winbindgen/src/root.zig:110-114` treats the full `Microsoft.UI.*` surface as projectable, so dependency discovery happily records those namespaces as valid imports.
- `packages/winbindgen/src/root.zig:367-452` always writes the common prelude for a namespace file; if no matching `TypeDef`s exist in the chosen metadata file, the result is the observed prelude-only stub.
- `build.zig:933-959` generates the checked-in WinUI snapshot from only `Microsoft.UI.Xaml` and `Microsoft.UI.Xaml.Controls`, then copies only those root files plus `winui_bundle_deps.zig` into `packages/win/src/generated/`.
- `packages/win/src/generated/winui_bundle_deps.zig:9-10` already records dependencies on `Microsoft.UI`, `Microsoft.UI.Composition`, `Microsoft.UI.Content`, `Microsoft.UI.Dispatching`, `Microsoft.UI.Input`, and `Microsoft.UI.Windowing`.
- `packages/win/src/generated/Microsoft.UI.Xaml.zig:4-8,6591-6598,6744-6745` imports `Microsoft.UI.Composition`, `Microsoft.UI.Dispatching`, and `Microsoft.UI.Windowing`, and directly references `Compositor`, `DispatcherQueue`, and `AppWindow`.
- `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig:5-6,5776,29895,31471-31502` imports `Microsoft.UI.Composition`, `Microsoft.UI.Input`, and `Microsoft.UI`, and directly references `Compositor`, `InputPointerSource`, and `WindowId`.
- `samples/winui_minimal_bindings/main.zig:3-10` explicitly documents #52 as one reason the repository avoids importing the full checked-in WinUI snapshot directly today.

## Desired End State

After the fix:

1. `zig build fetch-winui-metadata` stages `vendor/winmd/Microsoft.UI.winmd` alongside the existing XAML/Text files.
2. `winbindgen` routes `Microsoft.UI.Xaml.*` to `Microsoft.UI.Xaml.winmd`, `Microsoft.UI.Text.*` to `Microsoft.UI.Text.winmd`, and the remaining `Microsoft.UI.*` namespaces to `Microsoft.UI.winmd`.
3. `packages/win/src/generated/winui_bundle_deps.zig` describes a namespace set that is actually sufficient to materialize a compilable dependency bundle for the checked-in WinUI snapshot.
4. Re-running the issue repro with the regenerated manifest produces non-empty `Microsoft.UI.zig`, `Microsoft.UI.Composition.zig`, `Microsoft.UI.Content.zig`, `Microsoft.UI.Dispatching.zig`, `Microsoft.UI.Input.zig`, and `Microsoft.UI.Windowing.zig`.
5. A targeted compile canary proves the formerly-empty namespaces export the concrete WinUI types the checked-in XAML snapshot expects (`WindowId`, `ContentIsland`, `DispatcherQueue`, `InputPointerSource`, `Compositor`, `AppWindow`) without depending on still-open issues #53-#56.

## Key Discoveries

- The empty-file behavior is a metadata-source mismatch, not a “missing type in metadata” problem. Local reproduction on 2026-07-06 showed that `zig build run -- --list | Select-String '^Microsoft\.UI'` only enumerates `Microsoft.UI.Xaml*` and `Microsoft.UI.Text`, which matches the source-selection code in `packages/winbindgen/src/main.zig:38-60`.
- Local inspection of `Microsoft.WindowsAppSDK.WinUI.2.2.1.nupkg` confirmed it contains only `metadata/Microsoft.UI.Xaml.winmd` and `metadata/Microsoft.UI.Text.winmd`, which matches `tools/fetch-winui-metadata/main.zig:41-43` and `vendor/winmd/README.md:32-56`.
- Local inspection of the WinUI package’s nuspec showed it depends on `Microsoft.WindowsAppSDK.InteractiveExperiences` version `2.0.15`; extracting that package exposed `metadata/10.0.18362.0/Microsoft.UI.winmd`.
- Temporary type probes against that extracted `Microsoft.UI.winmd` confirmed that the concrete missing WinUI types already exist there: `Microsoft.UI.Composition.Compositor`, `Microsoft.UI.Dispatching.DispatcherQueue`, `Microsoft.UI.Windowing.AppWindow`, `Microsoft.UI.WindowId`, `Microsoft.UI.Input.InputPointerSource`, and `Microsoft.UI.Content.ContentIsland`.
- Fixing source routing alone is not enough for `winui_bundle_deps.zig` consumers. Local multi-source closure probing showed that once `Microsoft.UI.*` modules become real, they pull in additional Windows namespaces such as `Windows.Graphics`, `Windows.Graphics.Effects`, `Windows.System`, `Windows.UI`, `Windows.UI.Composition`, and `Windows.UI.Core`, which are not present in the current two-entry manifest at `packages/win/src/generated/winui_bundle_deps.zig:9-10`.
- “Graceful degradation” to `*anyopaque` would be the wrong primary fix here because the missing handle types are present in shipped metadata; the repository should preserve typed WinUI projections instead of discarding fidelity.

## What We're NOT Doing

- We are **not** broadening the checked-in WinUI snapshot beyond the current committed starter files (`Microsoft.UI.Xaml.zig`, `Microsoft.UI.Xaml.Controls.zig`, `Microsoft.UI.Xaml.Controls.Primitives.zig`, and the dependency manifest).
- We are **not** fixing the separate WinUI import blockers tracked in:
  - #53 (`IResourceManager` / `CoreWebView2*` undeclared identifiers)
  - #54 (bad `_Vtbl` type passed to `activateInstance`)
  - #55 (missing composable factory helpers)
  - #56 (remaining `*anyopaque` fallbacks)
- We are **not** papering over the bug by replacing valid WinUI references with `*anyopaque`.
- We are **not** changing generic Win32/WDK bundle semantics unless the change is required to support the WinUI transitive-closure flow.

## Implementation Approach

Keep the single-metadata-file emitter in `packages/winbindgen/src/root.zig` unchanged. The issue is in the orchestration layer: which `.winmd` files are fetched, how namespaces are mapped to those files, and how the WinUI starter snapshot’s dependency manifest is derived.

The implementation should therefore:

1. Expand the fetched WinUI metadata set to include the missing `Microsoft.UI.winmd`.
2. Split `Microsoft.UI.*` routing so XAML/Text stay on their existing files and the rest of WinUI resolves through `Microsoft.UI.winmd`.
3. Add a transitive-closure mode to the bundle driver so the WinUI bindings pipeline can generate a dependency manifest that remains valid after `Microsoft.UI.*` namespaces stop being empty stubs.
4. Add a narrowly-scoped compile canary for the previously-empty dependency namespaces, without waiting for the full checked-in WinUI snapshot to import cleanly end-to-end.

## Phase 1: Stage and route `Microsoft.UI.winmd`

### Overview

Teach the fetch pipeline and namespace selector about the metadata file that actually defines the missing WinUI dependency namespaces.

### Changes Required

#### 1. Extend the WinUI metadata fetch tool
**File**: `tools/fetch-winui-metadata/main.zig`  
**Changes**:
- Replace the single-package constants with a small `PackageSpec` table so the tool can fetch more than one NuGet package deterministically.
- Keep the current `Microsoft.WindowsAppSDK.WinUI` package entry for `Microsoft.UI.Xaml.winmd` and `Microsoft.UI.Text.winmd`.
- Add a second pinned package entry for `Microsoft.WindowsAppSDK.InteractiveExperiences` version `2.0.15`, extracting `metadata/10.0.18362.0/Microsoft.UI.winmd` to `vendor/winmd/Microsoft.UI.winmd`.
- Keep checksum verification per package and keep `haveWantedFiles` / idempotency logic working across all required outputs.

#### 2. Document the third fetched WinUI metadata file
**File**: `vendor/winmd/README.md`  
**Changes**:
- Add `Microsoft.UI.winmd` to the fetched-on-demand table with its source package and version.
- Update the explanatory text and bump instructions so future refreshes know that the WinUI metadata set now comes from two packages, not one.

#### 3. Split WinUI namespace routing by actual metadata file
**File**: `packages/winbindgen/src/main.zig`  
**Functions/areas**:
- top-of-file metadata path constants (`:38-39`)
- `MetadataSource` enum (`:41-46`)
- `selectMetadataSource` (`:56-60`)
- `metadataDisplayName`, `metadataPath`, `isFetchedMetadata`, `loadMetadataBytes`
- source iteration loops at `:148` and `:518`

**Changes**:
- Add a third fetched metadata source (name it explicitly, e.g. `winui_ui`) for `vendor/winmd/Microsoft.UI.winmd`.
- Change routing order to:
  - `Microsoft.UI.Xaml` / subnamespaces → `Microsoft.UI.Xaml.winmd`
  - `Microsoft.UI.Text` / subnamespaces → `Microsoft.UI.Text.winmd`
  - remaining `Microsoft.UI` namespaces → `Microsoft.UI.winmd`
- Update the `//!` file header so the documented namespace-to-winmd map matches reality.
- Keep `runReactorBindings` on `Microsoft.UI.Xaml.winmd` for now because the reactor generator is still XAML-manifest-driven.

### Success Criteria

- `zig build fetch-winui-metadata` leaves `Microsoft.UI.Xaml.winmd`, `Microsoft.UI.Text.winmd`, and `Microsoft.UI.winmd` under `vendor/winmd/`.
- `zig build run -- --list | Select-String '^Microsoft\.UI'` includes `Microsoft.UI`, `Microsoft.UI.Composition`, `Microsoft.UI.Content`, `Microsoft.UI.Dispatching`, `Microsoft.UI.Input`, and `Microsoft.UI.Windowing`.
- `zig build run -- bundle --arch=x64 --imports=module --outdir issue52-smoke Microsoft.UI.Composition` no longer emits a prelude-only stub.

## Phase 2: Generate a transitive WinUI dependency manifest

### Overview

Once `Microsoft.UI.*` modules stop being empty, the current root-only dependency manifest becomes too small. The WinUI bindings pipeline needs a transitive, multi-metadata closure so the checked-in starter snapshot can be rebuilt into a real dependency bundle.

### Changes Required

#### 1. Add transitive-closure support to `winbindgen bundle`
**File**: `packages/winbindgen/src/main.zig`  
**Functions/areas**:
- `runBundle` (`:424-571`)
- new helper(s) near `selectMetadataSource` / metadata loading

**Changes**:
- Add an opt-in bundle flag (for example `--closure=transitive`) so WinUI generation can expand the requested roots to their full cross-metadata namespace closure before emission.
- Implement a helper that:
  - starts from the user-specified root namespaces
  - groups the current frontier by `MetadataSource`
  - lazily loads each `.winmd` once
  - calls `winbindgen.collectNamespaceClosure` for each metadata group
  - repeats until no new namespaces are discovered
  - returns a sorted, deduplicated namespace list
- Feed that expanded namespace list into the existing per-source bundle emission path so `runBundle` emits concrete dependency modules and writes a manifest for the full emitted set.
- Keep the default bundle behavior unchanged for existing callers that only want the explicitly requested namespaces.

#### 2. Switch the WinUI bindings pipeline to transitive bundle generation
**File**: `build.zig`  
**Functions/areas**:
- WinUI bindings block at `:933-980`
- helper `addGeneratedNamespaceImports` at `:2052-2061`

**Changes**:
- Add the new transitive-closure flag to `winui_bundle_run` so the cached bundle output contains the full namespace set needed by `Microsoft.UI.Xaml` and `Microsoft.UI.Xaml.Controls`.
- Stop generating `Microsoft.UI.Xaml.Controls.Primitives.zig` from a separate one-off bundle run; copy it from the transitive WinUI bundle output instead so all committed WinUI snapshot files are produced from one consistent namespace set.
- Continue copying only the committed starter files and the regenerated `winui_bundle_deps.zig` into source control; the rest of the closure can stay build-cache-only.
- Update the WinUI bundle comments so they no longer describe the manifest as a shallow dependency list.

#### 3. Regenerate the committed WinUI dependency manifest
**File**: `packages/win/src/generated/winui_bundle_deps.zig`  
**Changes**:
- Regenerate it from the transitive bundle output.
- Expect the manifest to grow beyond the current two-entry direct-import list so it can reproduce the newly non-empty `Microsoft.UI.*` modules and the Windows namespaces they import.

### Success Criteria

- `zig build bindings` regenerates `packages/win/src/generated/winui_bundle_deps.zig` from the transitive WinUI closure.
- Re-running the issue repro with the regenerated manifest produces non-empty `Microsoft.UI.zig`, `Microsoft.UI.Composition.zig`, `Microsoft.UI.Content.zig`, `Microsoft.UI.Dispatching.zig`, `Microsoft.UI.Input.zig`, and `Microsoft.UI.Windowing.zig`.
- The regenerated manifest is deterministic across repeated `zig build bindings` runs.

## Phase 3: Add a targeted dependency-namespace canary

### Overview

Catch regressions in the formerly-empty WinUI dependency namespaces without depending on the broader WinUI snapshot issues that are still tracked separately.

### Changes Required

#### 1. Add a build-only WinUI dependency canary source
**File**: `tools/winui_dependency_canary.zig`  
**Changes**:
- Add a compile-only test/root that imports the generated dependency modules and references the concrete types that #52 needs to exist:
  - `@"Microsoft.UI".WindowId`
  - `@"Microsoft.UI.Content".ContentIsland`
  - `@"Microsoft.UI.Dispatching".DispatcherQueue`
  - `@"Microsoft.UI.Input".InputPointerSource`
  - `@"Microsoft.UI.Composition".Compositor`
  - `@"Microsoft.UI.Windowing".AppWindow`

#### 2. Wire the canary into the build graph using the transitive bundle output
**File**: `build.zig`  
**Changes**:
- Create build modules from the transitive WinUI bundle output for the six formerly-empty WinUI namespaces:
  - `Microsoft.UI`
  - `Microsoft.UI.Composition`
  - `Microsoft.UI.Content`
  - `Microsoft.UI.Dispatching`
  - `Microsoft.UI.Input`
  - `Microsoft.UI.Windowing`
- Also create the small Windows dependency set those modules need, based on the researched closure:
  - `Windows.Foundation`
  - `Windows.Foundation.Collections`
  - `Windows.Foundation.Numerics`
  - `Windows.Graphics`
  - `Windows.Graphics.Effects`
  - `Windows.System`
  - `Windows.UI`
  - `Windows.UI.Composition`
  - `Windows.UI.Core`
- Use `addGeneratedNamespaceImports` to wire those generated modules together, then add a test/compile step rooted at `tools/winui_dependency_canary.zig`.

#### 3. Remove the stale “#52 is still blocking” comment
**File**: `samples/winui_minimal_bindings/main.zig`  
**Changes**:
- Update the explanatory comment so it no longer lists empty `Microsoft.UI.*` dependency modules / #52 as an outstanding blocker once the fix lands.
- Keep the remaining references to #53-#56 as appropriate.

### Success Criteria

- The new canary compiles during normal validation and fails if any of the six formerly-empty namespaces regress back to stubs or lose their key types.
- `samples/winui_minimal_bindings/main.zig` reflects that #52 is fixed while the remaining WinUI gaps stay explicitly tracked.

## Testing Strategy

### Targeted metadata checks
- Run `zig build fetch-winui-metadata`.
- Verify `vendor/winmd/Microsoft.UI.winmd` exists beside the existing XAML/Text files.
- Run `zig build run -- --list | Select-String '^Microsoft\.UI'` and confirm the newly-supported namespaces appear.

### Targeted bundle reproduction
- Run:
  1. `zig build bindings`
  2. `zig build run -- bundle --arch=x64 --imports=module --outdir issue52-repro-full-bundle <namespaces from packages/win/src/generated/winui_bundle_deps.zig>`
- Inspect:
  - `issue52-repro-full-bundle\Microsoft.UI.zig`
  - `issue52-repro-full-bundle\Microsoft.UI.Composition.zig`
  - `issue52-repro-full-bundle\Microsoft.UI.Content.zig`
  - `issue52-repro-full-bundle\Microsoft.UI.Dispatching.zig`
  - `issue52-repro-full-bundle\Microsoft.UI.Input.zig`
  - `issue52-repro-full-bundle\Microsoft.UI.Windowing.zig`
- Verify those files contain real declarations rather than only the prelude.
- Use `Select-String` or equivalent to confirm the presence of:
  - `WindowId`
  - `ContentIsland`
  - `DispatcherQueue`
  - `InputPointerSource`
  - `Compositor`
  - `AppWindow`

### Compile validation
- Run the new WinUI dependency canary through the build graph.
- Run `zig build test` to ensure the repository’s existing package/unit coverage still passes.

### Cleanup
- Delete the ad-hoc repro output directory after manual verification so the worktree stays clean.

## References

- GitHub issue #52: `https://github.com/cataggar/windows-zig/issues/52`
- Related gap-inventory issue #3: `https://github.com/cataggar/windows-zig/issues/3`
- Related follow-up issues:
  - #53 — `https://github.com/cataggar/windows-zig/issues/53`
  - #54 — `https://github.com/cataggar/windows-zig/issues/54`
  - #55 — `https://github.com/cataggar/windows-zig/issues/55`
  - #56 — `https://github.com/cataggar/windows-zig/issues/56`
- Repository references:
  - `tools/fetch-winui-metadata/main.zig:25-43`
  - `vendor/winmd/README.md:32-56`
  - `packages/winbindgen/src/main.zig:38-60,148,518`
  - `packages/winbindgen/src/root.zig:110-114,367-452`
  - `build.zig:933-980,2052-2061`
  - `packages/win/src/generated/winui_bundle_deps.zig:9-10`
  - `packages/win/src/generated/Microsoft.UI.Xaml.zig:4-8,6591-6598,6744-6745`
  - `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig:5-6,5776,29895,31471-31502`
  - `samples/winui_minimal_bindings/main.zig:3-10`
- Local research performed in this worktree on 2026-07-06:
  - `Microsoft.WindowsAppSDK.WinUI.2.2.1.nupkg` contains only `Microsoft.UI.Xaml.winmd` and `Microsoft.UI.Text.winmd`.
  - Its nuspec depends on `Microsoft.WindowsAppSDK.InteractiveExperiences` version `2.0.15`.
  - `Microsoft.WindowsAppSDK.InteractiveExperiences.2.0.15.nupkg` contains `metadata/10.0.18362.0/Microsoft.UI.winmd`.
  - Temporary type probes against that file found `Microsoft.UI.WindowId`, `Microsoft.UI.Content.ContentIsland`, `Microsoft.UI.Dispatching.DispatcherQueue`, `Microsoft.UI.Input.InputPointerSource`, `Microsoft.UI.Composition.Compositor`, and `Microsoft.UI.Windowing.AppWindow`.
