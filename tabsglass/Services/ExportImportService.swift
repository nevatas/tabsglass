//
//  ExportImportService.swift
//  tabsglass
//
//  Service for export/import operations
//

import Foundation
import SwiftData
import UIKit
import ZIPFoundation
import os.log

// MARK: - Export/Import Errors

enum ExportImportError: LocalizedError {
    case invalidArchive
    case unsupportedVersion(Int)
    case missingManifest
    case missingData
    case compressionFailed
    case extractionFailed
    case insufficientSpace
    case fileAccessDenied

    var errorDescription: String? {
        switch self {
        case .invalidArchive:
            return "Invalid archive format"
        case .unsupportedVersion(let version):
            return "Unsupported archive version: \(version)"
        case .missingManifest:
            return "Archive is missing manifest"
        case .missingData:
            return "Archive is missing data"
        case .compressionFailed:
            return "Failed to compress archive"
        case .extractionFailed:
            return "Failed to extract archive"
        case .insufficientSpace:
            return "Not enough storage space"
        case .fileAccessDenied:
            return "Cannot access file"
        }
    }
}

// MARK: - Export/Import Service

@MainActor
final class ExportImportService {
    private let logger = Logger(subsystem: "com.thecool.taby", category: "ExportImport")
    private let fileManager = FileManager.default

    // Archive structure
    private let manifestFileName = "manifest.json"
    private let dataFileName = "data.json"
    private let photosFolder = "MessagePhotos"
    private let videosFolder = "MessageVideos"

    // MARK: - Helpers

