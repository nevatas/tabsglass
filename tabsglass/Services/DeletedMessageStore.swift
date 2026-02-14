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
    let videoFileNames: [String]
    let videoAspectRatios: [Double]
    let videoDurations: [Double]
    let videoThumbnailFileNames: [String]
    let tabId: UUID?  // nil = Inbox
    let createdAt: Date
    let deletedAt: Date
    let position: Int
    let sourceUrl: String?
    let linkPreview: LinkPreview?
    let mediaGroupId: String?
    let todoItems: [TodoItem]?
    let todoTitle: String?
    let contentBlocks: [ContentBlock]?
    let mediaOrder: [String]?
    let reminderDate: Date?
    let reminderRepeatInterval: ReminderRepeatInterval?

    init(message: Message) {
        self.content = message.content
        self.entities = message.entities
        self.photoFileNames = message.photoFileNames
        self.photoAspectRatios = message.photoAspectRatios
        self.videoFileNames = message.videoFileNames
        self.videoAspectRatios = message.videoAspectRatios
        self.videoDurations = message.videoDurations
        self.videoThumbnailFileNames = message.videoThumbnailFileNames
        self.tabId = message.tabId
        self.createdAt = message.createdAt
        self.deletedAt = Date()
        self.position = message.position
        self.sourceUrl = message.sourceUrl
        self.linkPreview = message.linkPreview
        self.mediaGroupId = message.mediaGroupId
        self.todoItems = message.todoItems
        self.todoTitle = message.todoTitle
        self.contentBlocks = message.contentBlocks
        self.mediaOrder = message.mediaOrder
        self.reminderDate = message.reminderDate
        self.reminderRepeatInterval = message.reminderRepeatInterval
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
        lastDeleted = DeletedMessageSnapshot(message: message)
    }

    /// Check if undo is available for a specific tab
    func canUndo(forTabId tabId: UUID?) -> Bool {
        guard let deleted = lastDeleted else { return false }

        // Must be same tab (nil == nil for Inbox)
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
