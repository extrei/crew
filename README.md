# Crew

Crew is a free-floating macOS island for local Markdown prompts. Choose a template, create an agent, and drag its mascot into another app. The island keeps the original file. Crew offers a file URL and prompt text; the receiving app chooses which format to accept.

Crew uses Swift, AppKit, and Core Animation. It has no package dependencies, embedded browser, network service, or AI provider integration. Ready means that the local prompt is available, not that an AI task is running.

## Build and run

Use a Mac with Swift 6 and the macOS Command Line Tools or Xcode. The app targets macOS 14 and later.

```sh
./scripts/build-app.sh
open dist/Crew.app
```

The build produces a locally signed `dist/Crew.app`. The signature supports local development; it is not a notarized distribution build.

## Use the shelf

- Drag the island's empty background or grip to place it anywhere on the desktop. Crew restores its position after relaunch.
- Right-click the island background for local actions. The menu-bar icon is a secondary control; the island is independent of the menu bar and notch.
- Click **+** to choose a local template or create a Markdown prompt.
- Drag a mascot into an app that accepts files or text. The original prompt stays in Crew.
- Select an agent to copy its prompt, open its Markdown file, or remove it from the shelf.
- Double-click the name in an agent's dropdown to rename it. Return saves; Escape cancels. Its file and identity stay unchanged.
- **Open Markdown file** opens Crew's in-app editor. **Save Markdown** updates the same file. If another editor changed it, Crew retains your draft and reports the conflict.
- All input values are left-aligned horizontally and centered vertically. Short Markdown blocks center vertically within the field; longer documents remain left-aligned and scroll vertically.
- Use the menu-bar control to show or hide Crew, refresh the library, open the template folder, or quit.
- Press **Escape** to dismiss a panel. The editor supports normal keyboard text editing.

The default library is `~/Documents/Crew/`. Templates live in `templates/`, prompt files in `agents/`, shelf membership in `library.json`, and the saved island position in `.island-position.json`. Removing an agent from the shelf preserves its Markdown file. Crew limits the shelf to six agents and each prompt to 512 KiB.

Use a separate library for development:

```sh
dist/Crew.app/Contents/MacOS/Crew --data-dir /tmp/crew-preview
```

## Run tests

```sh
./scripts/test.sh
```

The script runs Swift Testing. It supplies the installed testing macro library when needed by the Command Line Tools build engine. It installs nothing.

## Measure performance

Build the release app, then run:

```sh
python3 scripts/measure-performance.py --runs 3 --output artifacts/performance.json
```

The script uses a temporary library and terminates only the processes it starts. It records process launch to the app's ready marker, resident memory, virtual address size, and idle CPU time. It measures the first library launch and launches of the existing library separately. It does not simulate a cold disk cache.

Virtual size includes shared mappings and reserved address space. Compare it separately from resident memory; a large virtual mapping does not mean that the process consumes that amount of RAM.

Use at least 40 runs for p90/p95 measurements. `scripts/compare-performance.py` alternates two binaries under the same fresh-library protocol. `scripts/measure-editor.sh` measures native controller load/save and active/post-close memory for 8 KiB and 512 KiB documents. Both reports retain raw samples and state the measured scope.

## Project structure

- `Sources/CrewCore` owns validation, local templates, prompt files, and shelf persistence.
- `Sources/CrewUI` owns AppKit windows, vector mascots, input, and native drag behavior.
- `Sources/CrewApp` starts the app.
- `Tests` covers storage, layout, and drag contracts.
- `Docs/foundation-engineer-brief.md` contains the implementation brief and acceptance criteria.

The approved visual reference remains in `../agent-bar.design.html`.

See [verification results](Docs/verification.md) for test coverage, native UI checks, performance measurements, and remaining limitations.

The later dropdown, hover, and input refinements have [separate independent evidence for all eight fixes](Docs/ui-polish-verification.md). Quit and reopen a running Crew instance after rebuilding to load the updated interface.

See [rename, in-app Markdown, and p90/p95 verification](Docs/rename-editor-verification.md) for the latest 55-test result, live app checks, and performance comparison.

The latest [input-alignment verification](Docs/left-inputs-verification.md) records the 62-test result and independent native geometry evidence for left-aligned, vertically centered inputs.
