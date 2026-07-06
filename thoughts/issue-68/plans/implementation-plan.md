# Issue #68 Implementation Plan

## Overview

Issue #68 closes the remaining attached-property gap in `win-reactor`: manifest entries can already describe attached setters, but the generated setter/runtime path still cannot cover Grid's `FrameworkElement`-targeted attached properties, so the WinUI backend carries a handwritten `Grid.SetRow/SetColumn/SetRowSpan/SetColumnSpan` fallback today. The plan below makes attached properties first-class in the generated reactor pipeline, adds a typed builder surface for them, and removes the Grid-specific backend workaround without implementing unrelated widget/runtime refactors.

## Current State Analysis

- The manifest schema already has explicit attached-property shape: `SetterKind.attached`, `AttachedPropertyInit`, and `PropInit.attached` are defined in `tools/reactor/schema.zig:27-58`, and normalized properties retain the same metadata in `tools/reactor/schema.zig:109-117`.
- The manifest loader already defaults any property with `attached != null` to `setter = .attached` (`tools/reactor/manifest.zig:114-127`), and the existing loader test proves the Grid example shape is valid (`tools/reactor/manifest.zig:429-434`).
- The `reactor-bindings` entry point already emits manifest-driven setter glue via `winbindgen reactor-bindings --outdir <dir>` (`packages/winbindgen/src/main.zig:182-186`, `packages/winbindgen/src/main.zig:573-642`), and `build.zig` wires the generated setter/event files back into the tree (`build.zig:266-291`, `build.zig:982-997`).
- Reactor codegen already has a dedicated attached-setter branch: attached bindings bypass the instance-setter path in `emitTypedSetter` (`tools/reactor/codegen.zig:293-296`), and `emitAttachedSetterCall` generates `IInspectable -> IUIElement` casts plus static owner calls (`tools/reactor/codegen.zig:715-756`).
- Attached codegen is still blocked for Grid because `resolveAttachedSetter` only accepts attached setters whose first parameter is `Microsoft.UI.Xaml.UIElement` (or `object`) (`tools/reactor/codegen.zig:1241-1272`), while Grid statics require `FrameworkElement` for `SetRow/SetColumn/SetRowSpan/SetColumnSpan` (`packages/win-reactor/src/winui/Microsoft.UI.Xaml.Controls.zig:806-817`).
- The current manifest already proves generated attached support for Canvas: `canvas_left`, `canvas_top`, and `canvas_z_index` are hand-authored as attached properties in `tools/reactor/widget_manifest.zig:14-34`, and the generated setter table emits `.setter_kind = .attached` entries for those properties (`tools/reactor/generated/generated_set_prop.zig:72-118`, `tools/reactor/generated/generated_set_prop.zig:780-805`).
- Grid attached properties are not manifest-driven yet. The Grid widget declaration only contains manual `RowDefinitions`/`ColumnDefinitions` entries (`tools/reactor/widget_manifest.zig:236-244`), and the docs still teach child placement through raw string props (`docs/windows-reactor.md:569-587`).
- The WinUI backend still special-cases Grid attached properties before generated dispatch even runs: `setProperty` calls `setManualProperty` first (`packages/win-reactor/src/winui_backend.zig:410-417`), `setManualProperty`/`unsetManualProperty` route a hard-coded widget-kind list through `setGridAttachedProperty`/`clearGridAttachedProperty` (`packages/win-reactor/src/winui_backend.zig:875-936`), and those helpers manually inspect `"Grid.Row"`, `"Grid.Column"`, `"Grid.RowSpan"`, and `"Grid.ColumnSpan"` (`packages/win-reactor/src/winui_backend.zig:1172-1212`, `packages/win-reactor/src/winui_backend.zig:1474-1478`).
- The current public API has no typed attached-property builder surface. Builders only expose `.prop(...)` today (`docs/windows-reactor.md:90-100`), `grid()` explicitly documents Grid child placement as a raw escape hatch (`packages/win-reactor/src/widgets_layout.zig:139-142`), and the only ergonomic attached-property helper is the handwritten Canvas wrapper that emits `"Left"`, `"Top"`, and `"ZIndex"` strings (`packages/win-reactor/src/widgets_canvas.zig:22-38`, `docs/windows-reactor.md:589-603`).

## Desired End State

