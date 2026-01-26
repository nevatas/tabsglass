//
//  Message.swift
//  tabsglass
//

import Foundation
import SwiftData
import UIKit

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
}

// MARK: - Message Model

@Model
final class Message: Identifiable {
    var id: UUID
    var content: String
    var entities: [TextEntity]?
    var createdAt: Date
    var tab: Tab?
    var photoFileNames: [String] = []
    var photoAspectRatios: [Double] = []

    init(content: String, tab: Tab, entities: [TextEntity]? = nil, photoFileNames: [String] = [], photoAspectRatios: [Double] = []) {
        self.id = UUID()
        self.content = content
        self.entities = entities
        self.createdAt = Date()
        self.tab = tab
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

    /// Check if message has no content (no text and no valid photos)
    var isEmpty: Bool {
        let hasText = !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasText { return false }

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
            print("Failed to save photo: \(error)")
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
