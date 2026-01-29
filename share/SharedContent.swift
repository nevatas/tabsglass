//
//  SharedContent.swift
//  share
//
//  Model for content shared from other apps
//

import Foundation

/// Content extracted from share extension input
struct SharedContent {
    var text: String = ""
    var urls: [URL] = []
    var imageCount: Int = 0  // Just count, don't store image data
    var videoCount: Int = 0  // Just count, don't store video data

    /// Total media count (images + videos)
    var totalMediaCount: Int {
        imageCount + videoCount
    }

    /// Whether there's any content to save
    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        urls.isEmpty &&
        totalMediaCount == 0
    }
}
