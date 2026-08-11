import NetHackBridge
import SwiftUI

struct EquipmentView: View {
    @Environment(GameState.self) private var gameState

    // Slot order matches the 4×3 grid (row-major, top to bottom)
    private let slotOrder: [NHEquipSlot] = [
        .amulet,   .helmet, .blindfold,
        .weapon,   .armor,  .altHand,
        .gloves,   .shirt,  .cloak,
        .ringLeft, .boots,  .ringRight,
    ]

    private let columns = Array(repeating: GridItem(.fixed(32), spacing: 0), count: 3)

    var body: some View {
        VStack(spacing: 5) {
            Text("Wearing:")
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(slotOrder, id: \.self) { slot in
                    SlotView(item: gameState.equipment[slot])
                }
            }
            .frame(width: 96, height: 128)
        }
        .padding(.top, 2)
    }
}

private struct SlotView: View {
    var item: NHEquipItem?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(white: 0.75))
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
            if let item,
			   let tileImage = TileSet.shared?.image(forGlyph: item.glyph)
			{
                Image(nsImage: tileImage)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 30, height: 30)
            }
        }
        .frame(width: 32, height: 32)
        .help(item?.name ?? "")
    }
}

#Preview {
    EquipmentView()
        .environment(GameState())
        .frame(width: 118, height: 160)
}
