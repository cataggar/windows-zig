# Issue #54 Implementation Plan

## Overview

Issue #54 is a generator/runtime contract mismatch. `win_core.activateInstance` queries `Iface.IID`, so generated runtime-class `activate()` helpers must pass the default interface handle type (for example `ITextBlock`). Today `winbindgen` emits the default interface vtable type (`ITextBlock_Vtbl`) instead, which makes every generated parameterless `activate()` helper invalid once compiled. The fix should stay narrow: correct the emitter/template, update the nearby generator regression test, regenerate the checked-in WinUI snapshot, and verify the regenerated helpers all use handle types.

## Current State Analysis

- `packages/win-core/src/root.zig:1484-1503` defines `activateInstance(comptime Iface: type, class_name: []const u16) !*Iface` and calls `inspectable.queryInterface(&Iface.IID, &iface_raw)` at `packages/win-core/src/root.zig:1502`. That contract requires the first type argument to expose `pub const IID`.
- The current generated WinUI snapshot violates that contract. `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig:39151-39152` emits `TextBlock.activate()` as `win_core.activateInstance(ITextBlock_Vtbl, &NAME_W)`.
- The same file shows why that fails: `ITextBlock` defines `pub const IID` at `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig:32000-32003`, while `ITextBlock_Vtbl` begins at `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig:45432` and does not define `IID`.
- The exact codegen site is `packages/winbindgen/src/root.zig:4935-4946`; `writeActivateMethod` hardcodes `{s}_Vtbl` into every emitted `activate()` helper.
- The generator's own unit coverage currently locks in the same bug. `packages/winbindgen/src/root.zig:5285-5306` asserts that `Windows.Data.Json.JsonObject.activate()` contains `activateInstance(IJsonObject_Vtbl, &NAME_W)`, which proves the problem is not WinUI-specific even though the currently committed generated snapshot is.
- Manual/reference code already demonstrates the correct pattern:
  - `packages/win-reactor/src/winui/Microsoft.UI.Xaml.Controls.zig:143-144` uses `win_core.activateInstance(ITextBlock, &NAME_W)`.
  - `samples/winui_minimal_bindings/main.zig:59` uses `core.activateInstance(surface.ITextBlock, &surface.TextBlock.NAME_W)`.
- The currently checked-in generated blast radius is limited to the WinUI snapshot files that `zig build bindings` copies into source (`build.zig:452-458`, `build.zig:934-980`), so there are no committed `packages/win/src/generated/Windows.*.zig` files to patch today. Even so, the fix must remain generic because the emitter/test path already covers `Windows.Data.Json` classes.
- `build.zig:320`, `build.zig:331-350`, and `build.zig:1611-1616` show that `zig build test` runs the `winbindgen` unit suite and a Windows-only compile-check of the generated WinUI bundle, making those the right post-regeneration verification steps.

### Full grep inventory of affected generated call sites

`rg "activateInstance\([^,]+_Vtbl, &NAME_W\)" packages/win/src/generated` currently finds 73 call sites:

