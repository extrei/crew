import AppKit
import CrewCore

extension DragPayload {
    static func prepare(fileURL: URL, readPrompt: @Sendable () async throws -> String) async throws -> DragPayload {
        try Task.checkCancellation()
        let markdown = try await readPrompt()
        try Task.checkCancellation()
        return DragPayload(fileURL: fileURL, markdown: markdown)
    }

    @MainActor
    public func pasteboardItem() -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(fileURL.absoluteString, forType: .fileURL)
        item.setString(markdown, forType: .string)
        return item
    }
}

@MainActor
final class AgentCell: NSControl, NSDraggingSource {
    let agent: Agent
    let mascot: MascotView
    var onPress: ((AgentCell) -> Void)?
    var onBeginDrag: (() -> Void)?
    var onDragError: ((Error) -> Void)?
    private let readPrompt: @Sendable () async throws -> String
    private var preparation: Task<Void, Never>?
    private var preparedPayload: DragPayload?
    private var pendingDragEvent: NSEvent?
    private var downPoint: NSPoint?
    private var didDrag = false
    private var tracking: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { false }

    init(agent: Agent, readPrompt: @escaping @Sendable () async throws -> String) {
        self.agent = agent
        self.readPrompt = readPrompt
        mascot = MascotView(kind: agent.mascot, frame: NSRect(x: 5, y: 3, width: 52, height: 52))
        super.init(frame: NSRect(x: 0, y: 0, width: 62, height: 62))
        wantsLayer = true
        layer?.cornerRadius = 28
        addSubview(mascot)
        let status = CALayer()
        status.frame = CGRect(x: 28.5, y: 56, width: 5, height: 5)
        status.cornerRadius = 2.5
        status.backgroundColor = (agent.isAvailable ? NSColor(white: 0.52, alpha: 1) : NSColor.systemOrange).cgColor
        layer?.addSublayer(status)
        let state = agent.isAvailable ? "Ready" : "Missing file"
        toolTip = "\(agent.name) · \(state)\n\(agent.filename)\nDrag to copy the file, or click for actions."
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("\(agent.name), \(state), \(agent.filename)")
        setAccessibilityHelp("Drag to copy this Markdown file. Press for copy prompt, open file, and remove actions.")
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        setHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHovered(false)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: agent.isAvailable ? .openHand : .arrow)
    }

    private func setHovered(_ hovered: Bool) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(hovered ? 0.055 : 0).cgColor
        layer?.ease("backgroundColor", duration: 0.2)
        mascot.layer?.transform = hovered && !Motion.reduced ? Self.lift(in: mascot.bounds) : CATransform3DIdentity
        mascot.layer?.spring("transform", stiffness: 300, damping: 22)
    }

    /// Raises the face 5 points with a small tilt and growth, scaled about its own center.
    private static func lift(in bounds: CGRect) -> CATransform3D {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let transform = CGAffineTransform(translationX: center.x, y: center.y - 5)
            .rotated(by: -7 * .pi / 180)
            .scaledBy(x: 1.07, y: 1.07)
            .translatedBy(x: -center.x, y: -center.y)
        return CATransform3DMakeAffineTransform(transform)
    }

    /// Grows in from a small, transparent dot once the island has started widening for it.
    func animateArrival() {
        guard let layer, !Motion.reduced else { return }
        let start = CACurrentMediaTime() + 0.08
        let grow = CASpringAnimation(keyPath: "transform")
        let shrunk = CGAffineTransform(translationX: bounds.midX * 0.6, y: bounds.midY * 0.6).scaledBy(x: 0.4, y: 0.4)
        grow.fromValue = NSValue(caTransform3D: CATransform3DMakeAffineTransform(shrunk))
        grow.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        grow.mass = 1
        grow.stiffness = 260
        grow.damping = 20
        grow.duration = grow.settlingDuration
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.22
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        for animation in [grow, fade] as [CAAnimation] {
            animation.beginTime = start
            animation.fillMode = .backwards
        }
        layer.add(grow, forKey: "arriveScale")
        layer.add(fade, forKey: "arriveOpacity")
    }

    override func becomeFirstResponder() -> Bool {
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 0.6, alpha: 1).cgColor
        return true
    }

    override func resignFirstResponder() -> Bool {
        layer?.borderWidth = 0
        return true
    }

    override func mouseDown(with event: NSEvent) {
        cancelPreparation()
        downPoint = convert(event.locationInWindow, from: nil)
        didDrag = false
        guard agent.isAvailable else { return }
        let fileURL = agent.fileURL
        let readPrompt = readPrompt
        preparation = Task { [weak self] in
            do {
                let payload = try await DragPayload.prepare(fileURL: fileURL, readPrompt: readPrompt)
                guard let self, !Task.isCancelled, self.downPoint != nil else { return }
                self.preparedPayload = payload
                if let event = self.pendingDragEvent { self.startDrag(with: event, payload: payload) }
            } catch is CancellationError {
                return
            } catch {
                guard let self, !Task.isCancelled, self.downPoint != nil else { return }
                self.didDrag = true
                self.onDragError?(error)
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didDrag, agent.isAvailable, let downPoint else { return }
        let current = convert(event.locationInWindow, from: nil)
        guard hypot(current.x - downPoint.x, current.y - downPoint.y) >= 5 else { return }
        pendingDragEvent = event
        if let preparedPayload { startDrag(with: event, payload: preparedPayload) }
    }

    private func startDrag(with event: NSEvent, payload: DragPayload) {
        didDrag = true
        pendingDragEvent = nil
        onBeginDrag?()
        let item = NSDraggingItem(pasteboardWriter: payload.pasteboardItem())
        let image = NSImage(size: bounds.size)
        if let rep = bitmapImageRepForCachingDisplay(in: bounds) {
            cacheDisplay(in: bounds, to: rep)
            image.addRepresentation(rep)
        }
        item.setDraggingFrame(bounds, contents: image)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) {
        let wasClick = !didDrag && pendingDragEvent == nil
        cancelPreparation()
        downPoint = nil
        guard wasClick, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPress?(self)
    }

    private func cancelPreparation() {
        preparation?.cancel()
        preparation = nil
        preparedPayload = nil
        pendingDragEvent = nil
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { cancelPreparation(); downPoint = nil }
        super.viewWillMove(toWindow: newWindow)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 49: onPress?(self)
        case 123: window?.selectPreviousKeyView(self)
        case 124: window?.selectNextKeyView(self)
        default: super.keyDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        onPress?(self)
        return true
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
}
