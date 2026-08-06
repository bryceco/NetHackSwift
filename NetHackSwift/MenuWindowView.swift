import SwiftUI

// MARK: - Data Model

struct MenuCategory: Identifiable {
    var id = UUID()
    var title: String
    var items: [MenuItemData]
}

struct MenuItemData: Identifiable {
    var id = UUID()
    var key: String         // inventory letter, e.g. "a"
    var image: NSImage?
    var text: String
}

// MARK: - View

struct MenuWindowView: View {
    let categories: [MenuCategory]
    /// When true, checkboxes appear and Accept/Cancel/All buttons are shown.
    /// When false, a single Close button is shown.
    let isSelectable: Bool
    var onAccept: ([MenuItemData]) -> Void
    var onCancel: () -> Void

    @State private var selectedIDs: Set<UUID> = []
    @State private var sortAlphabetically = false

    // Cap the scroll area at 70% of the screen so the window never grows off-screen.
    private var maxScrollHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 800) * 0.7
    }

    private var allItems: [MenuItemData] { categories.flatMap { $0.items } }

    private var displayCategories: [MenuCategory] {
        guard sortAlphabetically else { return categories }
        return categories.map { cat in
            MenuCategory(title: cat.title,
                         items: cat.items.sorted { $0.text < $1.text })
        }
    }

    private var selectedItems: [MenuItemData] {
        allItems.filter { selectedIDs.contains($0.id) }
    }

    private func toggleSelectAll() {
        if selectedIDs.count == allItems.count {
            selectedIDs = []
        } else {
            selectedIDs = Set(allItems.map { $0.id })
        }
    }

    @ViewBuilder
    private var itemList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(displayCategories) { category in
                Text(category.title)
                    .font(.headline)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                    .padding(.horizontal, 20)

                ForEach(category.items) { item in
                    MenuItemRow(
                        item: item,
                        isSelectable: isSelectable,
                        isSelected: Binding(
                            get: { selectedIDs.contains(item.id) },
                            set: { selected in
                                if selected { selectedIDs.insert(item.id) }
                                else { selectedIDs.remove(item.id) }
                            }
                        )
                    )
                }
            }
        }
        .padding(.bottom, 8)
    }

    var body: some View {
        VStack(spacing: 0) {

            // Abc sort toggle pinned to the top-right
            HStack {
                Spacer()
                Toggle(isOn: $sortAlphabetically) {
                    Text("Abc").font(.system(size: 12).italic())
                }
                .toggleStyle(.button)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            // ViewThatFits tries the plain VStack first (no scroll, window sizes to
            // content). If the content is taller than maxScrollHeight it falls back
            // to the ScrollView automatically — single-pass, no preference keys.
            ViewThatFits(in: .vertical) {
                itemList
                ScrollView { itemList }
            }
            .frame(maxHeight: maxScrollHeight)

            Divider()

            // Button row
            HStack(spacing: 14) {
                if isSelectable {
                    Button("All", action: toggleSelectAll)
                        .keyboardShortcut("a", modifiers: .command)
                }
                Spacer()
                if isSelectable {
                    Button("Cancel", action: onCancel)
                        .keyboardShortcut(.escape, modifiers: [])
                    Button("Accept") { onAccept(selectedItems) }
                        .keyboardShortcut(.return, modifiers: [])
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedIDs.isEmpty)
                } else {
                    Button("Close") { onAccept(allItems) }
                        .keyboardShortcut(.return, modifiers: [])
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(minWidth: 250, minHeight: 100)
    }
}

// MARK: - Item Row

private struct MenuItemRow: View {
    let item: MenuItemData
    let isSelectable: Bool
    @Binding var isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isSelectable {
                Toggle("", isOn: $isSelected)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
            }

            if let image = item.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
            } else {
                Color.clear.frame(width: 32, height: 32)
            }

            Text("(\(item.key))")
                .foregroundStyle(.secondary)

            Text(item.text)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectable { isSelected.toggle() }
        }
    }
}

// MARK: - Previews

private let sampleCategories: [MenuCategory] = [
    MenuCategory(title: "Weapons", items: [
        MenuItemData(key: "a", text: "a +0 katana (weapon in hand)"),
        MenuItemData(key: "c", text: "a +0 yumi"),
        MenuItemData(key: "d", text: "44 +0 ya (in quiver)"),
        MenuItemData(key: "f", text: "a +0 wakizashi (alternate weapon; not wielded)"),
    ]),
    MenuCategory(title: "Armor", items: [
        MenuItemData(key: "e", text: "an uncursed rustproof +0 splint mail (being worn)"),
    ]),
    MenuCategory(title: "Comestibles", items: [
        MenuItemData(key: "j", text: "a tin"),
    ]),
    MenuCategory(title: "Tools", items: [
        MenuItemData(key: "b", text: "a bag containing 4 items"),
    ]),
]

#Preview("Display Only") {
    MenuWindowView(
        categories: sampleCategories,
        isSelectable: false,
        onAccept: { _ in },
        onCancel: { }
    )
    .frame(width: 398)
}

#Preview("Selectable") {
    MenuWindowView(
        categories: sampleCategories,
        isSelectable: true,
        onAccept: { _ in },
        onCancel: { }
    )
    .frame(width: 398)
}
