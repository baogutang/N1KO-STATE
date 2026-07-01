import SwiftUI

/// Circular progress ring with a centered value + caption.
struct RingGauge: View {
    var fraction: Double          // 0...1
    var color: Color
    var lineWidth: CGFloat = 8
    var value: String? = nil
    var caption: String? = nil

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.track, style: StrokeStyle(lineWidth: lineWidth))
            Circle()
                .trim(from: 0, to: CGFloat(min(max(fraction, 0), 1)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.45), value: fraction)
            VStack(spacing: 1) {
                if let value {
                    Text(value)
                        .font(.metric(16, weight: .bold))
                        .foregroundColor(Theme.textPrimary)
                }
                if let caption {
                    Text(loc: caption)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Theme.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let pct = Int((fraction * 100).rounded())
        if let value, let caption {
            return "\(caption.loc) \(value), \(pct)%"
        }
        return "\(pct)%"
    }
}

/// Premium dashboard ring with spring-animated arc, soft glow, and custom center content.
struct DashboardRingGauge<Center: View>: View {
    var fraction: Double
    var color: Color
    var lineWidth: CGFloat = 7
    var size: CGFloat = Theme.gaugeRingSize
    @ViewBuilder var center: () -> Center

    @State private var animatedFraction: Double = 0
    @State private var glowPulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(glowPulse ? 0.22 : 0.12), lineWidth: lineWidth + 10)
                .blur(radius: 6)
                .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: glowPulse)

            Circle()
                .stroke(Theme.track.opacity(0.9), style: StrokeStyle(lineWidth: lineWidth))

            Circle()
                .trim(from: 0, to: CGFloat(min(max(animatedFraction, 0), 1)))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            color.opacity(0.55),
                            color,
                            color.opacity(0.85)
                        ]),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.28), radius: 4, x: 0, y: 0)

            center()
                .frame(width: innerDiameter)
        }
        .frame(width: size, height: size)
        .onAppear {
            glowPulse = true
            withAnimation(.spring(response: 0.72, dampingFraction: 0.78)) {
                animatedFraction = fraction
            }
        }
        .onChange(of: fraction) { newValue in
            withAnimation(.spring(response: 0.52, dampingFraction: 0.84)) {
                animatedFraction = newValue
            }
        }
    }

    private var innerDiameter: CGFloat {
        max(size - lineWidth * 2 - 14, 44)
    }
}

/// Animated center stack for dashboard rings: primary value + compact detail rows.
struct DashboardRingCenter: View, Equatable {
    let primaryValue: String
    let primaryColor: Color
    let details: [DashboardRingDetail]

    var body: some View {
        VStack(spacing: 4) {
            Text(primaryValue)
                .font(.metric(15, weight: .heavy))
                .foregroundColor(primaryColor)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .animation(.spring(response: 0.42, dampingFraction: 0.86), value: primaryValue)

            VStack(spacing: 2) {
                ForEach(details) { detail in
                    Text(detailText(detail))
                        .font(.metric(7.5, weight: .semibold))
                        .foregroundColor(detail.placeholder ? .clear : Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .frame(maxWidth: .infinity)
                        .animation(.easeOut(duration: 0.28), value: detail.value)
                }
            }
        }
        .multilineTextAlignment(.center)
    }

    private func detailText(_ detail: DashboardRingDetail) -> String {
        guard !detail.placeholder else { return " " }
        return "\(detail.label.loc) \(detail.value)"
    }
}

struct DashboardRingDetail: Identifiable, Equatable {
    let label: String
    let value: String
    var placeholder = false

    var id: String { "\(label)|\(value)|\(placeholder)" }

    static let empty = DashboardRingDetail(label: "", value: "", placeholder: true)
}

/// Per-core "equalizer" bars. Each bar is labeled with its core (E1/E2,
/// P1…P8 on Apple Silicon) and tinted by type, with a legend when both
/// efficiency and performance clusters exist.
struct CoreGrid: View {
    let cores: [CoreSample]
    var height: CGFloat = 36

    private let efficiencyColor = Color(hex: 0x30D5C8)   // teal
    private let performanceColor = Theme.info             // blue

    private var hasBothTypes: Bool {
        cores.contains { $0.isPerformance } && cores.contains { !$0.isPerformance }
    }

    /// Sequential per-type labels so the user can tell which bar is which core.
    private var labeled: [(core: CoreSample, label: String, color: Color)] {
        var e = 0, p = 0
        return cores.map { c in
            if c.isPerformance {
                p += 1
                return (c, hasBothTypes ? "P\(p)" : "\(p)", performanceColor)
            } else {
                e += 1
                return (c, "E\(e)", efficiencyColor)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if hasBothTypes {
                HStack(spacing: 12) {
                    legendItem(color: performanceColor, text: "P-cores",
                               count: cores.filter { $0.isPerformance }.count)
                    legendItem(color: efficiencyColor, text: "E-cores",
                               count: cores.filter { !$0.isPerformance }.count)
                    Spacer()
                }
            }
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(labeled, id: \.core.id) { item in
                    VStack(spacing: 3) {
                        GeometryReader { g in
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                    .fill(item.color.opacity(0.16))
                                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                    .fill(item.color)
                                    .frame(height: max(2, g.size.height * CGFloat(item.core.usage)))
                                    .animation(.easeOut(duration: 0.35), value: item.core.usage)
                            }
                        }
                        .frame(height: height)
                        Text(item.label)
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundColor(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func legendItem(color: Color, text: String, count: Int) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text("\(text.loc) ·")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(Theme.textTertiary)
            + Text(" \(count)")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
        }
    }
}

/// Segmented horizontal bar (used for the memory pressure breakdown).
struct StackedBar: View {
    struct Segment: Identifiable {
        let id = UUID()
        let fraction: Double
        let color: Color
    }
    var segments: [Segment]
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { g in
            HStack(spacing: 1.5) {
                ForEach(segments) { seg in
                    Rectangle()
                        .fill(seg.color)
                        .frame(width: max(0, g.size.width * CGFloat(seg.fraction)))
                }
                Spacer(minLength: 0)
            }
            .frame(height: height)
            .clipShape(Capsule())
            .background(Capsule().fill(Theme.track))
        }
        .frame(height: height)
    }
}
