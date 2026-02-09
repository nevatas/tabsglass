//
//  ImportPreviewView.swift
//  tabsglass
//
//  Preview view for import with mode selection
//

import SwiftUI

struct ImportPreviewView: View {
    let manifest: ExportManifest
    let onImport: (ImportMode) -> Void
    let onCancel: () -> Void

    @State private var selectedMode: ImportMode = .replace

    private var themeManager: ThemeManager { ThemeManager.shared }

    var body: some View {
        NavigationStack {
            List {
                // Archive info section
                Section {
                    LabeledContent(L10n.Data.previewDate, value: formattedDate)
                    LabeledContent(L10n.Data.previewDevice, value: manifest.deviceName)
                    LabeledContent(L10n.Data.previewAppVersion, value: manifest.appVersion)
                } header: {
                    Text(L10n.Data.previewArchiveInfo)
                }

                // Content stats section
                Section {
                    LabeledContent(L10n.Data.previewTabs, value: "\(manifest.tabCount)")
                    LabeledContent(L10n.Data.previewMessages, value: "\(manifest.messageCount)")
                    LabeledContent(L10n.Data.previewPhotos, value: "\(manifest.photoCount)")
                    LabeledContent(L10n.Data.previewVideos, value: "\(manifest.videoCount)")
                    LabeledContent(L10n.Data.previewAudios, value: "\(manifest.audioCount)")
                } header: {
                    Text(L10n.Data.previewContents)
                }

                // Import mode section
                Section {
                    ForEach([ImportMode.replace, ImportMode.merge], id: \.self) { mode in
                        Button {
                            selectedMode = mode
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(mode == .replace ? L10n.Data.modeReplace : L10n.Data.modeMerge)
                                        .foregroundStyle(.primary)
                                    Text(mode == .replace ? L10n.Data.modeReplaceDescription : L10n.Data.modeMergeDescription)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if selectedMode == mode {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(themeManager.currentTheme.accentColor ?? .accentColor)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(L10n.Data.importMode)
                } footer: {
                    if selectedMode == .replace {
                        Text(L10n.Data.modeReplaceWarning)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(L10n.Data.importPreviewTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Tab.cancel) {
                        onCancel()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Data.importButton) {
                        onImport(selectedMode)
                    }
                }
            }
            .tint(themeManager.currentTheme.accentColor)
        }
        .preferredColorScheme(themeManager.currentTheme.colorSchemeOverride)
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: manifest.exportDate)
    }
}

#Preview {
    ImportPreviewView(
        manifest: ExportManifest(tabCount: 5, messageCount: 42, photoCount: 15, videoCount: 3, audioCount: 4, deviceName: "iPhone"),
        onImport: { _ in },
        onCancel: {}
    )
}