```text
packages/win/src/generated/Microsoft.UI.Xaml.Controls.Primitives.zig (13)
  7571  ICalendarPanel_Vtbl
  7668  ICornerRadiusFilterConverter_Vtbl
  7681  ICornerRadiusToThicknessConverter_Vtbl
  7756  IJumpListItemBackgroundConverter_Vtbl
  7769  IJumpListItemForegroundConverter_Vtbl
  7875  IPivotHeaderPanel_Vtbl
  7884  IPivotPanel_Vtbl
  7893  IPopup_Vtbl
  7919  IRepeatButton_Vtbl
  7957  IScrollBar_Vtbl
  8006  IScrollEventArgs_Vtbl
  8039  IThumb_Vtbl
  8052  ITickBar_Vtbl

packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig (48)
  37132  IAutoSuggestBox_Vtbl
  37145  IAutoSuggestBoxQuerySubmittedEventArgs_Vtbl
  37154  IAutoSuggestBoxSuggestionChosenEventArgs_Vtbl
  37163  IAutoSuggestBoxTextChangedEventArgs_Vtbl
  37194  IBorder_Vtbl
  37296  IChoosingGroupHeaderContainerEventArgs_Vtbl
  37305  IChoosingItemContainerEventArgs_Vtbl
  37337  IColumnDefinition_Vtbl
  37393  IContainerContentChangingEventArgs_Vtbl
  37455  IControlTemplate_Vtbl
  37474  IDatePickedEventArgs_Vtbl
  37492  IDatePickerFlyout_Vtbl
  37538  IDragItemsStartingEventArgs_Vtbl
  37552  IDynamicOverflowItemsChangingEventArgs_Vtbl
  37735  IHubSectionHeaderClickEventArgs_Vtbl
  37762  IImage_Vtbl
  37844  IItemClickEventArgs_Vtbl
  37892  IItemsPanelTemplate_Vtbl
  37901  IItemsPickedEventArgs_Vtbl
  37910  IItemsPresenter_Vtbl
  37951  IItemsRepeaterScrollHost_Vtbl
  37965  IItemsStackPanel_Vtbl
  38054  IListPickerFlyout_Vtbl
  38243  IMenuFlyoutSubItem_Vtbl
  38320  INavigationViewItemInvokedEventArgs_Vtbl
  38408  IPasswordBox_Vtbl
  38458  IPickerConfirmedEventArgs_Vtbl
  38467  IPickerFlyout_Vtbl
  38526  IPivotItemEventArgs_Vtbl
  38706  IRichTextBlock_Vtbl
  38719  IRichTextBlockOverflow_Vtbl
  38732  IRowDefinition_Vtbl
  38750  IScrollContentPresenter_Vtbl
  38772  IScrollViewer_Vtbl
  38790  IScrollViewerViewChangedEventArgs_Vtbl
  38877  ISemanticZoom_Vtbl
  38890  ISemanticZoomLocation_Vtbl
  38899  ISemanticZoomViewChangedEventArgs_Vtbl
  39014  ISymbolIcon_Vtbl
  39152  ITextBlock_Vtbl
  39229  ITimePickedEventArgs_Vtbl
  39247  ITimePickerFlyout_Vtbl
  39329  IToggleSwitch_Vtbl
  39462  IVariableSizedWrapGrid_Vtbl
  39475  IViewbox_Vtbl
  39493  IVirtualizingStackPanel_Vtbl
  39515  IWrapGrid_Vtbl
  39528  IXamlControlsResources_Vtbl

packages/win/src/generated/Microsoft.UI.Xaml.zig (12)
  7202  IBringIntoViewOptions_Vtbl
  7384  IEventTrigger_Vtbl
  7398  IFrameworkView_Vtbl
  7407  IFrameworkViewSource_Vtbl
  7496  ISetter_Vtbl
  7513  ISetterBaseCollection_Vtbl
  7536  IStateTrigger_Vtbl
  7549  IStyle_Vtbl
  7562  ITargetPropertyPath_Vtbl
  7609  IVisualState_Vtbl
  7618  IVisualStateChangedEventArgs_Vtbl
  7627  IVisualStateGroup_Vtbl
```

## Desired End State

- `packages/winbindgen/src/root.zig` emits `win_core.activateInstance(ITextBlock, &NAME_W)`-style calls for every parameterless runtime class, and its comment/test text reflect handle-type semantics.
- After `zig build bindings`, all 73 currently affected WinUI call sites regenerate with handle types, `TextBlock.activate()` becomes `ITextBlock`, and `rg "activateInstance\([^,]+_Vtbl, &NAME_W\)" packages/win/src/generated` returns no matches.
- `zig build test` passes on Windows, including the `winbindgen` unit tests and the `compile-check-bundle` coverage from `build.zig:1611-1616`.
- Related planning work on #52, #53, #55, and #56 remains untouched.

## Key Discoveries

- `activateInstance` and `activationFactory` intentionally have different calling conventions. `writeFactoryAlias` already emits handle aliases and then passes `Factory.Vtbl`/`Factory.IID` to `win_core.activationFactory` (`packages/winbindgen/src/root.zig:4998-5024`); `writeActivateMethod` is the outlier because `activateInstance` does its own `QueryInterface` via `Iface.IID`.
- `IInspectable_Vtbl` is a special-case core type that does carry `pub const IID = IID_IInspectable` (`packages/win-core/src/root.zig:1289-1308`), which explains why the end-to-end `win-core` test at `packages/win-core/src/root.zig:1892` can still pass `_Vtbl`. Generated WinUI vtables do not follow that convention.
- The repository's concrete failures are all in WinUI today, but the generic `Windows.Data.Json` unit test proves the underlying emitter bug would affect non-WinUI output as soon as those namespaces are regenerated or checked in.
- The compile-only WinUI sample already documents #54 beside #52/#53 and separates #55/#56 (`samples/winui_minimal_bindings/main.zig:3-11`), so this plan should treat #54 as a focused activate-helper correction rather than a broader namespace cleanup.

