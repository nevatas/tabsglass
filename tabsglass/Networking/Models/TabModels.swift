//
//  TabModels.swift
//  tabsglass
//
//  Tab API request/response models
//

import Foundation

// MARK: - Requests

struct CreateTabRequest: Codable {
    let title: String
    let position: Int
    let localId: UUID

    enum CodingKeys: String, CodingKey {
        case title
        case position
        case localId = "local_id"
    }
}

struct UpdateTabRequest: Codable {
    let title: String?
    let position: Int?
}

// MARK: - Responses

struct TabResponse: Decodable, Sendable {
    let id: Int
    let localId: UUID?
    let title: String
    let position: Int
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case localId = "local_id"
        case title
        case position
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct TabsResponse: Decodable {
    let tabs: [TabResponse]
}

/// Server tab data for sync operations
struct ServerTab: Sendable {
    let serverId: Int
    let localId: UUID?
    let title: String
    let position: Int
    let createdAt: Date
    let updatedAt: Date

    init(fromResponse response: TabResponse) {
        self.serverId = response.id
        self.localId = response.localId
        self.title = response.title
        self.position = response.position
        self.createdAt = response.createdAt
        self.updatedAt = response.updatedAt
    }
}
