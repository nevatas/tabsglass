//
//  SettingsView.swift
//  tabsglass
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var autoFocusInput = AppSettings.shared.autoFocusInput
    @ObservedObject private var themeManager = ThemeManager.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        Label(L10n.Settings.appearance, systemImage: "paintbrush")
                    }

                    NavigationLink {
                        ReorderTabsView()
                    } label: {
                        Label(L10n.Settings.reorderTabs, systemImage: "arrow.up.arrow.down")
                    }
                }

                Section {
                    Toggle(isOn: $autoFocusInput) {
                        Label(L10n.Settings.autoFocus, systemImage: "keyboard")
                    }
                    .onChange(of: autoFocusInput) { _, newValue in
                        AppSettings.shared.autoFocusInput = newValue
                    }
                }

                Section {
                    Link(destination: URL(string: "https://example.com/privacy")!) {
                        Label(L10n.Settings.privacyPolicy, systemImage: "hand.raised")
                    }

                    Link(destination: URL(string: "https://example.com/terms")!) {
                        Label(L10n.Settings.terms, systemImage: "doc.text")
                    }

                    Link(destination: URL(string: "mailto:support@example.com")!) {
                        Label(L10n.Settings.contact, systemImage: "envelope")
                    }
                }
            }
            .navigationTitle(L10n.Settings.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.Settings.done) {
                        dismiss()
                    }
                }
            }
        }
        .tint(themeManager.currentTheme.accentColor)
    }
}

// MARK: - Reorder Tabs View

struct ReorderTabsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \tabsglass.Tab.position) private var tabs: [tabsglass.Tab]

    // Local state for reordering
    @State private var reorderableTabs: [tabsglass.Tab] = []
    @State private var hasAppeared = false

    var body: some View {
        List {
            // Inbox section (virtual, not editable)
            Section {
                HStack {
                    Text(L10n.Reorder.inbox)
                    Spacer()
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            } footer: {
                Text(L10n.Reorder.inboxFooter)
            }

            // Reorderable tabs
            if !reorderableTabs.isEmpty {
                Section {
                    ForEach(reorderableTabs) { tab in
                        Text(tab.title)
                    }
                    .onMove(perform: moveTab)
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle(L10n.Reorder.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !hasAppeared {
                reorderableTabs = tabs
                hasAppeared = true
            }
        }
        .onDisappear {
            savePositions()
        }
    }

    private func moveTab(from source: IndexSet, to destination: Int) {
        reorderableTabs.move(fromOffsets: source, toOffset: destination)
    }

    private func savePositions() {
        // Update position for all tabs (0-indexed)
        for (index, tab) in reorderableTabs.enumerated() {
            tab.position = index
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
        .navigationTitle(L10n.Settings.appearance)
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
                        .foregroundStyle(theme.accentColor ?? Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            return Color(red: 0xFF/255, green: 0x45/255, blue: 0x8A/255)
        case .beige:
            return Color(red: 0xC4/255, green: 0x9A/255, blue: 0x6C/255)
        case .green:
            return Color(red: 0x2E/255, green: 0xA0/255, blue: 0x4A/255)
        case .brown:
            return Color(red: 0x7D/255, green: 0x5A/255, blue: 0x4F/255)
        case .blue:
            return Color(red: 0x29/255, green: 0x8D/255, blue: 0xF5/255)
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [Tab.self, Message.self], inMemory: true)
}
