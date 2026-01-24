//
//  Message.swift
//  tabsglass
//

import Foundation
import SwiftData
import UIKit

@Model
final class Message: Identifiable {
    var id: UUID
    var text: String
    var createdAt: Date
    var tab: Tab?
    var photoFileNames: [String] = []

    init(text: String, tab: Tab, photoFileNames: [String] = []) {
        self.id = UUID()
        self.text = text
        self.createdAt = Date()
        self.tab = tab
        self.photoFileNames = photoFileNames
    }

    /// Get UIImages for attached photos
    var photos: [UIImage] {
        photoFileNames.compactMap { fileName in
            let url = Message.photosDirectory.appendingPathComponent(fileName)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        }
    }

    /// Check if message has no content (no text and no valid photos)
    var isEmpty: Bool {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    /// Save image and return file name
    static func savePhoto(_ image: UIImage) -> String? {
        let fileName = UUID().uuidString + ".jpg"
        let url = photosDirectory.appendingPathComponent(fileName)

        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }

        do {
            try data.write(to: url)
            return fileName
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
