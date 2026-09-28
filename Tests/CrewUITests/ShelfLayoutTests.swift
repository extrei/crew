import AppKit
import Foundation
import CrewCore
import Testing
@testable import CrewUI

@Test func shelfWidthStopsAtSixAndKeepsMatchingCells() {
    #expect(ShelfLayout.cellSize == 62)
    #expect(ShelfLayout.width(agentCount: 4) == 404)
    #expect(ShelfLayout.width(agentCount: 6) == 546)
    #expect(ShelfLayout.width(agentCount: 20) == ShelfLayout.width(agentCount: 6))
    #expect(ShelfLayout.width(agentCount: -1) == ShelfLayout.width(agentCount: 0))
}

@Test func dragPreparationReadsExternallyUpdatedPrompt() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CrewDragTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AgentStore(dataDirectory: directory)
    let snapshot = try await store.load()
    let agent = try #require(snapshot.agents.first)
    let updated = "# Edited externally\n\nUse this text in the receiving app."
    try Data(updated.utf8).write(to: agent.fileURL, options: .atomic)
    let payload = try await DragPayload.prepare(fileURL: agent.fileURL) {
        try await store.readPrompt(id: agent.id)
    }
    #expect(payload.markdown == updated)
    #expect(payload.markdown != agent.prompt)
    #expect(payload.fileURL == agent.fileURL)
}

@Test func dragPreparationDiscardsReadCompletedAfterCancellation() async {
    let task = Task {
        try await DragPayload.prepare(fileURL: URL(fileURLWithPath: "/tmp/prompt.md")) {
            withUnsafeCurrentTask { $0?.cancel() }
            return "This read finished after the gesture was cancelled."
        }
    }
    await #expect(throws: CancellationError.self) { try await task.value }
}

@Test @MainActor func editorSupportsPlainTextUndoAndAgentsAreAccessible() throws {
    _ = NSApplication.shared
    let editor = PromptEditor()
    let initial = editor.prompt.string
    #expect(!editor.prompt.isRichText)
    #expect(editor.prompt.allowsUndo)
    editor.prompt.insertText("New text", replacementRange: NSRange(location: 0, length: 0))
    editor.prompt.breakUndoCoalescing()
    let undo = try #require(editor.prompt.undoManager)
    #expect(undo.canUndo)
    undo.undo()
    #expect(editor.prompt.string == initial)
    let agent = Agent(id: UUID(), name: "Scout", filename: "scout.md", prompt: "Prompt", mascot: .scout,
                      fileURL: URL(fileURLWithPath: "/tmp/scout.md"))
    let cell = AgentCell(agent: agent, readPrompt: { "Prompt" })
    #expect(cell.isAccessibilityElement())
    #expect(cell.accessibilityRole() == .button)
    #expect(cell.accessibilityLabel()?.contains("Scout") == true)
}

@Test func shelfAndPopupStayWithinEachDisplay() {
    let screens = [CGRect(x: 0, y: 0, width: 1440, height: 875),
                   CGRect(x: -1920, y: -240, width: 1920, height: 1080)]
    for screen in screens {
        for x in [screen.minX - 400, screen.midX, screen.maxX + 400] {
            for y in [screen.minY - 500, screen.midY, screen.maxY + 500] {
                let shelf = ShelfLayout.constrained(CGRect(x: x, y: y, width: 546, height: 86), to: screen)
                #expect(screen.insetBy(dx: 12, dy: 12).contains(shelf))
                let popup = ShelfLayout.popup(size: CGSize(width: 448, height: 490), shelf: shelf, screen: screen)
                #expect(screen.insetBy(dx: 12, dy: 12).contains(popup))
            }
        }
    }
}

@Test func popupUsesAvailableSideOfShelf() {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let size = CGSize(width: 324, height: 400)
    let lowShelf = CGRect(x: 600, y: 12, width: 404, height: 86)
    let highShelf = CGRect(x: 600, y: 770, width: 404, height: 86)
    #expect(ShelfLayout.popup(size: size, shelf: lowShelf, screen: screen).minY == lowShelf.maxY + 12)
    #expect(ShelfLayout.popup(size: size, shelf: highShelf, screen: screen).maxY == highShelf.minY - 12)
}

@Test @MainActor func dragAdvertisesOneRealFileAndUnmodifiedMarkdown() throws {
    let url = URL(fileURLWithPath: "/tmp/Crew Test/équipe #1.md")
    let markdown = "# A prompt\n\nKeep **Markdown** and café.\n"
    let payload = DragPayload(fileURL: url, markdown: markdown)
    let item = payload.pasteboardItem()
    #expect(Set(item.types) == Set([.fileURL, .string]))
    let advertisedURL = try #require(item.string(forType: .fileURL))
    #expect(URL(string: advertisedURL) == url)
    #expect(item.string(forType: .string) == markdown)
    #expect(!item.types.contains(NSPasteboard.PasteboardType("NSFilesPromisePboardType")))
}

