import AppKit
import CrewCore
import Testing
@testable import CrewUI

@MainActor
private func textBlock(_ text: NSTextView) throws -> NSRect {
    let manager = try #require(text.layoutManager)
    let container = try #require(text.textContainer)
    manager.ensureLayout(for: container)
    var block = manager.usedRect(for: container)
    if manager.extraLineFragmentTextContainer === container {
        block = block.isEmpty ? manager.extraLineFragmentRect : block.union(manager.extraLineFragmentRect)
    }
    return block.offsetBy(dx: text.textContainerOrigin.x, dy: text.textContainerOrigin.y)
}

@MainActor
private func expectVerticallyCentered(_ text: NSTextView, in viewport: NSView) throws {
    let block = try textBlock(text)
    let mapped = viewport.convert(block, from: text)
    #expect(abs(mapped.midY - viewport.bounds.midY) <= 1)
    try expectLeftAligned(text, in: viewport)
}

@MainActor
private func expectLeftAligned(_ text: NSTextView, in viewport: NSView) throws {
    let manager = try #require(text.layoutManager)
    let container = try #require(text.textContainer)
    let value = text.string as NSString
    manager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs)) { _, _, _, glyphRange, _ in
        var characters = manager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        while characters.length > 0 && CharacterSet.newlines.contains(UnicodeScalar(value.character(at: NSMaxRange(characters) - 1))!) {
            characters.length -= 1
        }
        guard characters.length > 0 else { return }
        let range = manager.glyphRange(forCharacterRange: characters, actualCharacterRange: nil)
        let glyphs = manager.boundingRect(forGlyphRange: range, in: container)
        let mappedGlyphs = viewport.convert(glyphs.offsetBy(dx: text.textContainerOrigin.x, dy: text.textContainerOrigin.y), from: text)
        let leading = viewport.convert(NSPoint(x: text.textContainerOrigin.x + container.lineFragmentPadding, y: 0), from: text).x
        #expect(abs(mappedGlyphs.minX - leading) <= 1)
    }
}

@Test @MainActor func shortPromptIsLeftAlignedAndVerticallyCentered() throws {
    _ = NSApplication.shared
    let editor = PromptEditor()
    let clip = try #require(editor.prompt.enclosingScrollView?.contentView)
    for value in ["", "Short", "First line\nAnother longer line", "Trailing\n"] {
        editor.prompt.string = value
        editor.panel.contentView?.layoutSubtreeIfNeeded()
        try expectVerticallyCentered(editor.prompt, in: clip)
        #expect(editor.prompt.string == value)
    }
}

