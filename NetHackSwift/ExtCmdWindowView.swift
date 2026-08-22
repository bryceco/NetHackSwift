import SwiftUI

// MARK: - Model

struct ExtCmdEntry: Identifiable {
    let id: Int        // filtered extcmdlist index returned to NetHack
    let name: String
    let description: String
    let key: UInt8     // 0 = no binding; ≥128 = ⌥ key; 1–31 = ⌃ key

    /// Human-readable key binding string, e.g. "⌥p" or "⌃A".
    var keyDisplayString: String {
        if key == 0 { return "" }
        if key >= 128 { return "⌥\(Character(UnicodeScalar(key & 0x7f)))" }
		if key < 32 { return "⌃\(Character(UnicodeScalar(key + 64)))" }
		return String(UnicodeScalar(key))
    }
}

// MARK: - View

struct ExtCmdWindowView: View {
    let commands: [ExtCmdEntry]
    var onAccept: (Int) -> Void   // passes ExtCmdEntry.id (filtered-list index)
    var onCancel: () -> Void

    @State private var selectedIndex: Int = 0
    @State private var searchText: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            commandList
            Divider()
            buttonBar
        }
        .frame(minWidth: 500, minHeight: 200)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onKeyPress { handleKeyPress($0) }
    }

    // MARK: - Subviews

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            Text(searchText.isEmpty ? "Type to search…" : searchText)
                .foregroundStyle(searchText.isEmpty ? .tertiary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var commandList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(commands) { cmd in
                        ExtCmdRow(
                            entry: cmd,
                            isSelected: !commands.isEmpty && commands[selectedIndex].id == cmd.id
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let idx = commands.firstIndex(where: { $0.id == cmd.id }) {
                                selectedIndex = idx
                            }
                        }
                        .id(cmd.id)
                    }
                }
            }
            .contentMargins(.vertical, 4, for: .scrollContent)
            .onChange(of: selectedIndex) { _, newIdx in
                guard newIdx < commands.count else { return }
                proxy.scrollTo(commands[newIdx].id, anchor: .center)
            }
        }
    }

    private var buttonBar: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.escape, modifiers: [])
            Spacer()
            Button("Accept") { acceptSelected() }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .disabled(commands.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private func acceptSelected() {
        guard !commands.isEmpty, selectedIndex < commands.count else { return }
        onAccept(commands[selectedIndex].id)
    }

    private func moveSelection(by delta: Int) {
        guard !commands.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + commands.count) % commands.count
    }

    /// Update the selection to the first command whose name has `searchText` as a prefix.
    private func updateAutocomplete() {
        guard !searchText.isEmpty else { return }
        let lower = searchText.lowercased()
        if let idx = commands.firstIndex(where: { $0.name.lowercased().hasPrefix(lower) }) {
            selectedIndex = idx
        }
    }

    // MARK: - Key handling

    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        // Accelerator: ⌥char or ⌃char → find matching command and accept immediately.
        if press.modifiers.contains(.option) || press.modifiers.contains(.control) {
            if let idx = acceleratorIndex(for: press) {
                selectedIndex = idx
                acceptSelected()
                return .handled
            }
        }

        switch press.key {
        case .upArrow:
            moveSelection(by: -1)
            return .handled
        case .downArrow:
            moveSelection(by: 1)
            return .handled
        case .tab:
            moveSelection(by: press.modifiers.contains(.shift) ? -1 : 1)
            return .handled
        default:
            break
        }

        // Printable ASCII → append to search buffer and autocomplete.
        let chars = press.characters
        // The macOS Delete key (⌫) sends \u{7F} (DEL, 127). KeyEquivalent.delete is
        // defined as \u{8} (BS, 8) and never matches, so we check characters directly.
        if chars == "\u{7F}" {
            if !searchText.isEmpty {
                searchText.removeLast()
                updateAutocomplete()
            }
            return .handled
        }
        if !chars.isEmpty && chars.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value < 127 }) {
            searchText += chars
            updateAutocomplete()
            return .handled
        }

        // Return and ESC are bound to the buttons via keyboardShortcut; let them through.
        return .ignored
    }

    /// Returns the index in `commands` whose `key` byte matches the accelerator pressed,
    /// or `nil` if no command has that binding.
    private func acceleratorIndex(for press: KeyPress) -> Int? {
        let baseChar = press.key.character
        guard let ascii = baseChar.asciiValue else { return nil }
        let keyByte: UInt8 = press.modifiers.contains(.option) ? (0x80 | ascii) : (ascii & 0x1f)
        guard keyByte != 0 else { return nil }
        return commands.firstIndex { $0.key == keyByte }
    }
}

// MARK: - Row

private struct ExtCmdRow: View {
    let entry: ExtCmdEntry
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isSelected ? "circle.inset.filled" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 16)

            Text(entry.keyDisplayString)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)

            Text(entry.name)
                .font(.system(.body, design: .monospaced))
                .frame(width: 110, alignment: .leading)

            Text(entry.description)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
    }
}
