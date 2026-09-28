import AppKit
import CrewCore

@MainActor
final class CrewPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onMoveEnded: (() -> Void)?
    /// Unit point, from the bottom-left corner, that popup transitions grow out of and shrink back toward.
    /// Callers set it to the edge that faces the control which opened the panel.
    var entranceOrigin = CGPoint(x: 0.5, y: 0.5)
    private(set) var isDraggingIsland = false

    func dragIsland(with event: NSEvent) {
        isDraggingIsland = true
        performDrag(with: event)
        isDraggingIsland = false
        onMoveEnded?()
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(size: NSSize, cornerRadius: CGFloat, nonactivating: Bool = false) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: nonactivating ? [.borderless, .nonactivatingPanel] : [.borderless],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        appearance = NSAppearance(named: .darkAqua)
        let content = RoundedBackground(frame: NSRect(origin: .zero, size: size))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.cgColor
        content.layer?.cornerRadius = cornerRadius
        content.layer?.borderColor = NSColor(white: 0.19, alpha: 1).cgColor
        content.layer?.borderWidth = 1
        contentView = content
    }

    override func cancelOperation(_ sender: Any?) { onEscape?() }

    private(set) var isDismissing = false
    private var animationGeneration = 0
    var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func animateEntrance() {
        animationGeneration += 1
        isDismissing = false
        guard let layer = contentView?.layer else { return }
        let interrupted = layer.animation(forKey: "popupOpacity") != nil
        let opacity = interrupted ? (layer.presentation()?.opacity ?? layer.opacity) : 0
        let transform = interrupted ? (layer.presentation()?.transform ?? layer.transform) : popupTransform(scale: 0.94, slide: 10)
        layer.removeAllAnimations()
        layer.opacity = 1
        layer.transform = CATransform3DIdentity
        guard !reduceMotion else { return }
        let scale = CASpringAnimation(keyPath: "transform")
        scale.fromValue = NSValue(caTransform3D: transform)
        scale.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        scale.mass = 1
        scale.stiffness = 380
        scale.damping = 30
        scale.duration = scale.settlingDuration
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = opacity
        fade.toValue = 1
        fade.duration = 0.18
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(scale, forKey: "popupScale")
        layer.add(fade, forKey: "popupOpacity")
    }

    func dismiss(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard !isDismissing else { return }
        animationGeneration += 1
        let generation = animationGeneration
        isDismissing = true
        resetHover(in: contentView)
        guard animated, isVisible, !reduceMotion, let layer = contentView?.layer else {
            parent?.removeChildWindow(self)
            orderOut(nil)
            completion?()
            return
        }
        let opacity = layer.presentation()?.opacity ?? 1
        let transform = layer.presentation()?.transform ?? CATransform3DIdentity
        let target = popupTransform(scale: 0.96, slide: 6)
        layer.removeAllAnimations()
        CATransaction.begin()
        CATransaction.setCompletionBlock { [self] in
            MainActor.assumeIsolated {
                guard animationGeneration == generation, isDismissing else { return }
                parent?.removeChildWindow(self)
                orderOut(nil)
                completion?()
            }
        }
        let scale = CABasicAnimation(keyPath: "transform")
        scale.fromValue = NSValue(caTransform3D: transform)
        scale.toValue = NSValue(caTransform3D: target)
        scale.duration = 0.14
        scale.timingFunction = CAMediaTimingFunction(name: .easeIn)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = opacity
        fade.toValue = 0
        fade.duration = 0.14
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        layer.opacity = 0
        layer.transform = target
        layer.add(scale, forKey: "popupScale")
        layer.add(fade, forKey: "popupOpacity")
        CATransaction.commit()
    }

    private func resetHover(in view: NSView?) {
        (view as? ActionButton)?.setHovered(false)
        view?.subviews.forEach { resetHover(in: $0) }
    }

    /// Scales about `entranceOrigin` and slides toward that edge. The root layer anchors at its bottom-left corner.
    private func popupTransform(scale: CGFloat, slide: CGFloat) -> CATransform3D {
        let origin = CGPoint(x: frame.width * entranceOrigin.x, y: frame.height * entranceOrigin.y)
        let offset = (entranceOrigin.y - 0.5) * 2 * slide
        return CATransform3DMakeAffineTransform(CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                                               tx: origin.x * (1 - scale), ty: origin.y * (1 - scale) + offset))
    }

    override func sendEvent(_ event: NSEvent) {
        guard !isDismissing else { return }
        super.sendEvent(event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?() } else { super.keyDown(with: event) }
    }
}

