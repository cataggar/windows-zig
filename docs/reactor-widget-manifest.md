# Reactor widget manifest

Issue #16 needs a manifest that tells future WinUI3 reactor codegen
which widget properties and events should get generated glue.

The Rust reactor already has this concept in
`crates/tools/reactor/src/winui.toml`. The Zig port keeps the same
high-level idea:

- the manifest is **hand-authored**
- the top-level keys are **full WinRT class names**
- each widget lists only the **properties/events that need glue**
- WinRT metadata still does the heavy lifting for interface/method lookup

The main adaptation is the file format: instead of TOML, windows-zig
uses a typed Zig source manifest.

## Why a `.zig` manifest

This repo already uses plain text manifests in `tools/bindings/src/*.txt`,
but those files only need to represent flat lists. Widget codegen needs
nested, typed data:

- per-widget sections
- separate property and event declarations
- enums for setter strategy / payload shape
- future support for attached properties and non-unit events

Using Zig source keeps that structure without adding a TOML/JSON parser
dependency:

- `tools/reactor/widget_manifest.zig` is the hand-edited manifest
- `tools/reactor/manifest.zig` imports it and exposes `load()` /
  `loadFromRaw()` helpers that normalize defaults into typed arrays
- `zig build test` compile-checks the manifest and its loader

This also fits the repo's broader "prefer Zig-native compile-time data
when it keeps the codegen path simple" direction from
`docs/comptime-vs-codegen.md`.

## Current codegen wiring

Issue #17's setter emitter reuses the existing `winbindgen` build-tool
entry point, but keeps the reactor-specific logic under `tools/reactor/`.
Running `zig build bindings` shells out to:

```text
winbindgen reactor-bindings --outdir <build-output>
```

and commits the generated setter glue to:

```text
tools/reactor/generated/generated_set_prop.zig
```

This keeps the WinMD loading / build-step plumbing in one place while
leaving room for future reactor-specific emitters (for example event
attacher glue) to land as sibling generated files in the same directory.

## Shape

`tools/reactor/widget_manifest.zig` exports one constant:

```zig
const schema = @import("schema.zig");
const Event = schema.EventInit;
const Prop = schema.PropInit;

pub const raw_widgets = .{
    .@"Microsoft.UI.Xaml.Controls.Button" = .{
        .props = .{
            .Content = Prop{
                .value = .string,
                .setter = .text_block,
            },
        },
        .events = .{
            .Click = Event{
                .payload = .unit,
            },
        },
    },
};
```

Compared to Rust's TOML, the only structural change is that members are
split into `.props` and `.events` blocks instead of being mixed in a
single table.

## Widget entry

Each top-level field name is the full WinRT class name:

```zig
.@"Microsoft.UI.Xaml.Controls.TextBlock" = .{ ... }
```

Each widget section may contain:

| Field | Meaning |
| --- | --- |
| `meta` | Optional widget-level overrides |
| `props` | Property declarations keyed by property name |
| `events` | Event declarations keyed by event name |

`meta` currently supports:

| Field | Default |
| --- | --- |
| `widget_name` | Short type name (`TextBlock`, `Button`, ...) |
| `handle_name` | Short type name |

The loader derives `namespace` and `short_name` from the top-level key,
so most entries do not need `meta`.

## Property declarations

Each `.props` member key is the logical property name. By default it is
also the WinRT metadata property name.

```zig
.Text = Prop{
    .value = .string,
}
```

Supported property fields:

| Field | Meaning |
| --- | --- |
| `winrt_name` | Override for the metadata property name; defaults to the manifest key |
| `field` | Override for the reactor widget struct field name; defaults to `snake_case(key)` |
| `value` | Reactor-facing value kind |
| `setter` | Setter strategy override |
| `winrt_type` | Optional fully qualified WinRT type override for enum/object cases |
| `attached` | Attached-property owner + setter info |

### `value`

`value` is a typed enum, not a stringly token:

- `.string`
- `.bool`
- `.f64`
- `.i32`
- `.u32`
- `.enum_i32`
- `.color`
- `.date_time`
- `.time_span`
- `.element`

Normal scalar props can usually omit `value` and let later codegen infer it
from WinUI metadata. The initial manifest uses explicit values because that
makes the intended shape load-bearing for issues #17 and #18.

### `setter`

`setter` tells the future property-setter generator how to turn the reactor
value into the WinRT call:

| Setter | Intended use |
| --- | --- |
| `direct` | Plain `put_*` call |
| `optional` | Nullable value (for setters like `IReference<bool>` patterns) |
| `boxed_reference` | Box a scalar/string into a WinRT reference type |
| `text_block` | Wrap a string in a `TextBlock` before assigning to an object/content property |
| `enum_i32` | Transport a Zig enum as an `i32`-backed WinRT enum |
| `attached` | Static attached-property setter |

