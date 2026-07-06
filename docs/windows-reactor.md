# windows-reactor

`win-reactor` is the hook engine, reconciler, and WinUI 3 backend under
`packages/win-reactor/src/`. This guide documents the Zig API that actually
ships today.

## Before you start

- Run `zig build fetch-winui-metadata` once in a fresh checkout.
- Stage the Windows App Runtime assets before running a WinUI sample or app;
  see [windows-reactor setup](windows-reactor-setup.md).
- All examples here assume:

```zig
const std = @import("std");
const reactor = @import("win-reactor");
```

## Getting started

### App host

`App` owns the WinUI bootstrap path. A root render function has this shape:

```zig
fn renderRoot(cx: *reactor.RenderCx) reactor.ElementError!reactor.Element
```

The host entry point is:

```zig
var app = reactor.App.init(allocator);
app.exit_after_ms = null; // optional; samples use this for automated exits
try app.render(renderRoot);
```

`App.render` creates the WinUI `Application`, initializes the Windows App
Runtime bootstrap, mounts the reconciler tree, and runs the WinUI message loop.
In user code you normally return a `window(...)` element from `renderRoot`.

### Minimal hello world

This is the shipped pattern from `samples/reactor_hello/main.zig`:

```zig
const std = @import("std");
const reactor = @import("win-reactor");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();

    var app = reactor.App.init(allocator);
    try app.render(renderRoot);
}

fn renderRoot(cx: *reactor.RenderCx) reactor.ElementError!reactor.Element {
    const allocator = cx.getAllocator();

    var button = try reactor.button(allocator, "WinUI 3 button", null);
    defer button.deinit(allocator);

    var text = try reactor.text_block(
        allocator,
        "Hello from the reconciler-driven backend.",
    );
    defer text.deinit(allocator);

    var content = try reactor.vstack(allocator, .{ &button, &text });
    defer content.deinit(allocator);

    var window_builder = reactor.window(allocator);
    defer window_builder.deinit();
    _ = try window_builder.prop("Title", @as([]const u8, "windows-zig reactor hello"));
    _ = try window_builder.child(&content);

    return window_builder.build();
}
```

### Two API layers

`win-reactor` exposes both:

1. **Convenience helpers that return `reactor.Element`**  
   Examples: `text_block`, `button`, `vstack`, `grid`, `canvas`.
2. **Raw builders that return builder structs**  
   Examples: `window`, `button_builder`, `grid_builder`,
   `text_block_builder`, `content_dialog_builder`.

Use raw builders when you need extra manifest-backed props or events, typed
attached properties such as `reactor.Grid.row(0)`, pointer events, or widget
refs.

All builders share the same core methods:

```zig
builder.withKey("stable-key")
builder.prop("Name", value)
builder.attached(reactor.Grid.row(0))
builder.on("EventName", callback)
builder.child(&child)
builder.childrenFrom(.{ &a, &b, &c })
try builder.build()
```

Raw builder entry points exported from `win-reactor`:

- `application` / `application_builder`
- `window` / `window_builder`
- `button_builder`
- `stack_panel_builder`
- `grid_builder`
- `scroll_viewer_builder`
- `border_builder`
- `text_block_builder`
- `text_box_builder`
- `check_box_builder`
- `slider_builder`
- `combo_box_builder`
- `toggle_switch_builder`
- `radio_button_builder`
- `content_dialog_builder`
- `flyout_builder`
- `navigation_view_builder`
- `navigation_view_item_builder`
- `menu_bar_builder`
- `menu_bar_item_builder`
- `canvas_builder`
- `list_view_builder`
- `items_repeater_builder`

### Ownership and borrowed data

Two rules matter in practice:

- Builders and temporary `Element` values own memory. Follow the samples and
  `defer ...deinit(...)` them.
- Most string props are stored as borrowed `[]const u8` slices. Keep the backing
  storage alive for as long as the element tree may read it. The samples use
  string literals, arena-backed arguments, or `useRef` buffers for formatted
  text.

## Event callbacks

The event layer is intentionally small:

```zig
reactor.EventCallback.init(userdata, fn (?*anyopaque) void)
reactor.EventCallback.initTyped(T, userdata, fn (?*anyopaque, T) void)
```

