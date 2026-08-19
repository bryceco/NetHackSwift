import SwiftUI

struct MessageWindowView: View {
    let text: String
    /// Called when the user dismisses with ESC or Return (or the Close button).
    var onClose: () -> Void
    /// If set, called with any other key press — the closure is responsible for
    /// both queuing the key and closing the modal.  Nil for non-blocking panels.
    var onAnyKey: ((Int32) -> Void)? = nil

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
        .onKeyPress { press in
            // ESC is handled by the Close button's keyboard shortcut above.
            // Return also acts as a dismiss key.
            if press.key == .return {
                onClose()
                return .handled
            }
            // Any other key: if this is a blocking modal (onAnyKey set), let the
            // closure queue the key and close; otherwise ignore.
            guard let onAnyKey else { return .ignored }
            let code = Self.keyCodeFrom(press)
            if code != 0 {
                onAnyKey(code)
                return .handled
            }
            return .ignored
        }
    }

    /// Converts a SwiftUI KeyPress to a NetHack character code.
    /// Arrow keys map to vi-direction characters (no chord support in this context).
    private static func keyCodeFrom(_ press: KeyPress) -> Int32 {
        switch press.key {
        case .upArrow:    return Int32(UInt8(ascii: "k"))
        case .downArrow:  return Int32(UInt8(ascii: "j"))
        case .leftArrow:  return Int32(UInt8(ascii: "h"))
        case .rightArrow: return Int32(UInt8(ascii: "l"))
        default: break
        }
        if let scalar = press.characters.unicodeScalars.first,
           scalar.value > 0, scalar.value < 128 {
            return Int32(scalar.value)
        }
        return 0
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