Examples:

```zig
.Content = Prop{
    .value = .string,
    .setter = .text_block,
}
```

```zig
.Header = Prop{
    .value = .string,
    .setter = .boxed_reference,
}
```

Attached-property example:

```zig
.Row = Prop{
    .value = .i32,
    .attached = .{
        .owner = "Microsoft.UI.Xaml.Controls.Grid",
        .setter = "SetRow",
    },
}
```

If `attached` is present and `setter` is omitted, the loader normalizes the
setter to `.attached`.

## Event declarations

Each `.events` member key is the logical event name. By default it is also
the WinRT metadata event name.

```zig
.Click = Event{
    .payload = .unit,
}
```

Supported event fields:

| Field | Meaning |
| --- | --- |
| `winrt_name` | Override for the metadata event name; defaults to the manifest key |
| `field` | Override for the reactor handler field name; defaults to `on_` + `snake_case(key)` |
| `delegate` | Optional fully qualified WinRT delegate type override |
| `payload` | Reactor-facing payload kind |
| `source` | How to extract the payload |
| `manual` | Skip generated attach/detach glue and leave it to handwritten backend code |

### `payload`

Supported payload kinds:

- `.unit`
- `.bool`
- `.string`
- `.f64`
- `.i32`
- `.color`
- `.date_time`
- `.time_span`

### `source`

`source` replaces Rust's stringly `property` / `false_event` / inferred
invoke-pattern combination with a typed union:

| Source | Meaning |
| --- | --- |
| `.none` | Unit event; invoke the handler directly |
| `.sender_property = "IsOn"` | Read the payload from a getter on the sender/control |
| `.args_property = "NewValue"` | Read the payload from a getter on the event args |
| `.paired_bool = "Unchecked"` | Treat this event as the `true` arm of a bool pair and use the named event for the `false` arm |

Examples:

```zig
.Toggled = Event{
    .payload = .bool,
    .source = .{ .sender_property = "IsOn" },
}
```

```zig
.ValueChanged = Event{
    .payload = .f64,
    .source = .{ .args_property = "NewValue" },
}
```

```zig
.Checked = Event{
    .source = .{ .paired_bool = "Unchecked" },
}
```

## Defaults applied by `tools/reactor/manifest.zig`

The loader intentionally does only shape validation + defaulting. It does
**not** read winmd yet.

Defaults today:

1. `namespace` and `short_name` are split from the top-level class key.
2. `widget_name` and `handle_name` default to `short_name`.
3. Property `field` defaults to `snake_case(name)`.
4. Event `field` defaults to `on_` + `snake_case(name)`.
5. `attached` implies `setter = .attached` when the setter is omitted.
6. Event `source` defaults to `.none`.

Metadata-driven inference is intentionally deferred to follow-on codegen:

- issue #17 should infer missing property `value`, `setter`, `winrt_type`,
  owning interface, and the final WinRT method to call
- issue #18 should infer missing `delegate`, `payload`, add/remove methods,
  and any getter signatures needed by `source`

That keeps this slice focused on the manifest contract while still giving
later issues a concrete typed input to consume.

`load()` returns an arena-backed `Manifest`; callers should `defer manifest.deinit()`.

## Initial manifest contents

The checked-in manifest covers the first M5 widget batch:

- `Microsoft.UI.Xaml.Application`
- `Microsoft.UI.Xaml.Window` (`Title`)
- `Microsoft.UI.Xaml.Controls.TextBlock` (`Text`)
- `Microsoft.UI.Xaml.Controls.Button` (`Content`, `Click`)
- `Microsoft.UI.Xaml.Controls.StackPanel` (`Orientation`, `Spacing`)

This is enough to anchor:

- the text/button counter sample from issue #20
- scalar setter codegen for strings, floats, and enums
- unit event codegen (`Button.Click`)
- future extension to bool/args-based events without changing the top-level shape

## How issues #17 and #18 should consume it

Future codegen should import `tools/reactor/manifest.zig`, load the
normalized manifest once, and iterate `manifest.widgets`:

```zig
const manifest_mod = @import("../../tools/reactor/manifest.zig");

var manifest = try manifest_mod.load(allocator);
defer manifest.deinit();

for (manifest.widgets) |widget| {
    for (widget.props) |prop| {
        // Resolve widget.class_name + prop.winrt_name against WinUI metadata,
        // then emit setter glue.
    }
    for (widget.events) |event| {
        // Resolve widget.class_name + event.winrt_name against WinUI metadata,
        // then emit attach/detach glue.
    }
}
```

The important contract is:

- the **outer shape is stable now**
- all names are **exact strings** available to codegen
- defaults are already normalized
- metadata inference is a follow-on implementation detail, not a manifest-format question

That means issue #17 can build the setter emitter and issue #18 can build
the event emitter without revisiting the file format.
