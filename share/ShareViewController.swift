//
//  ShareViewController.swift
//  share
//
//  Entry point for Share Extension
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers
import ImageIO
import AVFoundation

class ShareViewController: UIViewController {
    private var textContent: String = ""
    private var urlContent: [URL] = []
    private var imageProviders: [NSItemProvider] = []  // Don't load images, just keep providers
    private var videoProviders: [NSItemProvider] = []  // Don't load videos, just keep providers
    private var hostingController: UIHostingController<ShareExtensionView>?
    private let collectedContentQueue = DispatchQueue(label: "company.thecool.taby.share.collected-content")

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        collectProviders()
    }

    /// Collect providers without loading content into memory
    private func collectProviders() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            showShareUI()
            return
        }

        let group = DispatchGroup()

        for item in extensionItems {
            guard let attachments = item.attachments else { continue }

            for provider in attachments {
                // Check if it's a video - just save the provider, don't load
                if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) ||
                   provider.hasItemConformingToTypeIdentifier(UTType.video.identifier) ||
                   provider.hasItemConformingToTypeIdentifier(UTType.quickTimeMovie.identifier) ||
                   provider.hasItemConformingToTypeIdentifier(UTType.mpeg4Movie.identifier) {
                    videoProviders.append(provider)
                }
                // Check if it's an image - just save the provider, don't load
                else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) ||
                   provider.hasItemConformingToTypeIdentifier(UTType.jpeg.identifier) ||
                   provider.hasItemConformingToTypeIdentifier(UTType.png.identifier) ||
                   provider.hasItemConformingToTypeIdentifier(UTType.heic.identifier) {
                    imageProviders.append(provider)
                }
                // Handle URLs - small, safe to load
                else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
                        defer { group.leave() }
                        if let url = item as? URL {
                            self?.collectedContentQueue.sync {
                                self?.urlContent.append(url)
                            }
                        }
                    }
                }
                // Handle plain text - small, safe to load
                else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    group.enter()
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] item, _ in
                        defer { group.leave() }
                        if let text = item as? String {
                            self?.collectedContentQueue.sync {
                                if self?.textContent.isEmpty == true {
                                    self?.textContent = text
                                } else {
                                    self?.textContent += "\n\n" + text
                                }
                            }
                        }
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.showShareUI()
        }
    }

    private func showShareUI() {
        // Build content summary for UI (without loading images)
        var combinedText = textContent
        for url in urlContent {
            if combinedText.isEmpty {
                combinedText = url.absoluteString
            } else {
                combinedText += "\n\n" + url.absoluteString
            }
        }

        let content = SharedContent(
            text: combinedText,
            urls: urlContent,
            imageCount: imageProviders.count,
            videoCount: videoProviders.count
        )

        let shareView = ShareExtensionView(
            content: content,
            onCancel: { [weak self] in
                self?.cancel()
            },
            onSave: { [weak self] tabId in
                self?.save(to: tabId)
            }
        )

        let hostingController = UIHostingController(rootView: shareView)
        self.hostingController = hostingController

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        hostingController.didMove(toParent: self)
    }

    private func cancel() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private func save(to tabId: UUID?) {
        // Process images and videos one by one, writing directly to disk
        var photoFileNames: [String] = []
        var photoAspectRatios: [Double] = []
        var videoFileNames: [String] = []
        var videoAspectRatios: [Double] = []
        var videoDurations: [Double] = []
        var videoThumbnailFileNames: [String] = []
        let resultsQueue = DispatchQueue(label: "company.thecool.taby.share.save-results")

        let group = DispatchGroup()

        for provider in imageProviders {
            group.enter()
            saveImageProvider(provider) { result in
                defer { group.leave() }
                if let (fileName, aspectRatio) = result {
                    resultsQueue.sync {
                        photoFileNames.append(fileName)
                        photoAspectRatios.append(aspectRatio)
                    }
                }
            }
        }

        for provider in videoProviders {
            group.enter()
            saveVideoProvider(provider) { result in
                defer { group.leave() }
                if let result = result {
                    resultsQueue.sync {
                        videoFileNames.append(result.fileName)
                        videoAspectRatios.append(result.aspectRatio)
                        videoDurations.append(result.duration)
                        videoThumbnailFileNames.append(result.thumbnailFileName)
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }

            // Build combined text
            var combinedText = self.textContent
            for url in self.urlContent {
                if combinedText.isEmpty {
                    combinedText = url.absoluteString
                } else {
                    combinedText += "\n\n" + url.absoluteString
                }
            }

            // Create pending item
            let item = PendingShareItem(
                text: combinedText,
                photoFileNames: photoFileNames,
                photoAspectRatios: photoAspectRatios,
                videoFileNames: videoFileNames,
                videoAspectRatios: videoAspectRatios,
                videoDurations: videoDurations,
                videoThumbnailFileNames: videoThumbnailFileNames,
                tabId: tabId
            )

            PendingShareStorage.save(item)
            self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }

    /// Save image from provider directly to disk without holding in memory
    private func saveImageProvider(_ provider: NSItemProvider, completion: @escaping ((String, Double)?) -> Void) {
        // Use loadFileRepresentation to get file URL without loading into memory
        provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
            guard let url = url else {
                completion(nil)
                return
            }

            // Read image dimensions without loading full image
            guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
                  let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else {
                completion(nil)
                return
            }

            let aspectRatio = Double(width / height)

            // Create downsampled thumbnail using Core Graphics (memory efficient)
            let maxDimension: CGFloat = 1600
            let options: [CFString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: maxDimension,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]

            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
                completion(nil)
                return
            }

            // Save as JPEG
            let fileName = UUID().uuidString + ".jpg"
            guard let destURL = SharedPhotoStorage.photosDirectory?.appendingPathComponent(fileName) else {
                completion(nil)
                return
            }

            guard let destination = CGImageDestinationCreateWithURL(destURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
                completion(nil)
                return
            }

            let jpegOptions: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: 0.7
            ]
            CGImageDestinationAddImage(destination, thumbnail, jpegOptions as CFDictionary)

            if CGImageDestinationFinalize(destination) {
                completion((fileName, aspectRatio))
            } else {
                completion(nil)
            }
        }
    }

    /// Result of saving a video in Share Extension
    struct VideoSaveResultExtension {
        let fileName: String
        let thumbnailFileName: String
        let aspectRatio: Double
        let duration: Double
    }

    /// Save video from provider directly to disk without holding in memory
    private func saveVideoProvider(_ provider: NSItemProvider, completion: @escaping (VideoSaveResultExtension?) -> Void) {
        // Use loadFileRepresentation to get file URL without loading into memory
        provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
            guard let url = url else {
                completion(nil)
                return
            }

            // Check file size
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let fileSize = attributes[.size] as? Int64,
                  fileSize <= SharedVideoStorageExtension.maxVideoFileSize else {
                completion(nil)
                return
            }

            // Copy video to shared container
            let videoFileName = UUID().uuidString + ".mp4"
            guard let destURL = SharedVideoStorageExtension.videosDirectory?.appendingPathComponent(videoFileName) else {
                completion(nil)
                return
            }

            do {
                try FileManager.default.copyItem(at: url, to: destURL)
            } catch {
                completion(nil)
                return
            }

            // Extract metadata
            let asset = AVURLAsset(url: destURL)

            Task {
                // Load duration
                let duration: Double
                do {
                    let durationValue = try await asset.load(.duration)
                    duration = CMTimeGetSeconds(durationValue)
                } catch {
                    try? FileManager.default.removeItem(at: destURL)
                    completion(nil)
                    return
                }

                // Check duration limit
                guard duration > 0 && duration <= SharedVideoStorageExtension.maxVideoDuration else {
                    try? FileManager.default.removeItem(at: destURL)
                    completion(nil)
                    return
                }

                // Load aspect ratio
                let aspectRatio: Double
                do {
                    guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                        try? FileManager.default.removeItem(at: destURL)
                        completion(nil)
                        return
                    }
                    let size = try await track.load(.naturalSize)
                    let transform = try await track.load(.preferredTransform)
                    let transformedSize = size.applying(transform)
                    let width = abs(transformedSize.width)
                    let height = abs(transformedSize.height)
                    aspectRatio = height > 0 ? width / height : 1.0
                } catch {
                    try? FileManager.default.removeItem(at: destURL)
                    completion(nil)
                    return
                }

                // Generate thumbnail
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 800, height: 800)
                generator.requestedTimeToleranceBefore = .zero
                generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

                do {
                    let (cgImage, _) = try await generator.image(at: .zero)

                    // Save thumbnail
                    let thumbnailFileName = UUID().uuidString + ".jpg"
                    guard let thumbURL = SharedPhotoStorage.photosDirectory?.appendingPathComponent(thumbnailFileName),
                          let destination = CGImageDestinationCreateWithURL(thumbURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
                        try? FileManager.default.removeItem(at: destURL)
                        completion(nil)
                        return
                    }

                    let jpegOptions: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.8]
                    CGImageDestinationAddImage(destination, cgImage, jpegOptions as CFDictionary)

                    if CGImageDestinationFinalize(destination) {
                        let result = VideoSaveResultExtension(
                            fileName: videoFileName,
                            thumbnailFileName: thumbnailFileName,
                            aspectRatio: aspectRatio,
                            duration: duration
                        )
                        completion(result)
                    } else {
                        try? FileManager.default.removeItem(at: destURL)
                        completion(nil)
                    }
                } catch {
                    try? FileManager.default.removeItem(at: destURL)
                    completion(nil)
                }
            }
        }
    }
}
