//
//  SharedPhotoStorage.swift
//  tabsglass
//
//  Shared photo storage for main app and extensions
//

import Foundation
import UIKit
import os.log

enum SharedPhotoStorage {
    private static let logger = Logger(subsystem: "com.thecool.taby", category: "SharedPhotoStorage")

    /// Get the photos directory (shared container preferred, Documents fallback)
    static var photosDirectory: URL {
        if let sharedDir = SharedConstants.photosDirectory {
            return sharedDir
        }
        // Fallback to Documents for backward compatibility
        return SharedConstants.legacyPhotosDirectory
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
            logger.error("Failed to save photo: \(error.localizedDescription)")
            return nil
        }
    }

    /// Save image data directly and return file name
    static func savePhotoData(_ data: Data) -> String? {
        let fileName = UUID().uuidString + ".jpg"
        let url = photosDirectory.appendingPathComponent(fileName)

        do {
            try data.write(to: url)
            return fileName
        } catch {
            logger.error("Failed to save photo data: \(error.localizedDescription)")
            return nil
        }
    }

    /// Get URL for a photo file name
    static func photoURL(for fileName: String) -> URL {
        // Check shared container first
        if let sharedDir = SharedConstants.photosDirectory {
            let sharedURL = sharedDir.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: sharedURL.path) {
                return sharedURL
            }
        }

        // Fallback to legacy location
        return SharedConstants.legacyPhotosDirectory.appendingPathComponent(fileName)
    }

    /// Check if a photo exists
    static func photoExists(_ fileName: String) -> Bool {
        let url = photoURL(for: fileName)
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Delete a photo file
    static func deletePhoto(_ fileName: String) {
        // Try to delete from both locations
        if let sharedDir = SharedConstants.photosDirectory {
            let sharedURL = sharedDir.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: sharedURL)
        }

        let legacyURL = SharedConstants.legacyPhotosDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: legacyURL)
    }

    /// Calculate aspect ratio from image data
    static func aspectRatio(from data: Data) -> Double {
        guard let image = UIImage(data: data) else { return 1.0 }
        return Double(image.size.width / image.size.height)
    }
}