@MainActor
final class RoundedBackground: NSView {
    var movesIsland = false
    var onContextMenu: (() -> Void)?
    override func rightMouseDown(with event: NSEvent) { onContextMenu?() }
    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if movesIsland, !event.modifierFlags.contains(.control) { (window as? CrewPanel)?.dragIsland(with: event) }
        else if event.modifierFlags.contains(.control), let onContextMenu { onContextMenu() }
        else { super.mouseDown(with: event) }
    }

    override func resetCursorRects() {
        if movesIsland { addCursorRect(bounds, cursor: .openHand) }
    }
}

@MainActor
final class GripView: NSView {
    var onContextMenu: (() -> Void)?
    override func rightMouseDown(with event: NSEvent) { onContextMenu?() }
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.5, alpha: 1).setFill()
        for x in [CGFloat(3), 8] {
            for y in [CGFloat(22), 27, 32] {
                NSBezierPath(ovalIn: CGRect(x: x, y: y, width: 2, height: 2)).fill()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { onContextMenu?() }
        else { (window as? CrewPanel)?.dragIsland(with: event) }
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
}

@MainActor
final class ActionButton: NSButton {
    var onPress: (() -> Void)?
    var onArrow: ((UInt16) -> Void)?
    var onHoverChange: ((Bool) -> Void)?
    var baseFill: NSColor = .clear { didSet { updateHighlight() } }
    var selected = false { didSet { updateHighlight() } }
    var outlined = false
    private(set) var isHovered = false
    private var tracking: NSTrackingArea?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { isEnabled }
    override var isEnabled: Bool {
        didSet { if !isEnabled { isHovered = false }; updateHighlight() }
    }

    init(_ title: String, frame: NSRect, filled: Bool = false) {
        super.init(frame: frame)
        self.title = title
        bezelStyle = .inline
        isBordered = false
        font = .systemFont(ofSize: 12, weight: .medium)
        contentTintColor = .white
        wantsLayer = true
        layer?.cornerRadius = 15
        baseFill = filled ? NSColor(white: 0.15, alpha: 1) : .clear
        updateHighlight()
        target = self
        action = #selector(pressed)
        focusRingType = .none
    }

    required init?(coder: NSCoder) { nil }
    @objc private func pressed() {
        guard isEnabled, (window as? CrewPanel)?.isDismissing != true else { return }
        onPress?()
    }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }
    func setHovered(_ hovered: Bool) {
        let wasHovered = isHovered
        isHovered = hovered && isEnabled
        updateHighlight()
        if wasHovered != isHovered { onHoverChange?(isHovered) }
    }
    private func updateHighlight() {
        guard let layer else { return }
        // Hover lifts the fill a fixed step above its resting shade so dark and mid-grey buttons brighten alike.
        let resting = baseFill.usingColorSpace(.genericGamma22Gray).map { $0.alphaComponent == 0 ? 0 : $0.whiteComponent } ?? 0
        let raised = NSColor(white: max(selected ? 0.18 : 0.12, resting + 0.09), alpha: 1)
        let fill = isEnabled && (isHovered || selected) ? raised : baseFill
        layer.backgroundColor = fill.cgColor
        layer.ease("backgroundColor", duration: 0.18)
        alphaValue = isEnabled ? 1 : 0.42
    }
    override func becomeFirstResponder() -> Bool {
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 0.6, alpha: 1).cgColor
        return true
    }
    override func resignFirstResponder() -> Bool {
        layer?.borderWidth = outlined ? 1 : 0
        layer?.borderColor = NSColor(white: 0.28, alpha: 1).cgColor
        return true
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 49: pressed()
        case 123...126:
            if let onArrow { onArrow(event.keyCode) }
            else if event.keyCode == 125 || event.keyCode == 124 { window?.selectNextKeyView(self) }
            else { window?.selectPreviousKeyView(self) }
        case 53: (window as? CrewPanel)?.onEscape?()
        default: super.keyDown(with: event)
        }
    }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        pressed()
        return true
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { setHovered(false) }
        super.viewWillMove(toWindow: newWindow)
    }
}

@MainActor
func label(_ text: String, frame: NSRect, size: CGFloat = 12, color: NSColor = .white,
           weight: NSFont.Weight = .regular) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.frame = frame
    field.font = .systemFont(ofSize: size, weight: weight)
    field.textColor = color
    field.lineBreakMode = .byTruncatingMiddle
    return field
}

@MainActor
final class TemplatePicker {
    let panel: CrewPanel

