import AppKit
import CrewCore
import Testing
@testable import CrewUI

@MainActor
private func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(descendants)
}

@MainActor
private func labels(in view: NSView) -> [NSTextField] {
    descendants(view).compactMap { $0 as? NSTextField }
}

@MainActor
private func textLeftEdge(_ field: NSTextField) -> CGFloat {
    let cell = field.cell ?? NSTextFieldCell()
    return field.frame.minX + cell.drawingRect(forBounds: field.bounds).minX
}

@Test @MainActor func dropdownHeaderRowsAndNameShareOneLeftEdge() throws {
    _ = NSApplication.shared
    let menu = ActionDropdown(title: "Scout", subtitle: "scout.md", items: [.init(title: "Copy prompt", action: {})], status: "Ready")
    let content = try #require(menu.panel.contentView)
    let subtitle = try #require(labels(in: content).first { $0.stringValue == "scout.md" })
    let rowLabel = try #require(labels(in: menu.rows[0]).first)
    #expect(abs(textLeftEdge(menu.nameField) - textLeftEdge(subtitle)) <= 0.5)
    #expect(abs(menu.rows[0].frame.minX + rowLabel.frame.minX - textLeftEdge(subtitle)) <= 0.5)
    #expect(menu.nameField.frame.minX == menu.rows[0].frame.minX)
    #expect(abs(menu.nameField.frame.midY - 28) <= 0.5)
    let status = try #require(labels(in: content).first { $0.stringValue == "Ready" })
    #expect(status.alignment == .right)
    #expect(status.frame.maxX == menu.rows[0].frame.maxX - 10)
    #expect(abs(status.frame.midY - menu.nameField.frame.midY) <= 0.5)
    #expect(menu.nameField.lineBreakMode == .byTruncatingTail)
    let island = ActionDropdown(title: "Crew", subtitle: "Markdown agent shelf", items: [.init(title: "Hide Crew", action: {})])
    let islandContent = try #require(island.panel.contentView)
    let islandSubtitle = try #require(labels(in: islandContent).first { $0.stringValue == "Markdown agent shelf" })
    #expect(abs(textLeftEdge(island.nameField) - textLeftEdge(islandSubtitle)) <= 0.5)
    #expect(abs(island.nameField.frame.midY - 28) <= 0.5)
    for dropdown in [menu, island] {
        let last = try #require(dropdown.rows.last)
        #expect(dropdown.panel.frame.height - last.frame.maxY == 10)
    }
}

@Test @MainActor func renameKeepsSingleLineScrollingThenTruncatesAgain() throws {
    _ = NSApplication.shared
    let menu = ActionDropdown(title: "A rather long agent name that overflows", subtitle: "long.md",
                              items: [.init(title: "Copy prompt", action: {})], status: "Ready")
    menu.onRename = { $0 }
    menu.beginRename()
    #expect(menu.nameField.lineBreakMode == .byClipping)
    #expect(menu.nameField.cell?.isScrollable == true)
    #expect(menu.cancelRename())
    #expect(menu.nameField.lineBreakMode == .byTruncatingTail)
}

@Test @MainActor func editorColumnsAndInsetsLineUp() throws {
    _ = NSApplication.shared
    let editor = PromptEditor()
    let content = try #require(editor.panel.contentView)
    let all = labels(in: content)
    let fileLabel = try #require(all.first { $0.stringValue == "FILE NAME" })
    let faceLabel = try #require(all.first { $0.stringValue == "FACE" })
    let promptLabel = try #require(all.first { $0.stringValue == "PROMPT" })
    let field = try #require(editor.prompt.enclosingScrollView?.superview as? PromptField)
    #expect(fileLabel.frame.minX == editor.filename.frame.minX)
    #expect(faceLabel.frame.minX == editor.mascotChoice.button.frame.minX)
    #expect(faceLabel.frame.minY == fileLabel.frame.minY)
    #expect(editor.mascotChoice.button.frame.maxX == field.frame.maxX)
    #expect(editor.mascotChoice.button.frame.minY == editor.filename.frame.minY)
    #expect(editor.filename.frame.minY - fileLabel.frame.maxY == field.frame.minY - promptLabel.frame.maxY)
    #expect(editor.saveButton.frame.maxX == field.frame.maxX)
    let filenameText = textLeftEdge(editor.filename)
    let scroll = try #require(editor.prompt.enclosingScrollView)
    let promptText = field.frame.minX + scroll.frame.minX + editor.prompt.textContainerOrigin.x
        + (editor.prompt.textContainer?.lineFragmentPadding ?? 0)
    #expect(abs(filenameText - promptText) <= 0.5)
    let heading = try #require(all.first { $0.stringValue == "New agent" })
    let format = try #require(all.first { $0.stringValue == "Markdown" })
    let close = try #require(descendants(content).compactMap { $0 as? ActionButton }.first { $0.title == "×" })
    #expect(abs(heading.frame.midY - close.frame.midY) <= 1)
    #expect(abs(format.frame.midY - close.frame.midY) <= 1)
    #expect(format.alignment == .right)
    #expect(close.frame.maxX == field.frame.maxX)
    let footer = try #require(all.first { $0.stringValue == "Saved in your Crew library" })
    #expect(abs(footer.frame.midY - editor.saveButton.frame.midY) <= 1)
    #expect(editor.panel.frame.height - editor.saveButton.frame.maxY == heading.frame.minX)
}