- `zig build bindings` regenerates attached-property glue for both existing Canvas props and new Grid props, with no handwritten edits to `tools/reactor/generated/generated_set_prop.zig`.
- Grid attached setters are manifest-driven for the same widget classes the backend workaround supports today, and `packages/win-reactor/src/winui_backend.zig` no longer contains `setGridAttachedProperty`, `clearGridAttachedProperty`, or `isGridAttachedProperty`.
- Removing an attached property no longer depends on handwritten Grid default values; attached-property clear/unset is handled by generated code.
- The public builder API supports chained, typed attached setters via `builder.attached(reactor.Grid.row(1))` (and analogous owner-scoped helpers such as `reactor.Canvas.left(32)`), while raw `.prop("Grid.Row", value)` remains a compatible escape hatch.
- `zig build test` passes, `zig build bindings` is clean, and `zig build reactor-selftest` passes on Windows with Grid-using samples still compiling/running.

## Key Discoveries

- The schema/loader work from earlier reactor planning already did the heavy lifting for attached metadata; the remaining gaps are emitter/runtime/public API gaps, not manifest-shape gaps (`tools/reactor/schema.zig:27-58`, `tools/reactor/manifest.zig:114-127`).
- The generated setter path is not “missing” across the board: Canvas already uses it successfully, so the implementation can extend the existing attached pipeline instead of inventing a second one (`tools/reactor/widget_manifest.zig:14-34`, `tools/reactor/generated/generated_set_prop.zig:72-118`).
- The real Grid blocker is the target parameter type, not the owner lookup: Grid statics are discoverable, but their setter signatures use `FrameworkElement`, which the current attached resolver rejects (`tools/reactor/codegen.zig:1241-1272`, `packages/win-reactor/src/winui/Microsoft.UI.Xaml.Controls.zig:806-817`).
- The backend workaround has two distinct responsibilities that both have to disappear: handwritten apply-time setter calls and handwritten clear/unset behavior (`packages/win-reactor/src/winui_backend.zig:875-936`, `packages/win-reactor/src/winui_backend.zig:1172-1212`).
- The full generated WinUI projection already exposes `DependencyObject.ClearValue`, so attached-property clearing can be made generic instead of replacing one hard-coded Grid default table with another (`packages/win/src/generated/Microsoft.UI.Xaml.zig:2269-2278`).

## What We're NOT Doing

- We are **not** redesigning the generic `.prop(...)` escape hatch or removing string-based property names; the new attached API is additive and raw names stay supported for advanced callers.
- We are **not** broadening Grid attached-property support to every theoretical future widget in the catalog in this issue. The first pass will cover the same widget classes already proven by the current workaround, then future widgets can opt in by adding the same manifest entries.
- We are **not** converting every non-attached property unset path to generated metadata. This issue only removes handwritten backend logic for attached properties.
- We are **not** changing unrelated manual property paths such as `RowDefinitions`, `ColumnDefinitions`, `BorderThickness`, `CornerRadius`, or `Background`; those remain separate work items.

## Implementation Approach

### Chosen builder API

Use a single new builder method plus owner-scoped generated helpers:

```zig
_ = try (try cell.attached(reactor.Grid.row(0)))
    .attached(reactor.Grid.column(1));
```

### Rationale

1. **One builder change covers every widget builder.** Adding `attached(self, spec)` to the shared builder implementation is much less invasive than generating per-widget methods.
2. **Owner scoping prevents name collisions.** `Grid.row_span` and `Canvas.left` stay grouped by attached-property owner instead of spraying root-level `grid_row(...)`/`canvas_left(...)` helpers everywhere.
3. **The API can preserve raw-property compatibility.** Each generated helper can lower to the existing canonical property string (`"Grid.Row"`, `"Left"`, etc.), so current `.prop(...)` call sites still work.
4. **It composes with current helper patterns.** Existing wrappers such as `canvas_position()` can become thin sugar over the same attached helper surface instead of remaining a separate handwritten mechanism.

### Naming and manifest decisions

- Keep the public builder surface owner-scoped (`reactor.Grid.row`, `reactor.Grid.column_span`, `reactor.Canvas.left`, etc.).
- Represent Grid attached props in the manifest with quoted owner-qualified property keys such as `@"Grid.Row"` so raw `.prop("Grid.Row", ...)` stays valid.
- Set `winrt_name = "Row"` / `"Column"` / `"RowSpan"` / `"ColumnSpan"` for those quoted manifest entries so codegen still has the actual XAML property segment available for dependency-property getter generation and helper naming.
- Override Grid field names to `grid_row`, `grid_column`, `grid_row_span`, and `grid_column_span` so generated field metadata stays stable even though the raw property name contains a dot.

### Runtime/codegen strategy

