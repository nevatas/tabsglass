//
//  SettingsView.swift
//  tabsglass
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Tab.sortOrder) private var tabs: [Tab]
    @State private var autoFocusInput = AppSettings.shared.autoFocusInput

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ReorderTabsView()
                    } label: {
                        Label("Упорядочить табы", systemImage: "arrow.up.arrow.down")
                    }
                }

                Section {
                    Toggle(isOn: $autoFocusInput) {
                        Label("Автофокус ввода", systemImage: "keyboard")
                    }
                    .onChange(of: autoFocusInput) { _, newValue in
                        AppSettings.shared.autoFocusInput = newValue
                    }
                }

                Section {
                    Link(destination: URL(string: "https://example.com/privacy")!) {
                        Label("Политика Конфиденциальности", systemImage: "hand.raised")
                    }

                    Link(destination: URL(string: "https://example.com/terms")!) {
                        Label("Правила Пользования", systemImage: "doc.text")
                    }

                    Link(destination: URL(string: "mailto:support@example.com")!) {
                        Label("Связь с разработчиком", systemImage: "envelope")
                    }
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Reorder Tabs View

struct ReorderTabsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tab.sortOrder) private var tabs: [Tab]

    // Local state for reordering (excluding Inbox)
    @State private var reorderableTabs: [Tab] = []
    @State private var hasAppeared = false

    private var inboxTab: Tab? {
        tabs.first { $0.isInbox }
    }

    var body: some View {
        List {
            // Inbox always at top, not movable
            if let inbox = inboxTab {
                Section {
                    HStack {
                        Text(inbox.title)
                        Spacer()
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            // Reorderable tabs
            Section {
                ForEach(reorderableTabs) { tab in
                    Text(tab.title)
                }
                .onMove(perform: moveTab)
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Упорядочить")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !hasAppeared {
                reorderableTabs = tabs.filter { !$0.isInbox }
                hasAppeared = true
            }
        }
        .onDisappear {
            saveSortOrder()
        }
    }

    private func moveTab(from source: IndexSet, to destination: Int) {
        reorderableTabs.move(fromOffsets: source, toOffset: destination)
    }

    private func saveSortOrder() {
        // Inbox always has sortOrder 0
        inboxTab?.sortOrder = 0

        // Update sortOrder for reorderable tabs (starting from 1)
        for (index, tab) in reorderableTabs.enumerated() {
            tab.sortOrder = index + 1
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [Tab.self, Message.self], inMemory: true)
}