Use `init` for unit events such as `Click`. Use `initTyped` when the event
passes a payload.

Current typed payloads exposed by shipped widgets:

- `bool`
- `[]const u8`
- `f64`
- `i32`
- `reactor.PointerEventInfo`

`PointerEventInfo` contains:

```zig
pub const PointerEventInfo = struct {
    x: f64 = 0,
    y: f64 = 0,
    is_left_button_pressed: bool = false,
    is_right_button_pressed: bool = false,
    is_middle_button_pressed: bool = false,
};
```

## Hooks reference

### Common rules

- Hook order is stable-by-position. Changing the number or order of hooks in a
  component causes `HookOrderMismatch`.
- `useState`, `useReducer`, `useReducerFn`, `useAsyncState`, and `useContext`
  all expect **copy-safe** value types. Put owned resources behind pointers or
  store them in `useRef`.
- State, reducer, and async setters compare with `std.meta.eql` and request a
  rerender only when the value really changes.
- `useMemo`, `useEffect`, and `useEffectWithCleanup` also use equality on the
  `deps` value to decide whether work is needed.

### `useContext`

```zig
pub fn useContext(
    self: *RenderCx,
    comptime T: type,
    value_context: *const reactor.Context(T),
) reactor.Error!T
```

- Returns the nearest provided value, or the context default if nothing above
  provided one.
- Reads are by value, not by pointer.
- Provide values with `reactor.provide(...)`.

Example:

```zig
const ThemeContext = reactor.Context([]const u8);
const theme = ThemeContext.init("light");
// ...
const current = try cx.useContext([]const u8, &theme);
// ...
return reactor.provide(allocator, &child, &theme, "dark");
```

### `useState`

```zig
pub fn useState(
    self: *RenderCx,
    comptime T: type,
    initial: T,
) reactor.Error!reactor.StateResult(T)
```

Returns:

```zig
pub const StateResult = struct {
    value: *const T,
    set: reactor.SetState(T),
};
```

- `value` points into stable hook-slot storage.
- `set.call(new_value)` updates the slot and schedules a rerender.
- Equal values are ignored.

### `useRef`

```zig
pub fn useRef(
    self: *RenderCx,
    comptime T: type,
    initial: T,
) reactor.Error!reactor.HookRef(T)
```

`HookRef(T)` exposes:

```zig
get() *const T
getMut() *T
set(value: T) void
replace(value: T) T
```

- `useRef` is for mutable storage that should **not** rerender the component.
- Samples use it for reusable buffers, event-capture structs, and cached state.

### `useMemo`

```zig
pub fn useMemo(
    self: *RenderCx,
    comptime T: type,
    deps: anytype,
    memo_context: anytype,
    comptime factory: *const fn (*const @TypeOf(memo_context)) T,
) reactor.Error!*const T
```

- Computes once for a given `deps` value, then reuses the stored result until
  `deps` changes.
- Returns `*const T`, not `T`, so large or non-trivial memoized values are not
  copied on every render.

### `useEffect`

```zig
pub fn useEffect(
    self: *RenderCx,
    deps: anytype,
    effect_context: anytype,
    comptime effect: *const fn (*const @TypeOf(effect_context)) void,
) reactor.Error!void
```

- Schedules a side effect after the render commits.
- Runs on the first render and again whenever `deps` changes.
- If `deps` is unchanged, nothing is scheduled.

### `useEffectWithCleanup`

```zig
pub fn useEffectWithCleanup(
    self: *RenderCx,
    comptime CleanupContext: type,
    deps: anytype,
    effect_context: anytype,
    comptime effect: *const fn (*const @TypeOf(effect_context)) ?CleanupContext,
    comptime cleanup: *const fn (*CleanupContext) void,
) reactor.Error!void
```

- Same dependency rules as `useEffect`.
- If `effect` returns a cleanup context, `cleanup` runs:
  - before the next effect when `deps` changes
  - when the component unmounts
- The hook slot owns the cleanup context and deinits it after cleanup runs.

### `useReducer`

```zig
pub fn useReducer(
    self: *RenderCx,
    comptime T: type,
    initial: T,
) reactor.Error!reactor.ReducerResult(T)
```

Returns:

```zig
pub const ReducerResult = struct {
    value: *const T,
    update: reactor.Updater(T),
};
```

