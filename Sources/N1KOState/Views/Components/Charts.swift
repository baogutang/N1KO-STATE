import SwiftUI

/// Smooth area + line chart for a series of samples.
/// `maxValue == nil` auto-scales to the series peak (good for network rates);
/// pass `1` for fractional metrics (CPU / memory).
struct MetricChart: View {
    var values: [Double]
    var maxValue: Double?
    var color: Color
    var fill: Bool = true

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                if fill, pts.count > 1 {
                    areaPath(pts, height: geo.size.height)
                        .fill(Theme.chartGradient(color))
                }
                if pts.count > 1 {
                    linePath(pts)
                        .stroke(Theme.lineGradient(color),
                                style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                }
                // Baseline
                Path { p in
                    p.move(to: CGPoint(x: 0, y: geo.size.height - 0.5))
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height - 0.5))
                }
                .stroke(Theme.stroke, lineWidth: 1)
            }
        }
    }

    private func scaledMax() -> Double {
        if let m = maxValue { return max(m, 0.0001) }
        return max(values.max() ?? 1, 0.0001)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let m = scaledMax()
        let stepX = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { i, v in
            let clamped = min(max(v / m, 0), 1)
            return CGPoint(x: CGFloat(i) * stepX,
                           y: size.height - CGFloat(clamped) * size.height)
        }
    }

    private func linePath(_ pts: [CGPoint]) -> Path {
        Path { p in
            p.move(to: pts[0])
            for pt in pts.dropFirst() { p.addLine(to: pt) }
        }
    }

    private func areaPath(_ pts: [CGPoint], height: CGFloat) -> Path {
        Path { p in
            guard let first = pts.first, let last = pts.last else { return }
            p.move(to: CGPoint(x: first.x, y: height))
            p.addLine(to: first)
            for pt in pts.dropFirst() { p.addLine(to: pt) }
            p.addLine(to: CGPoint(x: last.x, y: height))
            p.closeSubpath()
        }
    }
}

/// Minimal line-only sparkline for tight spaces (menu bar / inline).
struct Sparkline: View {
    var values: [Double]
    var maxValue: Double?
    var color: Color

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            if pts.count > 1 {
                Path { p in
                    p.move(to: pts[0])
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let m = max(maxValue ?? (values.max() ?? 1), 0.0001)
        let stepX = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { i, v in
            let clamped = min(max(v / m, 0), 1)
            return CGPoint(x: CGFloat(i) * stepX,
                           y: size.height - CGFloat(clamped) * size.height)
        }
    }
}
