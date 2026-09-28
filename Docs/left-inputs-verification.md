# Left-aligned, vertically centered inputs

Filename, native filename editor, inline rename, Markdown, and selected Face values align left horizontally and center vertically. Long Markdown remains left-aligned and scrollable. Alignment does not change stored text.

## Evidence

- The new glyph-position expectation failed before implementation: [red test log](../artifacts/left-inputs/before.log).
- All 62 tests pass (36 UI, 26 core): [test log](../artifacts/left-inputs/tests.log). The optimized app built successfully: [build log](../artifacts/left-inputs/build.log). Its code signature verifies.
- An independent investigator received only the expected outcome and inspection constraints, with no implementation report or conversation history. Its native probe reported zero failures: [probe](../artifacts/left-inputs/independent/probe.swift), [results](../artifacts/left-inputs/independent/results.txt).
- Filename native editor: `(10,10,240,16)` in a `260×36` field. Rename: `(10,4,183,17)` in `203×25`. Both are left-aligned and vertically centered.
- Short Markdown blocks center vertically within 0.5 point. Overflow expands to 3391 points and scrolls; short text recenters after overflow. Typing, paste, and Undo preserve content and alignment.
- All four Face names start at x=41 with midpoint y=18 in a 36-point control, retaining mascot and chevron.

The independent probe used hidden native windows and a private pasteboard. Live desktop visual inspection could not complete because the Computer Use service timed out, including after resetting its client. No new screenshot or visual-animation claim is made for this change.