`Updater(T)` exposes:

```zig
call(reducer: *const fn (*const T) T) void
callWith(
    reducer_context: anytype,
    comptime reducer: *const fn (*const @TypeOf(reducer_context), *const T) T,
) void
```

- `useReducer` keeps reducer logic at the call site instead of storing a reducer
  function in the hook slot.
- Samples use `update.callWith(...)` for state transitions that need an action
  payload or extra context.

### `useReducerFn`

```zig
pub fn useReducerFn(
    self: *RenderCx,
    comptime State: type,
    comptime Action: type,
    reducer: *const fn (*const State, Action) State,
    initial: State,
) reactor.Error!reactor.ReducerFnResult(State, Action)
```

Returns:

```zig
pub const ReducerFnResult = struct {
    value: *const State,
    dispatch: reactor.Dispatch(State, Action),
};
```

- `dispatch.call(action)` runs the reducer and rerenders on change.
- The reducer function lives on the dispatch handle, so it can vary across
  renders if needed.
- `samples/reactor_minesweeper` uses this style.

### `useAsyncState`

```zig
pub fn useAsyncState(
    self: *RenderCx,
    comptime T: type,
    initial: T,
) reactor.Error!reactor.AsyncStateResult(T)
```

Returns:

```zig
pub const AsyncStateResult = struct {
    value: T,
    set: reactor.AsyncSetState(T),
};
```

- The stored cell is thread-safe.
- `value` is returned by value because the underlying slot is lock-protected.
- `set.call(new_value)` is safe to use from other threads.
- Calls after the hook is torn down are ignored by token, rather than writing
  into freed storage.

## Widget catalog

### Root/application builders

`App.render(...)` already creates the WinUI `Application`. Most apps only build
the window:

```zig
var window_builder = reactor.window(allocator);
defer window_builder.deinit();
_ = try window_builder.prop("Title", @as([]const u8, "My App"));
_ = try window_builder.child(&content);
return window_builder.build();
```

Notes:

- `window` is a builder, not a convenience helper.
- A window may have only one child.

### Text and stack helpers

- `pub fn text_block(allocator: Allocator, text: []const u8) ElementError!Element`  
  Sets `Text`.

- `pub fn button(allocator: Allocator, content: []const u8, on_click: ?EventCallback) ElementError!Element`  
  Sets `Content`; optionally wires `Click`.

- `pub fn vstack(allocator: Allocator, children: anytype) ElementError!Element`  
  Builds a `StackPanel` with `Orientation = Vertical` and
  `Spacing = reactor.DefaultStackSpacing`.

- `pub fn hstack(allocator: Allocator, children: anytype) ElementError!Element`  
  Builds a `StackPanel` with `Orientation = Horizontal` and the same default
  spacing.

- `pub fn vstack_spaced(allocator: Allocator, spacing: f64, children: anytype) ElementError!Element`

- `pub fn hstack_spaced(allocator: Allocator, spacing: f64, children: anytype) ElementError!Element`

Raw-builder extras:

- `button_builder`, `text_block_builder`, and `stack_panel_builder` can also
  attach pointer events with `"PointerPressed"`, `"PointerMoved"`, and
  `"PointerReleased"`.
- `button_builder` and `text_block_builder` can also use canvas positioning
  (`"Left"`, `"Top"`, `"ZIndex"`).

### Layout and containers

- `pub fn grid(allocator: Allocator, options: GridOptions, children: anytype) ElementError!Element`  
  Sets optional `RowDefinitions` and `ColumnDefinitions`, then appends children.

- `pub fn scroll_viewer(allocator: Allocator, child: anytype) ElementError!Element`  
  Single-child `ScrollViewer`.

- `pub fn border(allocator: Allocator, options: BorderOptions, child: anytype) ElementError!Element`  
  Optional `BorderThickness`, `CornerRadius`, `Background`, plus one child.

- `pub fn canvas(allocator: Allocator, children: anytype) ElementError!Element`  
  Free-positioned container.

Helper types:

- `GridTrack.auto()`
- `GridTrack.pixels(f64)`
- `GridTrack.star(f64)`
- `GridTracks.init(.{ ... })`
- `uniform_thickness(f64)`
- `uniform_corner_radius(f64)`
- `Color.rgb(r, g, b)`
- `Color.argb(a, r, g, b)`

