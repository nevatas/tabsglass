//
//  SharedVideoStorage.swift
//  tabsglass
//
//  Video storage service for saving, loading, and managing video files
//

import AVFoundation
import UIKit

/// Result of saving a video file
struct VideoSaveResult: Sendable {
    let fileName: String
    let thumbnailFileName: String
    let aspectRatio: Double
    let duration: Double
}

/// Shared video storage for main app and extension
enum SharedVideoStorage {
    private static let appGroupID = "group.company.thecool.taby"

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    /// Directory for storing message videos in shared container
    static var videosDirectory: URL {
        guard let container = containerURL else {
            // Fallback to documents directory if container unavailable
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let videosPath = documentsPath.appendingPathComponent("MessageVideos", isDirectory: true)
            createDirectoryIfNeeded(videosPath)
            return videosPath
        }
        let videosPath = container.appendingPathComponent("MessageVideos", isDirectory: true)
        createDirectoryIfNeeded(videosPath)
        return videosPath
    }

    private static func createDirectoryIfNeeded(_ url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    // MARK: - Video Constraints

    /// Maximum video duration in seconds (5 minutes)
    static let maxVideoDuration: Double = 300

    /// Maximum video file size in bytes (100MB)
    static let maxVideoFileSize: Int64 = 100 * 1024 * 1024

    /// Maximum resolution in megapixels (16MP)
    static let maxResolutionMegapixels: Double = 16

    // MARK: - Save Video

    /// Save video from source URL (memory-efficient file copy)
    /// - Parameter sourceURL: The source video file URL
    /// - Returns: VideoSaveResult with file names and metadata, or nil if failed
    static func saveVideo(from sourceURL: URL) async -> VideoSaveResult? {
        let fileName = UUID().uuidString + ".mp4"
        let destURL = videosDirectory.appendingPathComponent(fileName)

        // Copy file directly (memory-efficient)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
        } catch {
            return nil
        }

        // Extract metadata asynchronously
        let asset = AVURLAsset(url: destURL)

        async let duration = loadDuration(asset)
        async let aspectRatio = loadAspectRatio(asset)
        async let thumbnail = generateThumbnail(asset)

        guard let thumbImage = await thumbnail,
              let thumbResult = SharedPhotoStorage.savePhoto(thumbImage) else {
            // Clean up video file if thumbnail failed
            try? FileManager.default.removeItem(at: destURL)
            return nil
        }

        return VideoSaveResult(
            fileName: fileName,
            thumbnailFileName: thumbResult.fileName,
            aspectRatio: await aspectRatio,
            duration: await duration
        )
    }

    // MARK: - Thumbnail Generation

    /// Generate thumbnail from video asset (AVAssetImageGenerator best practices)
    /// - Parameter asset: The AVAsset to generate thumbnail from
    /// - Returns: UIImage thumbnail or nil if failed
    static func generateThumbnail(_ asset: AVAsset) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true  // Respect video orientation
        generator.maximumSize = CGSize(width: 800, height: 800)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

        do {
            let (cgImage, _) = try await generator.image(at: .zero)
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }

    /// Generate thumbnail from video file URL
    /// - Parameter url: The video file URL
    /// - Returns: UIImage thumbnail or nil if failed
    static func generateThumbnail(from url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        return await generateThumbnail(asset)
    }

    // MARK: - Metadata Loading

    /// Load video duration using async/await
    /// - Parameter asset: The AVAsset to get duration from
    /// - Returns: Duration in seconds
    static func loadDuration(_ asset: AVAsset) async -> Double {
        do {
            let duration = try await asset.load(.duration)
            return CMTimeGetSeconds(duration)
        } catch {
            return 0
        }
    }

    /// Load aspect ratio with proper orientation handling
    /// - Parameter asset: The AVAsset to get aspect ratio from
    /// - Returns: Width/height aspect ratio
    static func loadAspectRatio(_ asset: AVAsset) async -> Double {
        do {
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                return 1.0
            }
            let size = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)

            // Apply transform to get actual dimensions (handles rotation)
            let transformedSize = size.applying(transform)
            let width = abs(transformedSize.width)
            let height = abs(transformedSize.height)

            guard height > 0 else { return 1.0 }
            return width / height
        } catch {
            return 1.0
        }
    }

    // MARK: - Validation

    /// Check if video meets size and duration constraints
    /// - Parameter url: The video file URL to validate
    /// - Returns: true if valid, false otherwise
    static func validateVideo(at url: URL) async -> Bool {
        // Check file size
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? Int64,
              fileSize <= maxVideoFileSize else {
            return false
        }

        // Check duration
        let asset = AVURLAsset(url: url)
        let duration = await loadDuration(asset)
        guard duration > 0 && duration <= maxVideoDuration else {
            return false
        }

        return true
    }

    // MARK: - Delete

    /// Delete video file from storage
    /// - Parameter fileName: The video file name to delete
    static func deleteVideo(_ fileName: String) {
        let url = videosDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: url)
    }

    /// Get full URL for video file name
    /// - Parameter fileName: The video file name
    /// - Returns: Full URL to the video file
    static func videoURL(for fileName: String) -> URL {
        videosDirectory.appendingPathComponent(fileName)
    }
}

