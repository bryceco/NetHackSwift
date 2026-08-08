import SwiftUI

struct MainWindowView: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                StatsView()
                    .frame(width: 366, height: 160)
                EquipmentView()
                    .frame(width: 118, height: 160)
                MessagesView(model: MessageWindowModel())
                    .frame(minWidth: 153, maxWidth: .infinity)
                    .frame(height: 160)
            }
            MapView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 637, maxWidth: .infinity, minHeight: 376, maxHeight: .infinity)
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
    state.messages = ["You hit the goblin.",
					  "The goblin bites!",
					  "You feel hungry."]
    return MainWindowView()
        .environment(state)
}
