# Issue #56 Implementation Plan

## Overview

Fix the emitter path that still projects certain WinUI raw ABI delegate and collection signatures as `*anyopaque` even though bundle mode already discovers and emits the corresponding closed-generic handle types. The goal is to make the raw ABI wrappers/vtable slots in the committed WinUI snapshot use the same named handles that the existing event-sugar helpers already rely on.

## Current State Analysis

- `packages/win/src/generated/Microsoft.UI.Xaml.zig:1367-1383` shows the split clearly:
  - `IApplication2.add_ResourceManagerRequested(... p0: *anyopaque ...)`
  - the adjacent `addResourceManagerRequested(...)` helper already uses `@"Windows.Foundation".TypedEventHandler__G2__object__Microsoft_UI_Xaml_ResourceManagerRequestedEventArgs`.
- `packages/win/src/generated/Microsoft.UI.Xaml.zig:6622-6713` repeats the same pattern for `IWindow`:
  - raw ABI methods `add_Activated`, `add_Closed`, `add_SizeChanged`, and `add_VisibilityChanged` take `*anyopaque`
  - the adjacent helpers already name the expected `@"Windows.Foundation".TypedEventHandler__G2__object__...` handles.
- `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig:26417-26472` shows the same shape for `IRichTextBlock`:
  - `get_TextHighlighters(... result: **anyopaque)`
  - `add_IsTextTrimmedChanged(... p0: *anyopaque ...)`
  - the adjacent helper already names `@"Windows.Foundation".TypedEventHandler__G2__Microsoft_UI_Xaml_Controls_RichTextBlock__Microsoft_UI_Xaml_Controls_IsTextTrimmedChangedEventArgs`.
- `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig:26533-26552` shows `IRichTextBlockOverflow.add_IsTextTrimmedChanged(... p0: *anyopaque ...)` with the same family of typed helper nearby.
- `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig:32201-32250` shows the issue surface called out in #56:
  - `ITextBlock.get_TextHighlighters(... result: **anyopaque)`
  - `ITextBlock.add_IsTextTrimmedChanged(... p0: *anyopaque ...)`
  - the adjacent helper already names `@"Windows.Foundation".TypedEventHandler__G2__Microsoft_UI_Xaml_Controls_TextBlock__Microsoft_UI_Xaml_Controls_IsTextTrimmedChangedEventArgs`.
- `build.zig:940-980` confirms the committed WinUI snapshot is already generated through `winbindgen bundle`, not per-namespace one-offs.
- `build.zig:1573-1584` documents the intended bundle behavior: cross-namespace closed-generic instantiations are auto-routed into their home namespace.
- `packages/winbindgen/src/root.zig:1833-1898` shows the bundle discovery pre-pass already records cross-namespace closed generics whenever every arg is `isMangleableArg`, which already includes class/value refs.
- `packages/winbindgen/src/root.zig:3014-3072` shows the event-sugar path already trusts those routed cross-namespace closed generics and qualifies them through imported home namespaces.
- `packages/winbindgen/src/root.zig:3812-3846` is the stale branch: `writeZigTy` only emits a cross-namespace closed-generic reference when `allPrimitiveArgs(tn.generics)` is true; class/value generic args still fall back to `*anyopaque`.
- Grep survey of `packages/win/src/generated/Microsoft.UI.Xaml*.zig` found:
  - `337` public ABI wrappers matching `pN: *anyopaque` or `result: **anyopaque`
  - `337` corresponding vtable slots
  - wrapper breakdown: `185` `add_*`, `84` `get_*`, `38` `put_*`, and `30` other methods.
  This issue will validate the delegate/collection subset exercised by #56, not attempt to eliminate every remaining WinUI fallback in one pass.

## Desired End State

- `zig build bindings` regenerates the committed WinUI snapshot so the raw ABI members called out in #56 no longer use `*anyopaque`.
- The raw ABI event slots point at named delegate handles, e.g. `*@"Windows.Foundation".TypedEventHandler__G2__...`.
- The `TextHighlighters` getters point at a named collection handle instead of `**anyopaque`; for WinUI this should be `**@"Windows.Foundation.Collections".IVector__G1__Microsoft_UI_Xaml_Documents_TextHighlighter`.
- Immediate sibling surfaces with the same projection shape (`IRichTextBlock`, `IRichTextBlockOverflow`, and similar WinUI event members reached by bundle seeding) regenerate consistently.
- `zig build test` passes after the emitter change and committed snapshot refresh.

## Key Discoveries

- The problem is not missing generic discovery: bundle mode already discovers and routes cross-namespace closed generics with class/value args (`packages/winbindgen/src/root.zig:1833-1898`).
- The problem is not missing naming logic either: event sugar already constructs and qualifies the exact mangled delegate names it needs (`packages/winbindgen/src/root.zig:3014-3072`).
- The gap is specifically raw signature rendering in `writeZigTy`, which still assumes cross-namespace closed generics are only safe when every arg is primitive (`packages/winbindgen/src/root.zig:3812-3846`).
- The emitted helpers are the best source of truth for the ABI-level delegate handles that should appear in the raw slots; the raw wrappers should mirror those helper-emitted names instead of continuing to erase them to `*anyopaque`.
- Existing `Windows.*` tests already cover the same architectural mechanism (bundle-routed cross-namespace closed generics), so the regression suite can be strengthened without depending entirely on fetched WinUI metadata.