### Input widgets

- `pub fn check_box(allocator: Allocator, content: []const u8, is_checked: bool, on_checked: ?EventCallback, on_unchecked: ?EventCallback) ElementError!Element`  
  Sets `Content`, `IsChecked`; optionally wires `Checked` and `Unchecked`.

- `pub fn slider(allocator: Allocator, value: f64, minimum: f64, maximum: f64, on_value_changed: ?EventCallback) ElementError!Element`  
  Sets `Value`, `Minimum`, `Maximum`; optionally wires `ValueChanged`. Use
  `EventCallback.initTyped(f64, ...)` to receive the new value.

- `pub fn combo_box(allocator: Allocator, items: []const []const u8, selected_index: i32, on_selection_changed: ?EventCallback) ElementError!Element`  
  Sets `ItemsSource` from a string list and `SelectedIndex`; optionally wires
  `SelectionChanged`. Use `EventCallback.initTyped(i32, ...)` to receive the
  selected index.

- `pub fn toggle_switch(allocator: Allocator, is_on: bool, on_toggled: ?EventCallback) ElementError!Element`  
  Sets `IsOn`; optionally wires `Toggled`. Use `EventCallback.initTyped(bool, ...)`
  to receive the current `IsOn` value.

- `pub fn radio_button(allocator: Allocator, content: []const u8, is_checked: bool, on_checked: ?EventCallback) ElementError!Element`  
  Sets `Content`, `IsChecked`; optionally wires `Checked`.

- `pub fn text_box(allocator: Allocator, text: []const u8, on_text_changed: ?EventCallback) ElementError!Element`  
  Exported today, sets `Text`, and optionally wires `TextChanged` with a
  `[]const u8` payload via `EventCallback.initTyped([]const u8, ...)`.

  **Known gap:** real WinUI `TextBox` construction is still blocked by the
  runtime crash tracked in issue #74, so `text_box` is not part of the stable
  v1.0 surface yet. `samples/reactor_notepad` documents the intended API shape
  but currently exits with `error.NotYetSupported`.

### Collections

- `pub fn observable_items_source(allocator: Allocator, values: anytype) !*IObservableVector(T)`  
  Builds a WinRT observable vector from a slice, array, or `.items` collection.

- `pub fn items_source(value: anytype) ?*const anyopaque`  
  Accepts a WinRT interface pointer or `?*const anyopaque`.

- `pub fn list_view(allocator: Allocator, children: anytype, on_selection_changed: ?EventCallback) ElementError!Element`  
  Child-driven `ListView`; optionally wires `SelectionChanged`.

- `pub fn list_view_from_source(allocator: Allocator, source: anytype, on_selection_changed: ?EventCallback) ElementError!Element`  
  Explicit `ItemsSource`-driven `ListView`.

- `pub fn items_repeater(allocator: Allocator, children: anytype) ElementError!Element`  
  Child-driven `ItemsRepeater`.

- `pub fn items_repeater_from_source(allocator: Allocator, source: anytype) ElementError!Element`  
  Explicit `ItemsSource`-driven `ItemsRepeater`.

Rules:

- `list_view` and `items_repeater` can be driven either by child elements or by
  `ItemsSource`, but not both at once.
- For source-driven lists, the backend expects a WinRT object pointer, not an
  arbitrary Zig slice.

### Overlays and navigation

- `pub fn with_ref(builder: anytype, ref: *WidgetRef) ElementError!@TypeOf(builder)`  
  Attaches a widget ref to a builder.

- `pub fn content_dialog(allocator: Allocator, options: ContentDialogOptions, content: anytype) ElementError!Element`  
  Supports `Title`, `PrimaryButtonText`, `SecondaryButtonText`,
  `CloseButtonText`, optional `ref`, and one child content element.

- `pub fn flyout(allocator: Allocator, content: anytype, ref: ?*WidgetRef) ElementError!Element`  
  Single child content plus optional ref.

- `pub fn navigation_view_item(allocator: Allocator, content: []const u8) ElementError!Element`  
  Sets `Content`. The current surface is a simple content-only item builder.

