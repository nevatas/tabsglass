//
//  SyncModels.swift
//  tabsglass
//
//  Sync API request/response models
//

import Foundation

// MARK: - Initial Sync Request

struct InitialSyncRequest: Encodable {
    let tabs: [InitialSyncTab]
    let messages: [InitialSyncMessage]
}

struct InitialSyncTab: Encodable {
    let localId: UUID
    let title: String
    let position: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case localId = "local_id"
        case title
        case position
        case createdAt = "created_at"
    }

    @MainActor
    init(from tab: Tab) {
        self.localId = tab.id
        self.title = tab.title
        self.position = tab.position
        self.createdAt = tab.createdAt
    }
}

struct InitialSyncMessage: Encodable {
    let localId: UUID
    let tabLocalId: UUID?
    let content: String
    let position: Int
    let entities: [TextEntityDTO]?
    let linkPreview: LinkPreviewDTO?
    let sourceUrl: String?
    let mediaGroupId: String?
    let todoItems: [TodoItemDTO]?
    let todoTitle: String?
    let reminderDate: Date?
    let reminderRepeatInterval: String?
    let createdAt: Date
    // Media file names - server will provide upload URLs
    let photoFileNames: [String]
    let photoAspectRatios: [Double]
    let videoFileNames: [String]
    let videoAspectRatios: [Double]
    let videoDurations: [Double]
    let videoThumbnailFileNames: [String]

    enum CodingKeys: String, CodingKey {
        case localId = "local_id"
        case tabLocalId = "tab_local_id"
        case content
        case position
        case entities
        case linkPreview = "link_preview"
        case sourceUrl = "source_url"
        case mediaGroupId = "media_group_id"
        case todoItems = "todo_items"
        case todoTitle = "todo_title"
        case reminderDate = "reminder_date"
        case reminderRepeatInterval = "reminder_repeat_interval"
        case createdAt = "created_at"
        case photoFileNames = "photo_file_names"
        case photoAspectRatios = "photo_aspect_ratios"
        case videoFileNames = "video_file_names"
        case videoAspectRatios = "video_aspect_ratios"
        case videoDurations = "video_durations"
        case videoThumbnailFileNames = "video_thumbnail_file_names"
    }

    @MainActor
    init(from message: Message) {
        self.localId = message.id
        self.tabLocalId = message.tabId
        self.content = message.content
        self.position = message.position
        self.entities = message.entities?.map { TextEntityDTO(from: $0) }
        self.linkPreview = message.linkPreview.map { LinkPreviewDTO(from: $0) }
        self.sourceUrl = message.sourceUrl
        self.mediaGroupId = message.mediaGroupId
        self.todoItems = message.todoItems?.map { TodoItemDTO(from: $0) }
        self.todoTitle = message.todoTitle
        self.reminderDate = message.reminderDate
        self.reminderRepeatInterval = message.reminderRepeatInterval?.rawValue
        self.createdAt = message.createdAt
        self.photoFileNames = message.photoFileNames
        self.photoAspectRatios = message.photoAspectRatios
        self.videoFileNames = message.videoFileNames
        self.videoAspectRatios = message.videoAspectRatios
        self.videoDurations = message.videoDurations
        self.videoThumbnailFileNames = message.videoThumbnailFileNames
    }
}

// MARK: - Initial Sync Response

struct InitialSyncResponse: Decodable {
    let tabs: [InitialSyncTabResult]
    let messages: [InitialSyncMessageResult]
    let serverTime: Date

    enum CodingKeys: String, CodingKey {
        case tabs
        case messages
        case serverTime = "server_time"
    }
}

struct InitialSyncTabResult: Decodable {
    let localId: UUID
    let serverId: Int

    enum CodingKeys: String, CodingKey {
        case localId = "local_id"
        case serverId = "server_id"
    }
}

struct InitialSyncMessageResult: Decodable {
    let localId: UUID
    let serverId: Int
    let mediaUploadUrls: [MediaUploadInfo]?

    enum CodingKeys: String, CodingKey {
        case localId = "local_id"
        case serverId = "server_id"
        case mediaUploadUrls = "media_upload_urls"
    }
}

struct MediaUploadInfo: Decodable {
    let localFileName: String
    let uploadUrl: String
    let fileKey: String
    let mediaType: String  // "photo", "video", "thumbnail"

    enum CodingKeys: String, CodingKey {
        case localFileName = "local_file_name"
        case uploadUrl = "upload_url"
        case fileKey = "file_key"
        case mediaType = "media_type"
    }
}

// MARK: - Incremental Sync Response

struct IncrementalSyncResponse: Decodable {
    let tabs: SyncChanges<TabResponse>
    let messages: SyncChanges<MessageResponse>
    let serverTime: Date

    enum CodingKeys: String, CodingKey {
        case tabs
        case messages
        case serverTime = "server_time"
    }
}

struct SyncChanges<T: Decodable>: Decodable {
    let created: [T]
    let updated: [T]
    let deleted: [Int]  // Server IDs
}
