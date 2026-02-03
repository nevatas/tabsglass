//
//  SettingsView.swift
//  tabsglass
//

import SwiftUI
import SwiftData
import WebKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allTabs: [Tab]
    @Query private var allMessages: [Message]

    @State private var autoFocusInput = AppSettings.shared.autoFocusInput
    @AppStorage("spaceName") private var spaceName = "Taby"
    @State private var themeManager = ThemeManager.shared

    // Export/Import state
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var showExportProgress = false
    @State private var showImportPicker = false
    @State private var showImportPreview = false
    @State private var exportProgress: ExportImportProgress?
    @State private var importProgress: ExportImportProgress?
    @State private var importManifest: ExportManifest?
    @State private var importFileURL: URL?
    @State private var showExportShareSheet = false
    @State private var exportedFileURL: URL?
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    private let exportImportService = ExportImportService()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Label(L10n.Settings.spaceName, systemImage: "character.cursor.ibeam")
                        Spacer()
                        TextField("Taby", text: $spaceName)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                            .onChange(of: spaceName) { _, newValue in
                                if newValue.count > 20 {
                                    spaceName = String(newValue.prefix(20))
                                }
                            }
                    }

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
                } footer: {
                    Text(L10n.Settings.autoFocusFooter)
                }

                Section {
                    Button {
                        startExport()
                    } label: {
                        Label(L10n.Data.export, systemImage: "square.and.arrow.up")
                    }
                    .disabled(isExporting || isImporting)

                    Button {
                        showImportPicker = true
                    } label: {
                        Label(L10n.Data.importData, systemImage: "square.and.arrow.down")
                    }
                    .disabled(isExporting || isImporting)
                }

                Section {
                    NavigationLink {
                        WebView(url: URL(string: "https://nevatas.github.io/taby-legal/PRIVACY_POLICY")!)
                            .navigationTitle(L10n.Settings.privacyPolicy)
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Label(L10n.Settings.privacyPolicy, systemImage: "hand.raised")
                    }

                    NavigationLink {
                        WebView(url: URL(string: "https://nevatas.github.io/taby-legal/TERMS_OF_USE")!)
                            .navigationTitle(L10n.Settings.terms)
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Label(L10n.Settings.terms, systemImage: "doc.text")
                    }

                    Link(destination: URL(string: "https://t.me/serejens")!) {
                        Label(L10n.Settings.contact, systemImage: "paperplane")
                    }
                }
            }
            .tint(themeManager.currentTheme.accentColor)
            .navigationTitle(L10n.Settings.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.Settings.done) {
                        dismiss()
                    }
                }
            }
            .overlay {
                if showExportProgress, let progress = exportProgress {
                    ExportProgressView(progress: progress, isExporting: true)
                }
                if isImporting, let progress = importProgress {
                    ExportProgressView(progress: progress, isExporting: false)
                }
            }
            .fileImporter(
                isPresented: $showImportPicker,
                allowedContentTypes: [UTType(filenameExtension: "taby") ?? .zip],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .sheet(isPresented: $showImportPreview) {
                if let manifest = importManifest {
                    ImportPreviewView(
                        manifest: manifest,
                        onImport: { mode in
                            showImportPreview = false
                            startImport(mode: mode)
                        },
                        onCancel: {
                            showImportPreview = false
                            cleanupImportFile()
                        }
                    )
                }
            }
            .sheet(isPresented: $showExportShareSheet) {
                if let url = exportedFileURL {
                    ShareSheet(items: [url])
                        .onDisappear {
                            // Clean up exported file after sharing
                            try? FileManager.default.removeItem(at: url)
                            exportedFileURL = nil
                        }
                }
            }
            .alert(alertTitle, isPresented: $showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
        .preferredColorScheme(themeManager.currentTheme.colorSchemeOverride)
    }

    // MARK: - Export

    private func startExport() {
        isExporting = true
        showExportProgress = true
        exportProgress = ExportImportProgress(phase: .preparing, current: 0, total: 1)

        Task {
            do {
                let archiveURL = try await exportImportService.exportData(
                    tabs: allTabs,
                    messages: allMessages
                ) { progress in
                    exportProgress = progress
                }

                await MainActor.run {
                    isExporting = false
                    showExportProgress = false
                    exportedFileURL = archiveURL
                    showExportShareSheet = true
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    showExportProgress = false
                    alertTitle = L10n.Data.exportError
                    alertMessage = error.localizedDescription
                    showAlert = true
                }
            }
        }
    }

    // MARK: - Import

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            // Copy to temp location (file picker gives security-scoped URL)
            guard url.startAccessingSecurityScopedResource() else {
                alertTitle = L10n.Data.importError
                alertMessage = "Cannot access file"
                showAlert = true
                return
            }

            defer { url.stopAccessingSecurityScopedResource() }

            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: tempURL)

            do {
                try FileManager.default.copyItem(at: url, to: tempURL)
                importFileURL = tempURL

                // Validate and show preview
                Task {
                    do {
                        let manifest = try await exportImportService.validateArchive(at: tempURL)
                        await MainActor.run {
                            importManifest = manifest
                            showImportPreview = true
                        }
                    } catch {
                        await MainActor.run {
                            cleanupImportFile()
                            alertTitle = L10n.Data.importError
                            alertMessage = error.localizedDescription
                            showAlert = true
                        }
                    }
                }
            } catch {
                alertTitle = L10n.Data.importError
                alertMessage = error.localizedDescription
                showAlert = true
            }

        case .failure(let error):
            alertTitle = L10n.Data.importError
            alertMessage = error.localizedDescription
            showAlert = true
        }
    }

    private func startImport(mode: ImportMode) {
        guard let fileURL = importFileURL else { return }

        isImporting = true
        importProgress = ExportImportProgress(phase: .extracting, current: 0, total: 1)

        Task {
            do {
                let (tabCount, messageCount) = try await exportImportService.importData(
                    from: fileURL,
                    mode: mode,
                    modelContext: modelContext
                ) { progress in
                    importProgress = progress
                }

                await MainActor.run {
                    isImporting = false
                    importProgress = nil
                    cleanupImportFile()

                    alertTitle = L10n.Data.importSuccess
                    alertMessage = L10n.Data.importedStats(tabCount, messageCount)
                    showAlert = true
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    importProgress = nil
                    cleanupImportFile()

                    alertTitle = L10n.Data.importError
                    alertMessage = error.localizedDescription
                    showAlert = true
                }
            }
        }
    }

    private func cleanupImportFile() {
        if let url = importFileURL {
            try? FileManager.default.removeItem(at: url)
            importFileURL = nil
        }
        importManifest = nil
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
    @State private var themeManager = ThemeManager.shared

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
        case .blue:
            return Color(red: 0x29/255, green: 0x8D/255, blue: 0xF5/255)
        }
    }
}

// MARK: - Web View

struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

#Preview {
    SettingsView()
        .modelContainer(for: [Tab.self, Message.self], inMemory: true)
}
