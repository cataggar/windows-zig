# windows-reactor setup

This is the Zig-side equivalent of Rust's `windows-reactor-setup`, but the
current implementation is narrower: it stages the framework-dependent Windows
App Runtime bootstrap assets that `win-reactor` needs at startup.

## Current model: framework-dependent only

Today `windows-zig` ships **one** staging model:

- framework-dependent runtime staging

It does **not** currently ship direct equivalents of:

- `as_self_contained()`
- `as_example()`

`win-reactor.App.render(...)` still performs the runtime bootstrap at startup,
but it expects the bootstrap DLL and `resources.pri` to be present next to the
executable.

## Fresh-checkout build order

For a fresh worktree or clone:

```powershell
zig build fetch-winui-metadata --summary all
zig build stage-winui-runtime --summary all
```

Then build or run a sample:

```powershell
zig build run-reactor-hello -- --exit-after-ms 1500
```

Reactor sample run steps in `build.zig` already depend on `stage-winui-runtime`,
so the explicit staging step is mainly useful when you want to inspect or run
the installed `zig-out/bin/*.exe` layout yourself.

## What gets staged

`tools/stage-winui-runtime/main.zig` copies exactly two files into the target
directory:

- `Microsoft.WindowsAppRuntime.Bootstrap.dll`
- `resources.pri`

That matches the framework-dependent bring-up documented in
[windows-reactor-port.md](windows-reactor-port.md): the app uses the installed
Windows App Runtime on the machine, while the staged bootstrap DLL and PRI file
let the unpackaged executable start WinUI 3 correctly.

## Asset discovery order

`stage-winui-runtime` resolves assets in this order:

1. `WINDOWS_APP_RUNTIME_BOOTSTRAP_DLL`
2. `WINDOWS_APP_RUNTIME_RESOURCES_PRI`
3. a sibling `..\windows-rs\crates\libs\reactor-setup\...` checkout
4. for `x64` only, `C:\Program Files\WSL\wslsettings\Microsoft.WindowsAppRuntime.Bootstrap.dll`

The sibling-checkout paths are:

- `..\windows-rs\crates\libs\reactor-setup\bootstrap\<arch>\Microsoft.WindowsAppRuntime.Bootstrap.dll`
- `..\windows-rs\crates\libs\reactor-setup\assets\resources.pri`

If the files cannot be found, the step fails with a message telling you to set
the environment variables or place a sibling `windows-rs` checkout next to this
repo.

## Architecture mapping

`build.zig` passes one of:

- `--arch x86`
- `--arch x64`
- `--arch arm64`

The staging helper rejects other values.

## How `build.zig` wires it

The repo defines a host tool and a named build step:

```powershell
zig build stage-winui-runtime
```

That step copies the assets into `zig-out/bin/`.

Sample targets that set both:

- `run_installed = true`
- `needs_staged_winui_runtime = true`

automatically depend on the staging step. That includes:

- `hello-window`
- all current `reactor-*` samples

So `zig build run-reactor-counter` builds the sample, installs it to
`zig-out/bin/`, stages the runtime assets beside it, and then launches that
installed executable.

## What the app host does at runtime

Staging is only half of the story. At launch, `win-reactor.App.render(...)`:

1. initializes the STA apartment
2. loads `Microsoft.WindowsAppRuntime.Bootstrap.dll`
3. resolves `MddBootstrapInitialize2` / `MddBootstrapShutdown`
4. calls `MddBootstrapInitialize2(...)`
5. starts the WinUI `Application`

The user-facing result is simple: if `zig-out/bin/<app>.exe` sits next to the
two staged assets, `App.render(...)` can boot the unpackaged WinUI host.

## What is not implemented

Compared with the Rust helper stack, Zig intentionally does **not** yet add:

- self-contained runtime bundling
- an `as_example()` convenience mode
- WebView2-specific staging
- runtime-file downloads from the staging step itself

If those modes land later, they should be documented as additions to this page
rather than implied today.

## Related docs

- [windows-reactor](windows-reactor.md)
- [Windows reactor port findings](windows-reactor-port.md)
