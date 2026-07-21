import SwiftUI

struct ChartRangePicker: View {
    @Binding var range: String
    var accent: Color = Theme.accent

    private let options = HistoryStore.Range.allCases
    @State private var displayedRange: String
    @State private var pendingCommit: DispatchWorkItem?

    init(range: Binding<String>, accent: Color = Theme.accent) {
        self._range = range
        self.accent = accent
        self._displayedRange = State(initialValue: range.wrappedValue)
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { r in
                Button(action: { select(r.rawValue) }) {
                    Text(r.rawValue.uppercased())
                        .font(Theme.TypeScale.caption.weight(.semibold))
                        .foregroundColor(displayedRange == r.rawValue ? .white : Theme.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(displayedRange == r.rawValue ? accent : Theme.track)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Chart range %@".locf(r.rawValue.uppercased()))
                .accessibilityAddTraits(displayedRange == r.rawValue ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .onChange(of: range) { displayedRange = $0 }
    }

    private func select(_ nextRange: String) {
        displayedRange = nextRange
        pendingCommit?.cancel()
        let work = DispatchWorkItem {
            range = nextRange
        }
        pendingCommit = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }
}
