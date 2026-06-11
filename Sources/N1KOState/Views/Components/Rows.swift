import SwiftUI

/// Small uppercase-label / value stat used in compact rows.
struct StatPill: View {
    let label: String
    let value: String
    var color: Color = Theme.textPrimary
    var help: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.loc.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Theme.textTertiary)
            Text(value)
                .font(.metric(13))
                .foregroundColor(color)
        }
        .help(help?.loc ?? "")
    }
}

/// A process row with a subtle utilization bar behind the name.
struct ProcessRow: View {
    let name: String
    let value: String
    let fraction: Double
    let color: Color
    var onTerminate: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(value)
                .font(.metric(11))
                .foregroundColor(Theme.textPrimary)
            if let onTerminate {
                Button(action: onTerminate) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Quit process".loc)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 7)
        .background(
            GeometryReader { g in
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(color.opacity(0.14))
                        .frame(width: max(0, g.size.width * CGFloat(min(max(fraction, 0), 1))))
                    Spacer(minLength: 0)
                }
            }
        )
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.white.opacity(0.02))
        )
    }
}

/// Section label inside a card.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.loc.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundColor(Theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