## What We're NOT Doing

- We are not changing `win_core.activateInstance`'s signature, return type, or `QueryInterface` logic in `packages/win-core/src/root.zig`; the contract there is already correct.
- We are not adding `pub const IID` to generated `_Vtbl` structs just to make the current broken call compile.
- We are not hand-editing generated WinUI files; `zig build bindings` must produce the updated snapshots.
- We are not expanding the generated surface to new `Windows.*` files, nor solving unrelated namespace/import/opaque-placeholder issues tracked by #52, #53, #55, and #56.
- We are not changing manual `win-reactor` or `samples/winui_minimal_bindings` activate helpers that already use handle types correctly.

## Implementation Approach

Treat this as a codegen contract bug, not a runtime bug. The only logic change should happen where `winbindgen` synthesizes runtime-class `activate()` helpers. Update that template so it emits the default interface handle symbol (for example `ITextBlock`) exactly as `win_core.activateInstance` expects, then update the colocated unit test to lock in the new string output. After the emitter change, regenerate the checked-in WinUI snapshot via the existing `bindings` step so the repository source matches the template, then validate with grep plus the existing `zig build test` entry point.

## Phase 1: Fix the activate() emitter template

### Overview

Correct the generic `winbindgen` template so every generated parameterless runtime-class `activate()` helper passes the handle type instead of the `_Vtbl` type, and update the nearby unit test/documentation so the contract stays explicit.

### Changes Required

#### 1. Runtime-class activate() emission
**File**: `packages/winbindgen/src/root.zig`  
**Changes**:
- In `writeActivateMethod` (`packages/winbindgen/src/root.zig:4935-4946`), change the emitted call from `win_core.activateInstance({s}_Vtbl, &NAME_W)` to `win_core.activateInstance({s}, &NAME_W)`.
- Update the surrounding doc comment so `default_iface_name` is described as the default interface handle name, not a name used to construct a `_Vtbl` symbol.
- Keep the return type and `@ptrCast(raw)` behavior unchanged; only the first type argument changes.

```zig
pub fn activate() !*TextBlock {
    const raw = try win_core.activateInstance(ITextBlock, &NAME_W);
    return @ptrCast(raw);
}
```

#### 2. Generator regression coverage
**File**: `packages/winbindgen/src/root.zig`  
**Changes**:
- Update `test "emitRuntimeClasses emits activate() on parameterless WinRT classes"` (`packages/winbindgen/src/root.zig:5285-5318`) so it expects handle-type output for `JsonObject`.
- Strengthen that same test to assert the emitted `JsonArray.activate()` call string too, not just the presence of the method name. That keeps regression coverage generic and non-WinUI-specific.

### Success Criteria

- `packages/winbindgen/src/root.zig` no longer contains `activateInstance({s}_Vtbl, &NAME_W)` or `IJsonObject_Vtbl` in the activate-helper test.
- The `writeActivateMethod` comment and the emitted code both describe/use handle types consistently.
- No generated files are manually edited in this phase.

## Phase 2: Regenerate WinUI bindings and verify the repository snapshots

### Overview

Run the existing bindings pipeline so the checked-in WinUI snapshot matches the fixed emitter, then verify the 73 affected call sites are rewritten and the existing test suite stays green.

### Changes Required

#### 1. Regenerate committed WinUI snapshot
**Files**:
- `packages/win/src/generated/Microsoft.UI.Xaml.zig`
- `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig`
- `packages/win/src/generated/Microsoft.UI.Xaml.Controls.Primitives.zig`

**Changes**:
- Run `zig build bindings`.
- Accept only the regenerated output produced by the fixed template; do not hand-edit any generated file.
- Confirm representative helpers regenerate to the handle-based form, especially:
  - `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig:TextBlock.activate()`
  - at least one helper in `Microsoft.UI.Xaml.zig`
  - at least one helper in `Microsoft.UI.Xaml.Controls.Primitives.zig`

