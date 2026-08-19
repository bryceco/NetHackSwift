import SwiftUI

/// Modal editor for the NetHack configuration file ("NetHack Defaults.txt" / .nethackrc).
/// Accepts the current file content as `initialText` and reports the edited text via
/// `onAccept`, or calls `onCancel` if the user dismisses without saving.
struct NethackrcEditorView: View {
    let onAccept: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String
    @FocusState private var editorFocused: Bool

    init(initialText: String,
		 onAccept: @escaping (String) -> Void,
		 onCancel: @escaping () -> Void)
	{
        _text = State(initialValue: initialText)
        self.onAccept = onAccept
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .focused($editorFocused)
                .onKeyPress(.escape) { onCancel(); return .handled }
                .padding(4)

            Divider()

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") { onCancel() }
                Button("Accept") { onAccept(text) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear { editorFocused = true }
    }
}
