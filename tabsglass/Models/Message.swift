//
//  Message.swift
//  tabsglass
//

import Foundation
import SwiftData
import UIKit
import os.log

// MARK: - Reminder Repeat Interval

enum ReminderRepeatInterval: String, Codable, CaseIterable {
    case never
    case daily
    case weekly
    case biweekly
    case monthly
    case quarterly
    case semiannually
    case yearly
}

// MARK: - Content Block (ordered mixed content)

struct ContentBlock: Codable, Hashable {
    let id: UUID
    let type: String        // "text" or "todo"
    var text: String
    var isCompleted: Bool
    var entities: [TextEntity]?

    init(id: UUID = UUID(), type: String, text: String, isCompleted: Bool = false, entities: [TextEntity]? = nil) {
        self.id = id
        self.type = type
        self.text = text
        self.isCompleted = isCompleted
        self.entities = entities
    }

    /// Checkbox prefix used in composer text
    static let checkboxPrefix = "\u{25CB} "  // "○ "

    /// Reconstruct composer-format text from content blocks
    static func composerText(from blocks: [ContentBlock]) -> String {
        blocks.map { block in
            block.type == "todo" ? checkboxPrefix + block.text : block.text
        }.joined(separator: "\n")
    }

    /// Parse composer text into structured content blocks, optionally distributing entities
    static func parse(composerText: String, entities: [TextEntity]? = nil) -> (blocks: [ContentBlock], todoItems: [TodoItem], plainText: String, hasTodos: Bool) {
        let prefix = checkboxPrefix
        let prefixUTF16 = (prefix as NSString).length
        let lines = composerText.components(separatedBy: "\n")
        var blocks: [ContentBlock] = []
        var todoItems: [TodoItem] = []
        var hasTodos = false

        // Compute UTF-16 offset for each line
        struct LineInfo {
            let text: String
            let startOffset: Int
            let isTodo: Bool
        }
        var lineInfos: [LineInfo] = []
        var offset = 0
        for (index, line) in lines.enumerated() {
            lineInfos.append(LineInfo(text: line, startOffset: offset, isTodo: line.hasPrefix(prefix)))
            offset += (line as NSString).length
            if index < lines.count - 1 {
                offset += 1 // newline
            }
        }

        var currentTextLines: [(text: String, startOffset: Int)] = []

        func flushTextLines() {
            guard !currentTextLines.isEmpty else { return }
            let joinedText = currentTextLines.map { $0.text }.joined(separator: "\n")
            let trimmed = joinedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                currentTextLines.removeAll()
                return
            }

            var blockEntities: [TextEntity] = []

            if let entities = entities, !entities.isEmpty {
                // Map entities from composer text coordinates to block-local coordinates
                let blockStartInFull = currentTextLines.first!.startOffset
                let leadingTrimmed = String(joinedText.prefix(while: { $0.isWhitespace || $0.isNewline }))
                let leadingTrimUTF16 = (leadingTrimmed as NSString).length
                let trimmedStart = blockStartInFull + leadingTrimUTF16
                let trimmedLength = (trimmed as NSString).length
                let trimmedEnd = trimmedStart + trimmedLength

                for entity in entities {
                    let entityStart = entity.offset
                    let entityEnd = entity.offset + entity.length
                    guard entityStart < trimmedEnd && entityEnd > trimmedStart else { continue }

                    let clippedStart = max(entityStart, trimmedStart)
                    let clippedEnd = min(entityEnd, trimmedEnd)
                    let newLength = clippedEnd - clippedStart
                    guard newLength > 0 else { continue }

                    blockEntities.append(TextEntity(
                        type: entity.type,
                        offset: clippedStart - trimmedStart,
                        length: newLength,
                        url: entity.url
                    ))
                }
            }

            // Also detect plain-text URLs
            let urlEntities = TextEntity.detectURLs(in: trimmed)
            blockEntities.append(contentsOf: urlEntities)

            blocks.append(ContentBlock(type: "text", text: trimmed, entities: blockEntities.isEmpty ? nil : blockEntities))
            currentTextLines.removeAll()
        }

