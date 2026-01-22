//
//  MessageBubbleView.swift
//  tabsglass
//

import SwiftUI
import SwiftData

struct MessageBubbleView: View {
    let message: Message
    let onDelete: () -> Void

    var body: some View {
        Text(message.text)
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.accentColor.opacity(0.15))
            .foregroundStyle(.primary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contextMenu {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Tab.self, Message.self, configurations: config)
    let tab = Tab(title: "Preview")
    let message = Message(text: "This is a sample message to preview how it looks in the bubble view.", tab: tab)
    container.mainContext.insert(tab)
    container.mainContext.insert(message)

    return MessageBubbleView(message: message, onDelete: {})
        .padding()
        .modelContainer(container)
}
