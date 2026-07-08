# Issue #86 Implementation Plan

## Overview

Diagnose and resolve the deterministic crash inside `Microsoft.UI.Xaml.dll` that occurs the first time a window is activated (`activateWindows()` / `Window.Activate()`) once `Microsoft.UI.Xaml.Controls.XamlControlsResources` has been merged into an aggregated `Application`'s `Resources.MergedDictionaries` (the fix built for #74). The crash is deterministic, independent of `TextBox`, and happens *during* `Application.Start`'s blocking message pump — it never returns. Today the only evidence is an unsymbolized module+offset stack trace (`??? in Microsoft.UI.Xaml.dll`). This plan is a diagnostic spike with an explicit decision gate at the end: either a concrete fix/workaround is found and applied, or the limitation is documented and #74's permanent resource-merge work is explicitly held back until this resolves.

## Current State Analysis

- The crash only reproduces with the COM-aggregation + resource-merge spike code that currently lives on the still-open, unmerged `issue-74-plan` branch (PR #80, draft) — not on `main`. This plan's branch (`issue-86-plan`) is based directly on top of `issue-74-plan` (per user decision) so the existing working repro harness can be reused as-is instead of re-derived.
- The repro harness is entirely in place already and gated behind one flag:
  - `packages/win-reactor/src/app.zig:21` — `const issue74_use_aggregated_application = true;` (already `true` in this worktree).
  - `packages/win-reactor/src/app.zig:196-230` — `ReactorHost.start(...)` constructs an aggregated `Application` (`com_aggregate.createAggregated`, `app.zig:197-199`), mounts the initial tree (`app.zig:220`), then calls `self.backend_impl.activateWindows()` (`app.zig:228`, implemented at `packages/win-reactor/src/winui_backend.zig:186`) — this is the exact call after which the crash occurs — followed by a probe call (`app.zig:229`) that never gets to run its own logic because the crash happens first.
  - `packages/win-reactor/src/com_aggregate.zig` — the COM aggregation helper (`createAggregated`, ABI for `IXamlMetadataProvider`, delegation to the real framework `XamlControlsXamlMetaDataProvider`).
  - `packages/win-reactor/src/issue74_probe.zig` — probe harness; activates `XamlControlsResources` once, merges it into `MergedDictionaries` exactly once (`merged_dictionaries_populated` guard), and can optionally construct+release a real `TextBox` (already proven NOT necessary to trigger this crash).
- `samples/reactor_hello` is the correct minimal repro target: it mounts only a `Window` + basic content, no `TextBox`, and the crash still reproduces identically (`thoughts/issue-74/plans/implementation-plan.md`, "Further investigation" section).
- Repro command: `zig build run-reactor-hello -- --exit-after-ms 2000`. Deterministic — identical `Microsoft.UI.Xaml.dll` return addresses across independent runs (ruled out as a race).
- The crash currently prints only module+offset frames (`???:?:?: 0x7ff8ddf855fa in ??? (Microsoft.UI.Xaml.dll)`, etc.) because Zig's default panic/stack-trace handler has no debug info for system/framework DLLs — it is not a fundamental limitation, just something no one has tried to work around yet with an external debugger.
- `zig build test --summary all` does not exercise this runtime path at all (it stays green regardless of this bug), so this issue cannot be caught by the existing package test suite; validation is necessarily a manual runtime repro, same pattern already established for #60 and #74.
- Confirmed available in this environment: WinDbg Preview is installed (`Microsoft.WinDbg.Slow` MSIX package, entry point `DbgX.Shell.exe` under `C:\Program Files\WindowsApps\Microsoft.WinDbg.Slow_<version>_x64__8wekyb3d8bbwe\`). Launching it with no command-line automation opens its GUI shell (confirmed by direct invocation in this session); it also accepts the classic `windbg.exe`-style automation switches (`-g -G -c "<commands>;q"`) for scripted, non-interactive symbol/stack extraction, but that scripted path has **not yet been verified to work end-to-end** against this specific package in this environment — Phase 1 must confirm it or fall back to interactive use.
- Public research (general web search) indicates Microsoft publishes public PDBs for Windows App SDK / `Microsoft.UI.Xaml.dll` on the standard public symbol server (`https://msdl.microsoft.com/download/symbols`), but this has not been confirmed for the exact vendored WinAppSDK version (`2.2.1`, per `vendor/winmd/README.md`) in this repo. Phase 1 must confirm this directly rather than assume it.
- Issue #60 ("hello_window crashes if final WinUI refs are released after `Application.Start` returns") is already resolved on `main` (PR #82, merged) and turned out to be an unrelated teardown-ordering bug in `samples/hello_window` — releasing retained refs too late (after `MddBootstrapShutdown()`/`RoUninitialize()`), fixed by releasing them earlier on the same thread (`thoughts/issue-60/plans/implementation-plan.md`). That root cause (explicit-release-after-`Start`-returns ordering) does not match #86's symptom (crash *during* `Application.Start`'s blocking pump, no explicit release anywhere in the repro, no `TextBox`), so they are very likely different bugs, but this has not been definitively confirmed against #86's actual crash frames — only inferred from the repro shapes.

## Desired End State

One of two concrete outcomes, decided by Phase 5's gate:

- **Outcome A (fix found)**: `zig build run-reactor-hello -- --exit-after-ms 2000` (and `run-reactor-counter`, run twice each) exit cleanly with code `0`, with `XamlControlsResources` merged into `Application.Resources.MergedDictionaries` and a real `TextBox` constructed and shown, with no `Microsoft.UI.Xaml.dll` crash and no new Application-log crash entries. The fix (initialization ordering change, WinAppSDK version bump, or another concrete workaround) is documented in `thoughts/issue-74/plans/implementation-plan.md` and this issue's follow-up is closed.
- **Outcome B (no fix found)**: A symbolized (or best-effort partially symbolized) root-cause analysis is recorded in this plan document, cross-referenced against public issue trackers, with a definitive statement of what is and is not the same bug as #60. `docs/windows-reactor-port.md` and #74's plan document are updated to state plainly that permanently merging `XamlControlsResources` (and therefore permanently re-enabling `TextBox`) is blocked on this issue, so `reactor-selftest`'s existing `reactor-hello`/`reactor-counter` smoke checks are not put at risk by #74 landing.

In both outcomes, this plan itself produces a decision, not an open-ended investigation — Phase 5 is a hard stop with a documented answer.

### Key Discoveries

- The crash is triggered by the resource merge itself (or the aggregation/real-provider-delegation it depends on), not by `TextBox` construction — confirmed via bisection in the #74 investigation (removing the probe's `TextBox` test entirely does not change the outcome).
- The crash happens specifically after `self.backend_impl.activateWindows()` (`packages/win-reactor/src/app.zig:228`), i.e. the first real layout/style-resolution pass that actually consumes `XamlControlsResources`'s contents — not at `XamlControlsResources.activate()` or the `Append` into `MergedDictionaries` itself (both succeed with `S_OK` at the earlier `"post-mount"` stage without incident).
- `microsoft/microsoft-ui-xaml#7606` was already useful prior art for the related (but distinct) #74 metadata-provider problem; Phase 3 should check whether it, or a similar issue, also documents this specific post-activation crash.

## What We're NOT Doing

- We are **not** re-implementing or changing the COM aggregation helper (`com_aggregate.zig`) or the resource-merge logic itself — this plan diagnoses; any code change is confined to whatever Phase 5's gate decides is the minimal fix/workaround, or is deferred entirely to a future issue if no fix is found here.
- We are **not** merging this branch's findings into `main` directly — actionable code changes (if any) land via #74's own plan/PR per that plan's existing phase structure; this plan may recommend specific edits to `thoughts/issue-74/plans/implementation-plan.md` and `docs/windows-reactor-port.md`, but does not itself modify `packages/win-reactor/src/winui_backend.zig`'s `.text_box` gate.
- We are **not** attempting a from-scratch minimal C++/WinRT reproduction outside this repo in this plan — Phase 3's public-tracker cross-reference is the intended substitute for that (cheaper, and likely to surface prior art directly); only escalate to a standalone C++ repro if Phase 3 finds nothing and Phase 5's gate explicitly decides it's worth the added cost.
- We are **not** attempting to vendor or patch `Microsoft.UI.Xaml.dll` itself.
- We are **not** building permanent CI/automation around WinDbg symbolication — Phase 1's debugger session is a manual/one-off diagnostic tool, not a new build step.
- We are **not** re-investigating or re-opening issue #60 — Phase 4 only needs to compare root causes at the level of the already-published #60 plan/fix, not redo that investigation.

## Implementation Approach

Follow the same discipline #74's own plan used for its Phase 1 spike: each phase below ends with a recorded, falsifiable answer before moving to the next, and Phase 5 is a hard decision gate rather than an open-ended continuation. Phases 1-4 are independent research/diagnostic threads that narrow the problem from different angles (symbolized stack, bisection, public prior art, relationship to #60); Phase 5 synthesizes all of them into one of the two "Desired End State" outcomes.

## Phase 1: Get a symbolized crash stack trace

### Overview

Replace the current `???:?:?: (Microsoft.UI.Xaml.dll)` module+offset frames with real function names by running the exact repro under WinDbg Preview with the public Microsoft symbol server configured, so later phases have a concrete function/module to research instead of guessing from behavior alone.

### Changes Required

No permanent source changes. All work is running the existing repro under a debugger.

1. Confirm the worktree is fully built: `zig build fetch-winui-metadata` (if not already done in this worktree), then `zig build run-reactor-hello -- --exit-after-ms 2000` once un-debugged, to reconfirm the crash still reproduces identically in this worktree before attaching a debugger (guards against the repro having silently drifted from #74's recorded output).
2. Locate the built executable: `zig-out\bin\reactor-hello.exe` (per `build.zig`'s `b.getInstallPath(.bin, ...)` pattern).
3. Attempt scripted, non-interactive symbolication first via `DbgX.Shell.exe` (`C:\Program Files\WindowsApps\Microsoft.WinDbg.Slow_<version>_x64__8wekyb3d8bbwe\DbgX.Shell.exe`), using the classic `windbg.exe`-style automation switches, approximately:
   ```powershell
   & "C:\Program Files\WindowsApps\Microsoft.WinDbg.Slow_<version>_x64__8wekyb3d8bbwe\DbgX.Shell.exe" `
     -g -G `
     -c ".sympath srv*C:\symbols*https://msdl.microsoft.com/download/symbols; .reload; g; kc; !analyze -v; q" `
     zig-out\bin\reactor-hello.exe --exit-after-ms 2000
   ```
   - `-g -G` skips breaking on process/thread create so it runs straight to the first-chance access violation.
   - `.sympath` configures the public symbol server with a local cache directory.
   - `kc` prints a clean call stack (module!function, no args) once the exception breaks in; `!analyze -v` gives WinDbg's automated triage (exception record, faulting module, nearest symbol).
   - This was launched once already in this session with no arguments and opened a GUI shell rather than running headless, so headless scripted output is **not yet confirmed to work** — verify it actually produces console-capturable output before relying on it.
4. If scripted automation does not produce usable console output, fall back to interactive use: launch WinDbg Preview, `File > Attach` is not viable here since the crash needs the debugger present from process start, so use `File > Open executable...` with the same args, let it run to the exception, then manually run `.sympath srv*C:\symbols*https://msdl.microsoft.com/download/symbols`, `.reload`, `kc`, and `!analyze -v` from the command window, and copy the resulting stack text out by hand.
5. Record the resulting symbolized stack (or as many frames as resolve) directly in a new "Phase 1 results" subsection of this plan, including:
   - Whether public symbols loaded at all for `Microsoft.UI.Xaml.dll` (and any other framework modules in the stack, e.g. `Microsoft.WindowsAppRuntime.dll`).
   - The nearest resolved function name(s) at/near the fault, and the full symbolized call stack as far up as symbols allow.
   - The exception code/type from `!analyze -v` (confirm it's still the same access violation class as the original `Segmentation fault at address 0x7ff8e3135d00`, not a different fault this time).

### Success Criteria

- A definitive answer is recorded: did public symbols resolve for `Microsoft.UI.Xaml.dll`, yes or no?
- If yes: at least the immediately-faulting frame has a real function name (not just an address), suitable for direct use as a search term in Phase 3.
- If no (symbols genuinely unavailable or scripting proves impractical even interactively): explicitly recorded as a dead end so Phase 3 knows to search using only the behavioral description (crash after first activation post-merge) rather than a function name.

**Implementation Note**: Pause here for manual confirmation before proceeding to Phase 2.

---

## Phase 2: Bisect the merged-dictionary trigger

### Overview

Determine whether the crash is specific to `XamlControlsResources`'s own contents/behavior, or whether merging *any* non-trivial `ResourceDictionary` into `Application.Resources.MergedDictionaries` before first activation triggers it. This directly answers one of the two "Suggested next steps" from the issue body and narrows whether the bug lives in XAML's generic merged-dictionary/style-resolution machinery or specifically in `XamlControlsResources`'s theme-dictionary content.

### Changes Required

**File**: `packages/win-reactor/src/issue74_probe.zig` (temporary probe edits only — this file is already documented as throwaway spike code)

1. Add a second, gated probe path alongside the existing `XamlControlsResources` merge that instead constructs a plain empty `Microsoft.UI.Xaml.ResourceDictionary` (via `win_core.createComposable`/equivalent default-activatable construction — no `XamlControlsResources` involved at all) and appends *that* into `MergedDictionaries` at the same point. Re-run `zig build run-reactor-hello -- --exit-after-ms 2000` and record whether `activateWindows()` still crashes.
2. If the empty dictionary does **not** crash, add a minimal dictionary containing a single trivial resource (e.g. one `Style` targeting `Window` or a simple brush resource, whatever is cheapest to construct via the existing curated `winui/` surface or a hand-authored ABI snippet matching this probe file's existing pattern) and re-test, to find the simplest non-trivial dictionary that does reproduce the crash — if one exists short of the full `XamlControlsResources` theme dictionary.
3. If the empty dictionary **does** crash: that's a strong, surprising result (implicates generic `MergedDictionaries`/style-invalidation machinery, not `XamlControlsResources` content) — record it clearly and prioritize it in Phase 3's search terms.
4. Record each variant's result (crash / no crash, and exact repro command used) directly in a new "Phase 2 results" subsection of this plan.

### Success Criteria

- A definitive answer is recorded: does merging *any* non-trivial `ResourceDictionary` trigger the crash, or is it specific to `XamlControlsResources`?
- If it's specific to `XamlControlsResources`, the simplest reproducing variant found is recorded (useful for a minimized public bug report if Phase 3 doesn't find an existing one).

**Implementation Note**: Pause here for manual confirmation before proceeding to Phase 3.

---

## Phase 3: Cross-reference public issue trackers and check for a version fix

### Overview

Search `microsoft/microsoft-ui-xaml` and `microsoft/WindowsAppSDK` issue trackers (and general web search) for existing reports matching this crash, using Phase 1's symbol names (if any) and Phase 2's bisection result as search terms, and check whether a newer Windows App SDK release than the vendored `2.2.1` has a documented fix for a matching symptom.

### Changes Required

No source changes. This is a research task with a recorded outcome.

1. Search using the exact scenario keywords: unpackaged/aggregated `Application`, `XamlControlsResources`, first window activation crash, `Microsoft.UI.Xaml.dll` access violation. Include Phase 1's resolved function name(s) as search terms if available.
2. Specifically check `microsoft/microsoft-ui-xaml#7606` (already cited as relevant prior art for the related #74 metadata-provider problem) for any follow-on comments describing a *subsequent* crash after the metadata-provider fix is applied — this is a plausible place for someone to have already hit exactly this issue.
3. Check the Windows App SDK release notes/changelog between `2.2.1` (the vendored version, per `vendor/winmd/README.md`) and the latest stable release for changelog entries mentioning unpackaged-app theme-resource loading, first-activation crashes, or `XamlControlsXamlMetaDataProvider`-adjacent fixes.
4. Record findings in a new "Phase 3 results" subsection: any matching issue(s) found (with links), whether they're marked fixed and in which WinAppSDK version, and whether upgrading the vendored `.winmd`/runtime version is a plausible fix path (noting that a version bump would itself be a nontrivial follow-up: it changes `vendor/winmd/README.md`'s pinned version and needs its own re-validation across every WinUI-dependent sample, not just this repro).

### Success Criteria

- A definitive answer is recorded: is this a previously-known, already-fixed bug (with a specific version where it's fixed), a previously-known-but-unfixed bug (with a tracking link), or apparently novel/unreported?

**Implementation Note**: Pause here for manual confirmation before proceeding to Phase 4.

---

## Phase 4: Confirm relationship to #60

### Overview

Record a definitive same-root-cause-or-not finding against #60, using #60's already-published, already-fixed root cause (a teardown-ordering bug: releasing retained WinUI refs too late, after `MddBootstrapShutdown()`/`RoUninitialize()` — `thoughts/issue-60/plans/implementation-plan.md`) as the comparison baseline.

### Changes Required

No source changes.

1. Compare the two failure shapes directly: #60 crashed only when explicit `Release`/`deinit()` calls on retained refs happened *after* `Application.Start` returned and bootstrap/WinRT teardown had already run; #86 crashes *during* `Application.Start`'s blocking pump (it never returns), with no explicit release anywhere in the repro and no dependency on shutdown ordering at all.
2. Cross-check against Phase 1's symbolized stack (if obtained): does it show any frames related to teardown/shutdown/dispatcher-queue-shutdown machinery (which would suggest overlap with #60's fix area), or purely first-render/layout/style-resolution machinery (which would confirm they're unrelated)?
3. Record a definitive statement: same root cause, related-but-distinct, or confirmed unrelated.

### Success Criteria

- A definitive statement is recorded, replacing the current "likely related but not confirmed" hedge in the #86 issue body and in `thoughts/issue-74/plans/implementation-plan.md`.

**Implementation Note**: Pause here for manual confirmation before proceeding to Phase 5.

---

## Phase 5: Decision gate — apply a fix, or document the blocking limitation

### Overview

Synthesize Phases 1-4 into exactly one of this plan's two "Desired End State" outcomes, and act on it.

### Changes Required

**If a concrete fix or workaround was identified** (Outcome A — e.g., a specific initialization-order change, an additional API call needed before/after `activateWindows()`, or a WinAppSDK version bump with a matching changelog fix):

1. Apply the minimal version of that fix directly in this branch's copy of `packages/win-reactor/src/app.zig` / `com_aggregate.zig` / `issue74_probe.zig` (or, if it also requires an upgraded `vendor/winmd/README.md` pinned version, note that as a separate prerequisite follow-up rather than doing the version bump inside this plan — the version bump has its own blast radius across every WinUI sample and deserves its own scoped issue/plan).
2. Re-run `zig build run-reactor-hello -- --exit-after-ms 2000` and `zig build run-reactor-counter -- --exit-after-ms 1500` at least twice each; confirm exit code `0`, no crash stack trace, and (if feasible on this machine) no fresh Application-log `Application Error` entry for `Microsoft.UI.Xaml.dll` near the run timestamps.
3. Update `thoughts/issue-74/plans/implementation-plan.md` with a short "Issue #86 resolved" note summarizing the fix and pointing back at this plan document, so whoever resumes #74's Phase 2/3 work has the corrected context.
4. Update `docs/windows-reactor-port.md` if it documents the current crash/limitation, to reflect the fix.

**If no concrete fix was found** (Outcome B):

1. Do not modify any production code path. Do not change `packages/win-reactor/src/winui_backend.zig`'s `.text_box => error.NotYetSupported` gate.
2. Add an explicit blocking note to `thoughts/issue-74/plans/implementation-plan.md`'s Phase 2 section stating that permanently wiring the aggregation + resource merge (`Phase 2: Wire aggregation permanently and merge theme resources`) is blocked on #86, because merging `XamlControlsResources` crashes **any** activated window (not just ones with a `TextBox`), which would break the existing `reactor-selftest` smoke checks for `reactor-hello`/`reactor-counter` the moment it landed.
3. Update `docs/windows-reactor-port.md` to describe the confirmed limitation plainly (mirroring how the existing #60-era leak workaround was documented before its fix), citing this plan's Phase 1-4 findings.
4. Leave the throwaway `issue74_use_aggregated_application` / `issue74_probe.zig` / `com_aggregate.zig` spike code exactly as-is on the `issue-74-plan` branch (still useful as a live repro for whoever eventually picks this back up) — do not delete it as part of this plan, since deleting the only known repro harness while the bug is still unresolved would make future investigation strictly harder.

### Success Criteria

- Exactly one outcome (A or B) is recorded with supporting evidence from Phases 1-4.
- `thoughts/issue-74/plans/implementation-plan.md` accurately reflects whichever outcome was reached, so #74's own plan stays internally consistent with this issue's resolution.

## Testing Strategy

### Manual Repro / Regression Check

- Primary repro command throughout all phases: `zig build run-reactor-hello -- --exit-after-ms 2000` (matches the exact command used in the original #74/#86 investigation).
- Secondary sanity check once Phase 5 lands a fix: `zig build run-reactor-counter -- --exit-after-ms 1500` (the other sample already wired into `reactor-selftest`'s smoke pattern, per `build.zig`'s `reactor_selftest_step` wiring for `"reactor-hello"`/`"reactor-counter"`), run at least twice for flake resistance.
- `zig build test --summary all` should be run once at the end of this plan's work as a baseline sanity check (it won't exercise this runtime path directly, but confirms no incidental breakage from any Phase 5 code edits).

### Diagnostic Signals

- **Pass** (Outcome A validation): exit code `0`, no Zig segmentation-fault stack trace, no new Application-log `Application Error` entry for `Microsoft.UI.Xaml.dll`.
- **Fail**: segmentation fault (with or without symbols), non-zero/unexpected exit code, or a fresh matching Application-log crash entry.

## Performance Considerations

None — this is a crash/correctness investigation, not a performance-sensitive change.

## Migration Notes

Not applicable; no persisted data or public API affected. If Phase 5 requires a WinAppSDK/vendored `.winmd` version bump, that follow-up must separately account for re-validating every sample that depends on `vendor/winmd/README.md`'s pinned version, not just this repro.

## References

- Issue #86: <https://github.com/cataggar/windows-zig/issues/86>
- Issue #74: <https://github.com/cataggar/windows-zig/issues/74> / PR #80 (draft, `issue-74-plan` branch)
- Issue #60: <https://github.com/cataggar/windows-zig/issues/60> (resolved, PR #82, merged) / `thoughts/issue-60/plans/implementation-plan.md`
- `thoughts/issue-74/plans/implementation-plan.md` — full investigation record for the aggregation/resource-merge work and the discovery of this crash (see "Further investigation" and "MAJOR UPDATE" sections).
- `packages/win-reactor/src/app.zig:21,196-230`
- `packages/win-reactor/src/com_aggregate.zig`
- `packages/win-reactor/src/issue74_probe.zig`
- `packages/win-reactor/src/winui_backend.zig:186` (`activateWindows`)
- `build.zig` (`reactor_selftest_step` / sample smoke-check wiring for `reactor-hello`/`reactor-counter`)
- `vendor/winmd/README.md` (pinned WinAppSDK/`.winmd` version `2.2.1`)
- `docs/windows-reactor-port.md:127-175` (existing sample bring-up/validation conventions)
- microsoft/microsoft-ui-xaml#7606 (prior art for the related #74 metadata-provider problem)
- Public Microsoft symbol server: `https://msdl.microsoft.com/download/symbols`
- WinDbg Preview (`Microsoft.WinDbg.Slow` package, `DbgX.Shell.exe`), confirmed installed in this environment
