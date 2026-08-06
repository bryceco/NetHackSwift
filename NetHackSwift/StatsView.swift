import SwiftUI

struct StatsView: View {
    @Environment(GameState.self) private var gameState

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Player name and role
            HStack(spacing: 20) {
                Text(gameState.playerName).bold()
                Text(gameState.role)
            }
            Text(gameState.dlvl)

            Divider()

            // HP / Pw with progress meters
            Grid(alignment: .leading, horizontalSpacing: 3, verticalSpacing: 5) {
                GridRow {
                    Text("Hp:")
                    Text(gameState.hpDisplay).bold()
                    Meter(value: fraction(gameState.hp, of: gameState.maxHp))
                    Text("Level:")
                    Text("\(gameState.level)").bold()
                    Text("XP:")
                    Text("\(gameState.xp)").bold()
                }
                GridRow {
                    Text("Pw:")
                    Text(gameState.pwDisplay).bold()
                    Meter(value: fraction(gameState.pw, of: gameState.maxPw))
                    Text("AC:")
                    Text("\(gameState.ac)").bold()
                    Text("$:")
                    Text("\(gameState.gold)").bold()
                }
            }

            Divider()

            // Attributes
            Grid(alignment: .leading, horizontalSpacing: 3, verticalSpacing: 5) {
                GridRow {
                    Text("Str:"); Text(gameState.str).bold()
                    Text("Dex:"); Text("\(gameState.dex)").bold()
                    Text("Con:"); Text("\(gameState.con)").bold()
                    Text("Turn:"); Text("\(gameState.turn)").bold()
                }
                GridRow {
                    Text("Int:"); Text("\(gameState.int_)").bold()
                    Text("Wis:"); Text("\(gameState.wis)").bold()
                    Text("Cha:"); Text("\(gameState.cha)").bold()
                    // Pad to match row 1's column count
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                }
            }

            Divider()

            // Status effects (empty string → invisible but still takes space)
            Text(gameState.statusEffects.isEmpty ? " " : gameState.statusEffects)
                .bold()
                .foregroundStyle(.red)
        }
        .padding(.leading, 20)
        .padding(.vertical, 5)
    }

    private func fraction(_ value: Int, of maximum: Int) -> Double {
        guard maximum > 0 else { return 0 }
        return max(0, min(1, Double(value) / Double(maximum)))
    }
}

// Horizontal capacity bar, matching NSLevelIndicator's continuousCapacity style
private struct Meter: View {
    var value: Double  // 0.0 – 1.0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(.quaternary)
                Rectangle().fill(barColor)
                    .frame(width: geo.size.width * value)
            }
            .clipShape(RoundedRectangle(cornerRadius: 2))
        }
        .frame(width: 60, height: 10)
    }

    private var barColor: Color {
        if value > 0.5 { return .green }
        if value > 0.25 { return .yellow }
        return .red
    }
}

#Preview {
    let state = GameState()
    state.playerName = "Vlad the Enchanter"
    state.role = "Neutral Human Wizard"
    state.dlvl = "The Astral Plane"
    state.hp = 222; state.maxHp = 333
    state.pw = 222; state.maxPw = 333
    state.level = 23; state.xp = 999999
    state.ac = -23; state.gold = 999999
    state.str = "18/01"; state.dex = 18; state.con = 18
    state.int_ = 18; state.wis = 18; state.cha = 18
    state.turn = 9999999
    state.statusEffects = "Confused, Stunned, Hallucinating"
    return StatsView()
        .environment(state)
        .frame(width: 366, height: 160)
}
