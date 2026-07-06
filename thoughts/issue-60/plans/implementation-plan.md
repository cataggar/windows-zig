# Issue #60 Implementation Plan

## Overview

Issue #60 is most likely a teardown-ordering bug in `samples/hello_window`, not proof that WinUI objects can never be released after `Application.Start` returns. Local repro in this worktree showed that the sample only crashes when the retained `Application` / `Window` / `Button` / `TextBlock` refs are released from the current top-level defer, which runs after `MddBootstrapShutdown()` and `RoUninitialize()`. The implementation should move those final `Release`/`deinit()` calls earlier so they still happen on the original STA/UI thread, but before Windows App Runtime bootstrap and WinRT apartment teardown.

## Current State Analysis

- `setupWindow()` creates the WinUI objects inside the `Application.Start` callback, wires the auto-close timer, and stores the final retained refs in `g_lifetime` so they survive past callback scope (`samples/hello_window/main.zig:180-224`).
- The sample uses a Win32 timer to post `WM_CLOSE` to the native window handle; it does **not** own a manual `GetMessageW` loop (`samples/hello_window/main.zig:170-177`, `samples/hello_window/main.zig:212-217`, `docs/windows-reactor-port.md:127-130`).
- `main()` initializes the STA apartment, boots Windows App Runtime, calls `Application.Start`, and then intentionally leaks `g_lifetime` from a top-level defer because explicit releases in that defer previously crashed (`samples/hello_window/main.zig:232-271`).
- The repo documentation currently records that workaround as a runtime limitation: “Explicitly releasing the final retained refs … crashes during XAML teardown” (`docs/windows-reactor-port.md:152-166`).
- A separate sample (`samples/minesweeper`) demonstrates the repo’s manual dispatcher-queue shutdown pattern, but only because it explicitly creates a `DispatcherQueueController` and must pump `ShutdownQueueAsync()` to completion (`samples/minesweeper/main.zig:206-218`, `samples/minesweeper/main.zig:352-358`, `samples/minesweeper/main.zig:552-614`). `hello_window` does not create its own queue, so that pattern is informative but not the primary fix.
- `packages/win-reactor/src/app.zig` carries a parallel “keep the host alive until process exit” comment after `Application.Start` (`packages/win-reactor/src/app.zig:89-95`, `packages/win-reactor/src/app.zig:134-135`, `packages/win-reactor/src/app.zig:217-219`). That is a useful comparison point, but changing reactor-wide teardown is out of scope for issue #60.

## Desired End State

- `samples/hello_window/main.zig` explicitly releases the retained WinUI refs instead of intentionally leaking them.
- Those releases happen after `Application.Start(callback)` returns, on the same STA/UI thread, but **before** `MddBootstrapShutdown()` and `RoUninitialize()` run.
- `zig build run-hello-window -- --exit-after-ms 1500` exits cleanly with code 0, no Zig segmentation-fault stack trace, and no visible teardown crash.
- A post-run Application log scan shows no fresh `Application Error` / `Windows Error Reporting` crash entry for `hello-window.exe` on machines where Windows emits one.
- `docs/windows-reactor-port.md` and the in-file comment in `samples/hello_window/main.zig` describe the new ordering rule instead of documenting an intentional leak.

## Key Discoveries

- Microsoft’s WinUI/C++/WinRT guidance confirms XAML objects have UI-thread affinity: UI objects such as `TextBlock` must be touched from the thread that created them, and dispatcher shutdown notifications run on that dispatcher thread. That supports keeping teardown on the original STA thread rather than inventing a background cleanup path.  
  References: <https://learn.microsoft.com/en-us/windows/apps/develop/cpp-winrt/concurrency-2>, <https://learn.microsoft.com/en-us/uwp/api/windows.system.dispatcherqueuecontroller.shutdownqueueasync?view=winrt-22621>
- Local repro in this worktree narrowed the failure to teardown ordering:
  - Replacing the current leak with explicit `deinit()` calls **inside the existing top-level defer** reproduced the crash (`zig build run-hello-window -- --exit-after-ms 1500` segfaulted while unwinding `core.IInspectable.deinit()`).
  - Moving the **same releases** to immediately after `app_statics_this.Start(callback)` returned made the sample exit cleanly with code 0.
  - Releasing before bootstrap/WinRT teardown succeeded with both child-first and application-first release order, so release order is not the primary bug.