- Extend attached setter resolution to capture the required target parameter type (`UIElement` vs `FrameworkElement` vs `object`) instead of assuming everything is `UIElement`.
- Generate both **apply** and **clear** helpers for attached properties. Apply helpers continue to call the static owner setter; clear helpers use the owner’s `get_*Property` accessor plus `DependencyObject.ClearValue`.
- Teach `winui_backend.zig` to recognize attached bindings through generated metadata before falling back to manual logic: attached setters should convert values by `PropertySetter.value_kind`, dispatch through generated apply glue, and clear through generated attached-clear glue.
- Generate the attached builder namespaces from manifest data (deduped by attached owner + property), not by hand, so future attached props only require manifest additions.

## Phase 1: Extend generated attached-property plumbing

### Overview

Make the generated setter pipeline capable of handling Grid-style attached setters and attached-property clearing, while keeping the current manual Grid workaround in place until the manifest has been migrated.

### Changes Required

1. **Teach codegen about attached target interface types**
   - Update `tools/reactor/codegen.zig` so `ResolvedSetter` records the attached target type/interface instead of hard-coding `UIElement`.
   - Relax `resolveAttachedSetter` to accept `FrameworkElement`-targeted attached setters in addition to the existing `UIElement`/`object` cases (`tools/reactor/codegen.zig:1241-1272` is the current rejection point).
   - Change `emitAttachedSetterCall` to cast the widget handle to the resolved target interface before calling the owner statics (`tools/reactor/codegen.zig:715-756`).

2. **Generate attached clear helpers**
   - Extend the generated property metadata with an attached clear entry point (for example, a `clear` function pointer or dedicated attached clear dispatcher) alongside the existing `apply` function.
   - Have the generated clear helper call the owner’s `get_*Property` accessor and then `DependencyObject.ClearValue` using the already-generated WinUI projection (`packages/win/src/generated/Microsoft.UI.Xaml.zig:2269-2278`) instead of baking Grid-specific reset values into the backend.
   - Update `build.zig` module wiring if the generated setter module needs an extra import from the full `win` package for `DependencyObject.ClearValue`.

3. **Add attached-runtime lookup paths**
   - In `packages/win-reactor/src/winui_backend.zig`, look up the generated property entry before dispatch and, when `setter_kind == .attached`, convert the boxed property into a `SetterValue` using the generated `value_kind` instead of falling through the widget-kind-specific switch.
   - In `unsetProperty`, call the generated attached clear helper before the existing non-attached reset logic.

4. **Keep the pipeline regeneratable**
   - Update `packages/winbindgen/src/main.zig` and `build.zig` so `zig build bindings` keeps producing all required generated reactor files after the new attached-clear surface is added.

### Success Criteria

- `zig build bindings` regenerates `tools/reactor/generated/generated_set_prop.zig` with attached helpers that can target `FrameworkElement`.
- Existing Canvas attached entries continue to compile and now also have generated clear support.
- `zig build test` still passes before any Grid manifest migration happens.

## Phase 2: Add the public attached-property builder surface

### Overview

Expose attached properties through a typed, owner-scoped builder API that layers on top of the existing raw property storage model.

### Changes Required

1. **Add a shared builder hook**
   - Add `attached(self, spec)` to the shared builder implementation in `packages/win-reactor/src/element.zig`.
   - The method should be generic and chainable, returning the same builder after delegating to the attached spec’s `apply(...)` helper.

2. **Generate owner-scoped attached helper namespaces**
   - Add a new codegen emitter (for example `generated_attached_props.zig`) that walks the manifest, dedupes attached properties by owner/property, and emits namespaces such as `Grid` and `Canvas`.
   - Each generated helper should lower to the canonical property string for that attached property and preserve the declared value type (`i32` for Grid row/column/span, `f64`/`i32` for Canvas, etc.).
   - Wire the new generated file through `packages/winbindgen/src/main.zig`, `build.zig`, and `packages/win-reactor/src/root.zig` so it is exported from `win-reactor`.

3. **Rebase existing helper sugar on the new API**
   - Reimplement `canvas_position()` / `canvas_position_z()` in `packages/win-reactor/src/widgets_canvas.zig` on top of `builder.attached(reactor.Canvas.left(...))`, `reactor.Canvas.top(...)`, and `reactor.Canvas.z_index(...)`.
   - Leave the public helper names intact so existing sample code does not need a breaking rename.

### Success Criteria

- `builder.attached(reactor.Grid.row(1))` compiles from `win-reactor`.
- `canvas_position()` still works, but now uses the shared attached-property path instead of special handwritten property names.
- Raw `.prop("Grid.Row", ...)` and `.prop("Left", ...)` remain valid for compatibility.

