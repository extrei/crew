import AppKit
import CrewCore

@MainActor
final class MascotView: NSView {
    private let body = CALayer()
    private let eyes = CALayer()
    private let kind: MascotKind
    private var motionEnabled = false

    override var isFlipped: Bool { true }

    init(kind: MascotKind, frame: NSRect) {
        self.kind = kind
        super.init(frame: frame)
        wantsLayer = true
        setAccessibilityElement(false)
        buildLayers()
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body.bounds = CGRect(x: 0, y: 0, width: 64, height: 64)
        body.position = CGPoint(x: bounds.midX, y: bounds.midY)
        body.setAffineTransform(CGAffineTransform(scaleX: bounds.width / 64, y: bounds.height / 64))
        CATransaction.commit()
    }

    func setMotionEnabled(_ enabled: Bool) {
        guard enabled != motionEnabled else { return }
        motionEnabled = enabled
        body.removeAnimation(forKey: "breathing")
        eyes.removeAnimation(forKey: "blink")
        guard enabled else { return }
        let index = Double(MascotKind.allCases.firstIndex(of: kind) ?? 0)
        let period = kind == .pixel ? 1.85 : kind == .patch ? 2.55 : 2.2
        func sway(_ keyPath: String, from: CGFloat, to: CGFloat) -> CABasicAnimation {
            let animation = CABasicAnimation(keyPath: keyPath)
            animation.fromValue = from
            animation.toValue = to
            animation.duration = period
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            return animation
        }
        // A quiet bob: rise slightly while widening and shortening, then settle back. Staggered per face.
        let breathe = CAAnimationGroup()
        breathe.animations = [sway("transform.translation.y", from: 0, to: -1.4),
                              sway("transform.scale.x", from: bounds.width / 64, to: bounds.width / 64 * 1.015),
                              sway("transform.scale.y", from: bounds.height / 64, to: bounds.height / 64 * 0.985)]
        breathe.duration = period
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timeOffset = index * 0.6
        body.add(breathe, forKey: "breathing")
        let blink = CAKeyframeAnimation(keyPath: "transform.scale.y")
        blink.values = [1, 1, 0.1, 1, 1]
        blink.keyTimes = [0, 0.9, 0.93, 0.96, 1]
        blink.timingFunctions = [.linear, .easeIn, .easeOut, .linear].map { CAMediaTimingFunction(name: $0) }
        blink.duration = 6 + index * 0.7
        blink.repeatCount = .infinity
        eyes.add(blink, forKey: "blink")
    }

    private func buildLayers() {
        guard let layer else { return }
        layer.addSublayer(body)
        let shape = CAShapeLayer()
        shape.path = Self.outline(kind)
        shape.fillColor = Self.color(kind).cgColor
        body.addSublayer(shape)
        let shine = CAShapeLayer()
        let shinePath = CGMutablePath()
        shinePath.move(to: CGPoint(x: 17, y: 18))
        shinePath.addCurve(to: CGPoint(x: 33, y: 11), control1: CGPoint(x: 22, y: 12), control2: CGPoint(x: 28, y: 10))
        shine.path = shinePath
        shine.fillColor = nil
        shine.strokeColor = NSColor.white.withAlphaComponent(0.25).cgColor
        shine.lineWidth = 2
        shine.lineCap = .round
        body.addSublayer(shine)
        eyes.bounds = CGRect(x: 0, y: 0, width: 22, height: 16)
        eyes.position = CGPoint(x: 32, y: 28)
        body.addSublayer(eyes)
        for rect in [CGRect(x: 4, y: 3, width: 4.5, height: 10), CGRect(x: 15, y: 2, width: 4.5, height: 10)] {
            let eye = CAShapeLayer()
            eye.path = CGPath(roundedRect: rect, cornerWidth: 2.25, cornerHeight: 2.25, transform: nil)
            eye.fillColor = NSColor(srgbRed: 0.204, green: 0.235, blue: 0.196, alpha: 1).cgColor
            eyes.addSublayer(eye)
        }
        if kind == .pixel {
            let accent = CAShapeLayer()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 13, y: 12))
            path.addLine(to: CGPoint(x: 20, y: 7))
            accent.path = path
            accent.strokeColor = NSColor(srgbRed: 0.843, green: 0.773, blue: 0.984, alpha: 1).cgColor
            accent.lineWidth = 4
            accent.lineCap = .round
            body.addSublayer(accent)
        }
    }

    static func color(_ kind: MascotKind) -> NSColor {
        switch kind {
        case .scout: NSColor(srgbRed: 0.729, green: 0.847, blue: 0.643, alpha: 1)
        case .pixel: NSColor(srgbRed: 0.741, green: 0.686, blue: 0.886, alpha: 1)
        case .patch: NSColor(srgbRed: 0.910, green: 0.749, blue: 0.459, alpha: 1)
        case .sage: NSColor(srgbRed: 0.596, green: 0.788, blue: 0.784, alpha: 1)
        }
    }

    private static func outline(_ kind: MascotKind) -> CGPath {
        let p = CGMutablePath()
        func move(_ x: CGFloat, _ y: CGFloat) { p.move(to: CGPoint(x: x, y: y)) }
        func line(_ x: CGFloat, _ y: CGFloat) { p.addLine(to: CGPoint(x: x, y: y)) }
        func curve(_ x: CGFloat, _ y: CGFloat, _ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) {
            p.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: a, y: b), control2: CGPoint(x: c, y: d))
        }
        switch kind {
        case .scout:
            move(8, 35); curve(29, 7, 5, 20, 14, 8); curve(56, 31, 45, 5, 57, 16)
            curve(28, 56, 55, 46, 43, 57); curve(8, 35, 15, 55, 10, 47)
        case .pixel:
            move(10, 34); line(24, 10); curve(39, 10, 28, 3, 35, 3); line(56, 43)
            curve(48, 55, 59, 50, 56, 55); line(16, 55); curve(10, 34, 5, 55, 3, 48)
        case .patch:
            move(10, 19); line(23, 8); curve(40, 9, 29, 3, 34, 4); line(54, 24)
            curve(53, 42, 59, 30, 59, 36); line(40, 54); curve(22, 54, 34, 60, 28, 60)
            line(9, 41); curve(10, 19, 2, 34, 3, 27)
        case .sage:
            move(8, 29); curve(29, 8, 8, 14, 17, 7); curve(43, 12, 34, 0, 44, 5)
            curve(56, 41, 56, 14, 61, 28); curve(26, 56, 51, 54, 40, 60)
            curve(8, 29, 14, 53, 7, 43)
        }
        p.closeSubpath()
        return p
    }
}
