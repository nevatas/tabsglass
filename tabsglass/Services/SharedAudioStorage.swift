//
//  SharedAudioStorage.swift
//  tabsglass
//
//  Shared audio storage for main app and extensions
//

import AVFoundation
import Foundation

/// Result of saving an audio file.
struct AudioSaveResult: Sendable {
    let fileName: String
    let duration: Double
}

enum SharedAudioStorage {
    /// Get the audios directory (shared container preferred, Documents fallback)
    static var audiosDirectory: URL {
        if let sharedDir = SharedConstants.audiosDirectory {
            return sharedDir
        }

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audiosPath = documentsPath.appendingPathComponent("MessageAudio", isDirectory: true)
        if !FileManager.default.fileExists(atPath: audiosPath.path) {
            try? FileManager.default.createDirectory(at: audiosPath, withIntermediateDirectories: true)
        }
        return audiosPath
    }

    /// Save audio file from source URL.
    /// - Parameters:
    ///   - sourceURL: Source file URL.
    ///   - duration: Optional precomputed duration.
    /// - Returns: Saved file metadata.
    static func saveAudio(from sourceURL: URL, duration: Double? = nil) -> AudioSaveResult? {
        let fileName = UUID().uuidString + ".m4a"
        let destinationURL = audiosDirectory.appendingPathComponent(fileName)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            let resolvedDuration = max(duration ?? audioDuration(at: destinationURL), 0)
            return AudioSaveResult(fileName: fileName, duration: resolvedDuration)
        } catch {
            return nil
        }
    }

    /// Get URL for an audio file name.
    static func audioURL(for fileName: String) -> URL {
        if let sharedDir = SharedConstants.audiosDirectory {
            let sharedURL = sharedDir.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: sharedURL.path) {
                return sharedURL
            }
        }

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath
            .appendingPathComponent("MessageAudio", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    /// Delete an audio file from both shared and fallback locations.
    static func deleteAudio(_ fileName: String) {
        if let sharedDir = SharedConstants.audiosDirectory {
            let sharedURL = sharedDir.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: sharedURL)
        }

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fallbackURL = documentsPath
            .appendingPathComponent("MessageAudio", isDirectory: true)
            .appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fallbackURL)
    }

    /// Resolve duration from file URL.
    static func audioDuration(at url: URL) -> Double {
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return 0 }
        let seconds = player.duration
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return seconds
    }
}