## Phase 3: Migrate Grid onto the generated path and remove the backend workaround

### Overview

Move Grid attached properties into the manifest/codegen path, delete the backend workaround, and update the public docs/tests to use the new builder API.

### Changes Required

1. **Add Grid attached properties to the manifest**
   - In `tools/reactor/widget_manifest.zig`, add quoted `@"Grid.Row"`, `@"Grid.Column"`, `@"Grid.RowSpan"`, and `@"Grid.ColumnSpan"` entries (with `winrt_name`/`field` overrides) to the same widget classes currently covered by `setGridAttachedProperty` (`packages/win-reactor/src/winui_backend.zig:878-881`).
   - Reuse shared `Prop` constants for the four Grid entries the same way Canvas currently reuses `canvas_left`, `canvas_top`, and `canvas_z_index` (`tools/reactor/widget_manifest.zig:14-34`).

2. **Regenerate and verify Grid setter glue**
   - Run `zig build bindings` so `tools/reactor/generated/generated_set_prop.zig` gains Grid attached setter entries and any new generated attached-helper file gains `reactor.Grid.*`.
   - Add/extend manifest/codegen tests so the quoted Grid property names, field overrides, and attached normalization are covered.

3. **Delete the handwritten Grid backend path**
   - Remove `setGridAttachedProperty`, `clearGridAttachedProperty`, `isGridAttachedProperty`, and the Grid-specific branches in `setManualProperty`/`unsetManualProperty`.
   - Keep `RowDefinitions`/`ColumnDefinitions` in the manual path; only the attached-property workaround is deleted.

4. **Update docs and representative usage sites**
   - Update `docs/windows-reactor.md` and `packages/win-reactor/src/widgets_layout.zig` so the recommended Grid child-placement API is the new typed attached surface, with raw `.prop("Grid.Row", ...)` documented as an escape hatch instead of the primary example.
   - Add at least one builder/sample test that uses `builder.attached(reactor.Grid.row(...))` so the new API is exercised outside pure codegen unit tests.

### Success Criteria

- `packages/win-reactor/src/winui_backend.zig` no longer contains the Grid attached-property workaround.
- `tools/reactor/generated/generated_set_prop.zig` includes generated Grid attached entries.
- The docs show the new attached API, and at least one Grid sample/test uses it.

## Success Criteria

- Attached-property codegen supports both `UIElement`-targeted and `FrameworkElement`-targeted static setters.
- Attached-property apply and clear/unset both go through generated glue instead of handwritten Grid backend code.
- `win-reactor` exports a typed attached-property builder API centered on `builder.attached(reactor.Grid.row(...))`.
- Grid attached properties ship through the same manifest/codegen/runtime pipeline already used by Canvas attached props.
- `zig build bindings`, `zig build test`, and `zig build reactor-selftest` all pass after the work lands.

## Testing Strategy

### Generator / manifest coverage

- Extend `tools/reactor/manifest.zig` tests to cover quoted owner-qualified Grid property keys, `winrt_name` overrides, and field overrides.
- Add codegen assertions/golden coverage that a `FrameworkElement`-targeted attached setter resolves successfully and emits both apply + clear glue.
- Verify the regenerated setter table contains Grid entries with `.setter_kind = .attached`.

### Runtime / API coverage

- Add unit tests for `Builder.attached(...)` and the generated owner namespaces (`Grid`, `Canvas`) so the new API is compile-time and runtime exercised.
- Keep/extend `widgets_canvas.zig` tests to confirm the new attached builder surface still writes the expected attached properties.
- Add a Grid-specific builder test that writes row/column/span through the new API and verifies the stored property names/values before the backend is involved.

### End-to-end validation

- Run `zig build bindings` after manifest/codegen changes.
- Run `zig build test` to cover generator code, win-reactor unit tests, and sample compilation.
- Run `zig build reactor-selftest` on Windows to smoke-test real WinUI samples, with special attention to Grid-using samples such as `reactor_tictactoe`, `reactor_minesweeper`, and `reactor_dotsweeper` (the current Grid consumers).

## References

- GitHub issue #68: https://github.com/cataggar/windows-zig/issues/68
- GitHub issue #22: https://github.com/cataggar/windows-zig/issues/22
- GitHub issue #3: https://github.com/cataggar/windows-zig/issues/3
- Manifest schema: `tools/reactor/schema.zig`
- Reactor codegen entry point: `packages/winbindgen/src/main.zig`
- Current attached setter generator: `tools/reactor/codegen.zig`
- Current Grid workaround: `packages/win-reactor/src/winui_backend.zig`
