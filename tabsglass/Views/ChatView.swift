//
//  ChatView.swift
//  tabsglass
//

import SwiftUI
import SwiftData

struct ChatView: View {
    let tab: Tab
    var bottomInset: CGFloat = 0
    var onTapContent: (() -> Void)? = nil
    @Environment(\.modelContext) private var modelContext

    var sortedMessages: [Message] {
        tab.messages.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if sortedMessages.isEmpty {
                        emptyMessagesView
                    } else {
                        ForEach(sortedMessages) { message in
                            MessageBubbleView(message: message) {
                                deleteMessage(message)
                            }
                            .id(message.id)
                        }
                    }
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .contentMargins(.bottom, bottomInset, for: .scrollContent)
            .animation(.easeInOut(duration: 0.25), value: bottomInset)
            .onTapGesture {
                onTapContent?()
            }
            .onChange(of: sortedMessages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onAppear {
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private var emptyMessagesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("No messages yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Type a note below to get started")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastId = sortedMessages.last?.id {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }

    private func deleteMessage(_ message: Message) {
        modelContext.delete(message)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Tab.self, Message.self, configurations: config)
    let tab = Tab(title: "Preview Tab")
    container.mainContext.insert(tab)

    return ChatView(tab: tab)
        .modelContainer(container)
}