```zig
pub fn activate() !*TextBlock {
    const raw = try win_core.activateInstance(ITextBlock, &NAME_W);
    return @ptrCast(raw);
}
```

#### 2. Post-regeneration verification
**File/Command Surface**: repo root / existing build steps  
**Changes**:
- Run `rg "activateInstance\\([^,]+_Vtbl, &NAME_W\\)" packages\\win\\src\\generated` and confirm zero matches.
- Run targeted positive greps for `ITextBlock`, plus one helper from the other two generated files, to prove the regenerated snapshot now uses handle types.
- Run `zig build test` so the `winbindgen` unit tests and generated bundle compile-checks still pass.

### Success Criteria

- The regenerated snapshot rewrites all 73 current `activateInstance(..._Vtbl, &NAME_W)` call sites to handle-type calls.
- `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig` specifically emits `win_core.activateInstance(ITextBlock, &NAME_W)` for `TextBlock.activate()`.
- `rg "activateInstance\\([^,]+_Vtbl, &NAME_W\\)" packages\\win\\src\\generated` returns zero matches.
- `zig build test` passes on Windows after regeneration.

## Success Criteria

- The only hand-written source changes are in `packages/winbindgen/src/root.zig`; generated WinUI file changes come only from `zig build bindings`.
- The emitter/test path is generic (`Windows.Data.Json` unit test updated), while the checked-in snapshot fix is concrete (73 WinUI call sites regenerated).
- No changes are made to `win_core.activateInstance`, manual `win-reactor` bindings, or unrelated issue areas (#52, #53, #55, #56).
- The exact issue repro is eliminated: `TextBlock.activate()` now passes `ITextBlock` rather than `ITextBlock_Vtbl`.
- Existing repository verification steps (`zig build bindings`, `zig build test`) complete successfully.

## Testing Strategy

### Emitter/unit-test verification

- Update the `packages/winbindgen/src/root.zig:5285-5318` test so it explicitly expects handle-based `JsonObject.activate()` and `JsonArray.activate()` output.
- Run `zig build test` to execute the `winbindgen` unit suite described in `build.zig:320` and `build.zig:331-350`.

### Regenerated snapshot verification

- Run `zig build bindings`.
- Run `rg "activateInstance\\([^,]+_Vtbl, &NAME_W\\)" packages\\win\\src\\generated` and require zero matches.
- Run targeted positive greps for:
  - `activateInstance(ITextBlock, &NAME_W)` in `packages\\win\\src\\generated\\Microsoft.UI.Xaml.Controls.zig`
  - one representative helper in `Microsoft.UI.Xaml.zig`
  - one representative helper in `Microsoft.UI.Xaml.Controls.Primitives.zig`
- Diff the regenerated files and confirm only `activate()` helper call-site arguments changed from `<Iface>_Vtbl` to `<Iface>`.

### Compile/build verification

- Run `zig build test` after regeneration.
- Pay attention to the generated-bundle compile-check hooked into `build.zig:1611-1616`; even though this issue is compile-time-only, that is the existing repo-level guard that the generated WinUI bundle still type-checks on Windows.
- No manual UI/runtime smoke test is required for this issue because the failure mode is a compile-time symbol mismatch, not runtime behavior.

## References

- GitHub issue #54: `https://github.com/cataggar/windows-zig/issues/54`
- `packages/win-core/src/root.zig:1289-1308`
- `packages/win-core/src/root.zig:1484-1503`
- `packages/win-core/src/root.zig:1892`
- `packages/winbindgen/src/root.zig:4935-4946`
- `packages/winbindgen/src/root.zig:4998-5024`
- `packages/winbindgen/src/root.zig:5285-5318`
- `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig:32000-32003`
- `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig:39151-39152`
- `packages/win/src/generated/Microsoft.UI.Xaml.Controls.zig:45432`
- `packages/win-reactor/src/winui/Microsoft.UI.Xaml.Controls.zig:143-144`
- `samples/winui_minimal_bindings/main.zig:3-11`
- `samples/winui_minimal_bindings/main.zig:59`
- `build.zig:320`
- `build.zig:331-350`
- `build.zig:452-458`
- `build.zig:934-980`
- `build.zig:1611-1616`
