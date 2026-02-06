//
//  PendingShareItem.swift
//  tabsglass
//
//  Stores shared items from extension for main app to process
//

import Foundation

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
    private static var fileURL: URL? {
        SharedConstants.containerURL?.appendingPathComponent("pending_shares.json")
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

    /// Remove specific item by ID
    static func remove(id: UUID) {
        var items = loadAll()
        items.removeAll { $0.id == id }
        writeItems(items)
    }

    private static func writeItems(_ items: [PendingShareItem]) {
        guard let url = fileURL,
              let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: url)
    }
}
