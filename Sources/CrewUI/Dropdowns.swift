import AppKit
import CrewCore

@MainActor
func connectDropdownRows(_ rows: [ActionButton]) {
    guard !rows.isEmpty else { return }
    for (index, row) in rows.enumerated() {
        row.nextKeyView = rows[(index + 1) % rows.count]
        row.onArrow = { [weak row] keyCode in
            guard let row else { return }
            let forward = keyCode == 125 || keyCode == 124
            var candidate = forward ? row.nextKeyView : row.previousKeyView
            while let target = candidate, target !== row {
                if let button = target as? ActionButton, button.isEnabled {
                    row.window?.makeFirstResponder(button)
                    return
                }
                candidate = forward ? target.nextKeyView : target.previousKeyView
            }
        }
    }
}

@MainActor
final class ActionDropdown: NSObject, NSTextFieldDelegate {
    struct Item {
        let title: String
        var enabled = true
        let action: () -> Void
    }
    let panel: CrewPanel
    let rows: [ActionButton]
    let nameField = RenameNameField(labelWithString: "")
    let renameMessage = NSTextField(wrappingLabelWithString: "")
    private var committedName: String
    private var renaming = false
    private var savingName = false
    private(set) var renameTask: Task<Void, Never>?
    var onRename: ((String) async throws -> String)?

    init(title: String, subtitle: String, items: [Item], status: String? = nil) {
        committedName = title
        let rowsTop: CGFloat = status == nil ? 76 : 96
        panel = CrewPanel(size: NSSize(width: 324, height: rowsTop + CGFloat(items.count) * 38 + 8), cornerRadius: 28)
        panel.title = "\(title) actions"
        rows = items.enumerated().map { index, item in
            let row = ActionButton("", frame: NSRect(x: 10, y: rowsTop + CGFloat(index) * 38, width: 304, height: 36))
            row.addSubview(label(item.title, frame: NSRect(x: 10, y: 9, width: 284, height: 18), weight: .medium))
            row.isEnabled = item.enabled
            row.setAccessibilityLabel(item.title)
            row.onPress = item.action
            return row
        }
        super.init()
        guard let view = panel.contentView else { return }
        if status != nil { nameField.cell = CenteredTextFieldCell(textCell: title) }
        nameField.isEditable = false
        nameField.isSelectable = false
        nameField.isBezeled = false
        nameField.isBordered = false
        nameField.drawsBackground = false
        nameField.alignment = .left
        nameField.stringValue = title
        nameField.font = .systemFont(ofSize: 14, weight: .semibold)
        nameField.textColor = .white
        nameField.focusRingType = .none
        nameField.lineBreakMode = .byTruncatingTail
        // Header text shares a 20-point left edge. The renameable name sits in a 10-point-inset box so its
        // outline, once editing starts, lines up with the action rows below it.
        if status != nil {
            nameField.frame = NSRect(x: 10, y: 14, width: 213, height: 28)
        } else {
            let height = ceil(nameField.intrinsicContentSize.height)
            nameField.frame = NSRect(x: 20, y: 28 - height / 2, width: 284, height: height)
        }
        nameField.delegate = self
        nameField.onRename = { [weak self] in self?.beginRename() }
        nameField.setAccessibilityLabel(title)
        view.addSubview(nameField)
        if let status {
            let badge = label(status, frame: NSRect(x: 228, y: 19, width: 76, height: 18), size: 10, color: .lightGray)
            badge.alignment = .right
            view.addSubview(badge)
            nameField.toolTip = "Double-click to rename. Or focus the name and press Return."
            nameField.setAccessibilityHelp(nameField.toolTip)
            renameMessage.stringValue = "Double-click name to rename"
            renameMessage.frame = NSRect(x: 20, y: 62, width: 284, height: 28)
            renameMessage.font = .systemFont(ofSize: 9)
            renameMessage.textColor = .lightGray
            view.addSubview(renameMessage)
        }
        view.addSubview(label(subtitle, frame: NSRect(x: 20, y: 44, width: 284, height: 17), size: 10, color: .lightGray))
        rows.forEach(view.addSubview)
        connectDropdownRows(rows)
        if status != nil {
            nameField.nextKeyView = rows.first
            rows.last?.nextKeyView = nameField
            nameField.setAccessibilityRole(.button)
        }
    }
    func focusFirstItem() { panel.makeFirstResponder(rows.first { $0.isEnabled }) }

