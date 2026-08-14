import SwiftUI

/// A direction-picker panel matching the "Which direction?" XIB panel.
/// Each button sends a vi-direction key (or special key) via `onKey`.
struct DirectionView: View {
    let onKey: (Int32) -> Void

    private let buttonSize: CGFloat = 32
    private let gridGap: CGFloat = 4

    var body: some View {
        // Grid guarantees that each row of text buttons aligns with the
        // corresponding row of arrow buttons without any manual frame math.
        Grid(horizontalSpacing: gridGap, verticalSpacing: gridGap) {
            GridRow {
                arrowButton("Arrow-NW", key: "y")
                arrowButton("Arrow-N",  key: "k")
                arrowButton("Arrow-NE", key: "u")
                dividerCell
                textButton("Ceiling <", key: "<")
            }
            GridRow {
                arrowButton("Arrow-W",  key: "h")
                Color.clear.frame(width: buttonSize, height: buttonSize)
                arrowButton("Arrow-E",  key: "l")
                dividerCell
                textButton("Self .",    key: ".")
            }
            GridRow {
                arrowButton("Arrow-SW", key: "b")
                arrowButton("Arrow-S",  key: "j")
                arrowButton("Arrow-SE", key: "n")
                dividerCell
                textButton("Floor >",  key: ">")
            }
        }
        .padding(12)
    }

    // MARK: - Helpers

    /// A thin separator segment sized to one grid row.
    private var dividerCell: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 0.5, height: buttonSize)
            .padding(.horizontal, 7)
    }

    private func arrowButton(_ assetName: String, key: String) -> some View {
        Button {
            send(key)
        } label: {
            Image(assetName)
                .resizable()
                .frame(width: buttonSize, height: buttonSize)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .focusable(false)
    }

    private func textButton(_ title: String, key: String) -> some View {
        Button(title) { send(key) }
            .controlSize(.small)
            .frame(width: 72)
            .focusable(false)
    }

    private func send(_ key: String) {
        if let scalar = key.unicodeScalars.first {
            onKey(Int32(scalar.value))
        }
    }
}

#Preview {
    DirectionView { key in
        print("key: \(key)")
    }
}