## What We're NOT Doing

- We are **not** hand-editing `packages/win/src/generated/*.zig`; the fix belongs in `packages/winbindgen/src/root.zig`.
- We are **not** promising to eliminate all `337` WinUI `*anyopaque` fallback wrappers in this issue.
- We are **not** expanding support to non-mangleable generic args or non-projectable namespaces.
- We are **not** addressing related issues #52, #53, #54, or #55 here; they are planning-only context.

## Implementation Approach

Update the raw type renderer so bundle-seeded cross-namespace closed generics with mangleable class/value args are emitted as qualified named handles instead of `*anyopaque`. Concretely, the `writeZigTy` branch that currently requires `allPrimitiveArgs(tn.generics)` should be aligned with the broader `isMangleableArg` rule already used by `discoverCrossNsGenerics` and `tryEmitEventSugar`.

The intent is:

1. keep the current fallback for truly unsupported shapes
2. stop erasing supported bundle-seeded closed generics
3. prove the change with focused emitter tests
4. regenerate the committed WinUI snapshot and verify the exact #56 surfaces.

## Phase 1: Align raw signature rendering with bundle-seeded generic support

### Overview

Teach `writeZigTy` to emit cross-namespace closed-generic references for any projectable, mangleable instantiation, not just primitive-only ones.

### Changes Required

#### 1. Relax the stale primitive-only gate
**File**: `packages/winbindgen/src/root.zig`  
**Changes**:
- In the `.class_name` generic branch inside `writeZigTy`, replace the `allPrimitiveArgs(tn.generics)` requirement with the same “all args are `isMangleableArg`” rule already used by:
  - `collectGenericInstantiations`
  - `discoverCrossNsGenerics`
  - `tryEmitEventSugar`
- When the generic lives in another projectable namespace, always emit:
  - `*@"<home-ns>".<Mangled>` for params/results
  - plus the corresponding cross-namespace import registration.
- Preserve `*anyopaque` only when:
  - the generic args are not mangleable, or
  - the target namespace is not projectable.

#### 2. Update the surrounding invariants/comments
**File**: `packages/winbindgen/src/root.zig`  
**Changes**:
- Rewrite the comments at `3812-3846` so they describe the current reality:
  - bundle mode is expected to seed these cross-namespace instantiations into their home namespace
  - raw ABI signatures are now allowed to reference those seeded handles directly.
- Remove `allPrimitiveArgs` if it becomes unused after the change.

### Success Criteria

- The raw type renderer can emit a qualified cross-namespace closed-generic handle for class/value args without falling back to `*anyopaque`.
- Unsupported generic shapes still fall back cleanly.

## Phase 2: Add regression coverage for raw delegate/collection projection

### Overview

Strengthen the emitter tests so the raw ABI path is covered, not just helper sugar.

### Changes Required

#### 1. Add a raw delegate regression canary using existing Windows metadata
**File**: `packages/winbindgen/src/root.zig`  
**Changes**:
- Extend the existing `emitBundle emits sugar for cross-namespace DeviceWatcher events` coverage (or add a sibling test) so it also asserts the raw ABI slots in the emitted `Windows.Devices.Enumeration` output use typed delegate handles:
  - `add_Added`
  - `add_Updated`
  - `add_Removed`
  - `add_EnumerationCompleted`
  - `add_Stopped`
- Assert those slots no longer contain `*anyopaque` and instead reference `@"Windows.Foundation".TypedEventHandler__G2__...`.

#### 2. Add a focused collection-handle regression
**File**: `packages/winbindgen/src/root.zig`  
**Changes**:
- Add a narrow unit test around `writeZigTy` (or another small helper-level emission path) that constructs a cross-namespace generic like:
  - `Windows.Foundation.Collections.IVector\`1<Microsoft.UI.Xaml.Documents.TextHighlighter>`
- Assert it renders as:
  - `*@"Windows.Foundation.Collections".IVector__G1__Microsoft_UI_Xaml_Documents_TextHighlighter`
  instead of `*anyopaque`.
- This keeps the collection half of #56 covered without requiring checked-in WinUI metadata.

#### 3. Keep the primitive-only canaries in place
**File**: `packages/winbindgen/src/root.zig`  
**Changes**:
- Leave the existing `Calendar.Languages → IVectorView<HSTRING>` tests intact so the primitive-only path remains covered alongside the new class/value-arg path.

### Success Criteria

- Tests now cover both:
  - primitive cross-namespace closed generics, and
  - class/value-arg cross-namespace closed generics.
- The regression suite catches a reintroduction of `*anyopaque` in raw delegate/collection slots.

## Phase 3: Regenerate and verify the committed WinUI snapshot

### Overview

Run the real bindings pipeline and confirm the exact #56 surfaces regenerate with named types.

### Changes Required

#### 1. Regenerate the snapshot
**Command**: `zig build bindings`  
**Changes**:
- Refresh:
  - `packages/win/src/generated/Microsoft.UI.Xaml.zig`
  - `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig`
