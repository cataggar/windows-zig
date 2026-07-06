# Issue #55 Implementation Plan

## Overview

Teach `winbindgen` to emit `Factory` / `factory()` helpers for runtime classes that carry `ComposableAttribute`, not just typed `ActivatableAttribute`. This is a codegen-surface fix only: the raw WinUI factory interfaces already exist, so the work is to project the existing `win_core.activationFactory(...)` pattern onto composable runtime-class handles such as `Application`, `Window`, and `Button`.

Related context only: #52, #53, #54, and #56 are adjacent planning threads. The only directly related one here is #54, because it also touches runtime-class convenience helper generation; this plan intentionally keeps #55 scoped to `Factory` / `factory()` emission only.

## Current State Analysis

- The underlying WinUI composable factory interfaces are already emitted today:
  - `IApplicationFactory.CreateInstance(...)` exists at `packages/win/src/generated/Microsoft.UI.Xaml.zig:1399-1415`.
  - `IWindowFactory.CreateInstance(...)` exists at `packages/win/src/generated/Microsoft.UI.Xaml.zig:6401-6417`.
  - `IButtonFactory.CreateInstance(...)` exists at `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig:7337-7353`.
- The matching runtime-class handles do **not** expose `Factory` / `factory()` helpers:
  - `Application` only has `NAME`, `NAME_W`, and `Statics` at `packages/win/src/generated/Microsoft.UI.Xaml.zig:7178-7186`.
  - `Window` only has `NAME`, `NAME_W`, and `Statics` at `packages/win/src/generated/Microsoft.UI.Xaml.zig:7645-7653`.
  - `Button` only has `NAME`, `NAME_W`, and `Statics` at `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig:37073-37081`.
- Working typed-activatable examples show the intended projection shape:
  - `PropertyPath` emits `Factory` / `factory()` at `packages/win/src/generated/Microsoft.UI.Xaml.zig:7453-7459`.
  - `Setter` emits both `activate()` and `Factory` / `factory()` at `packages/win/src/generated/Microsoft.UI.Xaml.zig:7491-7507`.
  - `Style` emits both at `packages/win/src/generated/Microsoft.UI.Xaml.zig:7544-7556`.
- The runtime-class emitter always calls `writeFactoryAlias()`, but `writeFactoryAlias()` currently resolves the factory interface exclusively through `activationFactoryName()`, which only scans for typed `ActivatableAttribute` rows (`packages/winbindgen/src/root.zig:4873-4907`, `packages/winbindgen/src/root.zig:4981-5066`).
- `hasParameterlessActivation()` is already a separate path that correctly limits `activate()` emission to parameterless `ActivatableAttribute` rows (`packages/winbindgen/src/root.zig:4943-4950`, `packages/winbindgen/src/root.zig:5081-5099`). That separation is important: #55 should not change `activate()` behavior.
- Current WinUI helper coverage is visibly incomplete:
  - `rg "pub const Factory = I[A-Za-z0-9_]+Factory;" packages/win/src/generated/Microsoft.UI*.zig` finds only 10 helpers total (4 in `Microsoft.UI.Xaml.zig`, 2 in `Microsoft.UI.Xaml.Controls.zig`, 4 in `Microsoft.UI.Xaml.Controls.Primitives.zig`), all from typed activatable classes.
  - `rg "pub fn CreateInstance\(self: \*const I[A-Za-z0-9_]+Factory, p0: \?\*const anyopaque, p1: \*\?\*const anyopaque"` over those same three generated files finds 200 composition-style factory entry points already projected, so the raw interface surface is broad even though the convenience helpers are missing.
- Local metadata inspection of `vendor/winmd/Microsoft.UI.Xaml.winmd` (fetched by `zig build fetch-winui-metadata`, per `vendor/winmd/README.md` and `build.zig:377-408`) shows the broader impact:
  - 236 runtime classes in `Microsoft.UI.Xaml`, `Microsoft.UI.Xaml.Controls`, and `Microsoft.UI.Xaml.Controls.Primitives` carry exactly one `ComposableAttribute`.
  - All 236 currently lack a `Factory` alias inside their generated runtime-class block.
  - Every inspected `ComposableAttribute` row uses the same leading shape: first positional arg = factory interface `System.Type`, second = `Windows.Foundation.Metadata.CompositionType`, then contract/version data.
  - `Application`, `Window`, and `Button` all follow that shape, while `TextBlock` is a useful negative control because it remains parameterless-activatable (`ActivatableAttribute`) instead of composable.

## Desired End State

After the implementation:

- `winbindgen` treats typed `ComposableAttribute` the same way it already treats typed `ActivatableAttribute` for `Factory` / `factory()` emission.
- Running `zig build bindings` regenerates the committed WinUI snapshots so that:
  - `Microsoft.UI.Xaml.Application.factory()` exists.
  - `Microsoft.UI.Xaml.Window.factory()` exists.
  - `Microsoft.UI.Xaml.Controls.Button.factory()` exists.
  - the same helper pattern appears on the rest of the 236 composable runtime classes in the three generated WinUI namespaces.
- Existing activatable examples such as `PropertyPath.factory()`, `Setter.factory()`, and `Style.factory()` remain present and unchanged in behavior.
- `TextBlock` remains an `activate()`-only case; it should not gain a `Factory` helper unless its metadata actually changes.
- `zig build test` passes after regeneration.

## Key Discoveries

- `ComposableAttribute` is not referenced anywhere in `packages/winbindgen/src/root.zig` today; the omission is the direct root cause (`packages/winbindgen/src/root.zig:4981-5066`).
- The existing `factory()` template is already the right one for composable classes because it only returns `win_core.activationFactory(Factory.Vtbl, &Factory.IID, &NAME_W)`; that is the same manual sequence issue #55 describes.
- WinUI `ComposableAttribute` rows in the current metadata are uniform enough that the same “first positional `System.Type` wins” rule can be reused without inventing a separate emission template.
- There is no current overlap between `ComposableAttribute` and `ActivatableAttribute` in the affected WinUI namespaces, so broadening factory-interface discovery will not create an attribute-precedence conflict for this surface.
- The metadata includes both public and protected composition (`CompositionType` values `2` and `1` respectively), but the helper only exposes the factory interface handle; it does not call a constructor itself. That means the alias/helper can be emitted uniformly, and callers remain responsible for invoking the appropriate factory method.

## What We're NOT Doing

- We are **not** changing `activate()` generation or the `win_core.activateInstance(...)` call shape from #54.
- We are **not** adding higher-level `CreateInstance` convenience wrappers on the runtime classes; the fix is only the existing `Factory` alias plus `factory()` lookup helper.
- We are **not** changing WinUI namespace selection, bundle composition, or dependency import behavior from #52 / #53.
- We are **not** addressing `*anyopaque` event/collection projection gaps from #56.
- We are **not** expanding the committed WinUI snapshot beyond the namespaces already regenerated by `zig build bindings`.

## Implementation Approach

1. Keep the existing `writeFactoryAlias()` output shape intact.
2. Replace the narrow “typed activatable factory only” lookup with a neutral runtime-class factory lookup that accepts either:
   - `ActivatableAttribute` whose first positional argument is a `System.Type`, or
   - `ComposableAttribute` whose first positional argument is a `System.Type`.
3. Preserve all existing post-processing in `writeFactoryAlias()`:
   - skip generic factory interfaces,
   - honor same-namespace vs cross-namespace imports,
   - keep the emitted alias targeting the interface handle type (not `_Vtbl`).
4. Leave `hasParameterlessActivation()` unchanged so `activate()` remains gated only by the parameterless activatable path.
5. Add emitter regression coverage that proves:
   - typed-activatable classes still emit helpers,
   - composable WinUI classes now emit helpers,
   - parameterless-activatable classes like `TextBlock` do not accidentally switch categories.

## Phased changes

### Phase 1: Broaden runtime-class factory discovery

**Files**
- `packages/winbindgen/src/root.zig`

**Changes**
- Rename `activationFactoryName()` to `classFactoryName()` so the helper name matches its broadened responsibility.
- Update the attribute scan so the helper returns the first positional `type_name` from either a typed `ActivatableAttribute` row or a `ComposableAttribute` row.
- Update the surrounding doc comments to explicitly describe both supported attribute kinds and to document that parameterless `ActivatableAttribute` remains `activate()`-only.

**Why this is enough**
- `writeFactoryAlias()` already emits exactly the right alias/helper pair once it has the correct interface `TypeName`.
- The manual workaround in issue #55 already uses the same `win_core.activationFactory(...)` call the generated helper emits.

### Phase 2: Add focused regression coverage

**Files**
- `packages/winbindgen/src/root.zig`

**Changes**
- Extend the existing runtime-class emission tests near `emitRuntimeClasses` (`packages/winbindgen/src/root.zig:5248-5297`) with a WinUI-specific regression that:
  - loads `vendor/winmd/Microsoft.UI.Xaml.winmd`,
  - emits `Microsoft.UI.Xaml` and/or `Microsoft.UI.Xaml.Controls`,
  - asserts that `Application`, `Window`, and `Button` now include `pub const Factory = ...` plus `pub fn factory()`,
  - asserts that `TextBlock` still does **not** gain a `Factory` helper.
