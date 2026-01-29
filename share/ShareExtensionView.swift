//
//  ShareExtensionView.swift
//  share
//
//  SwiftUI view for Share Extension UI
//

import SwiftUI

// MARK: - Localization helpers for Share Extension

private enum ShareL10n {
    static var whereToSave: String { NSLocalizedString("share.where_to_save", comment: "Where to save title") }
    static var cancel: String { NSLocalizedString("share.cancel", comment: "Cancel button") }
    static var save: String { NSLocalizedString("share.save", comment: "Save button") }
    static var inbox: String { NSLocalizedString("share.inbox", comment: "Inbox option") }
}

struct ShareExtensionView: View {
    let content: SharedContent
    let onCancel: () -> Void
    let onSave: (UUID?) -> Void

    @State private var selectedTabId: UUID? = nil
    @State private var tabs: [SharedTab] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // Inbox option (always first)
                    rowButton(title: ShareL10n.inbox, isSelected: selectedTabId == nil) {
                        selectedTabId = nil
                    }

                    // User tabs
                    ForEach(tabs) { tab in
                        rowButton(title: tab.title, isSelected: selectedTabId == tab.id) {
                            selectedTabId = tab.id
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(ShareL10n.whereToSave)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .fontWeight(.medium)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSave(selectedTabId)
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                    }
                    .disabled(content.isEmpty)
                }
            }
        }
        .onAppear {
            tabs = TabsSync.loadTabs()
        }
    }

    // MARK: - Row Button

    @ViewBuilder
    private func rowButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
