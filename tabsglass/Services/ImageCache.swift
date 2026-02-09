//
//  ImageCache.swift
//  tabsglass
//
//  Optimized image loading with caching and downsampling
//

import UIKit

final class ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, UIImage>()
    private let thumbnailCache = NSCache<NSString, UIImage>()
    private let loadingQueue = DispatchQueue(label: "com.tabsglass.imageloading", qos: .userInitiated, attributes: .concurrent)

    private init() {
        // Limit cache size (approximately)
        cache.countLimit = 50
        thumbnailCache.countLimit = 100
    }

    // MARK: - Public API

    /// Load thumbnail for mosaic display (downsampled for performance)
    func loadThumbnail(
        for fileName: String,
        targetSize: CGSize,
        completion: @escaping (UIImage?) -> Void
    ) {
        let cacheKey = "\(fileName)_thumb_\(Int(targetSize.width))x\(Int(targetSize.height))" as NSString

        // Check cache first
        if let cached = thumbnailCache.object(forKey: cacheKey) {
            completion(cached)
            return
        }

        // Load async
        loadingQueue.async { [weak self] in
            guard let self = self else { return }

            let url = Message.photosDirectory.appendingPathComponent(fileName)
            let image = self.downsample(imageAt: url, to: targetSize)

            if let image = image {
                self.thumbnailCache.setObject(image, forKey: cacheKey)
            }

            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    /// Load full resolution image for gallery view
    func loadFullImage(
        for fileName: String,
        completion: @escaping (UIImage?) -> Void
    ) {
        let cacheKey = fileName as NSString

        // Check cache first
        if let cached = cache.object(forKey: cacheKey) {
            completion(cached)
            return
        }

        // Load async
        loadingQueue.async { [weak self] in
            guard let self = self else { return }

            let url = Message.photosDirectory.appendingPathComponent(fileName)
            guard let data = try? Data(contentsOf: url),
                  let image = UIImage(data: data) else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }

            self.cache.setObject(image, forKey: cacheKey)

            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    /// Synchronous thumbnail load (for cases where we need immediate result)
    func thumbnailSync(for fileName: String, targetSize: CGSize) -> UIImage? {
        let cacheKey = "\(fileName)_thumb_\(Int(targetSize.width))x\(Int(targetSize.height))" as NSString

        if let cached = thumbnailCache.object(forKey: cacheKey) {
            return cached
        }

        let url = Message.photosDirectory.appendingPathComponent(fileName)
        let image = downsample(imageAt: url, to: targetSize)

        if let image = image {
            thumbnailCache.setObject(image, forKey: cacheKey)
        }

        return image
    }

    /// Clear all caches
    func clearCache() {
        cache.removeAllObjects()
        thumbnailCache.removeAllObjects()
    }

    // MARK: - Downsampling

    /// Efficiently downsample image at URL to target size
    /// This decodes only the pixels needed, saving memory and CPU
    private func downsample(imageAt url: URL, to pointSize: CGSize) -> UIImage? {
        // Create image source without caching raw data
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }

        // Calculate max dimension in pixels
        let scale = UITraitCollection.current.displayScale
        let maxDimension = max(pointSize.width, pointSize.height) * scale

        // Create thumbnail with downsampling
        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ] as CFDictionary

        guard let downsampledImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else {
            return nil
        }

        return UIImage(cgImage: downsampledImage)
    }
}

// MARK: - Prefetch Helper

extension ImageCache {
    /// Prefetch thumbnails for file names (call from prefetchRowsAt)
    func prefetchThumbnails(for fileNames: [String], targetSize: CGSize) {
        for fileName in fileNames {
            let cacheKey = "\(fileName)_thumb_\(Int(targetSize.width))x\(Int(targetSize.height))" as NSString

            // Skip if already cached
            if thumbnailCache.object(forKey: cacheKey) != nil {
                continue
            }

            loadingQueue.async { [weak self] in
                guard let self = self else { return }
                let url = Message.photosDirectory.appendingPathComponent(fileName)
                if let image = self.downsample(imageAt: url, to: targetSize) {
                    self.thumbnailCache.setObject(image, forKey: cacheKey)
                }
            }
        }
    }
}

// MARK: - Video Thumbnail Support

extension ImageCache {
    /// Load video thumbnail (uses pre-saved thumbnail file)
    /// - Parameters:
    ///   - videoFileName: The video file name (used for cache key)
    ///   - thumbnailFileName: The pre-generated thumbnail file name
    ///   - targetSize: Target size for downsampling
    ///   - completion: Completion handler with the loaded image
    func loadVideoThumbnail(
        videoFileName: String,
        thumbnailFileName: String,
        targetSize: CGSize,
        completion: @escaping (UIImage?) -> Void
    ) {
        let cacheKey = "video_\(videoFileName)_thumb_\(Int(targetSize.width))x\(Int(targetSize.height))" as NSString

        // Check cache first
        if let cached = thumbnailCache.object(forKey: cacheKey) {
            completion(cached)
            return
        }

        // Load thumbnail file (stored in photos directory)
        loadingQueue.async { [weak self] in
            guard let self = self else { return }

            let url = Message.photosDirectory.appendingPathComponent(thumbnailFileName)
            let image = self.downsample(imageAt: url, to: targetSize)

            if let image = image {
                self.thumbnailCache.setObject(image, forKey: cacheKey)
            }

            DispatchQueue.main.async {
                completion(image)
            }
        }
    }

    /// Synchronous video thumbnail load
    func videoThumbnailSync(
        videoFileName: String,
        thumbnailFileName: String,
        targetSize: CGSize
    ) -> UIImage? {
        let cacheKey = "video_\(videoFileName)_thumb_\(Int(targetSize.width))x\(Int(targetSize.height))" as NSString

        if let cached = thumbnailCache.object(forKey: cacheKey) {
            return cached
        }

        let url = Message.photosDirectory.appendingPathComponent(thumbnailFileName)
        let image = downsample(imageAt: url, to: targetSize)

        if let image = image {
            thumbnailCache.setObject(image, forKey: cacheKey)
        }

        return image
    }

    /// Prefetch video thumbnails for upcoming cells.
    func prefetchVideoThumbnails(
        videoFileNames: [String],
        thumbnailFileNames: [String],
        targetSize: CGSize
    ) {
        guard !videoFileNames.isEmpty, !thumbnailFileNames.isEmpty else { return }

        for (videoFileName, thumbnailFileName) in zip(videoFileNames, thumbnailFileNames) {
            guard !thumbnailFileName.isEmpty else { continue }

            let cacheKey = "video_\(videoFileName)_thumb_\(Int(targetSize.width))x\(Int(targetSize.height))" as NSString
            if thumbnailCache.object(forKey: cacheKey) != nil {
                continue
            }

            loadingQueue.async { [weak self] in
                guard let self = self else { return }
                let url = Message.photosDirectory.appendingPathComponent(thumbnailFileName)
                if let image = self.downsample(imageAt: url, to: targetSize) {
                    self.thumbnailCache.setObject(image, forKey: cacheKey)
                }
            }
        }
    }
}
