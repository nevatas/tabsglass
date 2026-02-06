//
//  PendingShareItem.swift
//  share
//
//  Stores shared items from extension for main app to process
//

import Foundation

// MARK: - Shared Tab (for tab selection in extension)

struct SharedTab: Codable, Identifiable {
    let id: UUID
    let title: String
    let position: Int
}

enum TabsSync {
    private static let appGroupID = "group.company.thecool.taby"

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    private static var fileURL: URL? {
        containerURL?.appendingPathComponent("tabs_list.json")
    }

    /// Load tabs list (called from extension)
    static func loadTabs() -> [SharedTab] {
        guard let url = fileURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let tabs = try? JSONDecoder().decode([SharedTab].self, from: data) else {
            return []
        }
        return tabs.sorted { $0.position < $1.position }
    }
}

// MARK: - Pending Share Item

/// Item shared from Share Extension, waiting to be processed by main app
struct PendingShareItem: Codable {
    let id: UUID
    let text: String
    let photoFileNames: [String]
    let photoAspectRatios: [Double]
    let videoFileNames: [String]
    let videoAspectRatios: [Double]
    let videoDurations: [Double]
    let videoThumbnailFileNames: [String]
    let tabId: UUID?  // nil = Inbox
    let createdAt: Date

    init(
        text: String,
        photoFileNames: [String] = [],
        photoAspectRatios: [Double] = [],
        videoFileNames: [String] = [],
        videoAspectRatios: [Double] = [],
        videoDurations: [Double] = [],
        videoThumbnailFileNames: [String] = [],
        tabId: UUID? = nil
    ) {
        self.id = UUID()
        self.text = text
        self.photoFileNames = photoFileNames
        self.photoAspectRatios = photoAspectRatios
        self.videoFileNames = videoFileNames
        self.videoAspectRatios = videoAspectRatios
        self.videoDurations = videoDurations
        self.videoThumbnailFileNames = videoThumbnailFileNames
        self.tabId = tabId
        self.createdAt = Date()
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case text
        case photoFileNames
        case photoAspectRatios
        case videoFileNames
        case videoAspectRatios
        case videoDurations
        case videoThumbnailFileNames
        case tabId
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedPhotoFileNames = try container.decodeIfPresent([String].self, forKey: .photoFileNames) ?? []
        let decodedVideoFileNames = try container.decodeIfPresent([String].self, forKey: .videoFileNames) ?? []
        let decodedVideoThumbnailFileNames = try container.decodeIfPresent([String].self, forKey: .videoThumbnailFileNames) ?? []

        var decodedPhotoAspectRatios = try container.decodeIfPresent([Double].self, forKey: .photoAspectRatios) ?? []
        if decodedPhotoAspectRatios.count < decodedPhotoFileNames.count {
            decodedPhotoAspectRatios.append(contentsOf: repeatElement(1.0, count: decodedPhotoFileNames.count - decodedPhotoAspectRatios.count))
        } else if decodedPhotoAspectRatios.count > decodedPhotoFileNames.count {
            decodedPhotoAspectRatios = Array(decodedPhotoAspectRatios.prefix(decodedPhotoFileNames.count))
        }

        var decodedVideoAspectRatios = try container.decodeIfPresent([Double].self, forKey: .videoAspectRatios) ?? []
        if decodedVideoAspectRatios.count < decodedVideoFileNames.count {
            decodedVideoAspectRatios.append(contentsOf: repeatElement(1.0, count: decodedVideoFileNames.count - decodedVideoAspectRatios.count))
        } else if decodedVideoAspectRatios.count > decodedVideoFileNames.count {
            decodedVideoAspectRatios = Array(decodedVideoAspectRatios.prefix(decodedVideoFileNames.count))
        }

        var decodedVideoDurations = try container.decodeIfPresent([Double].self, forKey: .videoDurations) ?? []
        if decodedVideoDurations.count < decodedVideoFileNames.count {
            decodedVideoDurations.append(contentsOf: repeatElement(0.0, count: decodedVideoFileNames.count - decodedVideoDurations.count))
        } else if decodedVideoDurations.count > decodedVideoFileNames.count {
            decodedVideoDurations = Array(decodedVideoDurations.prefix(decodedVideoFileNames.count))
        }

        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        self.photoFileNames = decodedPhotoFileNames
        self.photoAspectRatios = decodedPhotoAspectRatios
        self.videoFileNames = decodedVideoFileNames
        self.videoAspectRatios = decodedVideoAspectRatios
        self.videoDurations = decodedVideoDurations
        self.videoThumbnailFileNames = decodedVideoThumbnailFileNames
        self.tabId = try container.decodeIfPresent(UUID.self, forKey: .tabId)
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}

/// Manages pending share items stored in App Group container
enum PendingShareStorage {
    private static let appGroupID = "group.company.thecool.taby"

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    private static var fileURL: URL? {
        containerURL?.appendingPathComponent("pending_shares.json")
    }

    /// Save a new pending item (called from Share Extension)
    static func save(_ item: PendingShareItem) {
        var items = loadAll()
        items.append(item)
        writeItems(items)
    }

    /// Load all pending items (called from main app)
    static func loadAll() -> [PendingShareItem] {
        guard let url = fileURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([PendingShareItem].self, from: data) else {
            return []
        }
        return items
    }

    /// Clear all pending items after processing
    static func clearAll() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func writeItems(_ items: [PendingShareItem]) {
        guard let url = fileURL,
              let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: url)
    }
}

/// Shared photo storage for extension
enum SharedPhotoStorage {
    private static let appGroupID = "group.company.thecool.taby"

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static var photosDirectory: URL? {
        guard let container = containerURL else { return nil }
        let photosPath = container.appendingPathComponent("MessagePhotos", isDirectory: true)

        if !FileManager.default.fileExists(atPath: photosPath.path) {
            try? FileManager.default.createDirectory(at: photosPath, withIntermediateDirectories: true)
        }

        return photosPath
    }

    /// Save image data and return file name
    static func savePhotoData(_ data: Data) -> String? {
        guard let dir = photosDirectory else { return nil }

        let fileName = UUID().uuidString + ".jpg"
        let url = dir.appendingPathComponent(fileName)

        do {
            try data.write(to: url)
            return fileName
        } catch {
            return nil
        }
    }
}

/// Shared video storage for extension
enum SharedVideoStorageExtension {
    private static let appGroupID = "group.company.thecool.taby"

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static var videosDirectory: URL? {
        guard let container = containerURL else { return nil }
        let videosPath = container.appendingPathComponent("MessageVideos", isDirectory: true)

        if !FileManager.default.fileExists(atPath: videosPath.path) {
            try? FileManager.default.createDirectory(at: videosPath, withIntermediateDirectories: true)
        }

        return videosPath
    }

    /// Maximum video file size in bytes (100MB)
    static let maxVideoFileSize: Int64 = 100 * 1024 * 1024

    /// Maximum video duration in seconds (5 minutes)
    static let maxVideoDuration: Double = 300
}