- `pub fn navigation_view(allocator: Allocator, menu_items: anytype, content: anytype) ElementError!Element`  
  Appends menu-item children, then the main content child.

- `pub fn menu_bar_item(allocator: Allocator, title: []const u8) ElementError!Element`  
  Sets `Title`. The current surface is a title-only menu item builder.

- `pub fn menu_bar(allocator: Allocator, items: anytype) ElementError!Element`  
  Container for `menu_bar_item` children.

Overlay hooks:

- `pub fn useOverlayHost(cx: *RenderCx) reactor.Error!*OverlayHost`
- `pub fn useContentDialog(cx: *RenderCx, ref: *WidgetRef) reactor.Error!ContentDialogHandle`
- `pub fn useFlyout(cx: *RenderCx, ref: *WidgetRef, anchor_ref: *WidgetRef) reactor.Error!FlyoutHandle`

`ContentDialogHandle.showAsync()` returns `ContentDialogFuture`, whose
`wait(allocator)` resolves to `reactor.ContentDialogResult`.

`content_dialog` and `flyout` describe the overlay widgets in the tree; showing
or hiding them is done through the handle returned by `useContentDialog(...)`
or `useFlyout(...)`.

## Layout and styling notes

### Stack layout

- `vstack`/`hstack` are thin `StackPanel` helpers.
- Default spacing is `reactor.DefaultStackSpacing` (`12.0`).
- Use `vstack_spaced` / `hstack_spaced` when the default is not enough.

### Grid layout

`grid` only sets track definitions. Child placement is done on the child
builder with typed attached-property helpers:

```zig
var cell = reactor.button_builder(allocator);
defer cell.deinit();
_ = try cell.prop("Content", "A1");
_ = try (try cell.attached(reactor.Grid.row(0)))
    .attached(reactor.Grid.column(0));
```

Supported attached grid helpers today:

- `reactor.Grid.row(...)`
- `reactor.Grid.column(...)`
- `reactor.Grid.row_span(...)`
- `reactor.Grid.column_span(...)`

Raw `.prop("Grid.Row", value)` / `.prop("Grid.Column", value)` remain valid as
an escape hatch when you need string-based property access.

### Canvas positioning

Canvas positioning is attached-property based. You can either use the typed
owner namespace directly or keep the convenience wrappers:

```zig
_ = try (try builder.attached(reactor.Canvas.left(32)))
    .attached(reactor.Canvas.top(64));
_ = try reactor.canvas_position(&builder, 32, 64);
_ = try reactor.canvas_position_z(&builder, 32, 64, 3);
```

These lower to the same attached-property names:

- `"Left"` → `Canvas.SetLeft`
- `"Top"` → `Canvas.SetTop`
- `"ZIndex"` → `Canvas.SetZIndex`

`button`, `text_block`, `stack_panel`, `text_box`, and `canvas` all have the
necessary manifest/backend support for these canvas properties.

### Border and simple styling

`border` accepts a `BorderOptions` struct:

```zig
.{
    .border_thickness = reactor.uniform_thickness(2),
    .corner_radius = reactor.uniform_corner_radius(8),
    .background = reactor.Color.rgb(0x20, 0x30, 0x40),
}
```

This is the shipped styling surface today. There is no broad Rust-style
modifier chain yet; use raw props when a widget already exposes a generated or
manual property.

## Sample apps

Shipped reactor samples are the best live references:

- `samples/reactor_hello` — smallest complete app
- `samples/reactor_counter` — `useState`, `check_box`, basic events
- `samples/reactor_canvas_drag` — pointer events + canvas positioning
- `samples/reactor_tictactoe` — `useState` + `grid`
- `samples/reactor_minesweeper` — `useReducerFn`
- `samples/reactor_dotsweeper` — `useReducer` + `useEffectWithCleanup`
- `samples/reactor_solitaire` — `canvas`, `Updater`, drag/drop
- `samples/reactor_notepad` — intended `text_box` API shape; currently blocked
  by issue #74

## Related docs

- [windows-reactor setup](windows-reactor-setup.md)
- [Windows reactor port findings](windows-reactor-port.md)
- [Reactor widget manifest](reactor-widget-manifest.md)
- [Multi-method COM / WinRT interface authoring](multi-method-authoring.md)
