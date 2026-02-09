//
//  SharedConstants.swift
//  tabsglass
//
//  Constants shared between main app and extensions
//

import Foundation

enum SharedConstants {
    /// App Group identifier for sharing data between main app and extensions
    static let appGroupID = "group.company.thecool.taby"

    /// Shared container URL for App Group
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    /// Directory for storing message photos in shared container
    static var photosDirectory: URL? {
        guard let container = containerURL else { return nil }
        let photosPath = container.appendingPathComponent("MessagePhotos", isDirectory: true)

        if !FileManager.default.fileExists(atPath: photosPath.path) {
            try? FileManager.default.createDirectory(at: photosPath, withIntermediateDirectories: true)
        }

        return photosPath
    }

    /// Legacy photos directory in Documents (for migration)
    static var legacyPhotosDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("MessagePhotos", isDirectory: true)
    }

    /// Directory for storing message videos in shared container
    static var videosDirectory: URL? {
        guard let container = containerURL else { return nil }
        let videosPath = container.appendingPathComponent("MessageVideos", isDirectory: true)

        if !FileManager.default.fileExists(atPath: videosPath.path) {
            try? FileManager.default.createDirectory(at: videosPath, withIntermediateDirectories: true)
        }

        return videosPath
    }

    /// Directory for storing message audio in shared container
    static var audiosDirectory: URL? {
        guard let container = containerURL else { return nil }
        let audioPath = container.appendingPathComponent("MessageAudio", isDirectory: true)

        if !FileManager.default.fileExists(atPath: audioPath.path) {
            try? FileManager.default.createDirectory(at: audioPath, withIntermediateDirectories: true)
        }

        return audioPath
    }

    /// SwiftData store URL in shared container
    static var sharedStoreURL: URL? {
        containerURL?.appendingPathComponent("default.store")
    }

    // MARK: - Video Constraints

    /// Maximum video duration in seconds (5 minutes)
    static let maxVideoDuration: Double = 300

    /// Maximum video file size in bytes (100MB)
    static let maxVideoFileSize: Int64 = 100 * 1024 * 1024

    /// Maximum media items (photos + videos) per message
    static let maxMediaPerMessage: Int = 10
}
