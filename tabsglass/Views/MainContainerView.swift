//
//  MainContainerView.swift
//  tabsglass
//

import SwiftUI
import SwiftData
import UIKit

struct MainContainerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tab.position) private var tabs: [Tab]
    @Query(sort: \Message.createdAt) private var allMessages: [Message]
    @State private var selectedTabIndex = 0  // 0 = Inbox (virtual), 1+ = real tabs
    @State private var showNewTabAlert = false
    @State private var showRenameAlert = false
    @State private var showRenameInboxAlert = false
    @State private var showDeleteAlert = false
    @State private var showSettings = false
    @State private var tabToRename: Tab?
    @State private var tabToDelete: Tab?
    @State private var messageToEdit: Message?
    @State private var newTabTitle = ""
    @State private var renameTabTitle = ""
    @State private var renameInboxTitle = ""
    @State private var messageText = ""
    @State private var switchFraction: CGFloat = 0  // -1.0 to 1.0 swipe progress
    @State private var attachedImages: [UIImage] = []

    /// Total number of tabs including virtual Inbox
    private var totalTabCount: Int {
        1 + tabs.count  // Inbox + real tabs
    }

    /// Get tabId for current selection (nil = Inbox)
    private var currentTabId: UUID? {
        guard selectedTabIndex > 0 && selectedTabIndex <= tabs.count else { return nil }
        return tabs[selectedTabIndex - 1].id
    }

    /// Check if currently on Inbox
    private var isOnInbox: Bool {
        selectedTabIndex == 0
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Content layer (full screen)
            // Always show chat view (Inbox is always available as virtual tab)
            UnifiedChatView(
                tabs: tabs,
                messages: allMessages,
                selectedIndex: $selectedTabIndex,
                messageText: $messageText,
                switchFraction: $switchFraction,
                attachedImages: $attachedImages,
                onSend: { sendMessage() },
                onDeleteMessage: { message in
                    deleteMessage(message)
                },
                onMoveMessage: { message, targetTabId in
                    moveMessage(message, toTabId: targetTabId)
                },
                onEditMessage: { message in
                    messageToEdit = message
                },
                onRestoreMessage: {
                    restoreDeletedMessage()
                }
            )
            .ignoresSafeArea(.keyboard)
            .scrollEdgeEffectStyle(.soft, for: .top)

            // Header layer (floating on top)
            TabBarView(
                tabs: tabs,
                selectedIndex: $selectedTabIndex,
                switchFraction: $switchFraction,
                onAddTap: {
                    newTabTitle = ""
                    showNewTabAlert = true
                },
                onMenuTap: { showSettings = true },
                onRenameTab: { tab in
                    tabToRename = tab
                    renameTabTitle = tab.title
                    showRenameAlert = true
                },
                onRenameInbox: {
                    renameInboxTitle = AppSettings.shared.inboxTitle
                    showRenameInboxAlert = true
                },
                onDeleteTab: { tab in
                    tabToDelete = tab
                    showDeleteAlert = true
                }
            )
        }
        .alert("Новый таб", isPresented: $showNewTabAlert) {
            TextField("Название", text: $newTabTitle)
            Button("Отмена", role: .cancel) { }
            Button("Создать") {
                let trimmed = newTabTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    createTab(title: trimmed)
                }
            }
        }
        .alert("Переименовать", isPresented: $showRenameAlert) {
            TextField("Название", text: $renameTabTitle)
            Button("Отмена", role: .cancel) { }
            Button("Сохранить") {
                let trimmed = renameTabTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, let tab = tabToRename {
                    renameTab(tab, to: trimmed)
                }
            }
        }
        .alert("Переименовать Inbox", isPresented: $showRenameInboxAlert) {
            TextField("Название", text: $renameInboxTitle)
            Button("Отмена", role: .cancel) { }
            Button("Сохранить") {
                let trimmed = renameInboxTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    AppSettings.shared.inboxTitle = trimmed
                }
            }
        }
        .alert("Удалить таб?", isPresented: $showDeleteAlert) {
            Button("Отмена", role: .cancel) { }
            Button("Удалить", role: .destructive) {
                if let tab = tabToDelete {
                    deleteTab(tab)
                }
            }
        } message: {
            if let tab = tabToDelete {
                Text("Таб \"\(tab.title)\" будет удалён, его сообщения перенесутся в Inbox")
            }
        }
        .onChange(of: tabs.count) { oldValue, newValue in
            if newValue > oldValue {
                // New tab created - select it with animation (index = newValue because of Inbox at 0)
                withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                    selectedTabIndex = newValue  // Last real tab index
                    switchFraction = 0
                }
            }
            // Ensure selected index is valid
            if selectedTabIndex > newValue {
                selectedTabIndex = max(0, newValue)
            }
        }
        .onChange(of: selectedTabIndex) { _, _ in
            // Reset fraction when tab changes (from tap or swipe completion)
            if abs(switchFraction) > 0.01 {
                withAnimation(.spring(duration: 0.2)) {
                    switchFraction = 0
                }
            }
        }
        .sheet(item: $messageToEdit) { message in
            EditMessageSheet(
                originalText: message.content,
                onSave: { newText in
                    message.content = newText
                    messageToEdit = nil
                },
                onCancel: {
                    messageToEdit = nil
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    private func sendMessage() {
        let trimmedText = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Allow sending if there's text OR images
        guard !trimmedText.isEmpty || !attachedImages.isEmpty else { return }

        // Save attached images and get file names with aspect ratios
        var photoFileNames: [String] = []
        var photoAspectRatios: [Double] = []
        for image in attachedImages {
            if let result = Message.savePhoto(image) {
                photoFileNames.append(result.fileName)
                photoAspectRatios.append(result.aspectRatio)
            }
        }

        // Detect URLs in text
        let entities = TextEntity.detectURLs(in: trimmedText)

        // tabId = nil for Inbox, or actual tab ID
        let message = Message(
            content: trimmedText,
            tabId: currentTabId,
            entities: entities.isEmpty ? nil : entities,
            photoFileNames: photoFileNames,
            photoAspectRatios: photoAspectRatios
        )
        modelContext.insert(message)
        messageText = ""
        attachedImages = []
    }

    private func deleteMessage(_ message: Message) {
        // Clean up previous deleted message's photos (if any)
        if let previousDeleted = DeletedMessageStore.shared.lastDeleted {
            for fileName in previousDeleted.photoFileNames {
                let url = Message.photosDirectory.appendingPathComponent(fileName)
                try? FileManager.default.removeItem(at: url)
            }
        }

        // Store for undo (don't delete photos yet)
        DeletedMessageStore.shared.store(message)

        // Delete from database (photos kept for potential restore)
        modelContext.delete(message)
    }

    private func moveMessage(_ message: Message, toTabId targetTabId: UUID?) {
        message.tabId = targetTabId
    }

    private func restoreDeletedMessage() {
        guard let snapshot = DeletedMessageStore.shared.popSnapshot() else { return }

        // Create new message with the snapshot data
        // tabId can be nil (Inbox) or a real tab ID
        let message = Message(
            content: snapshot.content,
            tabId: snapshot.tabId,
            entities: snapshot.entities,
            photoFileNames: snapshot.photoFileNames,
            photoAspectRatios: snapshot.photoAspectRatios,
            position: snapshot.position,
            sourceUrl: snapshot.sourceUrl,
            linkPreview: snapshot.linkPreview,
            mediaGroupId: snapshot.mediaGroupId
        )
        // Restore original creation date
        message.createdAt = snapshot.createdAt

        modelContext.insert(message)
    }

    private func createTab(title: String) {
        let maxPosition = tabs.map(\.position).max() ?? -1
        let newTab = Tab(title: title, position: maxPosition + 1)
        modelContext.insert(newTab)
    }

    private func renameTab(_ tab: Tab, to newTitle: String) {
        tab.title = newTitle
    }

    private func deleteTab(_ tab: Tab) {
        // Move all messages from this tab to Inbox (tabId = nil)
        let tabId = tab.id
        let descriptor = FetchDescriptor<Message>(predicate: #Predicate { $0.tabId == tabId })
        if let messages = try? modelContext.fetch(descriptor) {
            for message in messages {
                message.tabId = nil
            }
        }

        // Adjust selected index if needed (account for Inbox at index 0)
        if let index = tabs.firstIndex(where: { $0.id == tab.id }) {
            let tabIndex = index + 1  // +1 because Inbox is at 0
            if selectedTabIndex >= tabIndex {
                selectedTabIndex = max(0, selectedTabIndex - 1)
            }
        }

        modelContext.delete(tab)
    }
}

#Preview {
    MainContainerView()
        .modelContainer(for: [Tab.self, Message.self], inMemory: true)
}
