# Issue #53 Implementation Plan

## Overview

Issue #53 is caused by the WinUI namespace emitter treating some foreign reference types as if they were declared locally. The fix should keep the existing `Windows.*` / `Microsoft.UI.*` import model intact and instead synthesize explicit local opaque placeholders for unsupported external reference types so the generated WinUI snapshots are importable again without pretending the repository already vendors those foreign metadata surfaces.

## Current State Analysis

- `packages/win/src/generated/Microsoft.UI.Xaml.zig:4156-4159` and `packages/win/src/generated/Microsoft.UI.Xaml.zig:8334-8335` emit `IResourceManagerRequestedEventArgs` members that reference `IResourceManager`, but the file does not declare or import that identifier anywhere.
- `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig:36562-36563`, `:36749-36753`, and `:46426`, `:46455-46456` emit `CoreWebView2`, `CoreWebView2Environment`, and `CoreWebView2ControllerOptions` the same way.
- `packages/win/src/generated/winui_bundle_deps.zig:9-10` records only `Microsoft.UI.*` and `Windows.*` dependencies for the checked-in WinUI bundle; neither `Microsoft.Windows.ApplicationModel.Resources` nor `Microsoft.Web.WebView2.Core` is tracked as a dependency.
- `packages/winbindgen/src/root.zig:110-114` hard-codes the “projectable namespace” allowlist to `Windows*` plus `Microsoft.UI*`.
- `packages/winbindgen/src/root.zig:192-210` uses that same allowlist when collecting namespace closure dependencies, so non-projectable foreign types never become imports or bundle manifest entries.
- `packages/winbindgen/src/root.zig:367-421` buffers the namespace body, then emits only the imports reported through `CrossNsSet`; there is no second mechanism that declares unsupported foreign types locally.
- `packages/winbindgen/src/root.zig:3491-3521` considers every `.class_name` and `.value_name` representable, so the vtbl/method emitters do not fall back before rendering these signatures.
- `packages/winbindgen/src/root.zig:3748-3900` qualifies cross-namespace types only when `isProjectableNs(...)` is true; otherwise it falls back to bare local names (`*{s}` / `{s}`), which is exactly how the undeclared identifiers leak into the generated output.
- `build.zig:936-959` deliberately snapshots `Microsoft.UI.Xaml` / `Microsoft.UI.Xaml.Controls` “without first teaching the runtime bundle about every transitive Windows App SDK dependency,” which makes a local placeholder strategy consistent with the existing build intent.
- A direct metadata inspection of `vendor/winmd/Microsoft.UI.Xaml.winmd` showed the offending TypeRefs actually resolve to `Microsoft.Windows.ApplicationModel.Resources.IResourceManager` and `Microsoft.Web.WebView2.Core.CoreWebView2*`, and that the vendored WinUI metadata contains no matching TypeDefs under those exact namespaces. `Windows.winmd` does contain `Windows.ApplicationModel.Resources.Core.IResourceManager`, but that is a different namespace than the one referenced by the WinUI metadata, so special-casing it as an alias would be a guess rather than a metadata-driven fix.

## Desired End State

- `zig build bindings` regenerates `packages/win/src/generated/Microsoft.UI.Xaml.zig` and `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig` so every previously bare `IResourceManager` / `CoreWebView2*` reference is backed by an explicit local placeholder declaration.
- The regenerated files no longer fail with `use of undeclared identifier 'IResourceManager'` or `use of undeclared identifier 'CoreWebView2'` when these specific names are parsed/imported.
- The fix does **not** widen the WinUI dependency manifest to `Microsoft.Windows.ApplicationModel.Resources` or `Microsoft.Web.WebView2.Core`; unsupported foreign reference types remain local placeholders, which keeps issue #53 independent from metadata acquisition work.
- `zig build test` gains focused regression coverage in `packages/winbindgen/src/root.zig` that fails if the emitter ever reintroduces bare undeclared foreign reference types for these WinUI namespaces.
- As the parallel issue #52 work lands, the combined validation command remains `zig build bindings && zig build test`; after #53, those runs should no longer fail on the specific undeclared-identifier errors tracked here.