- Keep the existing `Uri`/`Windows.Foundation` tests intact so typed-activatable behavior remains covered.

**Testing note**
- Reuse the same runtime file-loading pattern already used by `packages/winbindgen/src/main.zig` for fetched WinUI metadata rather than introducing a separate metadata-ingestion mechanism just for tests.

### Phase 3: Regenerate committed WinUI outputs

**Files**
- `packages/win/src/generated/Microsoft.UI.Xaml.zig`
- `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig`
- `packages/win/src/generated/Microsoft.UI.Xaml.Controls.Primitives.zig`

**Changes**
- Run `zig build bindings` so the codegen change is reflected in the committed generated sources.
- Review the diff to confirm the change is localized to new `Factory` aliases and `factory()` helpers on composable runtime-class blocks.
- Spot-check the three issue examples plus at least one additional composable class from `Microsoft.UI.Xaml.Controls.Primitives` to confirm the fix is systematic rather than special-cased.

## Success Criteria

- `packages/winbindgen/src/root.zig` no longer treats typed `ActivatableAttribute` as the only source of runtime-class factory helpers.
- `Application`, `Window`, and `Button` each gain:
  - `pub const Factory = I*Factory;`
  - `pub fn factory() !win_core.Com(Factory.Vtbl)`
- Existing activatable classes (`PropertyPath`, `Setter`, `Style`, etc.) keep their current helper surface.
- `TextBlock` stays parameterless-activatable and does not pick up an incorrect `Factory` helper.
- Regenerated WinUI files show the helper addition across the broader composable surface, not just the three examples from the issue body.
- `zig build test` passes after regeneration.

## Testing Strategy

1. **Prepare metadata**
   - Run `zig build fetch-winui-metadata` if `vendor/winmd/Microsoft.UI.Xaml.winmd` is not already present.
   - `zig build bindings` already depends on that fetch step (`build.zig:377-408`, `build.zig:933-980`), so a fresh implementation branch can rely on the normal bindings pipeline.
2. **Regenerate**
   - Run `zig build bindings`.
3. **Diff / grep verification**
   - Confirm the issue examples now contain helpers:
     - `Application` in `packages/win/src/generated/Microsoft.UI.Xaml.zig`
     - `Window` in `packages/win/src/generated/Microsoft.UI.Xaml.zig`
     - `Button` in `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig`
   - Re-run `rg "pub const Factory = I[A-Za-z0-9_]+Factory;" packages/win/src/generated/Microsoft.UI*.zig` and verify the count increases materially beyond the current baseline of 10.
   - Re-run the composition-factory grep to confirm the helper addition is applied against the existing composable surface rather than just one-off examples.
4. **Regression checks**
   - Verify `PropertyPath.factory()`, `Setter.factory()`, and `Style.factory()` are still present.
   - Verify `TextBlock` still exposes `activate()` but not `Factory`.
5. **Automated validation**
   - Run `zig build test`.

## References

- Issue #55: `https://github.com/cataggar/windows-zig/issues/55`
- Related context:
  - #52 `winbindgen bundle emits empty Microsoft.UI dependency namespaces`
  - #53 `winbindgen emits undeclared IResourceManager/CoreWebView2 identifiers in WinUI namespaces`
  - #54 `Generated WinRT activate() helper passes _Vtbl type to win_core.activateInstance`
  - #56 `WinUI event and collection members still fall back to *anyopaque`
- Emitter logic:
  - `packages/winbindgen/src/root.zig:4873-4907`
  - `packages/winbindgen/src/root.zig:4981-5066`
  - `packages/winbindgen/src/root.zig:5081-5099`
  - `packages/winbindgen/src/root.zig:5248-5297`
- Generated examples:
  - `packages/win/src/generated/Microsoft.UI.Xaml.zig:1399-1415`
  - `packages/win/src/generated/Microsoft.UI.Xaml.zig:7178-7186`
  - `packages/win/src/generated/Microsoft.UI.Xaml.zig:7453-7459`
  - `packages/win/src/generated/Microsoft.UI.Xaml.zig:7645-7653`
  - `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig:7337-7353`
  - `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig:37073-37081`
- WinUI metadata sourcing:
  - `vendor/winmd/README.md`
  - `tools/fetch-winui-metadata/main.zig`
  - `packages/winbindgen/src/main.zig:38-123`
  - `build.zig:377-408`
  - `build.zig:933-980`
