//
//  MessageModels.swift
//  tabsglass
//
//  Message API request/response models
//

import Foundation

// MARK: - Requests

struct CreateMessageRequest: Codable {
    let content: String
    let tabLocalId: UUID?  // Tab reference by local_id (nil = Inbox)
    let localId: UUID
    let position: Int
    let entities: [TextEntityDTO]?
    let linkPreview: LinkPreviewDTO?
    let sourceUrl: String?
    let mediaGroupId: String?
    let todoItems: [TodoItemDTO]?
    let todoTitle: String?
    let reminderDate: Date?
    let reminderRepeatInterval: String?
    let media: [MediaItemRequest]  // Media items with metadata

    enum CodingKeys: String, CodingKey {
        case content
        case tabLocalId = "tab_local_id"
        case localId = "local_id"
        case position
        case entities
        case linkPreview = "link_preview"
        case sourceUrl = "source_url"
        case mediaGroupId = "media_group_id"
        case todoItems = "todo_items"
        case todoTitle = "todo_title"
        case reminderDate = "reminder_date"
        case reminderRepeatInterval = "reminder_repeat_interval"
        case media
    }
}

/// Media item for create/update requests
struct MediaItemRequest: Codable {
    let fileKey: String
    let mediaType: String  // "photo" or "video"
    let aspectRatio: Double
    let duration: Double?  // Only for videos
    let thumbnailFileKey: String?  // Only for videos

    enum CodingKeys: String, CodingKey {
        case fileKey = "file_key"
        case mediaType = "media_type"
        case aspectRatio = "aspect_ratio"
        case duration
        case thumbnailFileKey = "thumbnail_file_key"
    }
}

struct UpdateMessageRequest: Codable {
    let content: String?
    let entities: [TextEntityDTO]?
    let linkPreview: LinkPreviewDTO?
    let todoItems: [TodoItemDTO]?
    let todoTitle: String?
    let reminderDate: Date?
    let reminderRepeatInterval: String?
    let mediaFileKeys: [String]?

    enum CodingKeys: String, CodingKey {
        case content
        case entities
        case linkPreview = "link_preview"
        case todoItems = "todo_items"
        case todoTitle = "todo_title"
        case reminderDate = "reminder_date"
        case reminderRepeatInterval = "reminder_repeat_interval"
        case mediaFileKeys = "media_file_keys"
    }
}

struct MoveMessageRequest: Codable {
    let targetTabServerId: Int?

    enum CodingKeys: String, CodingKey {
        case targetTabServerId = "target_tab_server_id"
    }
}

// MARK: - Responses

struct MessageResponse: Decodable, Sendable {
    let id: Int
    let localId: UUID?
    let content: String
    let tabServerId: Int?
    let position: Int
    let entities: [TextEntityDTO]?
    let linkPreview: LinkPreviewDTO?
    let sourceUrl: String?
    let mediaGroupId: String?
    let media: [MediaItemResponse]?
    let todoItems: [TodoItemDTO]?
    let todoTitle: String?
    let reminderDate: Date?
    let reminderRepeatInterval: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case localId = "local_id"
        case content
        case tabServerId = "tab_server_id"
        case position
        case entities
        case linkPreview = "link_preview"
        case sourceUrl = "source_url"
        case mediaGroupId = "media_group_id"
        case media
        case todoItems = "todo_items"
        case todoTitle = "todo_title"
        case reminderDate = "reminder_date"
        case reminderRepeatInterval = "reminder_repeat_interval"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct MessagesResponse: Decodable {
    let messages: [MessageResponse]
}

// MARK: - DTOs for nested objects

struct TextEntityDTO: Codable, Sendable {
    let type: String
    let offset: Int
    let length: Int
    let url: String?

    init(type: String, offset: Int, length: Int, url: String? = nil) {
        self.type = type
        self.offset = offset
        self.length = length
        self.url = url
    }

    init(from entity: TextEntity) {
        self.type = entity.type
        self.offset = entity.offset
        self.length = entity.length
        self.url = entity.url
    }

    func toTextEntity() -> TextEntity {
        TextEntity(type: type, offset: offset, length: length, url: url)
    }
}

struct LinkPreviewDTO: Codable, Sendable {
    let url: String
    let title: String?
    let description: String?
    let image: String?
    let siteName: String?

    enum CodingKeys: String, CodingKey {
        case url, title, description, image
        case siteName = "site_name"
    }

    init(url: String, title: String? = nil, description: String? = nil, image: String? = nil, siteName: String? = nil) {
        self.url = url
        self.title = title
        self.description = description
        self.image = image
        self.siteName = siteName
    }

    init(from preview: LinkPreview) {
        self.url = preview.url
        self.title = preview.title
        self.description = preview.previewDescription
        self.image = preview.image
        self.siteName = preview.siteName
    }

    func toLinkPreview() -> LinkPreview {
        LinkPreview(
            url: url,
            title: title,
            previewDescription: description,
            image: image,
            siteName: siteName
        )
    }
}

struct TodoItemDTO: Codable, Sendable {
    let id: UUID
    let text: String
    let isCompleted: Bool

    enum CodingKeys: String, CodingKey {
        case id, text
        case isCompleted = "is_completed"
    }

    init(id: UUID, text: String, isCompleted: Bool) {
        self.id = id
        self.text = text
        self.isCompleted = isCompleted
    }

    init(from item: TodoItem) {
        self.id = item.id
        self.text = item.text
        self.isCompleted = item.isCompleted
    }

    func toTodoItem() -> TodoItem {
        TodoItem(id: id, text: text, isCompleted: isCompleted)
    }
}

struct MediaItemResponse: Decodable, Sendable {
    let fileKey: String
    let downloadUrl: String
    let mediaType: String  // "photo", "video"
    let aspectRatio: Double
    let duration: Double?
    let thumbnailFileKey: String?
    let thumbnailDownloadUrl: String?

    enum CodingKeys: String, CodingKey {
        case fileKey = "file_key"
        case downloadUrl = "download_url"
        case mediaType = "media_type"
        case aspectRatio = "aspect_ratio"
        case duration
        case thumbnailFileKey = "thumbnail_file_key"
        case thumbnailDownloadUrl = "thumbnail_download_url"
    }
}

/// Server message data for sync operations
struct ServerMessage: Sendable {
    let serverId: Int
    let localId: UUID?
    let content: String
    let tabServerId: Int?
    let position: Int
    let entities: [TextEntity]?
    let linkPreview: LinkPreview?
    let sourceUrl: String?
    let mediaGroupId: String?
    let media: [MediaItemResponse]?
    let todoItems: [TodoItem]?
    let todoTitle: String?
    let reminderDate: Date?
    let reminderRepeatInterval: ReminderRepeatInterval?
    let createdAt: Date
    let updatedAt: Date

    init(fromResponse response: MessageResponse) {
        self.serverId = response.id
        self.localId = response.localId
        self.content = response.content
        self.tabServerId = response.tabServerId
        self.position = response.position
        self.entities = response.entities?.map { $0.toTextEntity() }
        self.linkPreview = response.linkPreview?.toLinkPreview()
        self.sourceUrl = response.sourceUrl
        self.mediaGroupId = response.mediaGroupId
        self.media = response.media
        self.todoItems = response.todoItems?.map { $0.toTodoItem() }
        self.todoTitle = response.todoTitle
        self.reminderDate = response.reminderDate
        self.reminderRepeatInterval = response.reminderRepeatInterval.flatMap { ReminderRepeatInterval(rawValue: $0) }
        self.createdAt = response.createdAt
        self.updatedAt = response.updatedAt
    }
}
