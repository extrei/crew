# UI polish acceptance

Each numbered request receives a separate investigator with no conversation history, implementation explanation, or engineer result. Each investigator receives the expected outcome, the project location, and verification constraints. Investigators inspect the actual app, source, or executable tests and return their own conclusion. Unobserved behavior is marked unverified.

| Fix | Expected outcome |
| --- | --- |
| 1 | Clicking a mascot opens agent actions in the same black, rounded dropdown style as Add Agent. Existing actions remain usable. |
| 2 | Hovering a template row in Add Agent produces visible, smooth feedback that clears on exit. Disabled rows do not advertise availability. |
| 3 | Start with a new .md has visible hover feedback and still opens the editor. |
| 4 | Open templates folder has visible hover feedback and retains its folder action. |
| 5 | Filename uses a black background matching the surrounding panel, a rounded 1–2 px border, centered text, and a clear focus state. Editing does not reintroduce a native blue bezel. |
| 6 | The face picker uses the same dropdown style as Add Agent, retains hover, indicates selection, supports keyboard use, and saves the chosen face. |
| 7 | Prompt uses the same black, rounded outlined field treatment, with readable left-aligned Markdown, padding, caret, selection, scrolling, and Undo. |
| 8 | Add Agent, agent actions, and face choices open and close with consistent, short spring and opacity transitions. Interruptions do not leave stale windows or invisible clickable regions. Reduce Motion removes the spatial movement. |

The filename alignment request applies to the filename. The prompt shares its field styling but retains left alignment for Markdown. The system menu-bar menu keeps native macOS behavior.

Evidence will identify the investigator, observed result, executable check or screenshot, and any limitation for every fix. Results are recorded separately from this acceptance list.