    func beginRename() {
        guard onRename != nil, !savingName else { return }
        renaming = true
        nameField.isEditable = true
        nameField.isSelectable = true
        nameField.isBezeled = false
        nameField.isBordered = false
        nameField.backgroundColor = .black
        nameField.drawsBackground = true
        nameField.lineBreakMode = .byClipping
        nameField.cell?.isScrollable = true
        styleOutlinedField(nameField)
        setFieldFocused(nameField, true)
        renameMessage.stringValue = "Return to save · Escape to cancel"
        renameMessage.textColor = .lightGray
        panel.makeFirstResponder(nameField)
        nameField.selectText(nil)
    }

    @discardableResult func cancelRename() -> Bool {
        guard renaming, !savingName else { return false }
        finishRename(committedName)
        return true
    }

    private func finishRename(_ name: String) {
        committedName = name
        renaming = false
        nameField.stringValue = name
        nameField.isEditable = false
        nameField.isSelectable = false
        nameField.isBezeled = false
        nameField.drawsBackground = false
        nameField.lineBreakMode = .byTruncatingTail
        nameField.layer?.backgroundColor = NSColor.clear.cgColor
        nameField.layer?.borderWidth = 0
        nameField.layer?.cornerRadius = 0
        nameField.layer?.masksToBounds = false
        nameField.setAccessibilityLabel(name)
        panel.title = "\(name) actions"
        renameMessage.stringValue = "Double-click name to rename"
        renameMessage.textColor = .lightGray
        focusFirstItem()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { return cancelRename() }
        guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
        guard renaming, !savingName, let onRename else { return true }
        let draft = nameField.stringValue
        savingName = true
        nameField.isEditable = false
        renameTask = Task { [weak self] in
            defer { self?.renameTask = nil }
            do {
                let name = try await onRename(draft)
                guard let self else { return }
                self.savingName = false
                self.finishRename(name)
            } catch {
                guard let self else { return }
                self.savingName = false
                self.nameField.isEditable = true
                self.renameMessage.stringValue = error.localizedDescription
                self.renameMessage.toolTip = error.localizedDescription
                self.renameMessage.textColor = .systemOrange
                self.panel.makeFirstResponder(self.nameField)
                NSAccessibility.post(element: self.renameMessage, notification: .valueChanged)
            }
        }
        return true
    }
}

@MainActor
final class FaceSelector {
    let button = ActionButton("", frame: .zero, filled: true)
    private(set) var selected: MascotKind = MascotKind.allCases[0]
    private(set) var dropdown: CrewPanel?
    private(set) var rows: [ActionButton] = []
    private var localMonitor: Any?
    private var globalMonitor: Any?
    var isEnabled: Bool {
        get { button.isEnabled }
        set { button.isEnabled = newValue; if !newValue { close() } }
    }