## Key Discoveries

- The bug is **not** the same as issue #52’s empty-namespace problem. #52 is about missing generated dependency modules such as `Microsoft.UI.Dispatching`; #53 is about foreign type names being emitted inside otherwise non-empty files with no declaration at all.
- The actual `IResourceManager` TypeRef in `Microsoft.UI.Xaml.winmd` points to `Microsoft.Windows.ApplicationModel.Resources`, not to `Windows.ApplicationModel.Resources.Core`, so “just import the Windows namespace” would be an unsafe aliasing shortcut.
- `CoreWebView2*` lives in `Microsoft.Web.WebView2.Core`, which is outside the repository’s vendored metadata set and outside the emitter’s import allowlist, so a real import-based fix would require broader metadata/source-selection work that this issue does not need.
- The generator already has an established pattern of using opaque placeholders when it cannot safely emit a real layout or callable surface (`packages/winbindgen/src/root.zig:4255-4268` for structs, plus delegate/runtime-class opaque handles elsewhere). Reusing that strategy for unsupported foreign reference types is the smallest fix that restores importability.
- Because the current bare-name leak happens in `writeZigTy`, the most reliable fix point is the shared type-rendering path, not a one-off patch in the WinUI bundle driver.

## What We're NOT Doing

- We are **not** broadening `isProjectableNs` or `selectMetadataSource` to start importing `Microsoft.Windows.*` or `Microsoft.Web.*` namespaces.
- We are **not** inventing a namespace alias from `Microsoft.Windows.ApplicationModel.Resources.IResourceManager` to `Windows.ApplicationModel.Resources.Core.IResourceManager`.
- We are **not** trying to fully project the WebView2 or Microsoft.Windows resource APIs in this issue; placeholder handles are sufficient because the immediate problem is undeclared identifiers, not missing callable members.
- We are **not** fixing issue #52 (empty Microsoft.UI dependency namespaces), issue #54 (activate helper type mismatch), issue #55 (missing composable factory helpers), or issue #56 (`*anyopaque` fallback cleanup) in this plan.
- We are **not** expanding this issue to by-value external structs/enums; issue #53 only needs to make foreign reference-type identifiers legal again.

## Implementation Approach

Use the existing WinRT/WinUI import path for projectable namespaces exactly as-is, but add a second path for unsupported foreign reference types:

1. Detect non-projectable foreign `.class_name` references in `writeZigTy`.
2. Record those names in a per-namespace placeholder registry instead of pretending they are same-namespace declarations.
3. Emit one sorted `pub const <Name> = opaque {};` declaration per recorded foreign type before flushing the buffered namespace body.
4. Leave unsupported generic and by-value external cases on their existing opaque fallback paths so issue #53 stays narrowly focused and does not turn into a metadata expansion project.

This approach matches the repository’s existing “opaque placeholder over incorrect projection” policy and avoids coupling #53 to new metadata downloads or new namespace routing logic.

## Phase 1: Add explicit placeholder tracking for unsupported foreign reference types

### Overview

Teach the shared emitter to distinguish “foreign but importable” from “foreign and unsupported,” and make the unsupported case explicit.

### Changes Required

#### 1. Add a per-namespace external placeholder registry
**File**: `packages/winbindgen/src/root.zig`

**Functions to update**:
- `emitNamespaceExWithImports(...)`
- new helper(s) adjacent to the existing import/placeholder helpers (for example `recordExternalPlaceholder(...)` and `emitExternalPlaceholders(...)`)

**Changes**:
- Create a small registry keyed by emitted placeholder name, with the originating metadata namespace retained for diagnostics and deterministic sorting.
- Instantiate the registry alongside `CrossNsSet` inside `emitNamespaceExWithImports(...)`.
- Emit the placeholder declarations into the generated namespace prelude before the buffered body is written out, so every later `*IResourceManager` / `*CoreWebView2` reference has a matching top-level declaration.

#### 2. Route non-projectable foreign class handles through that registry
**File**: `packages/winbindgen/src/root.zig`

