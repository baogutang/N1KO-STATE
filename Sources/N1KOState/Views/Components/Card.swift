import SwiftUI

/// Rounded, hairline-bordered surface used for every popover module.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
    }
}

/// Standard header row: tinted glyph + title + optional trailing value.
struct CardHeader: View {
    let icon: String
    let title: String
    var accent: Color = Theme.accent
    var trailing: String? = nil
    var trailingColor: Color = Theme.textPrimary

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(accent)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(accent.opacity(0.15))
                )
            Text(loc: title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.metric(15, weight: .bold))
                    .foregroundColor(trailingColor)
            }
        }
    }
}
