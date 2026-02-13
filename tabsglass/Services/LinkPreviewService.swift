//
//  LinkPreviewService.swift
//  tabsglass
//
//  Link preview fetching with LPMetadataProvider
//

import Foundation
import LinkPresentation
import UIKit

final class LinkPreviewService {
    static let shared = LinkPreviewService()

    private var cache: [String: LinkPreview] = [:]
    private var currentTask: Task<Void, Never>?
    private var currentURL: String?

    /// Shared link detector (NSDataDetector is immutable after creation, thread-safe for matching)
    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private init() {}

    /// Return the latest cached preview (may include image downloaded after initial return)
    func cachedPreview(for urlString: String) -> LinkPreview? {
        return cache[urlString]
    }

    /// Extract first URL from text using NSDataDetector (same pattern as TextEntity.detectURLs)
    func firstURL(in text: String) -> URL? {
        guard !text.isEmpty else { return nil }
        let detector = Self.linkDetector
        let nsString = text as NSString
        let range = NSRange(location: 0, length: nsString.length)
        var result: URL?
        detector?.enumerateMatches(in: text, options: [], range: range) { match, _, stop in
            if let url = match?.url {
                result = url
                stop.pointee = true
            }
        }
        // NSDataDetector needs a word boundary to recognize URLs at end of text.
        // Retry with a trailing space so pasted URLs are detected immediately.
        if result == nil {
            let padded = text + " "
            let paddedRange = NSRange(location: 0, length: (padded as NSString).length)
            detector?.enumerateMatches(in: padded, options: [], range: paddedRange) { match, _, stop in
                if let url = match?.url {
                    result = url
                    stop.pointee = true
                }
            }
        }
        return result
    }

    /// Fetch preview for the first URL in text. Debounces 0.3s. Calls completion on main thread.
    func fetchPreview(for text: String, completion: @escaping (LinkPreview?) -> Void) {
        guard let url = firstURL(in: text) else {
            completion(nil)
            return
        }

        let urlString = url.absoluteString

        // Return cached result
        if let cached = cache[urlString] {
            completion(cached)
            return
        }

        // Same URL already fetching
        if currentURL == urlString {
            return
        }

        // Cancel previous
        currentTask?.cancel()
        currentURL = urlString

        currentTask = Task { @MainActor in
            // Debounce 0.3s
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            let preview = await self.fetchMetadata(for: url)
            guard !Task.isCancelled else { return }

            if let preview = preview {
                self.cache[urlString] = preview
            }
            self.currentURL = nil
            completion(preview)
        }
    }

