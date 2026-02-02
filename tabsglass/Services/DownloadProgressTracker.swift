//
//  DownloadProgressTracker.swift
//  tabsglass
//
//  Tracks download progress for media files
//

import Foundation
import Combine

/// Tracks download progress for individual media files
final class DownloadProgressTracker: @unchecked Sendable {
    static let shared = DownloadProgressTracker()

    /// Progress update event
    struct ProgressUpdate {
        let messageId: UUID
        let fileIndex: Int  // Index in the message's media array
        let progress: Double  // 0.0 to 1.0
        let isComplete: Bool
    }

    /// Publisher for progress updates
    let progressUpdated = PassthroughSubject<ProgressUpdate, Never>()

    /// Currently downloading message IDs
    private var downloadingMessages: Set<UUID> = []
    /// Track which files have completed: messageId -> Set of completed file indices
    private var completedFiles: [UUID: Set<Int>] = [:]
    /// Total file count for each message
    private var fileCounts: [UUID: Int] = [:]
    private let lock = NSLock()

    private init() {}

    // MARK: - Public API

    /// Mark message as downloading
    func startDownload(for messageId: UUID, fileCount: Int) {
        lock.lock()
        downloadingMessages.insert(messageId)
        fileCounts[messageId] = fileCount
        completedFiles[messageId] = []
        lock.unlock()
    }

    /// Update progress for a specific file in a message
    func updateProgress(for messageId: UUID, fileIndex: Int, progress: Double) {
        progressUpdated.send(ProgressUpdate(
            messageId: messageId,
            fileIndex: fileIndex,
            progress: min(1.0, max(0.0, progress)),
            isComplete: false
        ))
    }

    /// Mark file download as complete
    func completeFile(for messageId: UUID, fileIndex: Int) {
        lock.lock()
        completedFiles[messageId]?.insert(fileIndex)
        lock.unlock()

        progressUpdated.send(ProgressUpdate(
            messageId: messageId,
            fileIndex: fileIndex,
            progress: 1.0,
            isComplete: true
        ))
    }

    /// Mark entire message download as complete
    func completeDownload(for messageId: UUID) {
        lock.lock()
        downloadingMessages.remove(messageId)
        fileCounts.removeValue(forKey: messageId)
        completedFiles.removeValue(forKey: messageId)
        lock.unlock()
    }

    /// Check if message is currently downloading
    func isDownloading(messageId: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return downloadingMessages.contains(messageId)
    }

    /// Check if a specific file in a message is still downloading
    func isFileDownloading(messageId: UUID, fileIndex: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard downloadingMessages.contains(messageId) else { return false }
        return !(completedFiles[messageId]?.contains(fileIndex) ?? false)
    }

    /// Check if a file needs to be downloaded (not on disk and has blurHash)
    func needsDownload(fileName: String, isVideo: Bool) -> Bool {
        let directory = isVideo ? SharedVideoStorage.videosDirectory : SharedPhotoStorage.photosDirectory
        let fileURL = directory.appendingPathComponent(fileName)
        return !FileManager.default.fileExists(atPath: fileURL.path)
    }
}
