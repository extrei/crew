# Rename and internal Markdown verification

## Delivered behavior

Click an agent, then double-click its name in the action dropdown to rename it. Return commits the name; Escape restores the original. The display name changes without changing the agent ID, ordering, mascot, or Markdown filename/content.

Open Markdown file now opens Crew's own dropdown editor. It loads current disk contents, saves to the same file, and keeps metadata intact. Cancel writes nothing. Saving after another editor changes the file shows a conflict, retains the draft, and preserves the external version.

## Completion audit

| Requirement | Authoritative evidence | Result |
| --- | --- | --- |
| Double-click rename | Independent native hit-test/field-editor probe; live double-click, typed name, Return commit, and subsequent packaged-app relaunch | PASS |
| Rename cancellation and validation | Independent native Return/Escape and invalid-name checks; live Escape restored the prior name | PASS |
| Preserve identity and files | Store tests and independent byte/metadata comparisons; live `Research QA` retained `scout.md` and the same UUID | PASS |
| Open Markdown inside Crew | Production menu action routes to the internal controller; live `Edit Research QA` window appeared within the QA app after clicking Open Markdown file | PASS |
| Same-file save and relaunch | Live native edit/save plus filesystem assertion; final-build relaunch displayed the saved text and renamed agent | PASS |
| Cancel and conflict preservation | Controller/store tests and independent probe; live Escape did not write; live conflicting Save preserved the external file and displayed the draft/error | PASS |
| p90/p95 load and memory evidence | Forty matched launch pairs, forty loads per document size, raw samples, nearest-rank audit, binary/source/compiler identities | PASS for the defined measurements below |
| Correct performance failure handling | Six runner regression tests and independent malformed-marker/failed-process audit | PASS |
| Release delivery | Optimized app build and strict local code-signature verification | PASS |

## Independent feature checks

Investigators received expected outcomes and inspection constraints, with no engineering result or conversation history. They inspected actual code and wrote their own probes.

- [Rename investigation](../artifacts/rename-editor/independent/rename/report.md), [native probe](../artifacts/rename-editor/independent/rename/NativeRenameProbe.swift), [separate-process reload](../artifacts/rename-editor/independent/rename/relaunch-output.txt).
- [Internal Markdown investigation](../artifacts/rename-editor/independent/markdown/report.md), [25-check probe](../artifacts/rename-editor/independent/markdown/probe.swift), [results](../artifacts/rename-editor/independent/markdown/probe.log).
- [Performance audit](../artifacts/rename-editor/independent/performance/findings-current.md), [paired arithmetic/hash audit](../artifacts/rename-editor/independent/performance/paired-reaudit.json).

## Live native checks

Live checks used a separately signed QA copy of the release executable and a disposable library, leaving the user's library unchanged. Native desktop automation was reconnected before these checks.

1. Clicked Scout, double-clicked its displayed name, typed `Research QA`, and pressed Return.
2. Confirmed the dropdown and shelf showed the new name while the filename remained `scout.md`.
3. Clicked Open Markdown file. Crew displayed its own editor with current contents and read-only filename/face.
4. Typed Markdown and clicked Save Markdown. A filesystem check confirmed the original UUID/file received the exact text, with four agents still present.
5. Relaunched the final QA build against the same library. Both the renamed agent and saved Markdown reappeared.
6. Entered an unsaved draft and pressed Escape. The file remained unchanged. Also cancelled an inline rename with Escape.
7. Changed only the disposable file externally while the editor was open, then attempted to save a different draft. Crew displayed the conflict, retained the draft, and did not overwrite the external version.

[Renamed dropdown](../artifacts/rename-editor/live-rename.jpg), [saved Markdown editor](../artifacts/rename-editor/live-editor.jpg), [reopened editor](../artifacts/rename-editor/live-reopened-editor.jpg), [visible conflict](../artifacts/rename-editor/live-conflict.jpg), [filesystem evidence](../artifacts/rename-editor/live-save-evidence.json).

The accessibility tool sometimes reported an error as the clicked dropdown disappeared. The resulting editor state and file checks confirmed those actions completed. Physical screen configurations were not changed.

## Startup comparison

Forty launches per build were interleaved, reversing their order each round. Each launch used a fresh four-agent temporary library, with warm OS caches, a one-second settle period, and a one-second idle sample. All 80 attempts succeeded. Percentiles use nearest ranks, and binary hashes matched throughout.

