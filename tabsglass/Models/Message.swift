//
//  Message.swift
//  tabsglass
//

import Foundation
import SwiftData
import UIKit
import os.log

// MARK: - Todo Item

struct TodoItem: Codable, Hashable, Identifiable {
    let id: UUID
    var text: String
    var isCompleted: Bool

    init(id: UUID = UUID(), text: String, isCompleted: Bool = false) {
        self.id = id
        self.text = text
        self.isCompleted = isCompleted
    }
}

// MARK: - Text Entity (Telegram-style formatting)

struct TextEntity: Codable, Hashable {
    let type: String      // "bold", "italic", "underline", "strikethrough", "code", "pre", "text_link", "url"
    let offset: Int       // Start position in UTF-16 code units
    let length: Int       // Length in UTF-16 code units
    let url: String?      // URL for "text_link" type

    init(type: String, offset: Int, length: Int, url: String? = nil) {
        self.type = type
        self.offset = offset
        self.length = length
        self.url = url
    }

    /// Detect URLs in text and return entities
    static func detectURLs(in text: String) -> [TextEntity] {
        guard !text.isEmpty else { return [] }

        var entities: [TextEntity] = []

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let nsString = text as NSString
        let range = NSRange(location: 0, length: nsString.length)

        detector?.enumerateMatches(in: text, options: [], range: range) { result, _, _ in
            guard let result = result, let url = result.url else { return }

            let entity = TextEntity(
                type: "url",
                offset: result.range.location,
                length: result.range.length,
                url: url.absoluteString
            )
            entities.append(entity)
        }

        return entities
    }
}

// MARK: - Link Preview

struct LinkPreview: Codable, Hashable {
    let url: String
    let title: String?
    let previewDescription: String?  // "description" is reserved by Swift
    let image: String?               // URL to preview image
    let siteName: String?

    init(url: String, title: String? = nil, previewDescription: String? = nil, image: String? = nil, siteName: String? = nil) {
        self.url = url
        self.title = title
        self.previewDescription = previewDescription
        self.image = image
        self.siteName = siteName
    }

    // Custom coding keys to map "description" from JSON to "previewDescription"
    enum CodingKeys: String, CodingKey {
        case url, title, image, siteName
        case previewDescription = "description"
    }
}

// MARK: - Message Model

@Model
final class Message: Identifiable {
    var id: UUID
    var serverId: Int?              // Backend ID for sync (nil = local only)
    var content: String
    var entities: [TextEntity]?
    var createdAt: Date
    var tabId: UUID?                // nil = Inbox (virtual tab)
    var position: Int = 0           // For custom sorting (0 = default/newest first)
    var sourceUrl: String?          // Original source URL (e.g., Telegram message link)
    var linkPreview: LinkPreview?   // Rich link preview data
    var mediaGroupId: String?       // Groups multiple media in same message
    var photoFileNames: [String] = []
    var photoAspectRatios: [Double] = []
    var todoItems: [TodoItem]?      // Todo list items (nil = not a todo list)
    var todoTitle: String?          // Optional title for todo list

    /// Check if this message is a todo list
    var isTodoList: Bool {
        todoItems != nil && !(todoItems?.isEmpty ?? true)
    }

    /// Create a message in a specific tab (or Inbox if tabId is nil)
    init(
        content: String,
        tabId: UUID? = nil,
        entities: [TextEntity]? = nil,
        photoFileNames: [String] = [],
        photoAspectRatios: [Double] = [],
        position: Int = 0,
        sourceUrl: String? = nil,
        linkPreview: LinkPreview? = nil,
        mediaGroupId: String? = nil
    ) {
        self.id = UUID()
        self.serverId = nil
        self.content = content
        self.entities = entities
        self.createdAt = Date()
        self.tabId = tabId
        self.position = position
        self.sourceUrl = sourceUrl
        self.linkPreview = linkPreview
        self.mediaGroupId = mediaGroupId
        self.photoFileNames = photoFileNames
        self.photoAspectRatios = photoAspectRatios
    }

    /// Get aspect ratios as CGFloat array
    var aspectRatios: [CGFloat] {
        photoAspectRatios.map { CGFloat($0) }
    }

    /// Get UIImages for attached photos (use only for gallery, not for thumbnails)
    var photos: [UIImage] {
        photoFileNames.compactMap { fileName in
            let url = Message.photosDirectory.appendingPathComponent(fileName)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        }
    }

    /// Check if message has no content (no text, no valid photos, no todo items)
    var isEmpty: Bool {
        let hasText = !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasText { return false }

        // Check if has todo items
        if isTodoList { return false }

        // Check if any photo files exist (without loading them)
        let hasValidPhotos = photoFileNames.contains { fileName in
            let url = Message.photosDirectory.appendingPathComponent(fileName)
            return FileManager.default.fileExists(atPath: url.path)
        }
        return !hasValidPhotos
    }

    /// Directory for storing message photos
    static var photosDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let photosPath = documentsPath.appendingPathComponent("MessagePhotos", isDirectory: true)

        if !FileManager.default.fileExists(atPath: photosPath.path) {
            try? FileManager.default.createDirectory(at: photosPath, withIntermediateDirectories: true)
        }

        return photosPath
    }

    /// Save image and return file name and aspect ratio
    static func savePhoto(_ image: UIImage) -> (fileName: String, aspectRatio: Double)? {
        let fileName = UUID().uuidString + ".jpg"
        let url = photosDirectory.appendingPathComponent(fileName)

        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }

        do {
            try data.write(to: url)
            let aspectRatio = Double(image.size.width / image.size.height)
            return (fileName, aspectRatio)
        } catch {
            Logger().error("Failed to save photo: \(error.localizedDescription)")
            return nil
        }
    }

    /// Delete photo files when message is deleted
    func deletePhotoFiles() {
        for fileName in photoFileNames {
            let url = Message.photosDirectory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: url)
        }
    }
}
