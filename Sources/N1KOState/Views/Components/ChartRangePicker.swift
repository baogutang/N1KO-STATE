import SwiftUI

struct ChartRangePicker: View {
    @Binding var range: String
    var accent: Color = Theme.accent

    private let options = HistoryStore.Range.allCases

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { r in
                Button(action: { range = r.rawValue }) {
                    Text(r.rawValue.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(range == r.rawValue ? .white : Theme.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(range == r.rawValue ? accent : Theme.track)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}
