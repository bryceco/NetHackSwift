import SwiftUI

private let asciiESC: Int32 = 27

struct YesNoWindowView: View {
    let question: String
    // Each tuple: (display label, response character as Int32)
    let buttons: [(label: String, value: Int32)]
    let defaultValue: Int32
    let cancelValue: Int32  // sent on Escape or window close; 0 = no cancel supported
    var onSelect: (Int32) -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(question)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 19)
                .padding(.top, 21)

            Spacer()

            HStack(spacing: 12) {
                Spacer()
                ForEach(Array(buttons.enumerated()), id: \.offset) { _, button in
                    if button.value == defaultValue {
                        Button(button.label) { onSelect(button.value) }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button(button.label) { onSelect(button.value) }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 19)
        }
        .frame(width: 400, height: 115)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress { press in
            guard let char = press.characters.first else { return .ignored }
            // Escape cancels, but only if a cancel value is defined.
            if char.asciiValue == UInt8(asciiESC) {
                if cancelValue != 0 { onSelect(cancelValue) }
                return .handled
            }
            // Enter accepts the default.
            if char == "\r" || char == "\n" {
                onSelect(defaultValue)
                return .handled
            }
            let charCode = Int32(char.asciiValue ?? 0)
            if let button = buttons.first(where: { $0.value == charCode }) {
                onSelect(button.value)
                return .handled
            }
            return .ignored
        }
    }
}

// MARK: - Helpers

extension YesNoWindowView {

    /// Parses a NetHack choices string into inventory letters (`items`) and
    /// special characters like `?`, `*`, `$`, `-` (`specials`).
    ///
    /// Examples:
    ///   `"yn"`              → items `"yn"`,      specials `""`
    ///   `"ynq"`             → items `"ynq"`,     specials `""`
    ///   `"- ab or ?*"`      → items `"ab"`,      specials `"-?*"`
    ///   `"- a-cw-z or ?*"`  → items `"abcwxyz"`, specials `"-?*"`
    static func parseYnChoices(_ responses: String) -> (items: String, specials: String) {
        enum State { case start, inv, invInterval, end }
        var state = State.start
        var items = ""
        var specials = ""
        var lastInv: UInt8 = 0

        for c in responses {
            let isAlpha = c.isASCII && c.isLetter
            switch state {
            case .start:
                if isAlpha {
                    state = .inv
                    items.append(c)
                } else if c == " " {
                    state = .inv
                } else {
                    specials.append(c)
                }
            case .inv:
                if isAlpha {
                    items.append(c)
                    lastInv = c.asciiValue!
                } else if c == " " {
                    state = .end
                } else if c == "-" {
                    state = .invInterval
                }
            case .invInterval:
                if isAlpha, let v = c.asciiValue, lastInv > 0, lastInv < v {
                    var a = lastInv + 1
                    while a <= v {
                        items.append(Character(UnicodeScalar(a)))
                        a += 1
                    }
                }
                state = .inv
                lastInv = 0
            case .end:
                if !isAlpha && c != " " {
                    specials.append(c)
                }
            }
        }
        return (items: items, specials: specials)
    }

    /// Converts the inventory-letter portion of a NetHack choices string into
    /// labeled button tuples.
    /// Maps well-known response sequences to friendly button labels.
    /// Unrecognised sequences show the character itself (e.g. 'r' → "R").
    static let knownLabels: [String: [Character: String]] = [
        "yn":  ["y": "Yes", "n": "No"],
        "ynq": ["y": "Yes", "n": "No", "q": "Quit"],
        "lr":  ["r": "Right", "l": "Left"],
    ]

    static func makeButtons(from responses: String) -> [(label: String, value: Int32)] {
        let (items, _) = parseYnChoices(responses)
        let labelMap = knownLabels[items] ?? [:]
        return items.unicodeScalars.map { scalar in
            let char = Character(scalar)
            let label = labelMap[char] ?? String(char).uppercased()
            return (label: label, value: Int32(scalar.value))
        }
    }
}

// MARK: - Previews

#Preview("Yes / No") {
    YesNoWindowView(
        question: "Do you want to eat the food?",
        buttons: YesNoWindowView.makeButtons(from: "yn"),
        defaultValue: Int32(UInt8(ascii: "n")),
        cancelValue: 0,
        onSelect: { _ in }
    )
}

#Preview("Yes / No / Quit") {
    YesNoWindowView(
        question: "There is a scroll of remove curse here; pick it up?",
        buttons: YesNoWindowView.makeButtons(from: "ynq"),
        defaultValue: Int32(UInt8(ascii: "n")),
        cancelValue: Int32(UInt8(ascii: "q")),
        onSelect: { _ in }
    )
}
