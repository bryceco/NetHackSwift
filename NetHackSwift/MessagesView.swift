import SwiftUI

struct MessagesView: View {
    @Environment(GameState.self) private var gameState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(gameState.messages.enumerated()), id: \.offset) { i, message in
                        Text(message)
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(i)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
            .onChange(of: gameState.messages.count) { _, count in
                if count > 0 {
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1)
        }
    }
}

#Preview {
    let state = GameState()
    state.messages = [
        "Hello, welcome to NetHack!",
        "You see a goblin.",
        "You hit the goblin.",
        "The goblin bites!",
        "You feel hungry.",
    ]
    return MessagesView()
        .environment(state)
        .frame(width: 153, height: 160)
}