@Test @MainActor func nativeFilenameAndRenameAreLeftAlignedAndVerticallyCentered() throws {
    _ = NSApplication.shared
    let editor = PromptEditor()
    editor.filename.selectText(nil)
    try expectVerticallyCentered(try #require(editor.filename.currentEditor() as? NSTextView), in: editor.filename)
    let menu = ActionDropdown(title: "Scout", subtitle: "scout.md", items: [.init(title: "Copy", action: {})], status: "Ready")
    menu.onRename = { $0 }
    menu.beginRename()
    let fieldEditor = try #require(menu.nameField.currentEditor() as? NSTextView)
    try expectVerticallyCentered(fieldEditor, in: menu.nameField)
    fieldEditor.selectAll(nil)
    fieldEditor.insertText("A new name", replacementRange: fieldEditor.selectedRange())
    try expectVerticallyCentered(fieldEditor, in: menu.nameField)
}


@Test @MainActor func promptCentersAfterTypingPasteUndoAndViewportResize() throws {
    _ = NSApplication.shared
    let editor = PromptEditor()
    let text = editor.prompt
    let scroll = try #require(text.enclosingScrollView)
    editor.panel.makeFirstResponder(text)
    text.string = "Start"
    let undo = try #require(text.undoManager)
    undo.removeAllActions()
    text.insertText("\nMore", replacementRange: NSRange(location: 5, length: 0))
    text.breakUndoCoalescing()
    try expectVerticallyCentered(text, in: scroll.contentView)
    undo.undo()
    #expect(text.string == "Start")
    try expectVerticallyCentered(text, in: scroll.contentView)
    undo.redo()
    try expectVerticallyCentered(text, in: scroll.contentView)
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    pasteboard.setString("Pasted\ntext\n", forType: .string)
    text.selectAll(nil)
    #expect(text.readSelection(from: pasteboard, type: .string))
    #expect(text.string == "Pasted\ntext\n")
    try expectVerticallyCentered(text, in: scroll.contentView)
    scroll.setFrameSize(NSSize(width: 300, height: 320))
    try expectVerticallyCentered(text, in: scroll.contentView)
    scroll.setFrameSize(NSSize(width: 380, height: 180))
    try expectVerticallyCentered(text, in: scroll.contentView)
}

@Test @MainActor func overflowingPromptKeepsPaddingAndCaretReachableThenRecenters() throws {
    _ = NSApplication.shared
    let editor = PromptEditor()
    let text = editor.prompt
    let clip = try #require(text.enclosingScrollView?.contentView)
    editor.panel.makeFirstResponder(text)
    let value = String(repeating: "A centered paragraph\n", count: 80)
    text.string = value
    #expect(text.textContainerInset.height == 8)
    #expect(text.frame.height > clip.bounds.height)
    text.setSelectedRange(NSRange(location: value.utf16.count, length: 0))
    text.scrollRangeToVisible(text.selectedRange())
    let manager = try #require(text.layoutManager)
    let container = try #require(text.textContainer)
    manager.ensureLayout(for: container)
    let caret = manager.extraLineFragmentRect.offsetBy(dx: text.textContainerOrigin.x, dy: text.textContainerOrigin.y)
    #expect(caret.minY >= clip.bounds.minY)
    #expect(caret.maxY <= clip.bounds.maxY)
    #expect(text.string == value)
    try expectLeftAligned(text, in: clip)
    text.selectAll(nil)
    text.insertText("Short again", replacementRange: text.selectedRange())
    try expectVerticallyCentered(text, in: clip)
    #expect(clip.bounds.minY == 0)
}

@Test @MainActor func faceValueIsLeftAlignedAndVerticallyCentered() throws {
    _ = NSApplication.shared
    let editor = PromptEditor()
    let button = editor.mascotChoice.button
    for face in CrewCore.MascotKind.allCases {
        editor.mascotChoice.select(face)
        button.layoutSubtreeIfNeeded()
        let group = try #require(button.subviews.first as? NSStackView)
        #expect(abs(group.frame.minX - 10) <= 1)
        #expect(abs(group.frame.maxX - (button.bounds.maxX - 10)) <= 1)
        #expect(abs(group.frame.midY - button.bounds.midY) <= 1)
        
        let name = try #require(group.arrangedSubviews[1] as? NSTextField)
        #expect(name.alignment == .left)
        let bitmap = try #require(name.bitmapImageRepForCachingDisplay(in: name.bounds))
        name.cacheDisplay(in: name.bounds, to: bitmap)
        var ink = NSRect.null
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.alphaComponent > 0.5, color.redComponent > 0.5 else { continue }
                ink = ink.union(NSRect(x: x, y: y, width: 1, height: 1))
            }
        }
        #expect(!ink.isNull)
        let glyphMidpoint = button.convert(NSPoint(x: ink.midX * name.bounds.width / CGFloat(bitmap.pixelsWide),
                                                  y: ink.midY * name.bounds.height / CGFloat(bitmap.pixelsHigh)), from: name)
        #expect(ink.minX * name.bounds.width / CGFloat(bitmap.pixelsWide) <= 3)
        #expect(abs(glyphMidpoint.y - button.bounds.midY) <= 2)
        for item in group.arrangedSubviews {
            #expect(abs(item.frame.midY - group.bounds.midY) <= 1)
        }
    }
}

@Test @MainActor func largePromptCenteringDoesNotRequireWholeDocumentLayout() throws {
    _ = NSApplication.shared
    let editor = PromptEditor()
    let text = editor.prompt
    text.string = String(repeating: "A centered paragraph\n", count: 50_000)
    let manager = try #require(text.layoutManager)
    #expect(manager.firstUnlaidCharacterIndex() < text.string.utf16.count)
    text.insertText("X", replacementRange: NSRange(location: 0, length: 0))
    #expect(manager.firstUnlaidCharacterIndex() < text.string.utf16.count)
    #expect(text.textContainerInset.height == 8)
}


@Test @MainActor func genericActionMenuTitleRemainsLeftAligned() throws {
    _ = NSApplication.shared
    let menu = ActionDropdown(title: "Crew", subtitle: "Six agents", items: [.init(title: "Add agent", action: {})])
    #expect(menu.nameField.alignment == .left)
    #expect(!(menu.nameField.cell is CenteredTextFieldCell))
}
