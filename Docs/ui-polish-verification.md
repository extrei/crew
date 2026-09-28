# Independent UI verification

All eight requested changes are implemented in the native Swift app. Eight separate investigators started with no conversation history. Each received only its expected outcome, the project location, and inspection constraints. They were told not to read engineering reports, earlier task reports, README, or Docs. They inspected the source and wrote their own executable native-control probes.

The investigators did not accept the implementation engineer's result as proof. The filename and prompt investigators initially failed their checks; both defects were repaired and independently rechecked.

## Evidence for each fix

| Fix | Independent resolution | Evidence |
| --- | --- | --- |
| 1. Agent action dropdown | PASS for matching style, native controls, and application wiring. 26 checks compare black backgrounds, rounded borders, headers, rows, hover, callbacks, and disabled actions. | [Report](../artifacts/ui-polish/independent/fix-1/result.md), [native render](../artifacts/ui-polish/independent/fix-1/action-dropdown.png) |
| 2. Template-row hover | PASS. 17 checks cover the whole row, mascot/label hit routing, visible hover, reset, and disabled behavior. Resting and exit renders have identical hashes. | [Report](../artifacts/ui-polish/independent/fix-2/report.md), [hover render](../artifacts/ui-polish/independent/fix-2/hovered.png) |
| 3. New Markdown button hover | PASS. Hover brightens the button, exit restores it, disabled activation is rejected, and activation constructs the editor through its callback. | [Report](../artifacts/ui-polish/independent/fix-3/report.md), [results](../artifacts/ui-polish/independent/fix-3/results.json), [hover render](../artifacts/ui-polish/independent/fix-3/hover.png) |
| 4. Templates-folder button hover | PASS. 19 checks verify visible hover, exact reset, and callback activation, including when the shelf is full. Source connects that callback to folder opening. | [Report](../artifacts/ui-polish/independent/fix-4/result.md), [results](../artifacts/ui-polish/independent/fix-4/probe-output.txt) |
| 5. Filename input | PASS after independent recheck. Black fill, rounded neutral outline, centered native field-editor text, padding, immediate focus feedback, typing, selection, and blur pass. | [Report](../artifacts/ui-polish/independent/fix-5/result.md), [original failure](../artifacts/ui-polish/independent/fix-5/before/result.md), [focused render](../artifacts/ui-polish/independent/fix-5/focused-selected.png) |
| 6. Face dropdown | PASS. 17 checks cover the shared style, mascot rows, hover/selection, arrow and Return selection, dismissal/reopening, and saving/reloading the chosen face. | [Results](../artifacts/ui-polish/independent/fix-6/results.txt), [reproduction and limits](../artifacts/ui-polish/independent/fix-6/reproduce.txt), [hover/selection render](../artifacts/ui-polish/independent/fix-6/face-selected-scout-hover-patch.png) |
| 7. Prompt input | PASS after independent recheck. 24 assertions verify that the rendered outline survives native layout/display, focus, blur, and scrolling. Selection, multiline editing, Undo, and Redo pass. | [Report](../artifacts/ui-polish/independent/fix-7/report.md), [original failure](../artifacts/ui-polish/independent/fix-7/before/report.md), [native render](../artifacts/ui-polish/independent/fix-7/unfocused.png) |
| 8. Dropdown motion | PASS for measured native animation and lifecycle behavior. Spring/fade progression, interruptions, stale completion suppression, 25 rapid cycles, close-time input suppression, child-window cleanup, and Reduce Motion pass. | [Report and limits](../artifacts/ui-polish/independent/fix-8/results.md), [native probe log](../artifacts/ui-polish/independent/fix-8/probe.log) |

Each evidence folder contains its investigator-authored Swift probe and reproduction instructions. The parent reran all eight probes against the final debug build; each compiled and exited successfully. [Final rerun results](../artifacts/ui-polish/final-probe-results.json) record those runs. Probe 2 requires its documented `PREBUILT` compile flag; the initial parent invocation omitted it and was corrected without changing the probe or app.

## Defects caught and corrected

- A new keyboard regression found that default AppKit focus traversal did not reliably skip disabled custom rows. Dropdowns now navigate their enabled rows explicitly.
- Independent fix 5 found that filename focus styling appeared only after typing. It now follows the native field editor's actual focus lifecycle. The original failure is preserved alongside the successful recheck.
- Independent fix 7 found that AppKit removed the prompt scroll view's layer border during display. A surrounding field view now owns that outline. The investigator verified rendered edge pixels after native layout/display rather than only checking initial properties.

The before/after regression logs are in `artifacts/ui-polish/keyboard-regression-before.log`, `crew-filename-red.log`, `crew-filename-green.log`, `crew-prompt-red.log`, and `crew-prompt-green.log`.

## Build and test result

`./scripts/test.sh` passes 37 tests: 21 UI tests and 16 core tests. Existing storage, drag, floating placement, persistence, and Undo checks remain in the suite. The optimized `.app` builds and passes local code-signature verification. It has no new dependencies.

[Test log](../artifacts/ui-polish/tests-final.log), [build log](../artifacts/ui-polish/build-final.log), and [reviewed source hashes](../artifacts/ui-polish/source-manifest.sha256) are retained.

The final release measurement sampled three direct launches: 296.8, 147.8, and 135.0 ms to ready. Median readiness was 147.8 ms, with RSS ranging from 74.66 to 86.92 MiB. The first short idle interval recorded 5.65% of one CPU core; the next two recorded 0.00%. These are short local samples, not a zero-CPU guarantee or a frame-pacing test. [Raw performance data](../artifacts/ui-polish/performance.json) includes virtual size and the measurement method. Virtual size still includes macOS guard reservations, as discussed in the earlier verification report.

## What the evidence does not establish

The investigators exercised actual AppKit controls, native field editors, Core Animation presentation layers, and rendered bitmaps in isolated processes. They did not drive the shared desktop. Parent desktop automation also timed out on the running app, so this report does not claim a complete physical-pointer acceptance run.

Copy/Open/Remove and folder-opening callbacks were exercised in isolation and their production wiring was inspected. External clipboard, Finder, editor, and terminal side effects were not repeated through the live desktop during this pass. Caret blinking in a key window remains unverified.

Motion uses a proposed 300 ms spring with 160 ms opacity opening and 130 ms closing. The native animation/lifecycle checks passed, including process-local Reduce Motion simulation without changing system preferences. Perceived frame pacing under desktop load and exact equivalence to Droppy's proprietary animation are not established by these checks.

The filename is centered. The prompt shares its black rounded outlined style while retaining left-aligned Markdown.
