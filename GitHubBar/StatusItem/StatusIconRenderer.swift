import AppKit

enum StatusIconRenderer {
    private static let iconSize = NSSize(width: 18, height: 18)

    static func image(reviewCount: Int) -> NSImage {
        let image = NSImage(size: iconSize, flipped: false) { bounds in
            drawPullRequestMark(in: bounds)
            if reviewCount > 0 {
                drawBadge(reviewCount: reviewCount)
            }
            return true
        }
        image.isTemplate = true
        image.size = iconSize
        return image
    }

    private static func drawPullRequestMark(in bounds: NSRect) {
        NSColor.black.setStroke()

        let path = NSBezierPath()
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        path.move(to: NSPoint(x: 4.25, y: 5.5))
        path.line(to: NSPoint(x: 4.25, y: 12.5))

        path.move(to: NSPoint(x: 10.1, y: 13.1))
        path.line(to: NSPoint(x: 12.2, y: 15.2))
        path.line(to: NSPoint(x: 14.3, y: 13.1))
        path.move(to: NSPoint(x: 12.2, y: 15.1))
        path.line(to: NSPoint(x: 12.2, y: 11.8))
        path.curve(
            to: NSPoint(x: 9.1, y: 8.7),
            controlPoint1: NSPoint(x: 12.2, y: 10.1),
            controlPoint2: NSPoint(x: 10.8, y: 8.7)
        )
        path.line(to: NSPoint(x: 8.2, y: 8.7))
        path.stroke()

        drawNode(center: NSPoint(x: 4.25, y: 4.1))
        drawNode(center: NSPoint(x: 4.25, y: 13.9))
        drawNode(center: NSPoint(x: 12.2, y: 4.1))

        let rightStem = NSBezierPath()
        rightStem.lineWidth = 1.5
        rightStem.lineCapStyle = .round
        rightStem.move(to: NSPoint(x: 12.2, y: 5.5))
        rightStem.line(to: NSPoint(x: 12.2, y: 8.2))
        rightStem.stroke()
    }

    private static func drawNode(center: NSPoint) {
        let node = NSBezierPath(ovalIn: NSRect(x: center.x - 1.25, y: center.y - 1.25, width: 2.5, height: 2.5))
        node.lineWidth = 1.35
        node.stroke()
    }

    private static func drawBadge(reviewCount: Int) {
        let visibleCount = reviewCount > 9 ? "9+" : String(reviewCount)
        let badgeRect = NSRect(x: 9.1, y: 0.3, width: 8.6, height: 8.6)

        NSColor.black.setFill()
        NSBezierPath(ovalIn: badgeRect).fill()

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .clear
        let fontSize: CGFloat = reviewCount > 9 ? 4.2 : 5.6
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.clear,
        ]
        let string = NSAttributedString(string: visibleCount, attributes: attributes)
        let size = string.size()
        string.draw(at: NSPoint(x: badgeRect.midX - size.width / 2, y: badgeRect.midY - size.height / 2 - 0.2))
        NSGraphicsContext.restoreGraphicsState()
    }
}
