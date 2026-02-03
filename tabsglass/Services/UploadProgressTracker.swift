//
//  UploadProgressTracker.swift
//  tabsglass
//
//  Tracks upload progress for media files
//

import Foundation
import Combine

/// Tracks upload progress for individual media files
final class UploadProgressTracker: @unchecked Sendable {
    static let shared = UploadProgressTracker()

    /// Progress update event
    struct ProgressUpdate {
        let messageId: UUID
        let fileIndex: Int  // Index in the message's media array
        let progress: Double  // 0.0 to 1.0
        let isComplete: Bool
        let totalBytes: Int64?  // Total file size in bytes
        let isVideo: Bool
    }

    /// Publisher for progress updates
    let progressUpdated = PassthroughSubject<ProgressUpdate, Never>()

    /// Currently uploading message IDs
    private var uploadingMessages: Set<UUID> = []
    /// File sizes for uploading files: messageId -> [fileIndex -> totalBytes]
    private var fileSizes: [UUID: [Int: Int64]] = [:]
    /// Track which files are videos
    private var videoFlags: [UUID: [Int: Bool]] = [:]
    /// Track which files have completed: messageId -> Set of completed file indices
    private var completedFiles: [UUID: Set<Int>] = [:]
    private let lock = NSLock()

    private init() {}

    // MARK: - Public API

    /// Mark message as uploading
    func startUpload(for messageId: UUID) {
        lock.lock()
        uploadingMessages.insert(messageId)
        fileSizes[messageId] = [:]
        videoFlags[messageId] = [:]
        completedFiles[messageId] = []
        lock.unlock()
    }

    /// Set file info for a specific file
    func setFileInfo(for messageId: UUID, fileIndex: Int, totalBytes: Int64, isVideo: Bool) {
        lock.lock()
        fileSizes[messageId]?[fileIndex] = totalBytes
        videoFlags[messageId]?[fileIndex] = isVideo
        lock.unlock()
    }

    /// Update progress for a specific file in a message
    func updateProgress(for messageId: UUID, fileIndex: Int, progress: Double) {
        lock.lock()
        let totalBytes = fileSizes[messageId]?[fileIndex]
        let isVideo = videoFlags[messageId]?[fileIndex] ?? false
        lock.unlock()

        progressUpdated.send(ProgressUpdate(
            messageId: messageId,
            fileIndex: fileIndex,
            progress: min(1.0, max(0.0, progress)),
            isComplete: false,
            totalBytes: totalBytes,
            isVideo: isVideo
        ))
    }

    /// Mark file upload as complete
    func completeFile(for messageId: UUID, fileIndex: Int) {
        lock.lock()
        let totalBytes = fileSizes[messageId]?[fileIndex]
        let isVideo = videoFlags[messageId]?[fileIndex] ?? false
        completedFiles[messageId]?.insert(fileIndex)
        lock.unlock()

        progressUpdated.send(ProgressUpdate(
            messageId: messageId,
            fileIndex: fileIndex,
            progress: 1.0,
            isComplete: true,
            totalBytes: totalBytes,
            isVideo: isVideo
        ))
    }

    /// Mark entire message upload as complete
    func completeUpload(for messageId: UUID) {
        lock.lock()
        uploadingMessages.remove(messageId)
        fileSizes.removeValue(forKey: messageId)
        videoFlags.removeValue(forKey: messageId)
        completedFiles.removeValue(forKey: messageId)
        lock.unlock()
    }

    /// Check if message is currently uploading
    func isUploading(messageId: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return uploadingMessages.contains(messageId)
    }

    /// Check if a specific file in a message is still uploading
    func isFileUploading(messageId: UUID, fileIndex: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard uploadingMessages.contains(messageId) else { return false }
        return !(completedFiles[messageId]?.contains(fileIndex) ?? false)
    }

    /// Check if a specific file has completed uploading
    func isFileCompleted(messageId: UUID, fileIndex: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return completedFiles[messageId]?.contains(fileIndex) ?? false
    }
}
