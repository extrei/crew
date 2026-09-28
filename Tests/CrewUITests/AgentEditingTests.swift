import AppKit
import CrewCore
import Testing
@testable import CrewUI

@MainActor
private func key(_ code: UInt16, text: String = "") -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text,
                    isARepeat: false, keyCode: code)!
}

private func temporaryLibrary() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("CrewUI-\(UUID().uuidString)")
}

@Test @MainActor func doubleClickNameUsesNativeFieldEditorAndReturnPersistsOnlyName() async throws {
    _ = NSApplication.shared
    let directory = temporaryLibrary()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AgentStore(dataDirectory: directory)
    _ = try await store.load()
    let agent = try await store.add(name: "Original", filename: "original.md", prompt: "Original prompt", mascot: .sage)
    let menu = ActionDropdown(title: agent.name, subtitle: agent.filename, items: [.init(title: "Copy", action: {})], status: "Ready")
    menu.onRename = { name in try await store.rename(id: agent.id, name: name).name }
    let point = menu.nameField.convert(NSPoint(x: 8, y: 8), to: nil)
    let event = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
                                  windowNumber: menu.panel.windowNumber, context: nil, eventNumber: 1, clickCount: 2, pressure: 1)!
    let root = try #require(menu.panel.contentView)
    let hit = try #require(root.hitTest(root.superview?.convert(point, from: nil) ?? point))
    #expect(hit === menu.nameField)
    let single = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
                                   windowNumber: menu.panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    hit.mouseDown(with: single)
    #expect(!menu.nameField.isEditable)
    hit.mouseDown(with: event)
    let fieldEditor = try #require(menu.nameField.currentEditor() as? NSTextView)
    #expect(menu.panel.firstResponder === fieldEditor)
    #expect(fieldEditor.string == "Original")
    root.layoutSubtreeIfNeeded()
    root.displayIfNeeded()
    let bitmap = try #require(root.bitmapImageRepForCachingDisplay(in: root.bounds))
    root.cacheDisplay(in: root.bounds, to: bitmap)
    #expect(!menu.nameField.isBezeled)
    #expect(!menu.nameField.isBordered)
    #expect(menu.nameField.backgroundColor == .black)
    #expect(menu.nameField.layer?.backgroundColor == NSColor.black.cgColor)
    #expect(menu.nameField.layer?.cornerRadius == 12)
    #expect(menu.nameField.layer?.borderWidth == 1.5)
    #expect(menu.nameField.layer?.borderColor == NSColor(white: 0.58, alpha: 1).cgColor)
    fieldEditor.selectAll(nil)
    fieldEditor.insertText("Renamed", replacementRange: fieldEditor.selectedRange())
    fieldEditor.keyDown(with: key(36, text: "\r"))
    await menu.renameTask?.value
    #expect(menu.nameField.stringValue == "Renamed")
    #expect(menu.nameField.accessibilityLabel() == "Renamed")
    #expect(menu.panel.title == "Renamed actions")
    #expect(!menu.nameField.drawsBackground)
    #expect(menu.nameField.layer?.borderWidth == 0)
    #expect(menu.nameField.layer?.backgroundColor == NSColor.clear.cgColor)
    let persisted = try await AgentStore(dataDirectory: directory).load()
    let renamed = try #require(persisted.agents.first { $0.id == agent.id })
    #expect(renamed.name == "Renamed")
    #expect(renamed.filename == agent.filename)
    #expect(renamed.mascot == agent.mascot)
    #expect(renamed.prompt == agent.prompt)
}

