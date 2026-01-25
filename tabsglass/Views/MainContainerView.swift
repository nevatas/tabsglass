//
//  MainContainerView.swift
//  tabsglass
//

import SwiftUI
import SwiftData
import UIKit

struct MainContainerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tab.sortOrder) private var tabs: [Tab]
    @State private var selectedTabIndex = 0
    @State private var showNewTabAlert = false
    @State private var showRenameAlert = false
    @State private var showDeleteAlert = false
    @State private var tabToRename: Tab?
    @State private var tabToDelete: Tab?
    @State private var messageToEdit: Message?
    @State private var newTabTitle = ""
    @State private var renameTabTitle = ""
    @State private var messageText = ""
    @State private var scrollProgress: CGFloat = 0
    @State private var attachedImages: [UIImage] = []

    private var currentTab: Tab? {
        guard selectedTabIndex >= 0 && selectedTabIndex < tabs.count else { return nil }
        return tabs[selectedTabIndex]
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Content layer (full screen)
            if tabs.isEmpty {
                emptyStateView
            } else {
                UnifiedChatView(
                    tabs: tabs,
                    selectedIndex: $selectedTabIndex,
                    messageText: $messageText,
                    scrollProgress: $scrollProgress,
                    attachedImages: $attachedImages,
                    onSend: { sendMessage() },
                    onDeleteMessage: { message in
                        deleteMessage(message)
                    },
                    onMoveMessage: { message, targetTab in
                        moveMessage(message, to: targetTab)
                    },
                    onEditMessage: { message in
                        messageToEdit = message
                    }
                )
                .ignoresSafeArea(.keyboard)
                .scrollEdgeEffectStyle(.soft, for: .top)
            }

            // Header layer (floating on top)
            TabBarView(
                tabs: tabs,
                selectedIndex: $selectedTabIndex,
                scrollProgress: scrollProgress,
                onAddTap: {
                    newTabTitle = ""
                    showNewTabAlert = true
                },
                onMenuTap: { /* TODO: Open menu */ },
                onRenameTab: { tab in
                    tabToRename = tab
                    renameTabTitle = tab.title
                    showRenameAlert = true
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
        .alert("Удалить таб?", isPresented: $showDeleteAlert) {
            Button("Отмена", role: .cancel) { }
            Button("Удалить", role: .destructive) {
                if let tab = tabToDelete {
                    deleteTab(tab)
                }
            }
        } message: {
            if let tab = tabToDelete {
                Text("Таб \"\(tab.title)\" и все его сообщения будут удалены")
            }
        }
        .onAppear {
            createDefaultTabIfNeeded()
        }
        .onChange(of: tabs.count) { oldValue, newValue in
            if newValue > oldValue && newValue > 0 {
                // New tab created - select it with animation
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTabIndex = newValue - 1
                    scrollProgress = CGFloat(newValue - 1)
                }
            }
            if selectedTabIndex >= newValue && newValue > 0 {
                selectedTabIndex = newValue - 1
            }
        }
        .onChange(of: selectedTabIndex) { _, newValue in
            let targetProgress = CGFloat(newValue)
            // Only animate if far from target (tap on tab), otherwise just set (end of swipe)
            if abs(scrollProgress - targetProgress) > 0.3 {
                withAnimation(.easeInOut(duration: 0.2)) {
                    scrollProgress = targetProgress
                }
            } else {
                scrollProgress = targetProgress
            }
        }
        .sheet(item: $messageToEdit) { message in
            EditMessageSheet(
                originalText: message.text,
                onSave: { newText in
                    message.text = newText
                    messageToEdit = nil
                },
                onCancel: {
                    messageToEdit = nil
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
    }

    private func sendMessage() {
        let trimmedText = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        // Allow sending if there's text OR images
        guard !trimmedText.isEmpty || !attachedImages.isEmpty else { return }
        guard let tab = currentTab else { return }

        // Save attached images and get file names
        var photoFileNames: [String] = []
        for image in attachedImages {
            if let fileName = Message.savePhoto(image) {
                photoFileNames.append(fileName)
            }
        }

        let message = Message(text: trimmedText, tab: tab, photoFileNames: photoFileNames)
        modelContext.insert(message)
        messageText = ""
        attachedImages = []
    }

    private func deleteMessage(_ message: Message) {
        // Delete photo files first
        message.deletePhotoFiles()
        modelContext.delete(message)
    }

    private func moveMessage(_ message: Message, to targetTab: Tab) {
        message.tab = targetTab
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "note.text")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("No tabs yet")
                .font(.title2)
                .foregroundStyle(.secondary)
            Button("Create your first tab") {
                newTabTitle = ""
                showNewTabAlert = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func createDefaultTabIfNeeded() {
        if tabs.isEmpty {
            let defaultTab = Tab(title: "Notes", sortOrder: 0)
            modelContext.insert(defaultTab)
        }
    }

    private func createTab(title: String) {
        let maxSortOrder = tabs.map(\.sortOrder).max() ?? -1
        let newTab = Tab(title: title, sortOrder: maxSortOrder + 1)
        modelContext.insert(newTab)
    }

    private func renameTab(_ tab: Tab, to newTitle: String) {
        tab.title = newTitle
    }

    private func deleteTab(_ tab: Tab) {
        // Adjust selected index if needed
        if let index = tabs.firstIndex(where: { $0.id == tab.id }) {
            if selectedTabIndex >= index && selectedTabIndex > 0 {
                selectedTabIndex -= 1
            }
        }
        modelContext.delete(tab)
    }
}

#Preview {
    MainContainerView()
        .modelContainer(for: [Tab.self, Message.self], inMemory: true)
}
