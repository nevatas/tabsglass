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
    let onMove: () -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var themeManager: ThemeManager { ThemeManager.shared }

    private var composerTint: Color {
        let theme = themeManager.currentTheme
        return colorScheme == .dark ? theme.composerTintColorDark : theme.composerTintColor
    }

    private var isMoveDisabled: Bool {
        selectedCount == 0 || !canMove
    }

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 12) {
                // Move
                Button(action: onMove) {
                    Label(L10n.Selection.move, systemImage: "folder")
                        .font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .glassEffect(.regular.tint(composerTint), in: .capsule)
                .disabled(isMoveDisabled)
                .opacity(isMoveDisabled ? 0.5 : 1)

                // Delete
                Button(action: onDelete) {
                    Label(L10n.Selection.delete, systemImage: "trash")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .glassEffect(.regular.tint(composerTint), in: .capsule)
                .disabled(selectedCount == 0)
                .opacity(selectedCount == 0 ? 0.5 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .padding(.horizontal, 12)
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

    var body: some View {
        GlassEffectContainer {
            HStack {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .padding(12)
                }
                .glassEffect(.regular.tint(composerTint), in: .circle)

                Spacer()

                Text(L10n.Selection.count(selectedCount))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                // Invisible spacer to balance the layout
                Color.clear
                    .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
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
            onMove: {},
            onDelete: {}
        )
    }
    .background(Color.gray.opacity(0.2))
}
