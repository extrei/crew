import AppKit
import CrewCore
import Testing
@testable import CrewUI

@MainActor
private func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(descendants)
}

@MainActor
private func hoverEvent() -> NSEvent {
    NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
                          windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!
}

@Test @MainActor func templateAndFooterButtonsRespondToRealHoverCallbacks() throws {
    _ = NSApplication.shared
    let template = AgentTemplate(name: "Scout", filename: "scout.md", mascot: .scout)
    let picker = TemplatePicker(templates: [template], directory: URL(fileURLWithPath: "/tmp/templates"), canAdd: true,
                                choose: { _ in }, create: {}, openFolder: {})
    let buttons = descendants(try #require(picker.panel.contentView)).compactMap { $0 as? ActionButton }
    #expect(buttons.count == 3)
    for button in buttons {
        let original = try #require(button.layer?.backgroundColor)
        button.mouseEntered(with: hoverEvent())
        #expect(button.isHovered)
        #expect(button.layer?.backgroundColor != original)
        button.mouseExited(with: hoverEvent())
        #expect(!button.isHovered)
        #expect(button.layer?.backgroundColor == original)
        button.isEnabled = false
        button.mouseEntered(with: hoverEvent())
        #expect(!button.isHovered)
        #expect(button.layer?.backgroundColor == original)
    }
}

@Test @MainActor func actionDropdownPreservesCommandsAndUnavailableActions() throws {
    _ = NSApplication.shared
    var commands: [String] = []
    let menu = ActionDropdown(title: "Scout", subtitle: "scout.md", items: [
        .init(title: "Copy prompt", action: { commands.append("copy") }),
        .init(title: "Open Markdown file", enabled: false, action: { commands.append("open") }),
        .init(title: "Remove from shelf", action: { commands.append("remove") })
    ])
    #expect(menu.panel.contentView?.layer?.backgroundColor == NSColor.black.cgColor)
    #expect(menu.rows.map { $0.accessibilityLabel() } == ["Copy prompt", "Open Markdown file", "Remove from shelf"])
    #expect(menu.rows[0].accessibilityPerformPress())
    #expect(!menu.rows[1].accessibilityPerformPress())
    #expect(menu.rows[2].accessibilityPerformPress())
    #expect(commands == ["copy", "remove"])
    menu.panel.dismiss(animated: false)
    menu.rows[0].performClick(nil)
    #expect(commands == ["copy", "remove"])
}

@Test @MainActor func editorFieldsShareOutlineAndKeepNativeTextBehavior() throws {
    _ = NSApplication.shared
    let editor = PromptEditor()
    let scroll = try #require(editor.prompt.enclosingScrollView)
    let outline = try #require(scroll.superview as? PromptField)
    for field in [editor.filename as NSView, outline] {
        #expect(field.layer?.backgroundColor == NSColor.black.cgColor)
        #expect(field.layer?.borderWidth == 1)
        #expect(field.layer?.cornerRadius == 12)
    }
    #expect(editor.filename.alignment == .left)
    #expect(!editor.filename.isBezeled)
    #expect(editor.filename.focusRingType == .none)
    #expect(editor.panel.makeFirstResponder(editor.filename))
    editor.filename.selectText(nil)
    let fieldEditor = try #require(editor.filename.currentEditor() as? NSTextView)
    #expect(editor.panel.firstResponder === fieldEditor)
    #expect(fieldEditor.alignment == .left)
    #expect(fieldEditor.selectedRange().length == editor.filename.stringValue.utf16.count)
    #expect(editor.filename.layer?.borderWidth == 1.5)
    #expect(editor.filename.layer?.borderColor == NSColor(white: 0.58, alpha: 1).cgColor)
    #expect(editor.panel.makeFirstResponder(nil))
    #expect(editor.filename.layer?.borderWidth == 1)
    #expect(editor.filename.layer?.borderColor == NSColor(white: 0.28, alpha: 1).cgColor)
    #expect(editor.prompt.alignment == .left)
    #expect(editor.prompt.backgroundColor == .black)
    #expect(editor.prompt.textContainerInset.width >= 8)
    #expect(editor.prompt.textContainerInset.height >= 8)
    #expect(editor.panel.makeFirstResponder(editor.prompt))
    #expect(outline.layer?.borderWidth == 1.5)
    #expect(editor.panel.makeFirstResponder(editor.mascotChoice.button))
    #expect(outline.layer?.borderWidth == 1)
    #expect(editor.prompt.isSelectable)
    #expect(editor.prompt.allowsUndo)
    #expect(scroll.hasVerticalScroller)
}

@Test @MainActor func selectedCustomFaceReachesSaveAndDisabledSelectorCannotOpen() throws {
    _ = NSApplication.shared
    let editor = PromptEditor()
    let selected = try #require(MascotKind.allCases.last)
    editor.mascotChoice.select(selected)
    #expect(editor.mascotChoice.button.accessibilityValue() as? String == selected.rawValue.capitalized)
    #expect(descendants(editor.mascotChoice.button).contains { $0 is MascotView })
    var saved: MascotKind?
    editor.onSave = { _, _, face in saved = face }
    let content = try #require(editor.panel.contentView)
    let save = try #require(descendants(content).compactMap { $0 as? ActionButton }.first { $0.title == "Add to the bar ↗" })
    save.performClick(nil)
    #expect(saved == selected)
    editor.setSaving(true)
    editor.mascotChoice.show()
    #expect(editor.mascotChoice.dropdown == nil)
    #expect(!editor.filename.isEnabled)
    #expect(!editor.prompt.isEditable)
}

@Test @MainActor func panelAnimationReopensAfterDismissAndResetsHover() throws {
    _ = NSApplication.shared
    let panel = CrewPanel(size: NSSize(width: 324, height: 260), cornerRadius: 28)
    let button = ActionButton("Action", frame: NSRect(x: 10, y: 10, width: 100, height: 30))
    panel.contentView?.addSubview(button)
    button.mouseEntered(with: hoverEvent())
    panel.animateEntrance()
    if !panel.reduceMotion {
        #expect(panel.contentView?.layer?.animation(forKey: "popupScale") is CASpringAnimation)
        #expect(panel.contentView?.layer?.animation(forKey: "popupOpacity") != nil)
    }
    panel.dismiss(animated: false)
    #expect(panel.isDismissing)
    #expect(!button.isHovered)
    panel.animateEntrance()
    #expect(!panel.isDismissing)
    #expect(panel.contentView?.layer?.opacity == 1)
    #expect(CATransform3DIsIdentity(try #require(panel.contentView?.layer?.transform)))
}

@Test @MainActor func actionDropdownKeyboardSkipsDisabledRowsAndActivatesSelection() throws {
    _ = NSApplication.shared
    var activated = false
    let menu = ActionDropdown(title: "Scout", subtitle: "scout.md", items: [
        .init(title: "Copy prompt", action: {}),
        .init(title: "Open Markdown file", enabled: false, action: {}),
        .init(title: "Remove from shelf", action: { activated = true })
    ])
    menu.focusFirstItem()
    #expect(menu.panel.firstResponder === menu.rows[0])
    let down = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                          windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 125))
    menu.rows[0].keyDown(with: down)
    #expect(menu.panel.firstResponder === menu.rows[2])
    let enter = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                           windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
    menu.rows[2].keyDown(with: enter)
    #expect(activated)
}

