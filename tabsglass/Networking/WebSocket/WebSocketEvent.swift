//
//  WebSocketEvent.swift
//  tabsglass
//
//  WebSocket event types for real-time updates
//

import Foundation

/// Events received from the WebSocket connection
enum WebSocketEvent: Sendable {
    // Tab events
    case tabCreated(ServerTab)
    case tabUpdated(ServerTab)
    case tabDeleted(serverId: Int)

    // Message events
    case messageCreated(ServerMessage)
    case messageUpdated(ServerMessage)
    case messageDeleted(serverId: Int)
    case messageMoved(serverId: Int, newTabServerId: Int?)

    // Connection events
    case connected
    case disconnected(reason: String?)
    case error(String)

    // Sync events
    case syncRequired  // Server indicates client should perform full sync
}

/// Raw WebSocket message from server
struct WebSocketMessage: Decodable {
    let type: String
    let payload: WebSocketPayload?

    enum CodingKeys: String, CodingKey {
        case type
        case payload
    }
}

/// Payload container for different event types
enum WebSocketPayload: Decodable {
    case tab(TabResponse)
    case message(MessageResponse)
    case deletion(DeletionPayload)
    case move(MovePayload)
    case connected(ConnectedPayload)
    case empty

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Try to decode as different types
        if let connected = try? container.decode(ConnectedPayload.self) {
            self = .connected(connected)
        } else if let tab = try? container.decode(TabResponse.self) {
            self = .tab(tab)
        } else if let message = try? container.decode(MessageResponse.self) {
            self = .message(message)
        } else if let deletion = try? container.decode(DeletionPayload.self) {
            self = .deletion(deletion)
        } else if let move = try? container.decode(MovePayload.self) {
            self = .move(move)
        } else {
            self = .empty
        }
    }
}

struct ConnectedPayload: Decodable {
    let connectionId: String

    enum CodingKeys: String, CodingKey {
        case connectionId = "connection_id"
    }
}

struct DeletionPayload: Decodable {
    let serverId: Int

    enum CodingKeys: String, CodingKey {
        case serverId = "server_id"
    }
}

struct MovePayload: Decodable {
    let serverId: Int
    let newTabServerId: Int?

    enum CodingKeys: String, CodingKey {
        case serverId = "server_id"
        case newTabServerId = "new_tab_server_id"
    }
}