    /// Cancel in-flight fetch
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        currentURL = nil
    }

    /// Clear all cached previews
    func clearCache() {
        cache.removeAll()
    }

    /// Fetch preview for an already-sent message (no debounce). Returns best available result.
    /// Waits up to 2s for background image download after initial metadata fetch.
    func fetchPreviewForMessage(url urlString: String) async -> LinkPreview? {
        guard let url = URL(string: urlString) else { return nil }

        // Check cache first — may already have a full preview with image
        if let cached = cache[urlString], cached.isPlaceholder != true {
            return cached
        }

        // Fetch metadata directly (no debounce)
        guard let preview = await fetchMetadata(for: url) else { return nil }
        cache[urlString] = preview

        // If no image yet, wait up to 2s for background image download to finish
        if preview.image == nil {
            for _ in 0..<8 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                if let enriched = cache[urlString], enriched.image != nil {
                    return enriched
                }
            }
        }

        // Return best available from cache
        return cache[urlString] ?? preview
    }

    // MARK: - Private

    func fetchMetadata(for url: URL) async -> LinkPreview? {
        // Fetch HTML description in parallel with LPMetadataProvider
        async let descriptionResult = fetchHTMLDescription(for: url)
        async let metadataResult = fetchLPMetadata(for: url)

        let description = await descriptionResult
        let metadata = await metadataResult

        guard let metadata = metadata else { return nil }

        let title = metadata.title
        let siteName = metadata.url?.host(percentEncoded: false)
            ?? url.host(percentEncoded: false)

        // Use HTML description, or fall back to nil
        let desc = description

        // Need at least a title to show a preview
        guard title != nil || desc != nil else { return nil }

        let urlString = url.absoluteString

        // Return text-only preview immediately (banner doesn't need image)
        let preview = LinkPreview(
            url: urlString,
            title: title,
            previewDescription: desc,
            image: nil,
            siteName: siteName,
            imageAspectRatio: nil
        )

        // Download image in background — updates cache silently for send flow
        if let imageProvider = metadata.imageProvider {
            Task { [weak self] in
                guard let result = await self?.downloadImage(from: imageProvider) else { return }
                await MainActor.run {
                    let enriched = LinkPreview(
                        url: urlString,
                        title: title,
                        previewDescription: desc,
                        image: result.fileName,
                        siteName: siteName,
                        imageAspectRatio: result.aspectRatio
                    )
                    self?.cache[urlString] = enriched
                }
            }
        }

        return preview
    }

    private func fetchLPMetadata(for url: URL) async -> LPLinkMetadata? {
        let provider = LPMetadataProvider()
        provider.timeout = 10
        do {
            return try await provider.startFetchingMetadata(for: url)
        } catch {
            return nil
        }
    }

    private func fetchHTMLDescription(for url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            return nil
        }

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }

        // Only parse first 50KB to keep it lightweight
        let maxBytes = 50_000
        let htmlData = data.prefix(maxBytes)
        guard let html = String(data: htmlData, encoding: .utf8)
                ?? String(data: htmlData, encoding: .ascii) else {
            return nil
        }

        return parseDescription(from: html)
    }

    private func parseDescription(from html: String) -> String? {
        // Try og:description first
        if let desc = extractMetaContent(from: html, property: "og:description") {
            return desc
        }
        // Fallback to meta name="description"
        if let desc = extractMetaContent(from: html, name: "description") {
            return desc
        }
        return nil
    }

    /// Extract content from <meta property="X" content="Y">
    private func extractMetaContent(from html: String, property: String) -> String? {
        // Match: <meta property="og:description" content="...">
        let pattern = #"<meta[^>]+property\s*=\s*["']"# + NSRegularExpression.escapedPattern(for: property) + #"["'][^>]+content\s*=\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let contentRange = Range(match.range(at: 1), in: html) else {
            // Try reversed attribute order: content before property
            return extractMetaContentReversed(from: html, attributeName: "property", attributeValue: property)
        }
        let result = String(html[contentRange])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : decodeHTMLEntities(result)
    }

    /// Extract content from <meta name="X" content="Y">
    private func extractMetaContent(from html: String, name: String) -> String? {
        let pattern = #"<meta[^>]+name\s*=\s*["']"# + NSRegularExpression.escapedPattern(for: name) + #"["'][^>]+content\s*=\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let contentRange = Range(match.range(at: 1), in: html) else {
            return extractMetaContentReversed(from: html, attributeName: "name", attributeValue: name)
        }
        let result = String(html[contentRange])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : decodeHTMLEntities(result)
    }

    /// Handle reversed attribute order: <meta content="Y" property="X">
    private func extractMetaContentReversed(from html: String, attributeName: String, attributeValue: String) -> String? {
        let pattern = #"<meta[^>]+content\s*=\s*["']([^"']+)["'][^>]+"# + NSRegularExpression.escapedPattern(for: attributeName) + #"\s*=\s*["']"# + NSRegularExpression.escapedPattern(for: attributeValue) + #"["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let contentRange = Range(match.range(at: 1), in: html) else {
            return nil
        }
        let result = String(html[contentRange])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : decodeHTMLEntities(result)
    }

    private func decodeHTMLEntities(_ string: String) -> String {
        var result = string
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
            ("&#x27;", "'"), ("&#x2F;", "/"), ("&nbsp;", " ")
        ]
        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        return result
    }

    private struct ImageDownloadResult {
        let fileName: String
        let aspectRatio: Double
    }

    private func downloadImage(from provider: NSItemProvider) async -> ImageDownloadResult? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: "public.image") { data, error in
                guard let data = data, !data.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }
                // Get image dimensions before saving
                guard let image = UIImage(data: data) else {
                    continuation.resume(returning: nil)
                    return
                }
                let aspectRatio = Double(image.size.width / image.size.height)
                guard let fileName = SharedPhotoStorage.savePhotoData(data) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: ImageDownloadResult(
                    fileName: fileName,
                    aspectRatio: aspectRatio
                ))
            }
        }
    }
}
