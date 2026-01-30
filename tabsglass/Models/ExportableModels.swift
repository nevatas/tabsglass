//
//  ExportableModels.swift
//  tabsglass
//
//  Codable DTOs for export/import serialization
//

import Foundation
import UIKit

// MARK: - Export Manifest

/// Metadata about the exported archive
struct ExportManifest: Codable, Sendable {
    let version: Int
    let exportDate: Date
    let appVersion: String
    let deviceName: String
    let tabCount: Int
    let messageCount: Int
    let photoCount: Int
    let videoCount: Int

    static nonisolated let currentVersion = 1

    @MainActor
    init(tabCount: Int, messageCount: Int, photoCount: Int, videoCount: Int) {
        self.version = Self.currentVersion
        self.exportDate = Date()
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        self.deviceName = UIDevice.current.name
        self.tabCount = tabCount
        self.messageCount = messageCount
        self.photoCount = photoCount
        self.videoCount = videoCount
    }
}

// MARK: - Export Data Container

/// Container for all exported data
struct ExportData: Codable, Sendable {
    let tabs: [ExportableTab]
    let messages: [ExportableMessage]
}

// MARK: - Exportable Tab

/// Codable representation of Tab (without SwiftData)
struct ExportableTab: Codable, Sendable {
    let id: UUID
    let serverId: Int?
    let title: String
    let createdAt: Date
    let position: Int

    @MainActor
    init(from tab: Tab) {
        self.id = tab.id
        self.serverId = tab.serverId
        self.title = tab.title
        self.createdAt = tab.createdAt
        self.position = tab.position
    }
}

// MARK: - Exportable Message

/// Codable representation of Message (without SwiftData)
struct ExportableMessage: Codable, Sendable {
    let id: UUID
    let serverId: Int?
    let content: String
    let entities: [TextEntity]?
    let createdAt: Date
    let tabId: UUID?
    let position: Int
    let sourceUrl: String?
    let linkPreview: LinkPreview?
    let mediaGroupId: String?
    let photoFileNames: [String]
    let photoAspectRatios: [Double]
    let videoFileNames: [String]
    let videoAspectRatios: [Double]
    let videoDurations: [Double]
    let videoThumbnailFileNames: [String]
    let todoItems: [TodoItem]?
    let todoTitle: String?
    let reminderDate: Date?
    let reminderRepeatInterval: ReminderRepeatInterval?
    // Note: notificationId is NOT exported - will be regenerated on import

    @MainActor
    init(from message: Message) {
        self.id = message.id
        self.serverId = message.serverId
        self.content = message.content
        self.entities = message.entities
        self.createdAt = message.createdAt
        self.tabId = message.tabId
        self.position = message.position
        self.sourceUrl = message.sourceUrl
        self.linkPreview = message.linkPreview
        self.mediaGroupId = message.mediaGroupId
        self.photoFileNames = message.photoFileNames
        self.photoAspectRatios = message.photoAspectRatios
        self.videoFileNames = message.videoFileNames
        self.videoAspectRatios = message.videoAspectRatios
        self.videoDurations = message.videoDurations
        self.videoThumbnailFileNames = message.videoThumbnailFileNames
        self.todoItems = message.todoItems
        self.todoTitle = message.todoTitle
        self.reminderDate = message.reminderDate
        self.reminderRepeatInterval = message.reminderRepeatInterval
    }

    /// Convert back to Message model (for import)
    @MainActor
    func toMessage() -> Message {
        let message = Message(
            content: content,
            tabId: tabId,
            entities: entities,
            photoFileNames: photoFileNames,
            photoAspectRatios: photoAspectRatios,
            videoFileNames: videoFileNames,
            videoAspectRatios: videoAspectRatios,
            videoDurations: videoDurations,
            videoThumbnailFileNames: videoThumbnailFileNames,
            position: position,
            sourceUrl: sourceUrl,
            linkPreview: linkPreview,
            mediaGroupId: mediaGroupId
        )
        // Override auto-generated values
        message.id = id
        message.serverId = serverId
        message.createdAt = createdAt
        message.todoItems = todoItems
        message.todoTitle = todoTitle
        message.reminderDate = reminderDate
        message.reminderRepeatInterval = reminderRepeatInterval
        // notificationId will be set when scheduling reminder
        return message
    }
}

// MARK: - Import Mode

/// How to handle existing data during import
enum ImportMode: Sendable {
    case replace  // Delete all existing data first
    case merge    // Skip existing IDs, add new ones
}

// MARK: - Export/Import Progress

/// Progress tracking for export/import operations
struct ExportImportProgress: Sendable {
    enum Phase: Sendable {
        case preparing
        case exportingData
        case copyingPhotos
        case copyingVideos
        case compressing
        case extracting
        case importingData
        case copyingMedia
        case schedulingReminders
        case complete
    }

    var phase: Phase
    var current: Int
    var total: Int

    var fractionCompleted: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }

    var localizedPhase: String {
        switch phase {
        case .preparing: return L10n.Data.phasePrepairing
        case .exportingData: return L10n.Data.phaseExportingData
        case .copyingPhotos: return L10n.Data.phaseCopyingPhotos
        case .copyingVideos: return L10n.Data.phaseCopyingVideos
        case .compressing: return L10n.Data.phaseCompressing
        case .extracting: return L10n.Data.phaseExtracting
        case .importingData: return L10n.Data.phaseImportingData
        case .copyingMedia: return L10n.Data.phaseCopyingMedia
        case .schedulingReminders: return L10n.Data.phaseSchedulingReminders
        case .complete: return L10n.Data.phaseComplete
        }
    }
}
