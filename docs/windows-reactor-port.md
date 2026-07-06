# Windows reactor port findings

M1 asked two de-risking questions before later reactor milestones:

1. Can `windows-zig` consume WinUI 3 metadata without checking Microsoft's
   proprietary `.winmd` files into git?
2. Can a Zig sample bootstrap an unpackaged WinUI 3 window using the same
   Windows App Runtime contract as `windows-rs`?

The answer is "yes, with scoped follow-ups." The metadata flow works, a minimal
generated surface is usable, and a real `Application` + `Window` can be opened
from Zig. The remaining problems are concentrated in whole-namespace WinUI
projection and shutdown/lifetime polish, not in the basic viability of the
reactor port.

## M1 outcome

| Slice | Outcome |
|------|---------|
| Issue #2 / PR #50 | `zig build fetch-winui-metadata` can fetch the WinUI 3 metadata on demand and `winbindgen` can route `Microsoft.UI.*` namespaces to it. |
| Issue #3 / PR #57 | A compile-only canary proved the minimal `Application` / `Window` / `Button` / `TextBlock` surface type-checks end-to-end. |
| Issue #4 / PR #58 | A live `hello_window` sample opened a visible WinUI 3 window from Zig using Windows App Runtime bootstrap APIs. |
| Follow-ups | Full checked-in WinUI namespace snapshots still hit the emitter gaps tracked in #52-#56, and `hello_window` teardown now relies on releasing the final WinUI refs before bootstrap/WinRT shutdown (#60). |

## Metadata source and version

The M1 metadata source is the `Microsoft.WindowsAppSDK.WinUI` NuGet package,
version `2.2.1`.

The fetch path is intentionally on-demand rather than vendored:

- `zig build fetch-winui-metadata` downloads the `.nupkg` from NuGet's
  flat-container endpoint.
- The tool verifies the package against a pinned SHA-256 before extracting it.
- Only two files are copied into `vendor/winmd/`:
  - `Microsoft.UI.Xaml.winmd`
  - `Microsoft.UI.Text.winmd`
- If both files are already present, the tool skips the download.

This mirrors the existing repo policy for Windows App SDK metadata: the WinUI 3
metadata ships under Microsoft's Windows App SDK license, so it is fetched on
demand rather than committed to source control.

Once fetched, `winbindgen` selects metadata by namespace prefix:

- `Microsoft.UI.Text.*` → `Microsoft.UI.Text.winmd`
- `Microsoft.UI.*` → `Microsoft.UI.Xaml.winmd`
- everything else keeps using the existing `Windows*.winmd` files

That was enough to snapshot `Microsoft.UI.Xaml` and
`Microsoft.UI.Xaml.Controls` and to drive the minimal WinUI validation work in
M1.

## Minimal generated surface: what worked

Issue #3's `winui_minimal_bindings` canary intentionally avoided importing the
full generated WinUI namespaces and instead isolated the exact four-type surface
needed for the spike:

- `Microsoft.UI.Xaml.Application`
- `Microsoft.UI.Xaml.Window`
- `Microsoft.UI.Xaml.Controls.Button`
- `Microsoft.UI.Xaml.Controls.TextBlock`

Within that narrow slice, the emitter produced usable signatures for the core
bring-up path:

- composable `Application`, `Window`, and `Button` construction via
  `activationFactory(...CreateInstance...)`
- `TextBlock` activation via `win_core.activateInstance(ITextBlock, ...)`
- basic property/method calls such as `put_Title`, `put_Content`,
  `put_Text`, `SetTitleBar`, and `Activate`

So the important M1 viability result is not "all generated WinUI code is ready";
it is "the metadata and projection machinery are good enough to drive the
minimal reactor bring-up path, with specific remaining gaps called out below."

## Emitter gaps found during validation

The whole checked-in WinUI namespace snapshots are still not importable as a
drop-in surface. M1 narrowed the problems to five follow-up issues:

| Issue | Gap | M1 impact / workaround | Status |
|------|-----|-------------------------|--------|
| [#52](https://github.com/cataggar/windows-zig/issues/52) | Bundle generation emits empty `Microsoft.UI.*` dependency namespaces such as `Microsoft.UI.Dispatching`, `Microsoft.UI.Windowing`, and `Microsoft.UI.Composition`. | Full `Microsoft.UI.Xaml*` imports fail because referenced dependency types are missing. M1 used a local curated surface instead of the whole snapshot. | Open follow-up. |
| [#53](https://github.com/cataggar/windows-zig/issues/53) | Generated WinUI files reference undeclared `IResourceManager` and `CoreWebView2*` identifiers. | The whole namespace files are syntactically present but not importable. M1 again avoided them with a local four-type surface. | Open follow-up. |
| [#54](https://github.com/cataggar/windows-zig/issues/54) | Generated `activate()` helpers pass an `_Vtbl` type to `win_core.activateInstance` instead of the interface handle type. | `TextBlock.activate()` is broken today. The spike called `win_core.activateInstance(ITextBlock, &TextBlock.NAME_W)` directly. | Open follow-up. |
| [#55](https://github.com/cataggar/windows-zig/issues/55) | Composable WinUI runtime classes do not get `Factory` / `factory()` helpers. | `Application`, `Window`, and `Button` are still constructible, but only through manual `activationFactory(...CreateInstance...)` plumbing. | Open follow-up. |
| [#56](https://github.com/cataggar/windows-zig/issues/56) | Several WinUI event and collection members still fall back to `*anyopaque`. | Not a blocker for the minimal construction path, but still blocks a clean typed story for WinUI-specific events and collection APIs. | Open follow-up. |

Taken together, these are real emitter defects, but they are also bounded:
they break the "import the whole generated `Microsoft.UI.Xaml` namespace" path,
not the narrower question of whether WinUI 3 metadata and runtime bootstrap are
usable at all.

## Bootstrap/runtime sequence that worked

The working framework-dependent bring-up sequence was:

`RoInitialize(STA)` → stage/load bootstrap DLL + `resources.pri` →
`MddBootstrapInitialize2(0x00020000, L"", 2.0.1.0, ShowUI|PackageIdentityNoop)`
→ `Application.Start` callback → create `Application` / `Window` / `Button` /
`TextBlock` → `Window.Activate` → query `IWindowNative` for the HWND →
shutdown bootstrap / uninitialize COM.

Expanded step-by-step:

1. Call `RoInitialize(RO_INIT_SINGLETHREADED)` on the main thread.
2. Stage `Microsoft.WindowsAppRuntime.Bootstrap.dll` and `resources.pri` next
   to the sample executable, then load the bootstrap DLL dynamically.
3. Resolve `MddBootstrapInitialize2` / `MddBootstrapShutdown` from the DLL.
4. Call `MddBootstrapInitialize2` with the same constants used by the Rust
   reactor path:
   - `WINDOWSAPPSDK_RELEASE_MAJORMINOR = 0x0002_0000`
   - `WINDOWSAPPSDK_RELEASE_VERSION_TAG_W = L""`
   - minimum runtime `2.0.1.0`
   - options = `OnNoMatch_ShowUI | OnPackageIdentity_NOOP`
5. Get the `Microsoft.UI.Xaml.Application` statics interface from the
   activation factory and call `Application.Start(...)`.
6. Inside the `Application.Start` callback, create:
   - `Application`
   - `Window`
   - `Button` (to prove the composable-control construction path)
   - `TextBlock`
7. Set `Window.Content`, call `Window.Activate()`, then query
   `IWindowNative` to obtain the native HWND.
8. Let `Application.Start` own the WinUI message loop. The sample's optional
   `--exit-after-ms` path uses `SetTimer(..., TIMERPROC)` to post `WM_CLOSE`
   rather than running a manual `GetMessageW` loop.
9. After `Application.Start` returns, call `MddBootstrapShutdown()`, then
   `RoUninitialize()`.

### Asset staging

The `stage-winui-runtime` helper mirrors
`windows-reactor-setup::as_framework_dependent()` from the sibling
`windows-rs` checkout by staging exactly:

- `Microsoft.WindowsAppRuntime.Bootstrap.dll`
- `resources.pri`

The Zig helper currently locates those assets through:

1. `WINDOWS_APP_RUNTIME_BOOTSTRAP_DLL` /
   `WINDOWS_APP_RUNTIME_RESOURCES_PRI` overrides, or
2. a sibling `..\windows-rs\crates\libs\reactor-setup\...` checkout

That is enough for `zig build run-hello-window` to run the installed
`zig-out/bin/hello-window.exe` with the required bootstrap assets adjacent to
it.

### Runtime findings and limitations

The runtime surprises were at the WinUI layer, not at the metadata-fetch or
bootstrap layer:

- Creating `Window` outside `Application.Start` failed with `0x8001010E`
  (`RPC_E_WRONG_THREAD`). The WinUI window must be created from the
  `Application.Start` initialization callback.
- `TextBlock.put_Text(...)` worked, but `TextBlock.put_TextWrapping(...)`
  returned `0x80070057` (`E_INVALIDARG`) in the minimal hand-copied surface, so
  the sample leaves wrapping at its default.
- Explicitly releasing the final retained `Application` / `Window` / `Button` /
  `TextBlock` refs is safe once `Application.Start` returns, but those
  releases must happen before `MddBootstrapShutdown()` and `RoUninitialize()`.
  `hello_window` now drops the retained refs in that window; the shutdown
  ordering bug is tracked in [#60](https://github.com/cataggar/windows-zig/issues/60).

### Verification notes

The spike was validated on a machine with `Microsoft.WindowsAppRuntime.2_2.2.0.0`
installed. The concrete verification path was:

- `zig build run-hello-window -- --exit-after-ms 1500`
- separate `EnumWindows` verification that a visible top-level window titled
  `Hello WinUI 3 from Zig` existed while the sample was running

## Comparison with `windows-rs`

The encouraging part of M1 is how little divergence there was from the Rust
reference path:

- The asset-staging story matched `windows-reactor-setup::as_framework_dependent()`
  directly: copy bootstrap DLL + `resources.pri` next to the executable.
- The runtime bootstrap call matched `reactor::bootstrap()` directly: same
  `MddBootstrapInitialize2` constants, same framework-dependent Windows App
  Runtime contract.
- No extra hidden Rust-only magic was required. The Zig spike spelled the DLL
  loading and function-pointer resolution out manually, but the semantic
  sequence was the same.

The differences were mostly about maturity:

- Rust already packages this flow behind helper crates; Zig currently exposes it
  as a sample plus local staging/bootstrap helpers.
- Rust's mature reactor stack does not rely on a hand-curated WinUI surface;
  Zig still does until #52-#56 are fixed.
- The remaining surprises were runtime/lifetime quirks (`RPC_E_WRONG_THREAD`,
  `E_INVALIDARG` on `TextWrapping`, and the need to release final WinUI refs
  before bootstrap/WinRT teardown) rather than evidence that the Rust
  bootstrap contract was hiding some extra step.

## Recommendation: go, but keep the scope narrow

**Go** for later reactor milestones.

M1 answered the two existential questions positively:

1. WinUI 3 metadata can be sourced on demand from Windows App SDK packages and
   fed into `winbindgen`.
2. A real unpackaged WinUI 3 window can be bootstrapped from Zig with the same
   Windows App Runtime contract used by `windows-rs`.

The important caveat is scope. Later milestones should proceed on top of the
proven minimal surface and bootstrap path, but they should **not** assume the
full generated `Microsoft.UI.*` namespace snapshots are production-ready yet.
Those need the emitter follow-ups in #52-#56, and the shutdown/lifetime polish
in #60, before "just import WinUI" becomes a clean story.
