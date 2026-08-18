import SwiftUI

struct InputWindowView: View {
    let prompt: String
    let onAccept: (String) -> Void
    let onCancel: () -> Void

    @State private var inputText: String = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(prompt)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("", text: $inputText)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit { onAccept(inputText) }
                .onKeyPress(.escape) { onCancel(); return .handled }

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") { onCancel() }
                Button("Accept") { onAccept(inputText) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.top, 23)
        .padding(.bottom, 19)
        .padding(.horizontal, 19)
        .frame(minWidth: 363, maxWidth: 1000, minHeight: 115, maxHeight: 115)
        .onAppear { fieldFocused = true }
    }
}

// MARK: - Previews

#Preview {
    InputWindowView(
        prompt: "Response:",
        onAccept: { _ in },
        onCancel: { }
    )
}
