import AppKit

@MainActor
func styleOutlinedField(_ view: NSView) {
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.black.cgColor
    view.layer?.cornerRadius = 12
    view.layer?.borderWidth = 1
    view.layer?.borderColor = NSColor(white: 0.28, alpha: 1).cgColor
    view.layer?.masksToBounds = true
}

@MainActor
func setFieldFocused(_ view: NSView, _ focused: Bool) {
    view.layer?.borderWidth = focused ? 1.5 : 1
    view.layer?.borderColor = NSColor(white: focused ? 0.58 : 0.28, alpha: 1).cgColor
}

@MainActor
final class CenteredTextFieldCell: NSTextFieldCell {
    private func textRect(_ rect: NSRect) -> NSRect {
        let height = ceil(NSLayoutManager().defaultLineHeight(for: font ?? .systemFont(ofSize: 13)))
        return NSRect(x: rect.minX + 10, y: rect.midY - height / 2, width: rect.width - 20, height: height)
    }
    override func drawingRect(forBounds rect: NSRect) -> NSRect { textRect(rect) }
    override func edit(withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, event: NSEvent?) {
        editor.alignment = .left
        super.edit(withFrame: textRect(rect), in: view, editor: editor, delegate: delegate, event: event)
        setFieldFocused(view, view.window?.firstResponder === editor)
    }
    override func select(withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, start: Int, length: Int) {
        editor.alignment = .left
        super.select(withFrame: textRect(rect), in: view, editor: editor, delegate: delegate, start: start, length: length)
        setFieldFocused(view, view.window?.firstResponder === editor)
    }
    override func endEditing(_ textObj: NSText) {
        let field = controlView
        super.endEditing(textObj)
        if let field = field as? NSTextField, field.drawsBackground { setFieldFocused(field, false) }
    }
}

@MainActor
final class FilenameField: NSTextField {
    init(_ value: String) {
        super.init(frame: .zero)
        cell = CenteredTextFieldCell(textCell: value)
        stringValue = value
        font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        alignment = .left
        textColor = .white
        backgroundColor = .black
        drawsBackground = true
        isBezeled = false
        isBordered = false
        isEditable = true
        isSelectable = true
        focusRingType = .none
        styleOutlinedField(self)
    }
    required init?(coder: NSCoder) { nil }

}

@MainActor
final class PromptField: NSView {
    let scrollView: NSScrollView

    override init(frame: NSRect) {
        scrollView = NSScrollView(frame: NSRect(origin: .zero, size: frame.size).insetBy(dx: 2, dy: 2))
        super.init(frame: frame)
        styleOutlinedField(self)
        scrollView.contentView = PromptClipView(frame: scrollView.contentView.frame)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = .black
        addSubview(scrollView)
    }
    required init?(coder: NSCoder) { nil }
}

@MainActor
private final class PromptClipView: NSClipView {
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        (documentView as? PromptTextView)?.centerTextInViewport()
    }
}

@MainActor
final class PromptTextView: NSTextView {
    private var centering = false

    override var string: String {
        didSet { centerTextInViewport() }
    }

    override func didChangeText() {
        super.didChangeText()
        centerTextInViewport()
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged { centerTextInViewport() }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        centerTextInViewport()
    }

    func centerTextInViewport() {
        guard !centering, let clip = enclosingScrollView?.contentView,
              let manager = layoutManager, let container = textContainer,
              clip.bounds.height > 0 else { return }
        centering = true
        defer { centering = false }
        let available = max(0, clip.bounds.height - 16)
        // Only lay out enough text to establish whether it fits the viewport.
        manager.ensureLayout(forBoundingRect: NSRect(x: 0, y: 0, width: container.containerSize.width,
                                                    height: available + 1), in: container)
        var block = manager.usedRect(for: container)
        if manager.extraLineFragmentTextContainer === container {
            block = block.isEmpty ? manager.extraLineFragmentRect : block.union(manager.extraLineFragmentRect)
        }
        let fits = manager.firstUnlaidCharacterIndex() >= (textStorage?.length ?? 0) && block.height <= available
        let inset = fits ? max(8, (clip.bounds.height - block.height) / 2) : 8
        minSize = NSSize(width: 0, height: clip.bounds.height)
        if abs(textContainerInset.height - inset) > 0.01 {
            textContainerInset = NSSize(width: 8, height: inset)
        }
        sizeToFit()
        if fits { clip.scroll(to: .zero) }
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted, let field = enclosingScrollView?.superview as? PromptField { setFieldFocused(field, true) }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted, let field = enclosingScrollView?.superview as? PromptField { setFieldFocused(field, false) }
        return accepted
    }
}