@Test @MainActor func renameInvalidDraftRemainsEditableAndEscapeCancels() async throws {
    _ = NSApplication.shared
    let menu = ActionDropdown(title: "Scout", subtitle: "scout.md", items: [.init(title: "Copy", action: {})], status: "Ready")
    menu.onRename = { _ in throw AgentStoreError.invalidName }
    #expect(menu.nameField.accessibilityPerformPress())
    let editor = try #require(menu.nameField.currentEditor() as? NSTextView)
    editor.selectAll(nil)
    editor.insertText(" ", replacementRange: editor.selectedRange())
    editor.keyDown(with: key(36, text: "\r"))
    await menu.renameTask?.value
    #expect(menu.nameField.isEditable)
    #expect(menu.nameField.stringValue == " ")
    #expect(menu.renameMessage.stringValue == AgentStoreError.invalidName.localizedDescription)
    let responder = try #require(menu.nameField.currentEditor() as? NSTextView)
    responder.keyDown(with: key(53, text: "\u{1b}"))
    #expect(!menu.nameField.isEditable)
    #expect(menu.nameField.stringValue == "Scout")
    #expect(!menu.nameField.isBezeled)
    #expect(!menu.nameField.drawsBackground)
    #expect(menu.nameField.layer?.borderWidth == 0)
    #expect(menu.nameField.layer?.backgroundColor == NSColor.clear.cgColor)
    menu.panel.makeFirstResponder(menu.nameField)
    menu.nameField.keyDown(with: key(36, text: "\r"))
    #expect(menu.nameField.isEditable)
}

@Test @MainActor func editControllerReadsFreshMarkdownAndSavesSameAgent() async throws {
    _ = NSApplication.shared
    let directory = temporaryLibrary()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AgentStore(dataDirectory: directory)
    _ = try await store.load()
    let agent = try await store.add(name: "Kept display name", filename: "kept-file.md", prompt: "Cached", mascot: .patch)
    try "Fresh from disk".write(to: agent.fileURL, atomically: true, encoding: .utf8)
    let controller = PromptEditorController(store: store)
    var updated: Agent?
    controller.onUpdated = { updated = $0 }
    let editor = controller.open(.edit(agent))
    #expect(!editor.saveButton.isEnabled)
    await controller.loadTask?.value
    #expect(editor.prompt.string == "Fresh from disk")
    #expect(editor.filename.stringValue == agent.filename)
    #expect(!editor.filename.isEditable)
    #expect(!editor.mascotChoice.isEnabled)
    #expect(editor.mascotChoice.selected == agent.mascot)
    #expect(editor.prompt.allowsUndo)
    editor.prompt.string = "Saved draft"
    editor.saveButton.performClick(nil)
    await controller.saveTask?.value
    #expect(controller.editor == nil)
    #expect(updated?.id == agent.id)
    #expect(updated?.name == agent.name)
    #expect(updated?.filename == agent.filename)
    #expect(updated?.mascot == agent.mascot)
    #expect(try String(contentsOf: agent.fileURL, encoding: .utf8) == "Saved draft")
}

@Test @MainActor func editConflictKeepsDraftAndEscapeLeavesExternalFileUnchanged() async throws {
    _ = NSApplication.shared
    let directory = temporaryLibrary()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AgentStore(dataDirectory: directory)
    _ = try await store.load()
    let agent = try await store.add(name: "Scout", filename: "scout-test.md", prompt: "Original", mascot: .scout)
    let controller = PromptEditorController(store: store)
    let editor = controller.open(.edit(agent))
    await controller.loadTask?.value
    editor.prompt.string = "Unsaved draft"
    try "External update".write(to: agent.fileURL, atomically: true, encoding: .utf8)
    editor.saveButton.performClick(nil)
    await controller.saveTask?.value
    #expect(controller.editor === editor)
    #expect(editor.prompt.string == "Unsaved draft")
    #expect(editor.errorLabel.stringValue == AgentStoreError.promptChanged.localizedDescription)
    #expect(editor.prompt.isEditable)
    #expect(editor.saveButton.isEnabled)
    #expect(!editor.filename.isEditable)
    #expect(!editor.mascotChoice.isEnabled)
    editor.prompt.keyDown(with: key(53, text: "\u{1b}"))
    #expect(controller.editor == nil)
    #expect(try String(contentsOf: agent.fileURL, encoding: .utf8) == "External update")
}

@Test @MainActor func replacingAndCancelingEditorDiscardsPendingLoads() async throws {
    _ = NSApplication.shared
    let directory = temporaryLibrary()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AgentStore(dataDirectory: directory)
    _ = try await store.load()
    let agent = try await store.add(name: "Scout", filename: "load.md", prompt: "Disk prompt", mascot: .scout)
    let controller = PromptEditorController(store: store)
    let abandoned = controller.open(.edit(agent))
    let pending = controller.loadTask
    let created = controller.open(.create)
    await pending?.value
    #expect(controller.editor === created)
    #expect(created.mode.isCreate)
    #expect(created.prompt.string != "Disk prompt")
    #expect(abandoned.prompt.string.isEmpty)
    let canceled = controller.open(.edit(agent))
    let canceledLoad = controller.loadTask
    canceled.panel.cancelOperation(nil)
    await canceledLoad?.value
    #expect(controller.editor == nil)
    #expect(canceled.prompt.string.isEmpty)
    #expect(try String(contentsOf: agent.fileURL, encoding: .utf8) == "Disk prompt")
}

