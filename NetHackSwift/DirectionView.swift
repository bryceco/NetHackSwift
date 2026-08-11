import SwiftUI

/// A direction-picker panel matching the "Which direction?" XIB panel.
/// Each button sends a vi-direction key (or special key) via `onKey`.
struct DirectionView: View {
    let onKey: (Int32) -> Void

    private let buttonSize: CGFloat = 40

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            directionGrid
            Divider()
            specialButtons
        }
        .padding()
    }

    // MARK: - Subviews

    private var directionGrid: some View {
        let gap: CGFloat = 6
        return VStack(spacing: gap) {
            HStack(spacing: gap) {
                arrowButton("arrow.up.left",    key: "y")
                arrowButton("arrow.up",         key: "k")
                arrowButton("arrow.up.right",   key: "u")
            }
            HStack(spacing: gap) {
                arrowButton("arrow.left",       key: "h")
                Color.clear.frame(width: buttonSize, height: buttonSize)
                arrowButton("arrow.right",      key: "l")
            }
            HStack(spacing: gap) {
                arrowButton("arrow.down.left",  key: "b")
                arrowButton("arrow.down",       key: "j")
                arrowButton("arrow.down.right", key: "n")
            }
        }
    }

    private var specialButtons: some View {
        VStack(spacing: 8) {
            textButton("Ceiling <", key: "<")
            textButton("Self .",    key: ".")
            textButton("Floor >",   key: ">")
        }
    }

    // MARK: - Helpers

    private func arrowButton(_ systemImage: String, key: String) -> some View {
        Button {
            send(key)
        } label: {
            Image(systemName: systemImage)
                .imageScale(.large)
                .frame(width: buttonSize, height: buttonSize)
        }
        .buttonStyle(.bordered)
    }

    private func textButton(_ title: String, key: String) -> some View {
        Button(title) { send(key) }
            .frame(width: 84)
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
