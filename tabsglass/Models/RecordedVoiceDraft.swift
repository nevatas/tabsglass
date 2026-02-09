//
//  RecordedVoiceDraft.swift
//  tabsglass
//

import Foundation

/// Temporary voice recording created in composer before sending.
struct RecordedVoiceDraft: Equatable {
    let fileURL: URL
    let duration: Double
}