| Metric | Baseline p90 | Baseline p95 | Updated p90 | Updated p95 |
| --- | ---: | ---: | ---: | ---: |
| Startup ready, ms | 251.20 | 299.60 | 263.60 | 277.10 |
| Startup RSS, MiB | 82.36 | 82.42 | 82.44 | 82.62 |
| Startup virtual size, MiB | 477798.56 | 477801.94 | 477798.97 | 477801.02 |

Startup p95 improved while p90 was slightly higher, so these results do not establish a general speedup. Startup RSS was nearly unchanged. The virtual size includes large macOS guard/shared reservations and is not RAM consumption.

[Paired raw data](../artifacts/rename-editor/paired-performance.json). Earlier sequential runs are retained as diagnostics: [baseline](../artifacts/rename-editor/baseline-performance.json) and [superseded candidate](../artifacts/rename-editor/updated-performance.json). They used different ordering and the superseded candidate predates the deferred-controller optimization. They are not the final comparison.

## Editor load and memory

The optimized probe uses production UI sources, the current core object, and the real editor controller/native Save action. Each document size has 40 load/edit/save/rename cycles. Active memory is sampled after data load and first-viewport native layout. Post-close memory is recorded separately in the raw report.

| Document | Metric | p90 | p95 |
| --- | --- | ---: | ---: |
| 8 KiB | Load + viewport layout, ms | 37.64 | 41.08 |
| 8 KiB | Save controller, ms | 9.23 | 13.06 |
| 8 KiB | Active editor RSS, MiB | 93.81 | 94.45 |
| 8 KiB | Active editor physical footprint, MiB | 26.88 | 27.02 |
| 512 KiB | Load + viewport layout, ms | 30.49 | 31.46 |
| 512 KiB | Save controller, ms | 11.90 | 13.21 |
| 512 KiB | Active editor RSS, MiB | 94.47 | 94.72 |
| 512 KiB | Active editor physical footprint, MiB | 29.27 | 29.42 |

These are offscreen native-component timings, excluding popup animation, window-server presentation, and application shelf-redraw/focus callbacks. They are not full visible interaction latency or a production lifetime-memory guarantee. The first typical-editor construction outlier is retained in the raw data rather than discarded. RSS and physical footprint measure different things.

[Editor data and provenance](../artifacts/rename-editor/editor-performance.json) records source hashes, core/probe/release binary hashes, compiler/version/flags, host, all samples, and measurement limits. Reproduce with `./scripts/measure-editor.sh`.

## Optimizations and resource behavior

- Rename and Markdown save mutate only the required record/file and update the shelf snapshot directly; they do not rescan templates.
- Prompt reads and mutations run on the storage actor. Editor controller creation is deferred until it is used.
- Dismissal ends native editing and releases Undo/input/document state after the close animation. Some empty text views can remain deferred by AppKit, but closed editors/panels deallocate and their text is cleared/detached.
- Noncontiguous text layout limits initial work for large Markdown. Prompt size remains bounded at 512 KiB.
- The startup runner validates readiness, reports each failed attempt, and replaces stale output with a failed report. The editor runner rebuilds its core dependency and records provenance rather than linking an unidentified old object.

## Tests and commands

`./scripts/test.sh` passes 55 tests: 29 UI and 26 core. `python3 scripts/test-performance.py` passes six runner regressions. Relevant native tests exercise Undo while open, cleanup after dismissal, asynchronous load/save ownership, double-click responder routing, same-file edits, exact UTF-8 conflict checks, and metadata preservation.

Logs: [Swift tests](../artifacts/rename-editor/tests.log), [runner tests](../artifacts/rename-editor/performance-runner-tests.log), [release build](../artifacts/rename-editor/build.log).

```sh
./scripts/test.sh
python3 scripts/test-performance.py
./scripts/build-app.sh
./scripts/measure-editor.sh
python3 scripts/compare-performance.py --baseline artifacts/rename-editor/Baseline.app/Contents/MacOS/Crew --candidate dist/Crew.app/Contents/MacOS/Crew --rounds 40 --output artifacts/rename-editor/paired-performance.json
```

External editors do not participate in Crew's advisory lock. Changes present when Save checks the original are detected; the implementation does not promise an OS-level compare-and-swap against an unrelated writer racing after that check.
