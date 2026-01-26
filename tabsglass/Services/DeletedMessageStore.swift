//
//  DeletedMessageStore.swift
//  tabsglass
//
//  Stores recently deleted message for shake-to-undo
//

import Foundation

/// Snapshot of a deleted message for restoration
struct DeletedMessageSnapshot {
    let content: String
    let entities: [TextEntity]?
    let photoFileNames: [String]
    let photoAspectRatios: [Double]
    let tabId: UUID
    let createdAt: Date
    let deletedAt: Date

    init(message: Message, tabId: UUID) {
        self.content = message.content
        self.entities = message.entities
        self.photoFileNames = message.photoFileNames
        self.photoAspectRatios = message.photoAspectRatios
        self.tabId = tabId
        self.createdAt = message.createdAt
        self.deletedAt = Date()
    }
}

final class DeletedMessageStore {
    static let shared = DeletedMessageStore()

    private(set) var lastDeleted: DeletedMessageSnapshot?

    /// Time window for undo (30 seconds)
    private let undoWindow: TimeInterval = 30

    private init() {}

    /// Store a message before deletion
    func store(_ message: Message) {
        guard let tabId = message.tab?.id else { return }
        lastDeleted = DeletedMessageSnapshot(message: message, tabId: tabId)
    }

    /// Check if undo is available for a specific tab
    func canUndo(in tabId: UUID) -> Bool {
        guard let deleted = lastDeleted else { return false }

        // Must be same tab
        guard deleted.tabId == tabId else { return false }

        // Must be within time window
        let elapsed = Date().timeIntervalSince(deleted.deletedAt)
        return elapsed < undoWindow
    }

    /// Get the snapshot and clear it
    func popSnapshot() -> DeletedMessageSnapshot? {
        let snapshot = lastDeleted
        lastDeleted = nil
        return snapshot
    }

    /// Clear without returning
    func clear() {
        lastDeleted = nil
    }
}
