import SwiftUI

struct EquipmentView: View {
    @Environment(GameState.self) private var gameState

    // Slot order matches the 4×3 grid in the XIB (row-major, top to bottom)
    private let slotOrder: [EquipmentSlot] = [
        .amulet,     .helmet,  .blindfold,
        .weaponHand, .armor,   .alternateHand,
        .gloves,     .shirt,   .cloak,
        .ringLeft,   .boots,   .ringRight,
    ]

    private let columns = Array(repeating: GridItem(.fixed(32), spacing: 0), count: 3)

    var body: some View {
        VStack(spacing: 5) {
            Text("Wearing:")
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(slotOrder, id: \.self) { slot in
                    SlotView(image: gameState.equipment[slot])
                }
            }
            .frame(width: 96, height: 128)
        }
        .padding(.top, 2)
    }
}

private struct SlotView: View {
    var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(white: 0.75))
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(2)
            }
        }
        .frame(width: 32, height: 32)
    }
}

#Preview {
    EquipmentView()
        .environment(GameState())
        .frame(width: 118, height: 160)
}