**Functions to update**:
- `writeZigTy(...)`
- the intermediate helpers that already thread `CrossNsSet` down into `writeZigTy(...)` (notably the interface-handle, runtime-class, vtbl, and free-function signature emit paths)

**Changes**:
- Keep the existing behavior for:
  - same-namespace references,
  - `Windows.*` / `Microsoft.UI.*` qualified imports,
  - cross-namespace generics that already degrade to `*anyopaque`.
- Replace the current bare-name fallback for unsupported foreign `.class_name` references with:
  - “record placeholder” + emit `*<Name>` for direct reference types,
  - unchanged `*anyopaque` behavior for unsupported generic cases that already do not surface a bare foreign name.
- Do **not** alter the metadata-source selection logic in `packages/winbindgen/src/main.zig`; the new placeholder path keeps this issue local to the emitter.

### Success Criteria

- No code path in `writeZigTy(...)` can emit a bare foreign `.class_name` identifier unless a matching local placeholder declaration will also be emitted.
- The special issue #53 names (`IResourceManager`, `CoreWebView2`, `CoreWebView2Environment`, `CoreWebView2ControllerOptions`) all flow through the placeholder registry instead of the old undeclared-name path.

---

## Phase 2: Add WinUI-specific regression coverage

### Overview

Lock the fix in with tests that exercise the exact WinUI metadata that exposed the bug.

### Changes Required

#### 1. Make the WinUI metadata fixture available to winbindgen tests
**File**: `build.zig`

**Changes**:
- Add `vendor/winmd/Microsoft.UI.Xaml.winmd` as an anonymous import for `winbindgen_mod` so `packages/winbindgen/src/root.zig` tests can `@embedFile("Microsoft.UI.Xaml.winmd")` the same way they already embed `Windows.winmd`.
- Only add the test fixture exposure needed for the package tests; do not add new source-selection or bundle-routing behavior here.

#### 2. Add focused emitter tests for the WinUI snapshots
**File**: `packages/winbindgen/src/root.zig`

**Nearby existing tests to extend**:
- `test "emitNamespace qualifies cross-namespace refs and emits import aliases"` (`packages/winbindgen/src/root.zig:5387-5425`)
- `test "emitBundle can render module-name imports and dependency manifest"` (`packages/winbindgen/src/root.zig:6715-6759`)

**Changes**:
- Add a new WinUI-focused `emitBundleWithImports(...)` or `emitNamespaceExWithImports(...)` test that parses `Microsoft.UI.Xaml.winmd` and asserts:
  - `Microsoft.UI.Xaml` output contains `pub const IResourceManager = opaque {};`
  - `Microsoft.UI.Xaml.Controls` output contains `pub const CoreWebView2 = opaque {};`, `pub const CoreWebView2Environment = opaque {};`, and `pub const CoreWebView2ControllerOptions = opaque {};`
  - the previously failing signatures still mention those names, but they are now backed by declarations
  - no `const @"Microsoft.Windows.ApplicationModel.Resources" = ...` or `const @"Microsoft.Web.WebView2.Core" = ...` imports are emitted
- Keep the test scoped to issue #53’s undeclared-name regression instead of full WinUI bundle compilation, because issue #52 is tracking the separate empty-namespace failure mode.

### Success Criteria

- The new WinUI tests fail on the current pre-fix emitter and pass after the placeholder path is added.
- The tests prove the fix is local (placeholder declarations) rather than accidental (new unmanaged imports or guessed namespace aliases).

---

## Phase 3: Regenerate the checked-in WinUI snapshots and validate the issue-specific output

### Overview

Apply the emitter change to the committed snapshots and confirm the exact identifiers from issue #53 are no longer undeclared.

### Changes Required

#### 1. Regenerate the checked-in WinUI files
**Files**:
- `packages/win/src/generated/Microsoft.UI.Xaml.zig`
- `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig`
- `packages/win/src/generated/winui_bundle_deps.zig` (expected to stay functionally unchanged for this issue)

**Changes**:
- Run `zig build fetch-winui-metadata` if the vendor metadata is not already present.
- Run `zig build bindings` to regenerate the WinUI snapshots from the updated emitter.
- Confirm the regenerated files now declare the issue #53 placeholders explicitly instead of referencing undeclared bare names.

