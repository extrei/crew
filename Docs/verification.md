# Verification

For the later dropdown and input refinements, see [the eight independent UI checks and current 37-test result](ui-polish-verification.md). This file records the earlier floating-island delivery.

Checked on September 27, 2026, on Apple silicon with macOS 27.0 and Swift 6.4 Command Line Tools. The deployment target is macOS 14; older macOS versions have not been tested on a device.

## Automated checks

`./scripts/test.sh` passes 30 tests: 16 core tests and 14 UI tests. The filename-validation test includes 12 parameterized cases.

Core coverage includes restart persistence, exclusive prompt creation, duplicate filenames, idempotent initialization, six-agent limits, UTF-8 byte limits, missing prompt files, external edits, unsafe symlinks, bounded template enumeration, corrupt metadata, missing metadata, and oversized Unicode names. The missing-metadata regression was observed failing against the previous implementation before passing after the fix.

UI coverage includes layout bounds across positive and negative screen coordinates, popup placement, equal cell sizing, file URL and text pasteboard data, fresh drag text after external edits, cancellation during drag preparation, native text Undo, accessible agent controls, detached placement, anchor preservation across width changes, display selection, disconnected-display recovery, position-file isolation, initialization order, and movement hit targets.

`./scripts/build-app.sh` produces the optimized app. `codesign --verify --deep --strict dist/Crew.app` passes. The Command Line Tools linker emits warnings for nonexistent default Developer framework search directories; compilation and linking succeed without adding those directories or installing dependencies.

## Native interface checks

The running release app was driven through macOS accessibility and mouse controls using isolated libraries in `artifacts/`.

- The bar, template dropdown, and Markdown editor match the rounded black design without observed clipping.
- A custom `qa-planner.md` prompt saved the entered Markdown verbatim and added a fifth mascot.
- Relaunching the same library restored that prompt and all five agents.
- Choosing a template added a sixth agent, which fit in the shelf.
- Agent buttons expose their names, availability, and filenames to accessibility.
- Native typing, paste, Select All, and Command-Z worked in the editor.
- Escape dismissed the editor and restored shelf focus.
- Command-Q quit the QA instance.
- A drag gesture over the shelf completed without a crash or lost membership.

The automation tool refuses Terminal access. Live drops into Terminal, cmux, Codex, and Warp therefore remain unverified. The native copy-only source and its file/text representations are covered by tests and source review. Each receiving app chooses whether it accepts a file or text. No automatic command execution is implemented.

Reduce Motion and hidden-window animation shutdown passed source review. Their OS preference and display-change paths were not changed live during testing. Screen bounds are covered by geometry tests; a physical multi-monitor arrangement was not reconfigured.

Screenshots are saved in `artifacts/floating-island.jpg`, `artifacts/shelf.jpg`, `artifacts/templates.jpg`, and `artifacts/editor.jpg`.

## Performance measurements

Run `python3 scripts/measure-performance.py --runs 3 --output artifacts/performance.json` after a release build. The script uses a temporary library and records a marker after the initial shelf is populated and Core Animation is flushed.

| Run | Library | Process to ready | RSS | Idle CPU, one core |
| --- | --- | ---: | ---: | ---: |
| 1 | New | 612.9 ms | 76.83 MiB | 0.33% |
| 2 | Existing | 159.0 ms | 74.81 MiB | 0.00% |
| 3 | Existing | 206.8 ms | 76.22 MiB | 0.00% |

The final floating-island direct-process launch median is 206.8 ms. The report is `artifacts/performance-floating.json`; the earlier build measurement remains in `artifacts/performance.json`. These three samples are not a cold-cache benchmark or a performance guarantee. CPU samples span three seconds after a two-second settle period, with 10 ms CPU-time resolution. They do not include WindowServer GPU costs.

The virtual size reported by `ps` was approximately 477,800 MiB. A separate capture of the preceding release with `vmmap -summary` found a 385 GiB Guard region with zero resident pages. The same capture reported a 17.8 MiB physical footprint and an 18.0 MiB peak. Virtual reservation, resident mapped pages, and physical footprint measure different things; the virtual figure is not RAM consumption.

Launch Services QA starts also varied: one reported 4,027.6 ms inside the app, and a later start reported 332.0 ms. These are recorded in the QA marker files and are separate from the controlled direct-process samples.

The app has no web renderer or third-party runtime, no frame timer, no polling loop, and no network work. Core Animation handles idle mascot movement. File operations run on the storage actor, and drag preparation reads the current prompt asynchronously before starting the drag.

## Independent review

The independent foundation-engineer review passed after fixes for missing metadata recovery, Unicode metadata size, stale drag text, editor ownership during pending saves, and reporting errors after an editor closes. Locks coordinate Crew instances. Unrelated editors do not participate in Crew's advisory lock.

## Floating-island verification

The final island starts detached in the upper third of the desktop. Its background and grip move it independently of the menu bar. The menu-bar icon remains a secondary control; the background context menu provides New agent, templates, recenter, hide, and quit. The independent source review passed for movement, screen bounds, context actions, and serialized position writes.

A live background drag changed the QA library anchor from `[731, 573]` to `[1072, 980]`. Relaunching that library produced `island_center: [1072, 980]` in `artifacts/qa-floating-restored.json`, matching the original dragged position. That smoke launch populated the window in 615.8 ms and exited through normal application termination, which waits for position writes.

The automation tool timed out when inspecting the island's context menu and on a later app-state query. The process sample showed the main thread idle in the normal AppKit event loop, not a blocked drag operation. Context-menu interaction is therefore covered by source review, not claimed as a completed live check.
