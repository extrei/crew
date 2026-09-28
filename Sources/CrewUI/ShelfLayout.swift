import Foundation

public enum ShelfLayout {
    public static let cellSize: CGFloat = 62
    public static let gap: CGFloat = 9
    public static let height: CGFloat = 86

    public static func width(agentCount: Int) -> CGFloat {
        120 + CGFloat(min(6, max(0, agentCount))) * (cellSize + gap)
    }

    public static func constrained(_ frame: CGRect, to screen: CGRect, inset: CGFloat = 12) -> CGRect {
        let bounds = screen.insetBy(dx: inset, dy: inset)
        let size = CGSize(width: min(frame.width, bounds.width), height: min(frame.height, bounds.height))
        return CGRect(x: min(max(frame.minX, bounds.minX), bounds.maxX - size.width),
                      y: min(max(frame.minY, bounds.minY), bounds.maxY - size.height),
                      width: size.width, height: size.height)
    }

    public static func defaultAnchor(in screen: CGRect) -> CGPoint {
        CGPoint(x: screen.midX, y: screen.minY + screen.height * 2 / 3)
    }

    public static func screen(for frame: CGRect, among screens: [CGRect]) -> CGRect? {
        screens.max { left, right in
            func overlap(_ screen: CGRect) -> CGFloat {
                let intersection = frame.intersection(screen)
                return intersection.isNull ? 0 : intersection.width * intersection.height
            }
            let leftArea = overlap(left), rightArea = overlap(right)
            if leftArea != rightArea { return leftArea < rightArea }
            func distance(_ screen: CGRect) -> CGFloat {
                let x = max(screen.minX - frame.midX, 0, frame.midX - screen.maxX)
                let y = max(screen.minY - frame.midY, 0, frame.midY - screen.maxY)
                return x * x + y * y
            }
            return distance(left) > distance(right)
        }
    }

    public static func island(anchor: CGPoint, agentCount: Int, screens: [CGRect]) -> CGRect {
        let size = CGSize(width: width(agentCount: agentCount), height: height)
        let frame = CGRect(x: anchor.x - size.width / 2, y: anchor.y - size.height / 2,
                           width: size.width, height: size.height)
        guard let screen = screen(for: frame, among: screens) else { return frame }
        return constrained(frame, to: screen)
    }

    public static func popup(size: CGSize, shelf: CGRect, screen: CGRect) -> CGRect {
        let below = CGRect(x: shelf.maxX - size.width, y: shelf.minY - size.height - 12,
                           width: size.width, height: size.height)
        let proposed = below.minY >= screen.minY + 12 ? below
            : CGRect(x: below.minX, y: shelf.maxY + 12, width: size.width, height: size.height)
        return constrained(proposed, to: screen)
    }
}

public struct DragPayload: Equatable, Sendable {
    public let fileURL: URL
    public let markdown: String

    public init(fileURL: URL, markdown: String) {
        self.fileURL = fileURL
        self.markdown = markdown
    }
}