#### 2. Verify the issue-specific regression is gone
**Files / commands**:
- `zig build test`
- targeted grep/inspection of the regenerated `Microsoft.UI.Xaml*.zig` files

**Changes**:
- Verify the regenerated `Microsoft.UI.Xaml.zig` contains the `IResourceManager` placeholder and no longer has an undeclared bare `IResourceManager` at the former failure sites.
- Verify the regenerated `Microsoft.UI.Xaml.Controls.zig` contains the three `CoreWebView2*` placeholders and no longer has undeclared bare `CoreWebView2*` identifiers at the former failure sites.
- Treat full WinUI-bundle import compilation as the cross-issue end-to-end validation to rerun alongside issue #52, not as the primary blocking test for #53 by itself.

### Success Criteria

- The checked-in generated WinUI files contain explicit placeholder declarations for every identifier named in issue #53.
- The issue-specific undeclared-identifier strings are eliminated from the regenerated WinUI snapshots.
- `zig build test` passes the new winbindgen regression coverage for this case.

## Testing Strategy

### Unit Tests

- Add a WinUI metadata fixture test in `packages/winbindgen/src/root.zig` that emits `Microsoft.UI.Xaml` and `Microsoft.UI.Xaml.Controls` and asserts the exact placeholder declarations required by issue #53.
- Assert that the output still uses normal qualified imports for `Windows.*` / `Microsoft.UI.*` references, so the fix does not regress the established cross-namespace path.
- Assert that no new imports are emitted for `Microsoft.Windows.ApplicationModel.Resources` or `Microsoft.Web.WebView2.Core`.

### Integration / Regeneration Checks

1. `zig build fetch-winui-metadata` (only when the WinUI metadata is not already staged)
2. `zig build bindings`
3. Inspect:
   - `packages/win/src/generated/Microsoft.UI.Xaml.zig`
   - `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig`
4. Confirm the regenerated files contain the placeholder declarations and that the formerly failing signatures now bind to those declarations.

### End-to-End Validation

- Run `zig build test` so the new winbindgen regression tests become part of the normal repository validation flow.
- After the parallel fix for issue #52 lands, rerun `zig build bindings && zig build test` as the combined WinUI snapshot validation; #53’s contribution to that combined run is that the previous undeclared-identifier failures are gone.

## References

- GitHub issue #53: `https://github.com/cataggar/windows-zig/issues/53` — *winbindgen emits undeclared IResourceManager/CoreWebView2 identifiers in WinUI namespaces*
- GitHub issue #52: `https://github.com/cataggar/windows-zig/issues/52` — *winbindgen bundle emits empty Microsoft.UI dependency namespaces*
- Related source sites:
  - `packages/win/src/generated/Microsoft.UI.Xaml.zig:4156-4159`
  - `packages/win/src/generated/Microsoft.UI.Xaml.zig:8334-8335`
  - `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig:36562-36563`
  - `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig:36749-36753`
  - `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig:46426`
  - `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig:46455-46456`
  - `packages/win/src/generated/winui_bundle_deps.zig:9-10`
  - `packages/winbindgen/src/root.zig:110-114`
  - `packages/winbindgen/src/root.zig:192-210`
  - `packages/winbindgen/src/root.zig:367-421`
  - `packages/winbindgen/src/root.zig:3491-3521`
  - `packages/winbindgen/src/root.zig:3748-3900`
  - `packages/winbindgen/src/root.zig:4255-4268`
  - `build.zig:936-959`
- Parallel planning context only:
  - GitHub issue #54: `https://github.com/cataggar/windows-zig/issues/54` — *Generated WinRT activate() helper passes _Vtbl type to win_core.activateInstance*
  - GitHub issue #55: `https://github.com/cataggar/windows-zig/issues/55` — *Composable WinUI runtime classes do not get Factory/factory() helpers*
  - GitHub issue #56: `https://github.com/cataggar/windows-zig/issues/56` — *WinUI event and collection members still fall back to `*anyopaque`*