@Test func islandStartsDetachedInUpperThird() {
    let screen = CGRect(x: -1440, y: 80, width: 1440, height: 875)
    let anchor = ShelfLayout.defaultAnchor(in: screen)
    let frame = ShelfLayout.island(anchor: anchor, agentCount: 4, screens: [screen])
    #expect(frame.midX == screen.midX)
    #expect(abs(frame.midY - (screen.minY + screen.height * 2 / 3)) < 0.001)
    #expect(screen.maxY - frame.maxY > 200)
}

@Test func islandKeepsChosenAnchorWhenAgentCountChanges() {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
    let anchor = CGPoint(x: 735, y: 360)
    for count in 0...6 {
        let frame = ShelfLayout.island(anchor: anchor, agentCount: count, screens: [screen])
        #expect(frame.midX == anchor.x)
        #expect(frame.midY == anchor.y)
    }
}

@Test func islandSelectsDisplayWithMostOverlapWhenCrossingBoundary() {
    let left = CGRect(x: -1440, y: 0, width: 1440, height: 875)
    let right = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let crossing = CGRect(x: -100, y: 400, width: 404, height: 86)
    #expect(ShelfLayout.screen(for: crossing, among: [left, right]) == right)
    #expect(ShelfLayout.screen(for: crossing, among: [right, left]) == right)
    let movedLeft = CGRect(x: -350, y: 400, width: 404, height: 86)
    #expect(ShelfLayout.screen(for: movedLeft, among: [right, left]) == left)
}

@Test func restoredIslandClampsToNearestRemainingDisplay() {
    let left = CGRect(x: -1440, y: 0, width: 1440, height: 875)
    let right = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let anchor = CGPoint(x: -2200, y: 400)
    let frame = ShelfLayout.island(anchor: anchor, agentCount: 4, screens: [right, left])
    #expect(left.insetBy(dx: 12, dy: 12).contains(frame))
    #expect(frame.minX == left.minX + 12)
    let singleDisplay = ShelfLayout.island(anchor: anchor, agentCount: 4, screens: [right])
    #expect(right.insetBy(dx: 12, dy: 12).contains(singleDisplay))
}

@Test func positionLoadDoesNotCreateLibraryBeforeCoreSeeding() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CrewPosition-\(UUID().uuidString)")
    let positions = IslandPositionStore(dataDirectory: directory)
    #expect(try await positions.load() == nil)
    #expect(!FileManager.default.fileExists(atPath: directory.path))
}

@Test func islandPositionRestoresAcrossStoreInstancesAndStaysLibraryLocal() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CrewPosition-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = directory.appendingPathComponent("first")
    let second = directory.appendingPathComponent("second")
    let anchor = CGPoint(x: -830, y: 570)
    try await IslandPositionStore(dataDirectory: first).save(anchor)
    #expect(try await IslandPositionStore(dataDirectory: first).load() == anchor)
    #expect(try await IslandPositionStore(dataDirectory: second).load() == nil)
    let frame = ShelfLayout.island(anchor: anchor, agentCount: 4,
                                   screens: [CGRect(x: -1440, y: 0, width: 1440, height: 875)])
    #expect(frame.midX == anchor.x)
    #expect(frame.midY == anchor.y)
}

@Test @MainActor func islandBackgroundLeavesMascotAndPlusAsGestureTargets() throws {
    _ = NSApplication.shared
    let panel = CrewPanel(size: NSSize(width: 404, height: 86), cornerRadius: 40, nonactivating: true)
    let root = try #require(panel.contentView as? RoundedBackground)
    root.movesIsland = true
    let agent = Agent(id: UUID(), name: "Scout", filename: "scout.md", prompt: "Prompt", mascot: .scout,
                      fileURL: URL(fileURLWithPath: "/tmp/scout.md"))
    let cell = AgentCell(agent: agent, readPrompt: { "Prompt" })
    cell.frame.origin = CGPoint(x: 32, y: 12)
    let plus = ActionButton("+", frame: CGRect(x: 330, y: 12, width: 62, height: 62))
    root.addSubview(cell)
    root.addSubview(plus)
    #expect(root.hitTest(CGPoint(x: 20, y: 40)) === root)
    let mascotTarget = try #require(root.hitTest(CGPoint(x: 60, y: 40)))
    #expect(mascotTarget === cell || mascotTarget.isDescendant(of: cell))
    #expect(root.hitTest(CGPoint(x: 350, y: 40)) === plus)
}
