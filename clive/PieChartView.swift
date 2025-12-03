import SwiftUI
import AppKit

struct PieChart: View {
    let percent: Double
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 2)

            PieSlice(endAngle: Angle(degrees: percent * 3.6 - 90))
                .fill(colorForPercent(percent))
        }
        .frame(width: size, height: size)
    }

    private func colorForPercent(_ percent: Double) -> Color {
        if percent >= 90 {
            return .red
        } else if percent >= 70 {
            return .orange
        } else {
            return .green
        }
    }
}

struct PieSlice: Shape {
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        path.move(to: center)
        path.addArc(center: center, radius: radius, startAngle: .degrees(-90), endAngle: endAngle, clockwise: false)
        path.closeSubpath()

        return path
    }
}

struct DualPieChart: View {
    let sessionPercent: Double?
    let weeklyPercent: Double?
    let size: CGFloat = 16

    var body: some View {
        HStack(spacing: 3) {
            PieChart(percent: sessionPercent ?? 0, size: size)
            PieChart(percent: weeklyPercent ?? 0, size: size)
        }
    }
}

class PieChartRenderer {
    static func createImage(sessionPercent: Double?, weeklyPercent: Double?) -> NSImage {
        let size = NSSize(width: 42, height: 22)
        let session = sessionPercent ?? 0
        let weekly = weeklyPercent ?? 0

        let image = NSImage(size: size, flipped: false) { rect in
            let context = NSGraphicsContext.current!.cgContext

            // Draw shadow blob
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -1), blur: 3, color: NSColor.black.withAlphaComponent(0.5).cgColor)

            let pieSize: CGFloat = 14
            let yOffset = (rect.height - pieSize) / 2

            // Draw session pie (left)
            let sessionRect = NSRect(x: 4, y: yOffset, width: pieSize, height: pieSize)
            Self.drawPie(in: sessionRect, percent: session)

            // Draw weekly pie (right)
            let weeklyRect = NSRect(x: 24, y: yOffset, width: pieSize, height: pieSize)
            Self.drawPie(in: weeklyRect, percent: weekly)

            context.restoreGState()

            return true
        }
        return image
    }

    private static func drawPie(in rect: NSRect, percent: Double) {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        // Dark background fill for contrast
        let bgFillPath = NSBezierPath(ovalIn: rect)
        NSColor.black.withAlphaComponent(0.4).setFill()
        bgFillPath.fill()

        // Filled slice
        if percent > 0 {
            let slicePath = NSBezierPath()
            slicePath.move(to: center)
            let startAngle: CGFloat = 90
            let endAngle: CGFloat = 90 - CGFloat(percent * 3.6)
            slicePath.appendArc(withCenter: center, radius: radius - 0.5, startAngle: startAngle, endAngle: endAngle, clockwise: true)
            slicePath.close()

            colorForPercent(percent).setFill()
            slicePath.fill()
        }

        // Dark outline for contrast
        let outlinePath = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
        NSColor.black.withAlphaComponent(0.6).setStroke()
        outlinePath.lineWidth = 1
        outlinePath.stroke()
    }

    private static func colorForPercent(_ percent: Double) -> NSColor {
        if percent >= 90 {
            return NSColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1.0)
        } else if percent >= 70 {
            return NSColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1.0)
        } else {
            return NSColor(red: 0.2, green: 0.9, blue: 0.3, alpha: 1.0)
        }
    }
}

// MARK: - Bar Chart

struct HorizontalBar: View {
    let percent: Double
    let height: CGFloat
    let width: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.gray.opacity(0.3))
                .frame(width: width, height: height)

            RoundedRectangle(cornerRadius: 2)
                .fill(colorForPercent(percent))
                .frame(width: width * CGFloat(min(percent, 100) / 100), height: height)
        }
    }

    private func colorForPercent(_ percent: Double) -> Color {
        if percent >= 90 {
            return .red
        } else if percent >= 70 {
            return .orange
        } else {
            return .green
        }
    }
}

struct StackedBarChart: View {
    let sessionPercent: Double?
    let weeklyPercent: Double?
    let barWidth: CGFloat = 40
    let barHeight: CGFloat = 6

    var body: some View {
        VStack(spacing: 2) {
            HorizontalBar(percent: sessionPercent ?? 0, height: barHeight, width: barWidth)
            HorizontalBar(percent: weeklyPercent ?? 0, height: barHeight, width: barWidth)
        }
    }
}

class BarChartRenderer {
    static func createImage(sessionPercent: Double?, weeklyPercent: Double?) -> NSImage {
        let size = NSSize(width: 48, height: 22)
        let session = sessionPercent ?? 0
        let weekly = weeklyPercent ?? 0

        let image = NSImage(size: size, flipped: false) { rect in
            let context = NSGraphicsContext.current!.cgContext

            // Draw shadow blob
            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -1), blur: 3, color: NSColor.black.withAlphaComponent(0.5).cgColor)

            let barWidth: CGFloat = 40
            let barHeight: CGFloat = 6
            let spacing: CGFloat = 2
            let xOffset: CGFloat = 4

            // Draw session bar (top)
            let sessionY = rect.height / 2 + spacing / 2
            Self.drawBar(x: xOffset, y: sessionY, width: barWidth, height: barHeight, percent: session)

            // Draw weekly bar (bottom)
            let weeklyY = rect.height / 2 - barHeight - spacing / 2
            Self.drawBar(x: xOffset, y: weeklyY, width: barWidth, height: barHeight, percent: weekly)

            context.restoreGState()

            return true
        }
        return image
    }

    private static func drawBar(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, percent: Double) {
        let bgRect = NSRect(x: x, y: y, width: width, height: height)

        // Dark background for contrast
        let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 2, yRadius: 2)
        NSColor.black.withAlphaComponent(0.4).setFill()
        bgPath.fill()

        // Colored fill
        if percent > 0 {
            let fillWidth = width * CGFloat(min(percent, 100) / 100)
            let fillRect = NSRect(x: x, y: y, width: fillWidth, height: height)
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 2, yRadius: 2)
            colorForPercent(percent).setFill()
            fillPath.fill()
        }

        // Dark outline for contrast
        let outlinePath = NSBezierPath(roundedRect: bgRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 2, yRadius: 2)
        NSColor.black.withAlphaComponent(0.6).setStroke()
        outlinePath.lineWidth = 1
        outlinePath.stroke()
    }

    private static func colorForPercent(_ percent: Double) -> NSColor {
        if percent >= 90 {
            return NSColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1.0)
        } else if percent >= 70 {
            return NSColor(red: 1.0, green: 0.6, blue: 0.0, alpha: 1.0)
        } else {
            return NSColor(red: 0.2, green: 0.9, blue: 0.3, alpha: 1.0)
        }
    }
}
