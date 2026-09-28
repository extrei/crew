# Build Crew for macOS

Build the approved agent shelf as a native Swift app. The visual reference is `../../agent-bar.design.html`, revision 04: a black rounded shelf, colored vector mascots, a matching 62-point plus button, a black template dropdown, and a simple Markdown editor. Implement the shelf, not the surrounding design presentation or simulated terminal.

The island floats independently of the menu bar or notch. Start it detached from the top edge, let the user drag its empty background or grip anywhere, and restore its position after relaunch. Keep the chosen position when agents are added or the library refreshes. Clamp it to an available screen after display changes. Provide island-local controls so the menu-bar icon is only a secondary recovery control.

Keep the codebase clean. Use Foundation for the file model and AppKit with Core Animation for the interface. Avoid third-party packages, embedded browsers, continuously redrawn canvases, global frame timers, and speculative abstraction layers.

The user can select a local Markdown template or write a new prompt, then drag a mascot into another app. The drag offers an actual file URL with copy semantics and plain text for receivers that accept it. Keep the original agent and file. Receiving apps decide whether to use a file or text. A copy-prompt action supplies a keyboard fallback.

Store prompts and shelf metadata under `~/Documents/Crew/`. Read existing templates from its `templates/` directory. An explicit `--data-dir PATH` isolates tests and previews. Initialize sample prompts only in a new library. Never scan unrelated folders or overwrite an existing prompt. Report load and write failures to the user. Preserve corrupt metadata for recovery.

Show real local state, such as Ready or Missing file. This app does not start AI agents or fabricate provider activity. It needs no network access or API keys.

Write tests for behavior that can fail: filename validation, collisions, persistence, corrupted metadata, template loading, copy payloads, and layout bounds. Run tests with `swift test`. Build an optimized app with `swift build -c release` and package it as a local `.app`.

Keep startup, resident memory, and virtual memory consumption low. Read files away from the main thread. Bound prompt sizes and directory traversal. Draw mascots as vectors. Use compositor animations and stop them when hidden or when Reduce Motion is enabled. Avoid synchronous I/O during pointer movement. Report measured startup, RSS, virtual size, and idle CPU without confusing virtual address reservation with physical memory.

Check the running app for clipped faces, dropped shadows, invisible text, misplaced dropdowns, screen-edge overflow, failed drags, and editor focus problems. Support Escape, keyboard navigation, VoiceOver labels, multiple screen bounds, and Reduce Motion. Record what was checked and what remains unverified.

## Ownership

- Foundation engineer, core: `Sources/CrewCore/` and `Tests/CrewCoreTests/`.
- Foundation engineer, native UI: `Sources/CrewUI/`, `Sources/CrewApp/`, and `Tests/CrewUITests/`.
- Parent integrator: package manifest, scripts, documentation, packaging, performance measurements, and manual verification.
- Independent verifier: read-only review and tests after implementation.

All workers share a workspace. Do not revert another worker's edits. Do not create nested sub-agents.

## Acceptance

1. A built `.app` launches to the rounded black floating shelf.
2. Plus opens local templates and a new Markdown editor.
3. Added prompts persist across launches, with recoverable errors.
4. Native dragging advertises copy-only file and text data. Clicking Copy prompt copies the actual Markdown.
5. Tests and release compilation pass.
6. Startup, memory, and idle CPU measurements are reproducible.
7. The running bar, template picker, and editor receive a visual check.

## Shared API

The core target defines the following public values and actor. Keep names and signatures stable across workers.

```swift
public enum MascotKind: String, Codable, CaseIterable, Sendable {
    case scout, pixel, patch, sage
}

public struct Agent: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let filename: String
    public let prompt: String
    public let mascot: MascotKind
    public let fileURL: URL
    public let isAvailable: Bool // public initializer defaults to true
}

public struct AgentTemplate: Identifiable, Equatable, Sendable {
    public var id: String { filename }
    public let name: String
    public let filename: String
    public let mascot: MascotKind
}

public struct LibrarySnapshot: Sendable {
    public let agents: [Agent]
    public let templates: [AgentTemplate]
    public let warnings: [String]
}

public actor AgentStore {
    public static let maximumAgents: Int // 6
    public static let maximumPromptBytes: Int // 512 KiB
    public nonisolated let dataDirectory: URL
    public init(dataDirectory: URL)
    public func load() throws -> LibrarySnapshot
    public func addTemplate(filename: String) throws -> Agent
    public func add(name: String, filename: String, prompt: String,
                    mascot: MascotKind) throws -> Agent
    public func remove(id: UUID) throws
    public func readPrompt(id: UUID) throws -> String
}
```

Provide public initializers for these values. `load()` is idempotent and re-reads only this library. Adding requires a successful load. Missing prompt files yield warnings and preserve metadata; never silently erase records. Removing an agent removes its shelf membership but preserves its Markdown file. No UI worker edits core code.
