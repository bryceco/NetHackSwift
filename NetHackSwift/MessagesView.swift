import SwiftUI

struct MessagesView: View {
    let messages: [String]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                        Text(message)
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
            .onChange(of: messages.count) {
                if let last = messages.indices.last {
                    proxy.scrollTo(last, anchor: .bottom)
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
    MessagesView(messages: [
        "Hello, welcome to NetHack!",
        "You see a goblin.",
        "You hit the goblin.",
        "The goblin bites!",
        "You feel hungry.",
    ])
    .frame(width: 153, height: 160)
}