- Accept a related diff in:
  - `packages/win/src/generated/Microsoft.UI.Xaml.Controls.Primitives.zig`
  - `packages/win/src/generated/winui_bundle_deps.zig`
  only if it is a mechanical consequence of the same emitter fix.

#### 2. Verify the issue #56 targets
**Files**:
- `packages/win/src/generated/Microsoft.UI.Xaml.zig`
- `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig`

**Checks**:
- `IApplication2.add_ResourceManagerRequested` now uses a named `TypedEventHandler__G2__object__Microsoft_UI_Xaml_ResourceManagerRequestedEventArgs` handle.
- `IWindow.add_Activated`, `add_Closed`, `add_SizeChanged`, and `add_VisibilityChanged` now use named `TypedEventHandler__G2__object__...` handles.
- `ITextBlock.get_TextHighlighters` now returns a named `IVector__G1__Microsoft_UI_Xaml_Documents_TextHighlighter` handle via its out-param.
- `ITextBlock.add_IsTextTrimmedChanged` now uses a named `TypedEventHandler__G2__Microsoft_UI_Xaml_Controls_TextBlock__Microsoft_UI_Xaml_Controls_IsTextTrimmedChangedEventArgs` handle.
- Neighbor canaries also improve automatically:
  - `IRichTextBlock.get_TextHighlighters`
  - `IRichTextBlock.add_IsTextTrimmedChanged`
  - `IRichTextBlockOverflow.add_IsTextTrimmedChanged`

### Success Criteria

- The committed WinUI snapshot diff is generator-produced only.
- The exact issue #56 surfaces no longer contain raw `*anyopaque`.

## Phase 4: Validate end-to-end and record the remaining scope boundary

### Overview

Run the existing verification commands and make sure the fix stays scoped to the intended projection gap.

### Changes Required

#### 1. Run the emitter/unit test coverage
**Command**: targeted `zig` test invocation for `packages/winbindgen/src/root.zig` (or the narrowest existing build target that runs those tests)

#### 2. Run the repository test step
**Command**: `zig build test`

#### 3. Re-run the grep verification
**Checks**:
- Confirm the issue #56 members are now typed.
- Record any remaining unrelated WinUI `*anyopaque` sites as follow-up backlog rather than silently expanding scope.

### Success Criteria

- `zig build test` passes.
- The issue #56 minimal surface is fixed.
- Any remaining WinUI `*anyopaque` sites are explicitly understood to be out of scope for this change.

## Testing Strategy

### Unit Tests

- Add raw ABI string assertions for bundle-emitted cross-namespace delegate slots with class/value args.
- Add a focused collection-handle rendering test for `IVector<TextHighlighter>`-style shapes.
- Keep the existing primitive-arg `IVectorView<HSTRING>` tests as regression coverage.

### Integration Tests

- `zig build bindings`
- `zig build test`

### Manual/Grep Verification

1. Grep `packages/win/src/generated/Microsoft.UI.Xaml.zig` for:
   - `add_ResourceManagerRequested`
   - `add_Activated`
   - `add_Closed`
   - `add_SizeChanged`
   - `add_VisibilityChanged`
   and confirm the raw ABI params are no longer `*anyopaque`.
2. Grep `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig` for:
   - `get_TextHighlighters`
   - `add_IsTextTrimmedChanged`
   and confirm the raw ABI result/param types are named handles.
3. Grep for the expected mangled names:
   - `TypedEventHandler__G2__object__Microsoft_UI_Xaml_ResourceManagerRequestedEventArgs`
   - `TypedEventHandler__G2__object__Microsoft_UI_Xaml_WindowActivatedEventArgs`
   - `IVector__G1__Microsoft_UI_Xaml_Documents_TextHighlighter`
   - `TypedEventHandler__G2__Microsoft_UI_Xaml_Controls_TextBlock__Microsoft_UI_Xaml_Controls_IsTextTrimmedChangedEventArgs`

## References

- Issue #56: `https://github.com/cataggar/windows-zig/issues/56`
- WinUI snapshot generation: `build.zig:940-980`
- Bundle generic routing: `build.zig:1573-1584`
- Cross-namespace generic discovery: `packages/winbindgen/src/root.zig:1833-1898`
- Event-sugar cross-namespace generic usage: `packages/winbindgen/src/root.zig:3014-3072`
- Current primitive-only raw projection gate: `packages/winbindgen/src/root.zig:3812-3846`
- Working primitive cross-namespace collection canary: `packages/winbindgen/src/root.zig:5432-5460`
- Working typed raw event slot reference for same-namespace closed generics: `packages/win-reference/src/foundation.zig:460-472`
- Related planning-only context:
  - #52 `winbindgen bundle emits empty Microsoft.UI dependency namespaces`
  - #53 `winbindgen emits undeclared IResourceManager/CoreWebView2 identifiers in WinUI namespaces`
  - #54 `Generated WinRT activate() helper passes _Vtbl type to win_core.activateInstance`
  - #55 `Composable WinUI runtime classes do not get Factory/factory() helpers`
