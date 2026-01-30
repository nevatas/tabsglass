//
//  ExportProgressView.swift
//  tabsglass
//
//  Progress view for export/import operations
//

import SwiftUI

struct ExportProgressView: View {
    let progress: ExportImportProgress
    let isExporting: Bool
    let onCancel: (() -> Void)?

    init(progress: ExportImportProgress, isExporting: Bool = true, onCancel: (() -> Void)? = nil) {
        self.progress = progress
        self.isExporting = isExporting
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            Image(systemName: isExporting ? "square.and.arrow.up" : "square.and.arrow.down")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            // Title
            Text(isExporting ? L10n.Data.exporting : L10n.Data.importing)
                .font(.title2)
                .fontWeight(.semibold)

            // Progress indicator
            VStack(spacing: 12) {
                ProgressView(value: progress.fractionCompleted)
                    .progressViewStyle(.linear)

                Text(progress.localizedPhase)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if progress.total > 0 && progress.phase != .complete {
                    Text("\(progress.current) / \(progress.total)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 40)

            Spacer()

            // Cancel button (only during operation, not on complete)
            if let onCancel = onCancel, progress.phase != .complete {
                Button(L10n.Tab.cancel, role: .cancel) {
                    onCancel()
                }
                .padding(.bottom)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}

#Preview {
    ExportProgressView(
        progress: ExportImportProgress(phase: .copyingPhotos, current: 5, total: 10),
        isExporting: true
    )
}
