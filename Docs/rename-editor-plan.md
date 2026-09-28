# Rename and in-app Markdown

## Required outcomes

1. Double-clicking an agent's displayed name in its action dropdown starts inline renaming. Return commits, Escape cancels, invalid names retain an editable error state, and the name survives relaunch. The file, agent ID, order, and mascot remain unchanged.
2. Open Markdown file displays that agent's current Markdown in a Crew dropdown editor rather than launching another app. Save updates the same file. Cancel leaves the file intact. External changes are detected before saving. Existing dropdown styling, keyboard use, Undo, and floating placement remain intact.
3. Report p90 and p95 app startup, Markdown load, and memory use from reproducible measurements. Compare 40 baseline and 40 updated process launches. Distinguish RSS from virtual address reservations and state sampling limits. Avoid main-thread filesystem work and unnecessary template rescans for rename/edit updates.

## Shared core API additions

```swift
public func rename(id: UUID, name: String) throws -> Agent
public func updatePrompt(id: UUID, prompt: String, expectedPrompt: String) throws -> Agent
```

Both actor operations require a successful load, use the existing library lock, reject stale metadata, and preserve unrelated records. Rename applies existing name validation and does not rename the Markdown file. It remains possible for a missing-file agent. Updating Markdown keeps filename, ID, name, and mascot, enforces the existing UTF-8 byte limit, and compares the current file's UTF-8 bytes to the expected original before an atomic replacement. An empty saved Markdown document is allowed. Add `AgentStoreError.promptChanged` with a useful user-facing conflict message.

## Ownership and checks

- Core engineer: `Sources/CrewCore/`, `Tests/CrewCoreTests/`.
- UI engineer: `Sources/CrewUI/`, `Tests/CrewUITests/`.
- Parent: scripts, benchmark artifacts, packaging, documentation, integration.
- Fresh investigators: expected outcomes and artifact locations only; no engineer report or conversation history.

Run `scripts/test.sh`, build the release app, and verify the application paths rather than only isolated storage mutations. Preserve all existing tests and the user's local data. Independent checks must cover both successful changes and cancellation/conflict paths.
