import AppKit
import QuartzCore

@MainActor
enum Motion {
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// Fast start, long settle. Used for size and position changes that should feel weightless.
    static let settle = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
}

extension CALayer {
    /// Animates `keyPath` from its current on-screen value to the value already stored in the model layer.
    /// Re-targeting a running animation continues from where it is instead of jumping.
    @MainActor func ease(_ keyPath: String, duration: TimeInterval, timing: CAMediaTimingFunctionName = .easeOut) {
        guard !Motion.reduced else { removeAnimation(forKey: keyPath); return }
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = (presentation() ?? self).value(forKeyPath: keyPath)
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: timing)
        add(animation, forKey: keyPath)
    }

    /// Springs `keyPath` from its current on-screen value to the model value and runs until the spring settles.
    @MainActor func spring(_ keyPath: String, stiffness: CGFloat = 320, damping: CGFloat = 24) {
        guard !Motion.reduced else { removeAnimation(forKey: keyPath); return }
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.fromValue = (presentation() ?? self).value(forKeyPath: keyPath)
        animation.mass = 1
        animation.stiffness = stiffness
        animation.damping = damping
        animation.duration = animation.settlingDuration
        add(animation, forKey: keyPath)
    }
}
