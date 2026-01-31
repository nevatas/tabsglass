//
//  MediaSyncService.swift
//  tabsglass
//
//  Service for syncing media files (photos/videos) with R2 storage
//

import Foundation
import UIKit
import AVFoundation
import os.log

/// Service for uploading and downloading media files to/from R2
actor MediaSyncService {
    static let shared = MediaSyncService()

    private let apiClient = APIClient.shared
    private let logger = Logger(subsystem: "tabsglass", category: "MediaSyncService")

    private init() {}

    // MARK: - Upload

    /// Upload media files for a message using presigned URLs
    @MainActor
    func uploadMedia(for message: Message, uploadUrls: [MediaUploadInfo]) async {
        logger.info("Uploading \(uploadUrls.count) media items for message \(message.id)")

        for uploadInfo in uploadUrls {
            logger.debug("Processing upload: \(uploadInfo.mediaType) - \(uploadInfo.localFileName)")
            do {
                let fileURL: URL
                let contentType: String

                switch uploadInfo.mediaType {
                case "photo":
                    fileURL = Message.photosDirectory.appendingPathComponent(uploadInfo.localFileName)
                    contentType = "image/jpeg"
                case "video":
                    fileURL = Message.videosDirectory.appendingPathComponent(uploadInfo.localFileName)
                    contentType = "video/mp4"
                case "thumbnail":
                    fileURL = Message.photosDirectory.appendingPathComponent(uploadInfo.localFileName)
                    contentType = "image/jpeg"
                default:
                    logger.warning("Unknown media type: \(uploadInfo.mediaType)")
                    continue
                }

                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    logger.warning("File not found for upload: \(uploadInfo.localFileName)")
                    continue
                }

                guard let uploadURL = URL(string: uploadInfo.uploadUrl) else {
                    logger.error("Invalid upload URL: \(uploadInfo.uploadUrl)")
                    continue
                }

                try await apiClient.uploadFile(from: fileURL, to: uploadURL, contentType: contentType)

                // Confirm upload with server
                let _: ConfirmUploadResponse = try await apiClient.request(.confirmUpload(fileKey: uploadInfo.fileKey))

                logger.debug("Uploaded \(uploadInfo.mediaType): \(uploadInfo.localFileName)")
            } catch {
                logger.error("Failed to upload \(uploadInfo.localFileName): \(error.localizedDescription)")
            }
        }
    }

    /// Request upload URL for a single file
    func getUploadURL(contentType: String, contentLength: Int64) async throws -> UploadURLResponse {
        try await apiClient.request(.getUploadURL(contentType: contentType, contentLength: contentLength))
    }

    /// Upload a single file to R2
    func uploadFile(data: Data, contentType: String) async throws -> String {
        // Get presigned URL
        let uploadResponse = try await getUploadURL(contentType: contentType, contentLength: Int64(data.count))

        guard let uploadURL = URL(string: uploadResponse.uploadUrl) else {
            throw APIError.invalidURL
        }

        // Upload to R2
        try await apiClient.upload(data: data, to: uploadURL, contentType: contentType)

        // Confirm with server
        let _: ConfirmUploadResponse = try await apiClient.request(.confirmUpload(fileKey: uploadResponse.fileKey))

        return uploadResponse.fileKey
    }

    // MARK: - Download

    /// Download media files for a message
    @MainActor
    func downloadMedia(for message: Message, media: [MediaItemResponse]) async {
        logger.info("Downloading \(media.count) media items for message \(message.id)")

        var photoFileNames: [String] = []
        var photoAspectRatios: [Double] = []
        var videoFileNames: [String] = []
        var videoAspectRatios: [Double] = []
        var videoDurations: [Double] = []
        var videoThumbnailFileNames: [String] = []

        // Separate videos and their thumbnails from photos
        // Thumbnails are downloaded together with their videos, not separately
        let videoItems = media.filter { $0.mediaType == "video" }
        let thumbnailFileKeys = Set(videoItems.compactMap { $0.thumbnailFileKey })

        for item in media {
            logger.debug("Downloading \(item.mediaType): \(item.fileKey)")

            switch item.mediaType {
            case "photo":
                // Skip if this is actually a video thumbnail
                if thumbnailFileKeys.contains(item.fileKey) {
                    logger.debug("Skipping photo \(item.fileKey) - it's a video thumbnail")
                    continue
                }
                if let fileName = await downloadPhoto(from: item.downloadUrl) {
                    photoFileNames.append(fileName)
                    photoAspectRatios.append(item.aspectRatio)
                }

            case "video":
                logger.info("Video item - thumbnailUrl: \(item.thumbnailDownloadUrl ?? "nil"), thumbnailKey: \(item.thumbnailFileKey ?? "nil")")
                if let result = await downloadVideo(from: item.downloadUrl, thumbnailUrl: item.thumbnailDownloadUrl) {
                    videoFileNames.append(result.fileName)
                    videoAspectRatios.append(item.aspectRatio)
                    videoDurations.append(item.duration ?? 0)
                    if let thumbnailFileName = result.thumbnailFileName {
                        videoThumbnailFileNames.append(thumbnailFileName)
                        logger.info("Downloaded video thumbnail: \(thumbnailFileName)")
                    } else {
                        logger.warning("Video has no thumbnail!")
                    }
                }

            case "thumbnail":
                // Thumbnails are downloaded with their videos, skip standalone
                logger.debug("Skipping standalone thumbnail: \(item.fileKey)")

            default:
                logger.warning("Unknown media type: \(item.mediaType)")
            }
        }

        // Update message with downloaded media
        message.photoFileNames = photoFileNames
        message.photoAspectRatios = photoAspectRatios
        message.videoFileNames = videoFileNames
        message.videoAspectRatios = videoAspectRatios
        message.videoDurations = videoDurations
        message.videoThumbnailFileNames = videoThumbnailFileNames

        logger.info("Downloaded media: \(photoFileNames.count) photos, \(videoFileNames.count) videos")
    }

    /// Download a single photo
    private func downloadPhoto(from urlString: String) async -> String? {
        guard let url = URL(string: urlString) else {
            logger.error("Invalid photo URL: \(urlString)")
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)

            let fileName = UUID().uuidString + ".jpg"
            let fileURL = await MainActor.run { Message.photosDirectory.appendingPathComponent(fileName) }

            try data.write(to: fileURL)
            logger.debug("Downloaded photo: \(fileName)")
            return fileName
        } catch {
            logger.error("Failed to download photo: \(error.localizedDescription)")
            return nil
        }
    }

    /// Download a video and its thumbnail
    private func downloadVideo(from urlString: String, thumbnailUrl: String?) async -> (fileName: String, thumbnailFileName: String?)? {
        guard let url = URL(string: urlString) else {
            logger.error("Invalid video URL: \(urlString)")
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)

            let fileName = UUID().uuidString + ".mp4"
            let fileURL = await MainActor.run { Message.videosDirectory.appendingPathComponent(fileName) }

            try data.write(to: fileURL)
            logger.debug("Downloaded video: \(fileName)")

            // Download thumbnail if available
            var thumbnailFileName: String? = nil
            if let thumbUrl = thumbnailUrl {
                thumbnailFileName = await downloadPhoto(from: thumbUrl)
            }

            return (fileName, thumbnailFileName)
        } catch {
            logger.error("Failed to download video: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Batch Operations

    /// Upload all local media for a message and return media items with metadata
    @MainActor
    func uploadAllMedia(for message: Message) async throws -> [MediaItemRequest] {
        var mediaItems: [MediaItemRequest] = []

        // Upload compressed photos
        for (index, fileName) in message.photoFileNames.enumerated() {
            let fileURL = Message.photosDirectory.appendingPathComponent(fileName)
            guard let compressedData = compressPhoto(at: fileURL) else {
                logger.warning("Failed to compress photo: \(fileName)")
                continue
            }

            let fileKey = try await uploadFile(data: compressedData, contentType: "image/jpeg")
            let aspectRatio = index < message.photoAspectRatios.count ? message.photoAspectRatios[index] : 1.0

            mediaItems.append(MediaItemRequest(
                fileKey: fileKey,
                mediaType: "photo",
                aspectRatio: aspectRatio,
                duration: nil,
                thumbnailFileKey: nil
            ))
            logger.debug("Uploaded compressed photo: \(fileName) (\(compressedData.count / 1024)KB)")
        }

        // Upload compressed videos
        for (index, fileName) in message.videoFileNames.enumerated() {
            let fileURL = Message.videosDirectory.appendingPathComponent(fileName)
            var videoFileKey: String?

            if let compressedURL = await compressVideo(at: fileURL) {
                guard let data = try? Data(contentsOf: compressedURL) else { continue }

                videoFileKey = try await uploadFile(data: data, contentType: "video/mp4")
                logger.debug("Uploaded compressed video: \(fileName) (\(data.count / 1024 / 1024)MB)")

                // Clean up temp compressed file
                try? FileManager.default.removeItem(at: compressedURL)
            } else {
                // Fallback: upload original if compression fails
                guard let data = try? Data(contentsOf: fileURL) else { continue }
                videoFileKey = try await uploadFile(data: data, contentType: "video/mp4")
                logger.warning("Uploaded original video (compression failed): \(fileName)")
            }

            guard let fileKey = videoFileKey else { continue }

            // Upload video thumbnail
            var thumbnailFileKey: String? = nil
            if index < message.videoThumbnailFileNames.count {
                let thumbFileName = message.videoThumbnailFileNames[index]
                let thumbURL = Message.photosDirectory.appendingPathComponent(thumbFileName)
                if let thumbData = compressPhoto(at: thumbURL, maxDimension: 480, quality: 0.7) {
                    thumbnailFileKey = try await uploadFile(data: thumbData, contentType: "image/jpeg")
                    logger.debug("Uploaded video thumbnail: \(thumbFileName)")
                }
            }

            let aspectRatio = index < message.videoAspectRatios.count ? message.videoAspectRatios[index] : 1.78
            let duration = index < message.videoDurations.count ? message.videoDurations[index] : nil

            mediaItems.append(MediaItemRequest(
                fileKey: fileKey,
                mediaType: "video",
                aspectRatio: aspectRatio,
                duration: duration,
                thumbnailFileKey: thumbnailFileKey
            ))
        }

        return mediaItems
    }

    // MARK: - Compression

    /// Compress photo to reasonable size for upload
    /// - Parameters:
    ///   - url: Local file URL
    ///   - maxDimension: Maximum width or height (default 1920)
    ///   - quality: JPEG compression quality 0-1 (default 0.8)
    /// - Returns: Compressed JPEG data
    nonisolated private func compressPhoto(at url: URL, maxDimension: CGFloat = 1920, quality: CGFloat = 0.8) -> Data? {
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }

        let resized = resizeImage(image, maxDimension: maxDimension)
        return resized.jpegData(compressionQuality: quality)
    }

    /// Resize image while maintaining aspect ratio
    nonisolated private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size

        // Don't upscale
        guard size.width > maxDimension || size.height > maxDimension else {
            return image
        }

        let aspectRatio = size.width / size.height
        let newSize: CGSize

        if size.width > size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Compress video for upload
    /// - Parameters:
    ///   - url: Local video file URL
    /// - Returns: URL to compressed video (temp file)
    private func compressVideo(at url: URL) async -> URL? {
        let asset = AVURLAsset(url: url)

        // Check if compression is needed
        guard let videoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            return nil
        }

        let naturalSize = try? await videoTrack.load(.naturalSize)
        let estimatedBitrate = try? await videoTrack.load(.estimatedDataRate)

        // Skip compression for small videos (< 5MB and < 720p)
        if let size = naturalSize, let bitrate = estimatedBitrate {
            let durationValue = try? await asset.load(.duration)
            let durationSeconds = durationValue?.seconds ?? 0
            let estimatedSize = Double(bitrate / 8) * durationSeconds

            if estimatedSize < 5_000_000 && max(size.width, size.height) <= 720 {
                logger.debug("Video is small enough, skipping compression")
                return url
            }
        }

        // Choose preset based on resolution
        let preset: String
        if let size = naturalSize, max(size.width, size.height) > 1080 {
            preset = AVAssetExportPreset1280x720
        } else {
            preset = AVAssetExportPresetMediumQuality
        }

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset) else {
            logger.error("Failed to create export session")
            return nil
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true

        await exportSession.export()

        switch exportSession.status {
        case .completed:
            logger.info("Video compression completed")
            return outputURL
        case .failed:
            logger.error("Video compression failed: \(exportSession.error?.localizedDescription ?? "unknown")")
            return nil
        case .cancelled:
            logger.warning("Video compression cancelled")
            return nil
        default:
            return nil
        }
    }
}