        for info in lineInfos {
            if info.isTodo {
                flushTextLines()
                let afterPrefix = String(info.text.dropFirst(prefix.count))
                let todoText = afterPrefix.trimmingCharacters(in: .whitespaces)
                if !todoText.isEmpty {
                    var todoEntities: [TextEntity] = []

                    if let entities = entities, !entities.isEmpty {
                        // Map entities from composer text coordinates to todo-local coordinates
                        let leadingSpaces = String(afterPrefix.prefix(while: { $0 == " " }))
                        let leadingSpacesUTF16 = (leadingSpaces as NSString).length
                        let todoStart = info.startOffset + prefixUTF16 + leadingSpacesUTF16
                        let todoLength = (todoText as NSString).length
                        let todoEnd = todoStart + todoLength

                        for entity in entities {
                            let entityStart = entity.offset
                            let entityEnd = entity.offset + entity.length
                            guard entityStart < todoEnd && entityEnd > todoStart else { continue }

                            let clippedStart = max(entityStart, todoStart)
                            let clippedEnd = min(entityEnd, todoEnd)
                            let newLength = clippedEnd - clippedStart
                            guard newLength > 0 else { continue }

                            todoEntities.append(TextEntity(
                                type: entity.type,
                                offset: clippedStart - todoStart,
                                length: newLength,
                                url: entity.url
                            ))
                        }
                    }

                    // Also detect plain-text URLs
                    let urlEntities = TextEntity.detectURLs(in: todoText)
                    todoEntities.append(contentsOf: urlEntities)

                    let itemId = UUID()
                    blocks.append(ContentBlock(id: itemId, type: "todo", text: todoText, entities: todoEntities.isEmpty ? nil : todoEntities))
                    todoItems.append(TodoItem(id: itemId, text: todoText))
                    hasTodos = true
                }
            } else {
                currentTextLines.append((text: info.text, startOffset: info.startOffset))
            }
        }
        flushTextLines()