    init() {
        button.baseFill = .black
        button.outlined = true
        button.layer?.borderWidth = 1
        button.layer?.borderColor = NSColor(white: 0.28, alpha: 1).cgColor
        button.onPress = { [weak self] in self?.toggle() }
        button.onArrow = { [weak self] _ in self?.show() }
        button.setAccessibilityRole(.popUpButton)
        button.setAccessibilityLabel("Agent face")
        button.setAccessibilityHelp("Choose a face. Use arrow keys to move and Return to select.")
        updateButton()
    }
    func select(_ kind: MascotKind) {
        selected = kind
        updateButton()
        NSAccessibility.post(element: button, notification: .valueChanged)
        close()
    }
    private func updateButton() {
        button.subviews.forEach { $0.removeFromSuperview() }
        let mascot = MascotView(kind: selected, frame: .zero)
        let name = label(selected.rawValue.capitalized, frame: .zero, size: 11)
        name.alignment = .left
        name.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let chevron = label("⌄", frame: .zero, size: 12, color: .lightGray)
        chevron.alignment = .center
        let group = NSStackView(views: [mascot, name, chevron])
        group.orientation = .horizontal
        group.alignment = .centerY
        group.spacing = 7
        group.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(group)
        NSLayoutConstraint.activate([
            mascot.widthAnchor.constraint(equalToConstant: 26),
            mascot.heightAnchor.constraint(equalToConstant: 26),
            chevron.widthAnchor.constraint(equalTo: mascot.widthAnchor),
            group.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 10),
            group.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -10),
            group.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])
        button.setAccessibilityValue(selected.rawValue.capitalized)
    }
    func toggle() { if dropdown == nil { show() } else { close() } }
    func show() {
        guard isEnabled, dropdown == nil, let parent = button.window else { return }
        let panel = CrewPanel(size: NSSize(width: 204, height: CGFloat(MascotKind.allCases.count) * 43 + 18), cornerRadius: 22)
        panel.title = "Agent face choices"
        dropdown = panel
        rows = MascotKind.allCases.enumerated().map { index, kind in
            let row = ActionButton("", frame: NSRect(x: 10, y: 10 + CGFloat(index) * 43, width: 184, height: 41))
            row.addSubview(MascotView(kind: kind, frame: NSRect(x: 10, y: 5, width: 30, height: 30)))
            row.addSubview(label(kind.rawValue.capitalized, frame: NSRect(x: 51, y: 12, width: 98, height: 18), size: 12))
            row.selected = kind == selected
            if row.selected {
                let check = label("✓", frame: NSRect(x: 150, y: 12, width: 24, height: 18))
                check.alignment = .right
                row.addSubview(check)
            }
            row.setAccessibilityLabel(kind.rawValue.capitalized)
            row.setAccessibilityValue(kind == selected ? "Selected" : "")
            row.onPress = { [weak self] in self?.select(kind) }
            panel.contentView?.addSubview(row)
            return row
        }
        connectDropdownRows(rows)
        let anchor = parent.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? parent.frame
        let frame = ShelfLayout.popup(size: panel.frame.size, shelf: anchor, screen: screen)
        panel.setFrame(frame, display: true)
        panel.entranceOrigin = CGPoint(x: 0.5, y: frame.midY < anchor.midY ? 1 : 0)
        parent.addChildWindow(panel, ordered: .above)
        panel.onEscape = { [weak self] in self?.close() }
        panel.makeKeyAndOrderFront(nil)
        panel.animateEntrance()
        panel.makeFirstResponder(rows.first { $0.selected })
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let panel = self.dropdown, event.window !== panel else { return }
                if event.window === self.button.window,
                   self.button.convert(self.button.bounds, to: nil).contains(event.locationInWindow) { return }
                self.close(restoreFocus: false)
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close(restoreFocus: false) }
        }
    }
    func close(restoreFocus: Bool = true, animated: Bool = true) {
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        guard let panel = dropdown else { return }
        dropdown = nil
        rows = []
        let parent = panel.parent
        panel.dismiss(animated: animated)
        if restoreFocus { parent?.makeKey(); parent?.makeFirstResponder(button) }
    }
}

@MainActor
final class RenameNameField: NSTextField {
    var onRename: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) {
        if !isEditable {
            if event.clickCount == 2 { onRename?() }
            else { window?.makeFirstResponder(self) }
        } else { super.mouseDown(with: event) }
    }
    override func keyDown(with event: NSEvent) {
        if !isEditable, event.keyCode == 36 { onRename?() }
        else { super.keyDown(with: event) }
    }
    override func accessibilityPerformPress() -> Bool { onRename?(); return onRename != nil }
}