    init(templates: [AgentTemplate], directory: URL, canAdd: Bool,
         choose: @escaping (AgentTemplate) -> Void, create: @escaping () -> Void,
         openFolder: @escaping () -> Void) {
        let rowHeight: CGFloat = 58
        let listHeight = min(260, max(38, CGFloat(templates.count) * rowHeight))
        let listTop: CGFloat = 89
        panel = CrewPanel(size: NSSize(width: 324, height: listTop + listHeight + 92), cornerRadius: 28)
        panel.title = "Add an agent"
        guard let view = panel.contentView else { return }
        view.addSubview(label("Add an agent", frame: NSRect(x: 20, y: 16, width: 284, height: 21), size: 14, weight: .semibold))
        let path = directory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") + "/"
        view.addSubview(label(path, frame: NSRect(x: 20, y: 40, width: 284, height: 17), size: 10, color: .lightGray))
        view.addSubview(label(canAdd ? "LOCAL TEMPLATES" : "SHELF FULL · REMOVE AN AGENT TO ADD ONE", frame: NSRect(x: 20, y: 68, width: 284, height: 15), size: 9, color: .lightGray))
        let scroll = NSScrollView(frame: NSRect(x: 10, y: listTop, width: 304, height: listHeight))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = templates.count > 4
        scroll.autohidesScrollers = true
        let rowWidth = scroll.contentSize.width
        let list = RoundedBackground(frame: NSRect(x: 0, y: 0, width: rowWidth, height: max(listHeight, CGFloat(templates.count) * rowHeight)))
        if templates.isEmpty {
            list.addSubview(label("No .md templates yet", frame: NSRect(x: 10, y: 9, width: rowWidth - 20, height: 20), color: .lightGray))
        }
        var buttons: [ActionButton] = []
        for (index, template) in templates.enumerated() {
            let row = ActionButton("", frame: NSRect(x: 0, y: CGFloat(index) * rowHeight, width: rowWidth, height: rowHeight - 2))
            row.isEnabled = canAdd
            row.setAccessibilityLabel("Add \(template.name), \(template.filename)")
            let mascot = MascotView(kind: template.mascot, frame: NSRect(x: 10, y: 10, width: 35, height: 35))
            row.addSubview(mascot)
            row.addSubview(label(template.name, frame: NSRect(x: 56, y: 9, width: rowWidth - 66, height: 18), weight: .medium))
            row.addSubview(label(template.filename, frame: NSRect(x: 56, y: 29, width: rowWidth - 66, height: 16), size: 10, color: .lightGray))
            row.onPress = { choose(template) }
            list.addSubview(row)
            buttons.append(row)
        }
        scroll.documentView = list
        view.addSubview(scroll)
        let newButton = ActionButton("＋   Start with a new .md", frame: NSRect(x: 10, y: listTop + listHeight + 10, width: 304, height: 36), filled: true)
        newButton.onPress = create
        newButton.isEnabled = canAdd
        view.addSubview(newButton)
        let folder = ActionButton("Open templates folder ↗", frame: NSRect(x: 10, y: newButton.frame.maxY + 4, width: 304, height: 30))
        folder.contentTintColor = .lightGray
        folder.onPress = openFolder
        view.addSubview(folder)
        connectDropdownRows(buttons + [newButton, folder])
    }
}

@MainActor
enum PromptEditorMode {
    case create
    case edit(Agent)

    var isCreate: Bool { if case .create = self { true } else { false } }
}

@MainActor
final class PromptEditor {
    let mode: PromptEditorMode
    let panel = CrewPanel(size: NSSize(width: 448, height: 490), cornerRadius: 28)
    let filename = FilenameField("my-agent.md")
    let prompt = PromptTextView(frame: .zero)
    let mascotChoice = FaceSelector()
    let errorLabel = NSTextField(wrappingLabelWithString: "")
    let saveButton = ActionButton("Add to the bar ↗", frame: NSRect(x: 270, y: 432, width: 154, height: 34), filled: true)
    var onSave: ((String, String, MascotKind) -> Void)?
    var onClose: (() -> Void)?

