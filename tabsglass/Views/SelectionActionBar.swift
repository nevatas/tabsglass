//
//  SelectionActionBar.swift
//  tabsglass
//
//  Action bar for bulk message selection mode with Liquid Glass style
//

import SwiftUI

struct SelectionActionBar: View {
    let selectedCount: Int
    let canMove: Bool  // false if no tabs to move to
    let tabs: [Tab]
    let currentTabId: UUID?
    let onMove: (UUID?) -> Void  // targetTabId (nil = Inbox)
    let onMoveToNewTab: () -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var themeManager: ThemeManager { ThemeManager.shared }

    private var isMoveDisabled: Bool {
        selectedCount == 0
    }

    /// Accent color for icons and text (uses theme color or falls back to primary)
    private var accentColor: Color {
        themeManager.currentTheme.accentColor ?? (colorScheme == .dark ? .white : .primary)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Move — Menu outside GlassEffectContainer for proper morph animation
            Menu {
                Button {
                    onMoveToNewTab()
                } label: {
                    Label(L10n.Tab.new, systemImage: "plus")
                }
                Divider()
                if currentTabId != nil {
                    Button {
                        onMove(nil)
                    } label: {
                        Text(L10n.Reorder.inbox)
                    }
                }
                let otherTabs = tabs.filter { $0.id != currentTabId }
                ForEach(otherTabs) { tab in
                    Button {
                        onMove(tab.id)
                    } label: {
                        Text(tab.title)
                    }
                }
            } label: {
                Label(L10n.Selection.move, systemImage: "folder")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .tint(accentColor)
            .disabled(isMoveDisabled)
            .opacity(isMoveDisabled ? 0.5 : 1)

            // Delete
            Button(action: onDelete) {
                Label(L10n.Selection.delete, systemImage: "trash")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .tint(.red)
            .disabled(selectedCount == 0)
            .opacity(selectedCount == 0 ? 0.5 : 1)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .padding(.bottom, 8)
    }
}

struct SelectionCancelBar: View {
    let selectedCount: Int
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var themeManager: ThemeManager { ThemeManager.shared }

    private var composerTint: Color {
        let theme = themeManager.currentTheme
        return colorScheme == .dark ? theme.composerTintColorDark : theme.composerTintColor
    }

    /// Accent color for icons (uses theme color or falls back to primary)
    private var accentColor: Color {
        themeManager.currentTheme.accentColor ?? (colorScheme == .dark ? .white : .primary)
    }

    var body: some View {
        HStack {
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(accentColor)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)

            Spacer()

            Text(L10n.Selection.count(selectedCount))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular.tint(composerTint), in: .capsule)

            Spacer()

            // Invisible spacer to balance the layout
            Color.clear
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}

#Preview {
    VStack {
        SelectionCancelBar(
            selectedCount: 2,
            onCancel: {}
        )
        Spacer()
        SelectionActionBar(
            selectedCount: 2,
            canMove: true,
            tabs: [],
            currentTabId: nil,
            onMove: { _ in },
            onMoveToNewTab: {},
            onDelete: {}
        )
    }
    .background(Color.gray.opacity(0.2))
}
