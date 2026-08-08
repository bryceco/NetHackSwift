import Observation
import SwiftUI

@Observable final class MessageWindowModel {
    var messages: [String] = []
    /// Flat string passed to MessageWindowView; rebuilt whenever messages changes.
    var text: String { messages.joined(separator: "\n") }
}

struct MessagesView: View {
    var model: MessageWindowModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.messages.enumerated()), id: \.offset) { i, message in
                        Text(message)
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(i)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
            .onChange(of: model.messages.count) { _, count in
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
    let model = MessageWindowModel()
    model.messages = [
        "Hello, welcome to NetHack!",
        "You see a goblin.",
        "You hit the goblin.",
        "The goblin bites!",
        "You feel hungry.",
    ]
    return MessagesView(model: model)
        .frame(width: 153, height: 160)
}