- The issue title/body points at “after `Application.Start` returns,” but the stronger evidence is: releasing after `Start` returns is safe **as long as** bootstrap shutdown and `RoUninitialize()` have not already run.
- Because `hello_window` lets WinUI own the message loop, there is no repo precedent showing that a manual dispatcher drain is required for this sample. The manual-drain code path is only present where the repo explicitly creates a dispatcher queue.
- This environment reproduced the crash via console/Zig stack trace, but a subsequent `Get-WinEvent` scan did not surface a matching Application-log error entry. That means process exit code and console output must remain the primary validation signals, with event-log scanning treated as a secondary signal.

## What We're NOT Doing

- We are **not** addressing emitter issues #52-#56.
- We are **not** rewriting `hello_window` to use a custom `DispatcherQueueController` or a manual `GetMessageW` loop.
- We are **not** broadening the code change to `packages/win-reactor/src/app.zig` in this issue/PR, even though the same assumption appears there.
- We are **not** introducing an `Application.Exit()` path unless the primary teardown-ordering fix fails in validation.
- We are **not** changing the sample’s bring-up model (`RoInitialize` -> bootstrap -> `Application.Start` callback -> create WinUI objects -> `Window.Activate`).

## Implementation Approach

The primary fix is to separate “release retained WinUI refs” from “reset scalar globals,” then schedule the WinUI release helper so it runs after `Application.Start` unwinds but before `bootstrap.deinit()` and `RoUninitialize()`. That directly matches the successful local experiment and preserves the required STA-thread affinity.

The preferred implementation shape is:

```zig
fn releaseLifetime() void {
    if (g_lifetime) |lifetime| {
        lifetime.text_block.deinit();
        lifetime.button.deinit();
        lifetime.window.deinit();
        lifetime.application.deinit();
        g_lifetime = null;
    }
}

try core.roInitialize(.single_threaded);
defer core.winrt.RoUninitialize();

var bootstrap = try BootstrapRuntime.init();
defer bootstrap.deinit();
defer releaseLifetime(); // must run before bootstrap.deinit() / RoUninitialize()
```

That ordering keeps the final `Release` calls on the same thread that created the XAML objects, avoids relying on undocumented post-`RoUninitialize` behavior, and does not require additional dispatcher plumbing. If this still crashes on validation hardware, the fallback is to drop the refs from a WinUI-owned shutdown callback (`Window.Closed` first choice, dispatcher enqueue second choice) while the UI thread is still actively unwinding window teardown.

## Phase 1: Reorder `hello_window` teardown

### Overview

Replace the intentional leak with an explicit retained-ref teardown path that runs before bootstrap and COM apartment shutdown.

### Changes Required

1. In `samples/hello_window/main.zig`, add a dedicated `releaseLifetime()` helper near `WindowLifetime`/`g_lifetime`.
2. Have `releaseLifetime()`:
   - no-op when `g_lifetime == null`;
   - call `deinit()` on `text_block`, `button`, `window`, and `application`;
   - set `g_lifetime = null` after releasing the refs so the helper is idempotent.
3. Keep the existing top-level defer focused on non-COM state only:
   - `KillTimer` if needed;
   - reset `g_main_hwnd`, `g_exit_after_ms`, and `g_timer_id`.
4. Add a second cleanup point that runs **before** `bootstrap.deinit()` and `RoUninitialize()`:
   - preferred: `defer releaseLifetime();` declared immediately after `defer bootstrap.deinit();`;
   - acceptable alternative: explicit `releaseLifetime();` immediately after `app_statics_this.Start(callback)` returns.
   Prefer the defer placement because it also covers any unwind that occurs after the app loop finishes.
5. Replace the stale “Intentionally leak the final references on process exit” comment with one that states the actual rule: retained WinUI refs must be released before bootstrap shutdown and WinRT apartment teardown.
6. Update `docs/windows-reactor-port.md` so the runtime findings reflect the verified fix instead of documenting the leak workaround as a permanent limitation.

### Success Criteria

- `g_lifetime` is no longer intentionally leaked.
- The release helper runs before `MddBootstrapShutdown()` and `RoUninitialize()` on the normal shutdown path.
- The sample source and docs now describe the correct teardown ordering.

## Phase 2: Validate the issue repro end-to-end

### Overview

Prove that the sample now shuts down cleanly under the exact repro path from issue #60.

### Changes Required

