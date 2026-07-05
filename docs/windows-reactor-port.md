# Windows reactor port findings

## Issue #4 hello-window spike

### Bootstrap/runtime sequence

The working Zig bring-up sequence for a framework-dependent WinUI 3 desktop sample is:

1. `RoInitialize(RO_INIT_SINGLETHREADED)` on the main thread.
2. Load `Microsoft.WindowsAppRuntime.Bootstrap.dll` dynamically from the sample directory.
3. Call `MddBootstrapInitialize2` with the same constants used by `windows-rs` reactor:
   - `WINDOWSAPPSDK_RELEASE_MAJORMINOR = 0x0002_0000` (`131072`, WinAppSDK 2.0)
   - `WINDOWSAPPSDK_RELEASE_VERSION_TAG_W = L""`
   - `WINDOWSAPPSDK_RUNTIME_VERSION_UINT64 = 0x0002_0000_0001_0000` (minimum runtime `2.0.1.0`)
   - options = `OnNoMatch_ShowUI | OnPackageIdentity_NOOP`
4. Get the `Microsoft.UI.Xaml.Application` statics interface from the activation factory and call `Application.Start(...)`.
5. Inside the `Application.Start` callback, create `Microsoft.UI.Xaml.Application`, `Window`, and `Controls.Button` via `activationFactory(...CreateInstance...)`.
6. Still inside that callback, create `Controls.TextBlock` via `activateInstance(ITextBlock, &TextBlock.NAME_W)`.
7. Set `Window.Content = TextBlock`, call `Window.Activate()`, then obtain the native HWND by querying `IWindowNative` (`IID = EECDBF0E-BAE9-4CB6-A68E-9598E1CB57BB`).
8. Optional CLI verification path: `SetTimer(..., TIMERPROC)` posts `WM_CLOSE` to the HWND after `--exit-after-ms`; `Application.Start` owns the WinUI message loop, so no manual `GetMessageW` loop is required in the final spike.
9. After `Application.Start` returns, call `MddBootstrapShutdown()`, then `RoUninitialize()`.

### Runtime findings from the spike

- Creating `Window` directly after bootstrapping but **outside** `Application.Start` failed with `0x8001010E` (`RPC_E_WRONG_THREAD`). The WinUI window must be created from the `Application.Start` initialization callback.
- The local `TextBlock.put_Text(...)` path works, but `TextBlock.put_TextWrapping(...)` still returns `0x80070057` (`E_INVALIDARG`) in this minimal hand-copied surface, so the sample leaves wrapping at its default.
- Explicitly `Release`-ing the retained `Application` / `Window` / `Button` / `TextBlock` references after `Application.Start` returns crashes during XAML teardown. The sample intentionally leaks those final refs on process exit instead of releasing them during shutdown.

### Issue #3 binding workarounds reused here

`origin/main` still lacks the merged issue #3 canary in the current repo state, so `samples/hello_window/surface.zig` carries the same local four-type WinUI slice:

- `Microsoft.UI.Xaml.Application`
- `Microsoft.UI.Xaml.Window`
- `Microsoft.UI.Xaml.Controls.Button`
- `Microsoft.UI.Xaml.Controls.TextBlock`

This intentionally avoids the known whole-namespace gaps tracked in #52-#56:

- empty `Microsoft.UI.*` dependency bundles
- undeclared `IResourceManager` / `CoreWebView2*`
- broken generated `activate()` helper
- missing composable `Factory` helpers
- remaining `*anyopaque` event/collection slots

### Asset staging

`zig build stage-winui-runtime` mirrors `windows-reactor-setup::as_framework_dependent()`:

- `Microsoft.WindowsAppRuntime.Bootstrap.dll`
- `resources.pri`

The current spike resolves them from:

1. `WINDOWS_APP_RUNTIME_BOOTSTRAP_DLL` / `WINDOWS_APP_RUNTIME_RESOURCES_PRI` env overrides, or
2. a sibling `..\windows-rs\crates\libs\reactor-setup\...` checkout.

`zig build run-hello-window` depends on that staging step and runs the installed `zig-out/bin/hello-window.exe`, so the bootstrap DLL and PRI file are adjacent to the executable. Running the build-cache artifact directly is not sufficient because the bootstrap DLL and PRI must be next to the launched `.exe`.

### Verification notes

- The dev machine used for the spike has `Microsoft.WindowsAppRuntime.2_2.2.0.0_{x64,x86}` installed.
- `samples/hello_window/main.zig` accepts `--exit-after-ms <n>` so CLI automation can prove the window opens without requiring manual close.
- Verified command in this repo: `zig build run-hello-window -- --exit-after-ms 1500`
- Verified separately via `EnumWindows`: while `hello-window.exe --exit-after-ms 5000` was running, a visible top-level window titled `Hello WinUI 3 from Zig` was present.
- This spike stays intentionally low-level: no reactor host, no generated WinUI namespace import, and no codegen fixes beyond the local surface copy.
