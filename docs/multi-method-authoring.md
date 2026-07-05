# Multi-method COM / WinRT interface authoring

`win-core.MultiInterfaceObject` is the reusable helper for authoring a
single heap allocation that exposes **multiple** COM / WinRT interface
faces. It is the multi-method companion to `win-core.Delegate(...)`:
use `Delegate` for one-method callback objects, and `MultiInterfaceObject`
for authored interfaces such as `IVector<T>`, `IMap<K,V>`, event args,
or future widget data sources.

## When to use it

Use `MultiInterfaceObject` when a custom object must:

- expose more than one interface (`IIterable<T>` + `IVector<T>`)
- own mutable backing state
- answer `QueryInterface` for several IIDs
- participate in normal COM / WinRT refcounting
- optionally provide WinRT metadata (`IInspectable`)

## Shape

```zig
const Author = core.MultiInterfaceObject(State, .{
    .runtime_class_name = MyInterface.NAME_W,
    .trust_level = 0,
    .agile = true,
}, .{
    core.interfaceSpec(IFirst, .{
        .base = undefined,
        .MethodA = methodA,
    }),
    core.interfaceSpec(ISecond, .{
        .base = undefined,
        .MethodB = methodB,
    }),
});
```

- `State` is your backing storage.
- Each `interfaceSpec` entry supplies one authored face.
- The `base` field is always `undefined`; `MultiInterfaceObject`
  fills `QueryInterface` / `AddRef` / `Release` automatically.
- For WinRT faces (`IInspectable_Vtbl` base), it also fills
  `GetIids`, `GetRuntimeClassName`, and `GetTrustLevel`.

## Returned helpers

The generated namespace exposes:

- `create(allocator, state)` → allocate storage with refcount 1
- `as(storage, Handle)` → borrowed pointer to one face
- `storageFrom(Handle, iface)` → recover the backing allocation
- `stateFrom(Handle, iface)` → recover `State`
- `allocatorFrom(Handle, iface)` → recover the allocator

`QueryInterface(IID_IUnknown)` returns the **first** authored face, so
put the interface you want to act as the identity face first.

## State cleanup

If `State` needs teardown, provide one of:

```zig
pub fn deinit(self: *@This()) void
pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void
```

The function must be `pub`; it is called automatically when the final
`Release()` drops the refcount to zero.

## Minimal example

```zig
const State = struct {
    value: u32,
};

const Author = core.MultiInterfaceObject(State, .{
    .runtime_class_name = IMyValue.NAME_W,
}, .{
    core.interfaceSpec(IMyValue, .{
        .base = undefined,
        .get_Value = getValue,
        .SetValue = setValue,
    }),
});

fn getValue(this: *const IMyValue, result: *u32) callconv(.winapi) core.HRESULT {
    result.* = Author.stateFrom(IMyValue, this).value;
    return core.hresult.S_OK;
}

fn setValue(this: *const IMyValue, value: u32) callconv(.winapi) core.HRESULT {
    Author.stateFrom(IMyValue, this).value = value;
    return core.hresult.S_OK;
}
```

Creating and returning the interface:

```zig
const storage = try Author.create(allocator, .{ .value = 42 });
return Author.as(storage, IMyValue);
```

## Collection-package examples

Issue #10 uses this helper for:

- `IVectorChangedEventArgs`
- `IMapChangedEventArgs<K>`
- stock `IIterable<T>` / `IVector<T>` / `IVectorView<T>`
- stock `IMap<K,V>` / `IMapView<K,V>`
- stock `IObservableVector<T>` / `IObservableMap<K,V>`

See:

- `packages/win-collections/src/stock_vector.zig`
- `packages/win-collections/src/stock_map.zig`

Those files show the intended pattern for future reusable WinRT
infrastructure: keep all authored faces on one allocation, store
backing state separately from vtable glue, and recover that state via
`stateFrom(...)` inside each ABI entrypoint.
