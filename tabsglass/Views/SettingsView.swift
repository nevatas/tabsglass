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
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        Label("Оформление", systemImage: "paintbrush")
                    }

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

// MARK: - Appearance Settings View

struct AppearanceSettingsView: View {
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        List {
            // Standard themes section
            Section {
                ForEach(0..<AppTheme.standardThemes.count, id: \.self) { index in
                    let theme = AppTheme.standardThemes[index]
                    ThemeRowView(
                        theme: theme,
                        isSelected: themeManager.currentTheme == theme,
                        onSelect: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                themeManager.currentTheme = theme
                            }
                        }
                    )
                }
            }

            // Color themes section
            Section {
                ForEach(0..<AppTheme.colorThemes.count, id: \.self) { index in
                    let theme = AppTheme.colorThemes[index]
                    ThemeRowView(
                        theme: theme,
                        isSelected: themeManager.currentTheme == theme,
                        onSelect: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                themeManager.currentTheme = theme
                            }
                        }
                    )
                }
            }
        }
        .navigationTitle("Оформление")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ThemeRowView: View {
    let theme: AppTheme
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: theme.iconName)
                    .font(.system(size: 17))
                    .frame(width: 28)
                    .foregroundStyle(themeColorPreview)

                Text(theme.displayName)
                    .foregroundStyle(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    private var themeColorPreview: Color {
        switch theme {
        case .system:
            return .secondary
        case .light:
            return .orange
        case .dark:
            return .indigo
        case .pink:
            return Color(red: 0xFF/255, green: 0x69/255, blue: 0xB4/255)
        case .beige:
            return Color(red: 0xD2/255, green: 0xB4/255, blue: 0x8C/255)
        case .green:
            return Color(red: 0x4C/255, green: 0xAF/255, blue: 0x50/255)
        case .brown:
            return Color(red: 0x8D/255, green: 0x6E/255, blue: 0x63/255)
        case .blue:
            return Color(red: 0x42/255, green: 0xA5/255, blue: 0xF5/255)
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [Tab.self, Message.self], inMemory: true)
}
