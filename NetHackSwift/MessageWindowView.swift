import SwiftUI

struct MessageWindowView: View {
    let text: String
    var onClose: () -> Void
    @FocusState private var isFocused: Bool

    private var maxTextHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 800) * 0.6
    }

    private var textContent: some View {
        Text(text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 20)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            // ViewThatFits sizes to text naturally; falls back to a ScrollView only
            // when text exceeds maxTextHeight. The frame(maxHeight:) here caps the
            // ideal height that preferredContentSize uses for initial window sizing.
            ViewThatFits(in: .vertical) {
                textContent
                ScrollView { textContent }
            }
            .frame(maxHeight: maxTextHeight)

            Button("Close", action: onClose)
                .keyboardShortcut(.escape, modifiers: [])
                .buttonStyle(.borderedProminent)
                .padding(.top, 21)
                .padding(.bottom, 19)
                .padding(.trailing, 21)
        }
        .frame(minWidth: 259, idealWidth: 400)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress(.escape) { onClose(); return .handled }
    }
}

#Preview("Short text") {
    MessageWindowView(
        text: "You feel a strange sensation as you advance to level 10!",
        onClose: { }
    )
}

#Preview("Long text") {
    MessageWindowView(
        text: String(repeating: "You feel a strange sensation. ", count: 40),
        onClose: { }
    )
}