@Test @MainActor func promptOutlineSurvivesNativeDisplayAndFocusChanges() throws {
    _ = NSApplication.shared
    let editor = PromptEditor()
    let content = try #require(editor.panel.contentView)
    let scroll = try #require(editor.prompt.enclosingScrollView)
    let outline = try #require(scroll.superview as? PromptField)
    func displayNativeControls() throws {
        content.layoutSubtreeIfNeeded()
        descendants(content).forEach { $0.needsDisplay = true }
        CATransaction.flush()
        content.displayIfNeeded()
        let bitmap = try #require(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: bitmap)
    }
    try displayNativeControls()
    #expect(outline.layer?.borderWidth == 1)
    #expect(outline.layer?.borderColor == NSColor(white: 0.28, alpha: 1).cgColor)
    #expect(editor.panel.makeFirstResponder(editor.prompt))
    try displayNativeControls()
    #expect(outline.layer?.borderWidth == 1.5)
    #expect(outline.layer?.borderColor == NSColor(white: 0.58, alpha: 1).cgColor)
    #expect(editor.panel.makeFirstResponder(editor.filename))
    try displayNativeControls()
    #expect(outline.layer?.borderWidth == 1)
    #expect(outline.layer?.borderColor == NSColor(white: 0.28, alpha: 1).cgColor)
}