        let plainText = blocks.filter { $0.type == "text" }.map { $0.text }.joined(separator: "\n")
        return (blocks, todoItems, plainText, hasTodos)
    }

    /// Map block-level entities back to composer text coordinate space
    static func composerEntities(from blocks: [ContentBlock]) -> [TextEntity] {
        var entities: [TextEntity] = []
        var offset = 0
        let prefixUTF16 = (checkboxPrefix as NSString).length

        for (index, block) in blocks.enumerated() {
            if block.type == "todo" {
                // Todo text starts after "○ " prefix in composer
                if let blockEntities = block.entities {
                    for entity in blockEntities {
                        if entity.type == "url" { continue }
                        entities.append(TextEntity(
                            type: entity.type,
                            offset: entity.offset + offset + prefixUTF16,
                            length: entity.length,
                            url: entity.url
                        ))
                    }
                }
                offset += prefixUTF16 + (block.text as NSString).length
            } else {
                // Map text block entities to composer text coordinates
                if let blockEntities = block.entities {
                    for entity in blockEntities {
                        if entity.type == "url" { continue }
                        entities.append(TextEntity(
                            type: entity.type,
                            offset: entity.offset + offset,
                            length: entity.length,
                            url: entity.url
                        ))
                    }
                }
                offset += (block.text as NSString).length
            }

            if index < blocks.count - 1 {
                offset += 1 // newline between blocks
            }
        }

        return entities
    }
}

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

    /// Shared link detector (NSDataDetector is immutable after creation, thread-safe for matching)
    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// Detect URLs in text and return entities
    static func detectURLs(in text: String) -> [TextEntity] {
        guard !text.isEmpty else { return [] }

        var entities: [TextEntity] = []

        let detector = linkDetector
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
    let image: String?               // Local filename for preview image
    let siteName: String?
    let imageAspectRatio: Double?    // width / height — determines large vs compact layout
    var isPlaceholder: Bool?         // true while real preview is loading (nil for existing data)

    /// Large layout: full-width image below title (landscape og:image, width >= 300)
    var isLargeImage: Bool {
        guard image != nil && !(image?.isEmpty ?? true) else { return false }
        guard let ratio = imageAspectRatio else { return false }
        return ratio >= 1.2
    }

    init(url: String, title: String? = nil, previewDescription: String? = nil, image: String? = nil, siteName: String? = nil, imageAspectRatio: Double? = nil, isPlaceholder: Bool? = nil) {
        self.url = url
        self.title = title
        self.previewDescription = previewDescription
        self.image = image
        self.siteName = siteName
        self.imageAspectRatio = imageAspectRatio
        self.isPlaceholder = isPlaceholder
    }

    // Custom coding keys to map "description" from JSON to "previewDescription"
    enum CodingKeys: String, CodingKey {
        case url, title, image, siteName, imageAspectRatio, isPlaceholder
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
    var videoFileNames: [String] = []
    var videoAspectRatios: [Double] = []
    var videoDurations: [Double] = []
    var videoThumbnailFileNames: [String] = []
    var todoItems: [TodoItem]?      // Todo list items (nil = not a todo list)
    var todoTitle: String?          // Optional title for todo list
    var contentBlocks: [ContentBlock]?  // Ordered mixed content blocks (nil = old format)
    var reminderDate: Date?         // When to send reminder notification
    var reminderRepeatInterval: ReminderRepeatInterval?  // How often to repeat
    var notificationId: String?     // ID for canceling scheduled notification

    /// Whether this message has a reminder set
    var hasReminder: Bool {
        reminderDate != nil
    }

    /// Whether this message has any media (photos or videos)
    var hasMedia: Bool {
        !photoFileNames.isEmpty || !videoFileNames.isEmpty
    }

    /// Total count of all media items (photos + videos)
    var totalMediaCount: Int {
        photoFileNames.count + videoFileNames.count
    }

    /// Check if media at given index is a video (photos come first, then videos)
    func isVideo(at index: Int) -> Bool {
        index >= photoFileNames.count
    }

    /// Get video index from combined media index
    func videoIndex(from mediaIndex: Int) -> Int {
        mediaIndex - photoFileNames.count
    }

    /// Check if this message is a todo list
    var isTodoList: Bool {
        todoItems != nil && !(todoItems?.isEmpty ?? true)
    }

    /// Whether this message uses the new ordered content blocks format
    var hasContentBlocks: Bool {
        contentBlocks != nil && !(contentBlocks?.isEmpty ?? true)
    }

    /// Reconstruct composer-format text from content blocks (text + "○ " prefixed todos)
    var composerText: String {
        guard let blocks = contentBlocks, !blocks.isEmpty else { return content }
        return ContentBlock.composerText(from: blocks)
    }

    /// Create a message in a specific tab (or Inbox if tabId is nil)
    init(
        content: String,
        tabId: UUID? = nil,
        entities: [TextEntity]? = nil,
        photoFileNames: [String] = [],
        photoAspectRatios: [Double] = [],
        videoFileNames: [String] = [],
        videoAspectRatios: [Double] = [],
        videoDurations: [Double] = [],
        videoThumbnailFileNames: [String] = [],
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
        self.videoFileNames = videoFileNames
        self.videoAspectRatios = videoAspectRatios
        self.videoDurations = videoDurations
        self.videoThumbnailFileNames = videoThumbnailFileNames
    }

    /// Get aspect ratios as CGFloat array (photos + videos combined)
    var aspectRatios: [CGFloat] {
        (photoAspectRatios + videoAspectRatios).map { CGFloat($0) }
    }

    /// Get photo-only aspect ratios as CGFloat array
    var photoOnlyAspectRatios: [CGFloat] {
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

    /// Check if message has no content (no text, no media, no todo items)
    var isEmpty: Bool {
        let hasText = !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasText { return false }
        if isTodoList { return false }
        if !photoFileNames.isEmpty { return false }
        if !videoFileNames.isEmpty { return false }
        return true
    }

    /// Directory for storing message photos (uses shared container for extension support)
    static var photosDirectory: URL {
        SharedPhotoStorage.photosDirectory
    }

    /// Directory for storing message videos (uses shared container for extension support)
    static var videosDirectory: URL {
        SharedVideoStorage.videosDirectory
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
            SharedPhotoStorage.deletePhoto(fileName)
        }
    }

    /// Delete video files and their thumbnails when message is deleted
    func deleteVideoFiles() {
        for fileName in videoFileNames {
            SharedVideoStorage.deleteVideo(fileName)
        }
        for fileName in videoThumbnailFileNames {
            SharedPhotoStorage.deletePhoto(fileName)
        }
    }

    /// Delete all media files (photos, videos, and link preview image)
    func deleteMediaFiles() {
        deletePhotoFiles()
        deleteVideoFiles()
        if let imageFileName = linkPreview?.image {
            SharedPhotoStorage.deletePhoto(imageFileName)
        }
    }
}