    init(mode: PromptEditorMode = .create) {
        self.mode = mode
        let heading: String
        switch mode {
        case .create: heading = "New agent"
        case .edit(let agent):
            heading = agent.name
            filename.stringValue = agent.filename
            filename.isEditable = false
            mascotChoice.select(agent.mascot)
            mascotChoice.isEnabled = false
            saveButton.title = "Save Markdown"
        }
        panel.title = mode.isCreate ? heading : "Edit \(heading)"
        guard let view = panel.contentView else { return }
        view.addSubview(label(heading, frame: NSRect(x: 24, y: 21, width: 250, height: 22), size: 15, weight: .semibold))
        let format = label("Markdown", frame: NSRect(x: 290, y: 23, width: 94, height: 18), size: 11, color: .lightGray)
        format.alignment = .right
        view.addSubview(format)
        let close = ActionButton("×", frame: NSRect(x: 394, y: 17, width: 30, height: 30))
        close.font = .systemFont(ofSize: 21)
        close.setAccessibilityLabel("Close editor")
        close.onPress = { [weak self] in self?.onClose?() }
        view.addSubview(close)
        view.addSubview(label("FILE NAME", frame: NSRect(x: 24, y: 68, width: 260, height: 16), size: 10, color: .lightGray))
        filename.frame = NSRect(x: 24, y: 90, width: 260, height: 36)
        filename.setAccessibilityLabel("Markdown filename")
        view.addSubview(filename)
        view.addSubview(label("FACE", frame: NSRect(x: 296, y: 68, width: 128, height: 16), size: 10, color: .lightGray))
        mascotChoice.button.frame = NSRect(x: 296, y: 90, width: 128, height: 36)
        view.addSubview(mascotChoice.button)
        view.addSubview(label("PROMPT", frame: NSRect(x: 24, y: 148, width: 400, height: 16), size: 10, color: .lightGray))
        let promptField = PromptField(frame: NSRect(x: 24, y: 170, width: 400, height: 208))
        let scroll = promptField.scrollView
        prompt.frame = NSRect(origin: .zero, size: scroll.contentSize)
        prompt.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        prompt.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        prompt.isVerticallyResizable = true
        prompt.isHorizontallyResizable = false
        prompt.autoresizingMask = [.width]
        prompt.textContainer?.containerSize = NSSize(width: 380, height: CGFloat.greatestFiniteMagnitude)
        prompt.textContainer?.widthTracksTextView = true
        // No fragment padding: the 8-point inset alone lines the prompt up with the filename field's 10-point text inset.
        prompt.textContainer?.lineFragmentPadding = 0
        prompt.layoutManager?.allowsNonContiguousLayout = true
        prompt.textContainerInset = NSSize(width: 8, height: 8)
        prompt.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        prompt.textColor = NSColor(white: 0.88, alpha: 1)
        prompt.backgroundColor = .black
        prompt.alignment = .left
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        prompt.defaultParagraphStyle = paragraph
        prompt.insertionPointColor = .white
        prompt.isRichText = false
        prompt.allowsUndo = true
        prompt.isAutomaticQuoteSubstitutionEnabled = false
        prompt.isAutomaticDashSubstitutionEnabled = false
        prompt.isAutomaticSpellingCorrectionEnabled = false
        prompt.string = "# My agent\n\nYou are a thoughtful project partner.\n\n## Your job\nTurn a rough idea into a clear next step.\n\n## How you work\nBe curious. Be concise. Make it useful."
        if !mode.isCreate { prompt.string = "" }
        prompt.setAccessibilityLabel("Markdown prompt")
        scroll.documentView = prompt
        view.addSubview(promptField)
        errorLabel.frame = NSRect(x: 24, y: 388, width: 400, height: 32)
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemOrange
        view.addSubview(errorLabel)
        view.addSubview(label("Saved in your Crew library", frame: NSRect(x: 24, y: 440, width: 236, height: 18), size: 10, color: .lightGray))
        saveButton.onPress = { [weak self] in
            guard let self else { return }
            self.onSave?(self.filename.stringValue, self.prompt.string,
                         self.mascotChoice.selected)
        }
        view.addSubview(saveButton)
        panel.onEscape = { [weak self] in self?.onClose?() }
        filename.nextKeyView = mascotChoice.button
        mascotChoice.button.nextKeyView = prompt
        prompt.nextKeyView = saveButton
        saveButton.nextKeyView = close
        close.nextKeyView = filename
    }

    func dismiss(animated: Bool = true) {
        mascotChoice.close(restoreFocus: false, animated: false)
        prompt.breakUndoCoalescing()
        prompt.undoManager?.removeAllActions()
        prompt.inputContext?.discardMarkedText()
        panel.makeFirstResponder(nil)
        panel.endEditing(for: nil)
        panel.dismiss(animated: animated) { [prompt] in
            prompt.string = ""
            prompt.enclosingScrollView?.documentView = nil
        }
    }

    func setSaving(_ saving: Bool) {
        saveButton.isEnabled = !saving
        filename.isEnabled = !saving
        filename.isEditable = !saving && mode.isCreate
        mascotChoice.isEnabled = !saving && mode.isCreate
        prompt.isEditable = !saving
    }

    func setLoading() {
        setSaving(true)
        errorLabel.stringValue = "Loading Markdown…"
    }

    func loaded(_ markdown: String) {
        prompt.string = markdown
        prompt.undoManager?.removeAllActions()
        errorLabel.stringValue = ""
        setSaving(false)
        panel.makeFirstResponder(prompt)
    }

    func showLoadError(_ message: String) {
        errorLabel.stringValue = message
        errorLabel.toolTip = message
        setSaving(true)
    }

    func showError(_ message: String) {
        errorLabel.stringValue = message
        errorLabel.toolTip = message
        setSaving(false)
        NSAccessibility.post(element: errorLabel, notification: .valueChanged)
    }
}
