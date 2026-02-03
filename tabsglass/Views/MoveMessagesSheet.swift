//
//  MoveMessagesSheet.swift
//  tabsglass
//
//  Sheet for selecting destination tab when moving messages
//

import SwiftUI

struct MoveMessagesSheet: View {
    let tabs: [Tab]
    let currentTabId: UUID?
    let onMove: (UUID?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Show Inbox option if not already in Inbox
                if currentTabId != nil {
                    Button {
                        onMove(nil)
                        dismiss()
                    } label: {
                        Label(L10n.Reorder.inbox, systemImage: "tray")
                    }
                    .buttonStyle(.plain)
                }

                // Show other tabs (excluding current tab)
                ForEach(tabs.filter { $0.id != currentTabId }) { tab in
                    Button {
                        onMove(tab.id)
                        dismiss()
                    } label: {
                        Text(tab.title)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle(L10n.Selection.moveTo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Tab.cancel) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    MoveMessagesSheet(
        tabs: [],
        currentTabId: nil,
        onMove: { _ in }
    )
}