1. From the repo root, run:
   - `zig build fetch-winui-metadata`
   - `zig build run-hello-window -- --exit-after-ms 1500`
2. Repeat the `run-hello-window` command at least once more to catch shutdown flakiness.
3. Verify all of the following:
   - the process exits with code 0;
   - console output still includes the normal activation line;
   - there is no Zig segmentation-fault stack trace and no build-step failure.
4. Immediately after the successful run, query the Application log for new `Application Error` / `Windows Error Reporting` entries near the run timestamp mentioning `hello-window.exe`.
5. If the implementation changed comments/docs, make sure the written rationale still matches the validated behavior.

### Success Criteria

- The exact issue repro command passes twice consecutively.
- There is no visible crash via exit code or console output.
- No matching Application-log crash entry appears on environments that emit one.

## Phase 3: UI-thread shutdown fallback if Phase 1 still fails

### Overview

Only escalate to dispatcher/XAML shutdown hooks if the simple ordering fix still reproduces on target validation hardware.

### Changes Required

1. Add the minimal event/binding surface needed to observe `Window.Closed` (preferred) or otherwise enqueue work onto the window’s dispatcher queue from the close path.
2. Move `releaseLifetime()` into that callback/enqueued work so the final retained refs are dropped while the XAML-owned UI thread is still processing shutdown.
3. Keep the Phase 1 bootstrap/`RoUninitialize()` ordering; only the point where `g_lifetime` drops should change.
4. Re-run the full Phase 2 validation matrix unchanged.
5. Only if this still fails, restore the intentional leak and document it as a confirmed external Windows App SDK/XAML teardown quirk with the collected evidence.

### Success Criteria

- Either the fallback removes the crash, or the team has strong evidence that a documented leak is the only safe behavior on the tested platform.

## Success Criteria

- The implementation uses explicit final `deinit()` calls for the retained WinUI objects instead of leaking them.
- Those releases happen before bootstrap/WinRT teardown and no longer fault in `hello_window`.
- The issue #60 repro command (`zig build run-hello-window -- --exit-after-ms 1500`) is a stable green smoke check.
- The sample comment and the porting doc both match the verified shutdown behavior.

## Testing Strategy

### Primary Smoke Test

- `zig build fetch-winui-metadata`
- `zig build run-hello-window -- --exit-after-ms 1500`
- Repeat the run once more

This mirrors the repo’s existing `--exit-after-ms` sample-smoke pattern, which already exists for other WinUI samples in `build.zig` (`build.zig:1827-1832`, `build.zig:1989-1998`).

### Validation Signals

- **Pass**: exit code 0, normal activation log line, no Zig crash stack trace.
- **Fail**: segmentation fault, non-zero exit, or `run-hello-window` build-step failure.
- **Secondary pass/fail signal**: no fresh `Application Error` / `Windows Error Reporting` event for `hello-window.exe` after the run, recognizing that this environment reproduced the crash without emitting a matching Application-log entry.

### Diagnostic Checks If Needed

- If Phase 1 unexpectedly still crashes, add temporary logging around `releaseLifetime()`, `bootstrap.deinit()`, and `RoUninitialize()` to prove actual teardown order before moving to Phase 3.
- If Phase 3 is required, validate that the chosen callback (`Window.Closed` or dispatcher enqueue) actually runs before `Application.Start` returns.

## References

- Issue #60: <https://github.com/cataggar/windows-zig/issues/60>
- `samples/hello_window/main.zig:76-83`
- `samples/hello_window/main.zig:170-177`
- `samples/hello_window/main.zig:180-224`
- `samples/hello_window/main.zig:232-271`
- `docs/windows-reactor-port.md:127-166`
- `samples/minesweeper/main.zig:206-218`
- `samples/minesweeper/main.zig:352-358`
- `samples/minesweeper/main.zig:552-614`
- `packages/win-reactor/src/app.zig:89-95`
- `packages/win-reactor/src/app.zig:134-135`
- `packages/win-reactor/src/app.zig:217-219`
- Microsoft Learn: <https://learn.microsoft.com/en-us/windows/apps/develop/cpp-winrt/concurrency-2>
- Microsoft Learn: <https://learn.microsoft.com/en-us/uwp/api/windows.system.dispatcherqueuecontroller.shutdownqueueasync?view=winrt-22621>
- Microsoft Learn: <https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.xaml.application?view=windows-app-sdk-2.0>