    /// Find a file in directory, checking root first then one level deep (for backward compat)
    private nonisolated func findFile(named name: String, in directory: URL, fileManager: FileManager) -> URL? {
        // Check root first
        let rootURL = directory.appendingPathComponent(name)
        if fileManager.fileExists(atPath: rootURL.path) {
            return rootURL
        }

        // Check one level deep (backward compatibility with wrapper folder)
        if let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) {
            for item in contents {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                    let nestedURL = item.appendingPathComponent(name)
                    if fileManager.fileExists(atPath: nestedURL.path) {
                        return nestedURL
                    }
                }
            }
        }

        return nil
    }

    /// Find the base directory containing archive files
    private nonisolated func findArchiveBase(in directory: URL, fileManager: FileManager) -> URL {
        // Check if manifest is at root
        let rootManifest = directory.appendingPathComponent(manifestFileName)
        if fileManager.fileExists(atPath: rootManifest.path) {
            return directory
        }

        // Check one level deep
        if let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) {
            for item in contents {
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                    let nestedManifest = item.appendingPathComponent(manifestFileName)
                    if fileManager.fileExists(atPath: nestedManifest.path) {
                        return item
                    }
                }
            }
        }

        return directory
    }

    // MARK: - Export

    /// Export all data to a .taby archive
    /// - Parameters:
    ///   - tabs: All tabs to export
    ///   - messages: All messages to export
    ///   - progressHandler: Called with progress updates
    /// - Returns: URL to the created archive file
    func exportData(
        tabs: [Tab],
        messages: [Message],
        progressHandler: @escaping (ExportImportProgress) -> Void
    ) async throws -> URL {
        // Create temp directory for archive contents
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? fileManager.removeItem(at: tempDir)
        }

        progressHandler(ExportImportProgress(phase: .preparing, current: 0, total: 1))

        // Collect all media files
        var allPhotoFiles: Set<String> = []
        var allVideoFiles: Set<String> = []
        var allThumbnailFiles: Set<String> = []

        for message in messages {
            allPhotoFiles.formUnion(message.photoFileNames)
            allVideoFiles.formUnion(message.videoFileNames)
            allThumbnailFiles.formUnion(message.videoThumbnailFileNames)
        }

        // Create exportable models
        let exportableTabs = tabs.map { ExportableTab(from: $0) }
        let exportableMessages = messages.map { ExportableMessage(from: $0) }

        // Create manifest
        let manifest = ExportManifest(
            tabCount: tabs.count,
            messageCount: messages.count,
            photoCount: allPhotoFiles.count + allThumbnailFiles.count,
            videoCount: allVideoFiles.count,
            deviceName: UIDevice.current.name
        )

        // Write manifest.json
        progressHandler(ExportImportProgress(phase: .exportingData, current: 0, total: 2))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let manifestData = try encoder.encode(manifest)
        try manifestData.write(to: tempDir.appendingPathComponent(manifestFileName))

        // Write data.json
        let exportData = ExportData(tabs: exportableTabs, messages: exportableMessages)
        let dataData = try encoder.encode(exportData)
        try dataData.write(to: tempDir.appendingPathComponent(dataFileName))

        progressHandler(ExportImportProgress(phase: .exportingData, current: 2, total: 2))

        // Copy photos (including video thumbnails)
        let allPhotos = allPhotoFiles.union(allThumbnailFiles)
        if !allPhotos.isEmpty {
            let photosDir = tempDir.appendingPathComponent(photosFolder)
            try fileManager.createDirectory(at: photosDir, withIntermediateDirectories: true)

            var photosCopied = 0
            let totalPhotos = allPhotos.count

            for fileName in allPhotos {
                progressHandler(ExportImportProgress(phase: .copyingPhotos, current: photosCopied, total: totalPhotos))

                let sourceURL = SharedPhotoStorage.photoURL(for: fileName)
                if fileManager.fileExists(atPath: sourceURL.path) {
                    let destURL = photosDir.appendingPathComponent(fileName)
                    do {
                        try fileManager.copyItem(at: sourceURL, to: destURL)
                    } catch {
                        logger.error("Failed to copy photo \(fileName): \(error.localizedDescription)")
                        throw ExportImportError.fileAccessDenied
                    }
                }
                photosCopied += 1
            }
        }

        // Copy videos
        if !allVideoFiles.isEmpty {
            let videosDir = tempDir.appendingPathComponent(videosFolder)
            try fileManager.createDirectory(at: videosDir, withIntermediateDirectories: true)

            var videosCopied = 0
            let totalVideos = allVideoFiles.count

            for fileName in allVideoFiles {
                progressHandler(ExportImportProgress(phase: .copyingVideos, current: videosCopied, total: totalVideos))

                let sourceURL = SharedVideoStorage.videoURL(for: fileName)
                if fileManager.fileExists(atPath: sourceURL.path) {
                    let destURL = videosDir.appendingPathComponent(fileName)
                    do {
                        try fileManager.copyItem(at: sourceURL, to: destURL)
                    } catch {
                        logger.error("Failed to copy video \(fileName): \(error.localizedDescription)")
                        throw ExportImportError.fileAccessDenied
                    }
                }
                videosCopied += 1
            }
        }

        // Compress to .taby (ZIP)
        progressHandler(ExportImportProgress(phase: .compressing, current: 0, total: 1))

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())
        let archiveName = "Taby_\(dateString).taby"
        let archiveURL = fileManager.temporaryDirectory.appendingPathComponent(archiveName)

        // Remove existing file if any
        try? fileManager.removeItem(at: archiveURL)

        // Use ZIPFoundation Archive API to add files without wrapper folder
        do {
            let archive = try Archive(url: archiveURL, accessMode: .create)

            // Add all items from temp directory without the parent folder
            let contents = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            for itemURL in contents {
                let itemName = itemURL.lastPathComponent
                if itemURL.hasDirectoryPath {
                    // Add directory recursively
                    try archive.addEntry(with: itemName + "/", relativeTo: tempDir)
                    let subContents = try fileManager.contentsOfDirectory(at: itemURL, includingPropertiesForKeys: nil)
                    for subItem in subContents {
                        let subName = itemName + "/" + subItem.lastPathComponent
                        try archive.addEntry(with: subName, relativeTo: tempDir)
                    }
                } else {
                    // Add file
                    try archive.addEntry(with: itemName, relativeTo: tempDir)
                }
            }
        } catch {
            logger.error("Compression failed: \(error.localizedDescription)")
            throw ExportImportError.compressionFailed
        }

        progressHandler(ExportImportProgress(phase: .complete, current: 1, total: 1))

        logger.info("Export completed: \(tabs.count) tabs, \(messages.count) messages")
        return archiveURL
    }

    // MARK: - Validate Archive

    /// Validate an archive and return its manifest
    /// - Parameter url: URL to the .taby archive
    /// - Returns: The manifest from the archive
    nonisolated func validateArchive(at url: URL) async throws -> ExportManifest {
        let fileManager = FileManager.default

        // Create temp directory for extraction
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? fileManager.removeItem(at: tempDir)
        }

        // Extract archive using ZIPFoundation
        do {
            try fileManager.unzipItem(at: url, to: tempDir)
        } catch {
            throw ExportImportError.extractionFailed
        }

        // Find manifest - might be at root or in a subdirectory (backward compat)
        let manifestURL = findFile(named: "manifest.json", in: tempDir, fileManager: fileManager)
        guard let manifestURL = manifestURL else {
            throw ExportImportError.missingManifest
        }

        let manifestData = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let manifest = try decoder.decode(ExportManifest.self, from: manifestData)

        // Check version
        guard manifest.version <= ExportManifest.currentVersion else {
            throw ExportImportError.unsupportedVersion(manifest.version)
        }

        return manifest
    }

    // MARK: - Import

    /// Import data from a .taby archive
    /// - Parameters:
    ///   - url: URL to the .taby archive
    ///   - mode: How to handle existing data
    ///   - modelContext: SwiftData model context
    ///   - progressHandler: Called with progress updates
    /// - Returns: Tuple of (imported tabs count, imported messages count)
    func importData(
        from url: URL,
        mode: ImportMode,
        modelContext: ModelContext,
        progressHandler: @escaping (ExportImportProgress) -> Void
    ) async throws -> (Int, Int) {
        // Create temp directory for extraction
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? fileManager.removeItem(at: tempDir)
        }

        progressHandler(ExportImportProgress(phase: .extracting, current: 0, total: 1))

        // Extract archive using ZIPFoundation
        do {
            try fileManager.unzipItem(at: url, to: tempDir)
        } catch {
            logger.error("Extraction failed: \(error.localizedDescription)")
            throw ExportImportError.extractionFailed
        }

        // Find archive base directory (handles wrapper folder for backward compat)
        let archiveBase = findArchiveBase(in: tempDir, fileManager: fileManager)

        // Read and validate manifest
        let manifestURL = archiveBase.appendingPathComponent(manifestFileName)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw ExportImportError.missingManifest
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try decoder.decode(ExportManifest.self, from: manifestData)

        guard manifest.version <= ExportManifest.currentVersion else {
            throw ExportImportError.unsupportedVersion(manifest.version)
        }

        // Read data.json
        let dataURL = archiveBase.appendingPathComponent(dataFileName)
        guard fileManager.fileExists(atPath: dataURL.path) else {
            throw ExportImportError.missingData
        }

        progressHandler(ExportImportProgress(phase: .importingData, current: 0, total: 1))

        let dataData = try Data(contentsOf: dataURL)
        let exportData = try decoder.decode(ExportData.self, from: dataData)

        // Get existing IDs for merge mode
        var existingTabIds: Set<UUID> = []
        var existingMessageIds: Set<UUID> = []

        if mode == .merge {
            let tabDescriptor = FetchDescriptor<Tab>()
            let existingTabs = try modelContext.fetch(tabDescriptor)
            existingTabIds = Set(existingTabs.map { $0.id })

            let messageDescriptor = FetchDescriptor<Message>()
            let existingMessages = try modelContext.fetch(messageDescriptor)
            existingMessageIds = Set(existingMessages.map { $0.id })
        }

        // Replace mode: delete all existing data
        if mode == .replace {
            // Delete all messages first (to clean up media files)
            let messageDescriptor = FetchDescriptor<Message>()
            let existingMessages = try modelContext.fetch(messageDescriptor)

            // Collect all data we need BEFORE deleting (to avoid detached context issues)
            var photoFilesToDelete: [String] = []
            var videoFilesToDelete: [String] = []
            var thumbnailFilesToDelete: [String] = []
            var notificationIdsToCancel: [String] = []

            for message in existingMessages {
                photoFilesToDelete.append(contentsOf: message.photoFileNames)
                videoFilesToDelete.append(contentsOf: message.videoFileNames)
                thumbnailFilesToDelete.append(contentsOf: message.videoThumbnailFileNames)
                if let notificationId = message.notificationId {
                    notificationIdsToCancel.append(notificationId)
                }
            }

            // Delete objects from context first
            for message in existingMessages {
                modelContext.delete(message)
            }

            let tabDescriptor = FetchDescriptor<Tab>()
            let existingTabs = try modelContext.fetch(tabDescriptor)
            for tab in existingTabs {
                modelContext.delete(tab)
            }

            try modelContext.save()

            // Now clean up files and notifications (after context is saved)
            for fileName in photoFilesToDelete {
                SharedPhotoStorage.deletePhoto(fileName)
            }
            for fileName in videoFilesToDelete {
                SharedVideoStorage.deleteVideo(fileName)
            }
            for fileName in thumbnailFilesToDelete {
                SharedPhotoStorage.deletePhoto(fileName)
            }
            for notificationId in notificationIdsToCancel {
                NotificationService.shared.cancelReminder(notificationId: notificationId)
            }
        }

        // Import tabs
        var importedTabCount = 0
        for exportableTab in exportData.tabs {
            if mode == .merge && existingTabIds.contains(exportableTab.id) {
                continue  // Skip existing
            }

            let tab = Tab(title: exportableTab.title, position: exportableTab.position)
            tab.id = exportableTab.id
            tab.serverId = exportableTab.serverId
            tab.createdAt = exportableTab.createdAt
            modelContext.insert(tab)
            importedTabCount += 1
        }

        progressHandler(ExportImportProgress(phase: .importingData, current: 1, total: 1))

        // Copy media files
        let photosSourceDir = archiveBase.appendingPathComponent(photosFolder)
        let videosSourceDir = archiveBase.appendingPathComponent(videosFolder)

        var mediaFilesCopied = 0
        let totalMediaFiles = manifest.photoCount + manifest.videoCount

        // Copy photos
        if fileManager.fileExists(atPath: photosSourceDir.path) {
            let photoFiles = try fileManager.contentsOfDirectory(atPath: photosSourceDir.path)
            for fileName in photoFiles {
                progressHandler(ExportImportProgress(phase: .copyingMedia, current: mediaFilesCopied, total: totalMediaFiles))

                let sourceURL = photosSourceDir.appendingPathComponent(fileName)
                let destURL = SharedPhotoStorage.photosDirectory.appendingPathComponent(fileName)

                // Don't overwrite existing files in merge mode
                if mode == .merge && fileManager.fileExists(atPath: destURL.path) {
                    mediaFilesCopied += 1
                    continue
                }

                if fileManager.fileExists(atPath: destURL.path) {
                    try fileManager.removeItem(at: destURL)
                }
                do {
                    try fileManager.copyItem(at: sourceURL, to: destURL)
                } catch {
                    logger.error("Failed to import photo \(fileName): \(error.localizedDescription)")
                    throw ExportImportError.fileAccessDenied
                }
                mediaFilesCopied += 1
            }
        }

        // Copy videos
        if fileManager.fileExists(atPath: videosSourceDir.path) {
            let videoFiles = try fileManager.contentsOfDirectory(atPath: videosSourceDir.path)
            for fileName in videoFiles {
                progressHandler(ExportImportProgress(phase: .copyingMedia, current: mediaFilesCopied, total: totalMediaFiles))

                let sourceURL = videosSourceDir.appendingPathComponent(fileName)
                let destURL = SharedVideoStorage.videosDirectory.appendingPathComponent(fileName)

                // Don't overwrite existing files in merge mode
                if mode == .merge && fileManager.fileExists(atPath: destURL.path) {
                    mediaFilesCopied += 1
                    continue
                }

                if fileManager.fileExists(atPath: destURL.path) {
                    try fileManager.removeItem(at: destURL)
                }
                do {
                    try fileManager.copyItem(at: sourceURL, to: destURL)
                } catch {
                    logger.error("Failed to import video \(fileName): \(error.localizedDescription)")
                    throw ExportImportError.fileAccessDenied
                }
                mediaFilesCopied += 1
            }
        }

        // Import messages
        var importedMessageCount = 0
        var messagesWithReminders: [Message] = []

        for exportableMessage in exportData.messages {
            if mode == .merge && existingMessageIds.contains(exportableMessage.id) {
                continue  // Skip existing
            }

            let message = exportableMessage.toMessage()
            modelContext.insert(message)
            importedMessageCount += 1

            if message.reminderDate != nil {
                messagesWithReminders.append(message)
            }
        }

        try modelContext.save()

        // Schedule reminders for imported messages
        if !messagesWithReminders.isEmpty {
            var remindersScheduled = 0
            let totalReminders = messagesWithReminders.count

            for message in messagesWithReminders {
                progressHandler(ExportImportProgress(phase: .schedulingReminders, current: remindersScheduled, total: totalReminders))

                if let reminderDate = message.reminderDate, reminderDate > Date() {
                    let notificationId = await NotificationService.shared.scheduleReminder(
                        for: message,
                        date: reminderDate,
                        repeatInterval: message.reminderRepeatInterval ?? .never
                    )
                    message.notificationId = notificationId
                } else {
                    // Past reminder - clear it
                    message.reminderDate = nil
                    message.reminderRepeatInterval = nil
                }
                remindersScheduled += 1
            }

            try modelContext.save()
        }

        progressHandler(ExportImportProgress(phase: .complete, current: 1, total: 1))

        logger.info("Import completed: \(importedTabCount) tabs, \(importedMessageCount) messages")
        return (importedTabCount, importedMessageCount)
    }
}