@Test @MainActor func closedSaveFailureIsReportedWithoutReplacingNewEditor() async throws {
    _ = NSApplication.shared
    let directory = temporaryLibrary()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AgentStore(dataDirectory: directory)
    _ = try await store.load()
    let controller = PromptEditorController(store: store)
    var failures: [String] = []
    controller.onError = { failures.append($0) }
    let invalid = controller.open(.create)
    invalid.filename.stringValue = "../invalid.md"
    invalid.saveButton.performClick(nil)
    let oldSave = controller.saveTask
    let next = controller.open(.create)
    next.filename.stringValue = "next.md"
    next.prompt.string = "Next draft"
    await oldSave?.value
    #expect(failures == [AgentStoreError.invalidFilename.localizedDescription])
    #expect(controller.editor === next)
    #expect(next.prompt.string == "Next draft")
    next.saveButton.performClick(nil)
    await controller.saveTask?.value
    #expect(controller.editor == nil)
    let snapshot = try await store.load()
    #expect(snapshot.agents.contains { $0.filename == "next.md" && $0.prompt == "Next draft" })
}

@Test @MainActor func earlierSaveCompletionCannotClearNewerSaveOrCloseItsEditor() async throws {
    _ = NSApplication.shared
    let directory = temporaryLibrary()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = AgentStore(dataDirectory: directory)
    _ = try await store.load()
    let controller = PromptEditorController(store: store)
    var completed: [String] = []
    controller.onCreated = { completed.append($0.filename) }
    let first = controller.open(.create)
    first.filename.stringValue = "first.md"
    first.saveButton.performClick(nil)
    let firstSave = controller.saveTask
    let second = controller.open(.create)
    second.filename.stringValue = "second.md"
    second.saveButton.performClick(nil)
    let secondSave = try #require(controller.saveTask)
    await firstSave?.value
    if controller.editor === second { #expect(controller.saveTask != nil) }
    await secondSave.value
    #expect(controller.editor == nil)
    #expect(Set(completed) == ["first.md", "second.md"])
}

@Test @MainActor func closingEditorReleasesDocumentAfterPreservingOpenUndo() async throws {
    _ = NSApplication.shared
    weak var releasedEditor: PromptEditor?
    weak var releasedPanel: CrewPanel?
    weak var releasedText: PromptTextView?
    try autoreleasepool {
        let editor = PromptEditor()
        releasedEditor = editor
        releasedPanel = editor.panel
        releasedText = editor.prompt
        editor.panel.makeFirstResponder(editor.prompt)
        editor.prompt.string = "Original"
        let undo = try #require(editor.prompt.undoManager)
        undo.removeAllActions()
        editor.prompt.insertText("Draft", replacementRange: NSRange(location: 0, length: 8))
        editor.prompt.breakUndoCoalescing()
        #expect(editor.prompt.string == "Draft")
        #expect(undo.canUndo)
        undo.undo()
        #expect(editor.prompt.string == "Original")
        undo.redo()
        #expect(editor.prompt.string == "Draft")
        #expect(editor.prompt.layoutManager?.allowsNonContiguousLayout == true)
        editor.dismiss(animated: false)
        #expect(editor.panel.firstResponder !== editor.prompt)
        #expect(editor.prompt.string.isEmpty)
        #expect(editor.prompt.enclosingScrollView == nil)
        #expect(!undo.canUndo)
        #expect(!undo.canRedo)
    }
    await Task.yield()
    #expect(releasedEditor == nil)
    #expect(releasedPanel == nil)
    if let releasedText {
        #expect(releasedText.window == nil)
        #expect(releasedText.string.isEmpty)
        #expect(releasedText.undoManager?.canUndo != true)
    }
}
