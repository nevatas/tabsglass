//
//  MainContainerView.swift
//  tabsglass
//

import SwiftUI
import SwiftData

struct MainContainerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tab.sortOrder) private var tabs: [Tab]
    @State private var selectedTabIndex = 0
    @State private var showNewTabSheet = false
    @State private var messageText = ""
    @State private var scrollProgress: CGFloat = 0
    @FocusState private var isComposerFocused: Bool

    private var currentTab: Tab? {
        guard selectedTabIndex >= 0 && selectedTabIndex < tabs.count else { return nil }
        return tabs[selectedTabIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            TabBarView(
                tabs: tabs,
                selectedIndex: $selectedTabIndex,
                scrollProgress: scrollProgress,
                onAddTap: { showNewTabSheet = true }
            )

            if tabs.isEmpty {
                emptyStateView
            } else {
                UnifiedChatView(
                    tabs: tabs,
                    selectedIndex: $selectedTabIndex,
                    messageText: $messageText,
                    scrollProgress: $scrollProgress,
                    onSend: { sendMessage() }
                )
            }
        }
        .sheet(isPresented: $showNewTabSheet) {
            NewTabSheet { title in
                createTab(title: title)
            }
        }
        .onAppear {
            createDefaultTabIfNeeded()
        }
        .onChange(of: tabs.count) { oldValue, newValue in
            if newValue > oldValue && newValue > 0 {
                selectedTabIndex = newValue - 1
            }
            if selectedTabIndex >= newValue && newValue > 0 {
                selectedTabIndex = newValue - 1
            }
        }
        .onChange(of: selectedTabIndex) { _, newValue in
            // Sync scrollProgress when tab is selected by tap
            withAnimation(.easeInOut(duration: 0.2)) {
                scrollProgress = CGFloat(newValue)
            }
        }
    }

    private func sendMessage() {
        guard let tab = currentTab else { return }
        let trimmedText = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        let message = Message(text: trimmedText, tab: tab)
        modelContext.insert(message)
        messageText = ""
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
                showNewTabSheet = true
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
        let newTab = Tab(title: title, sortOrder: tabs.count)
        modelContext.insert(newTab)
    }
}

#Preview {
    MainContainerView()
        .modelContainer(for: [Tab.self, Message.self], inMemory: true)
}