@Test @MainActor func templatePickerUsesOneGutterForRowsAndFooter() throws {
    _ = NSApplication.shared
    let templates = MascotKind.allCases.map { AgentTemplate(name: $0.rawValue.capitalized, filename: "\($0.rawValue).md", mascot: $0) }
    let picker = TemplatePicker(templates: templates, directory: URL(fileURLWithPath: "/tmp/templates"), canAdd: true,
                                choose: { _ in }, create: {}, openFolder: {})
    let content = try #require(picker.panel.contentView)
    let scroll = try #require(descendants(content).compactMap { $0 as? NSScrollView }.first)
    let buttons = descendants(content).compactMap { $0 as? ActionButton }
    let rows = buttons.filter { $0.isDescendant(of: scroll) }
    let footer = buttons.filter { !$0.isDescendant(of: scroll) }
    #expect(rows.count == templates.count)
    #expect(footer.count == 2)
    let title = try #require(labels(in: content).first { $0.stringValue == "Add an agent" })
    for row in rows {
        let mascot = try #require(row.subviews.compactMap { $0 as? MascotView }.first)
        #expect(scroll.frame.minX + row.frame.minX + mascot.frame.minX == title.frame.minX)
        #expect(abs(mascot.frame.midY - row.bounds.midY) <= 1)
        let texts = labels(in: row)
        #expect(texts.count == 2)
        let block = texts.map(\.frame).reduce(NSRect.null) { $0.union($1) }
        #expect(abs(block.midY - row.bounds.midY) <= 1.5)
        #expect(texts.allSatisfy { $0.frame.minX == mascot.frame.maxX + 11 })
    }
    for button in footer {
        #expect(button.frame.minX == scroll.frame.minX)
        #expect(button.frame.width == scroll.frame.width)
    }
    let bottom = try #require(footer.map(\.frame.maxY).max())
    #expect(picker.panel.frame.height - bottom == 12)
}

@Test @MainActor func faceChoicesAlignMascotNameAndCheckmark() throws {
    _ = NSApplication.shared
    let editor = PromptEditor()
    editor.mascotChoice.select(.patch)
    editor.mascotChoice.show()
    let panel = try #require(editor.mascotChoice.dropdown)
    for row in editor.mascotChoice.rows {
        let mascot = try #require(row.subviews.compactMap { $0 as? MascotView }.first)
        let name = try #require(labels(in: row).first { $0.stringValue != "✓" })
        #expect(mascot.frame.minX == 10)
        #expect(name.frame.minX == mascot.frame.maxX + 11)
        #expect(abs(name.frame.midY - row.bounds.midY) <= 1)
        if let check = labels(in: row).first(where: { $0.stringValue == "✓" }) {
            #expect(check.alignment == .right)
            #expect(check.frame.maxX == row.bounds.maxX - 10)
            #expect(row.selected)
        }
    }
    let last = try #require(editor.mascotChoice.rows.last)
    #expect(panel.frame.height - last.frame.maxY == 10)
    #expect(panel.entranceOrigin.y == 1 || panel.entranceOrigin.y == 0)
    editor.mascotChoice.close(restoreFocus: false, animated: false)
}

@Test @MainActor func hoverAndPopupMotionRunAsCompositorAnimations() throws {
    _ = NSApplication.shared
    let agent = Agent(id: UUID(), name: "Scout", filename: "scout.md", prompt: "Prompt", mascot: .scout,
                      fileURL: URL(fileURLWithPath: "/tmp/scout.md"))
    let cell = AgentCell(agent: agent, readPrompt: { "Prompt" })
    let enter = try #require(NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0,
                                                   windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
    cell.mouseEntered(with: enter)
    let mascotLayer = try #require(cell.mascot.layer)
    if Motion.reduced {
        #expect(CATransform3DIsIdentity(mascotLayer.transform))
    } else {
        #expect(!CATransform3DIsIdentity(mascotLayer.transform))
        #expect(mascotLayer.animation(forKey: "transform") is CASpringAnimation)
        #expect(cell.layer?.animation(forKey: "backgroundColor") != nil)
        cell.animateArrival()
        #expect(cell.layer?.animation(forKey: "arriveScale") is CASpringAnimation)
        #expect(cell.layer?.animation(forKey: "arriveOpacity")?.fillMode == .backwards)
    }
    let exit = try #require(NSEvent.enterExitEvent(with: .mouseExited, location: .zero, modifierFlags: [], timestamp: 0,
                                                  windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil))
    cell.mouseExited(with: exit)
    #expect(CATransform3DIsIdentity(mascotLayer.transform))
    let panel = CrewPanel(size: NSSize(width: 324, height: 200), cornerRadius: 28)
    panel.entranceOrigin = CGPoint(x: 0.85, y: 1)
    panel.animateEntrance()
    if !panel.reduceMotion {
        let spring = try #require(panel.contentView?.layer?.animation(forKey: "popupScale") as? CASpringAnimation)
        #expect(spring.duration == spring.settlingDuration)
        let start = try #require((spring.fromValue as? NSValue)?.caTransform3DValue)
        // Scaling about the top-right corner keeps that corner in place: its image is the corner itself.
        let corner = CGPoint(x: 324 * 0.85, y: 200)
        let affine = CATransform3DGetAffineTransform(start)
        let moved = corner.applying(affine)
        #expect(abs(moved.x - corner.x) <= 0.01)
        #expect(moved.y > corner.y)
    }
}
