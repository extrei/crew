# Input centering

Historical result: the later [left-alignment change](left-inputs-verification.md) supersedes horizontal centering.

All text inputs now center their contents horizontally and vertically: filename, inline agent rename, Markdown prompt, and selected Face value. Ordinary menu labels keep their existing alignment.

Short and empty Markdown blocks center within the visible field. Content taller than the viewport uses normal vertical scrolling with centered paragraphs and enough padding for the caret. Centering follows typing, paste, Undo, programmatic loading, and viewport resizing without adding whitespace to the document.

## Evidence

- `scripts/test.sh` passes 62 tests: 36 UI and 26 core.
- `InputAlignmentTests.swift` checks actual native glyph geometry and field editors, not just alignment flags. It covers empty/single/multiline/trailing-newline text, resize, paste, Undo/Redo, overflow/caret reachability, all Face values, and bounded layout for 50,000 paragraphs.
- A fresh investigator received only the expected outcome and inspection constraints, with no engineering report or prior task context. Its independent native probe passed: filename/rename glyphs centered exactly, short/wrapped prompt blocks within 0.5 point, Face values within 0.5 point, and Markdown bytes preserved.
- For a 480,889-character document, the independent probe found the first unlaid character at 902 after loading and 903 after typing. The centering calculation did not lay out the whole document.
- Live QA showed `centered.md`, the selected Face name, and a two-line prompt centered in the running native editor.

[Independent report and reproduction](../artifacts/input-centering/independent/result.md), [native probe](../artifacts/input-centering/independent/native-probe.swift), [probe output](../artifacts/input-centering/independent/native-probe.txt), [live screenshot](../artifacts/input-centering/centered-fields.jpg), [test log](../artifacts/input-centering/tests.log), [release build](../artifacts/input-centering/build.log).

The targeted 40-cycle native-editor workload also completed for 8 KiB and 512 KiB documents. Its [raw performance/provenance report](../artifacts/input-centering/editor-performance.json) describes the measured scope. No new startup-tail claim is made for this layout change.

IME behavior and exhaustive Unicode/font combinations were not tested. Geometry evidence uses native AppKit on this Mac; the live check supplements the investigator's offscreen rendering.

This change supersedes earlier left-aligned Markdown styling described in historical verification reports.
