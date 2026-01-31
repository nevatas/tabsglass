//
//  WebSocketService.swift
//  tabsglass
//
//  WebSocket service for real-time updates from the backend
//

import Foundation
import os.log

/// Service for managing WebSocket connections for real-time sync
actor WebSocketService {
    static let shared = WebSocketService()

    // MARK: - Configuration

    private let baseURL: URL
    private let logger = Logger(subsystem: "tabsglass", category: "WebSocketService")

    // MARK: - State

    private var webSocketTask: URLSessionWebSocketTask?
    private var isConnected = false
    private var shouldReconnect = true
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 10

    /// Stream for broadcasting events to subscribers
    private var eventContinuations: [UUID: AsyncStream<WebSocketEvent>.Continuation] = [:]

    private init(baseURL: URL = SharedConstants.webSocketURL) {
        self.baseURL = baseURL
    }

    // MARK: - Public API

    /// Connect to WebSocket server
    func connect() async throws {
        guard !isConnected else {
            logger.debug("Already connected")
            return
        }

        guard let token = try? KeychainService.shared.load(.accessToken) else {
            logger.warning("No access token, cannot connect to WebSocket")
            return
        }

        shouldReconnect = true
        reconnectAttempts = 0

        // Build WebSocket URL with token as query parameter
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/ws"
        components.queryItems = [URLQueryItem(name: "token", value: token)]

        guard let url = components.url else {
            logger.error("Failed to build WebSocket URL")
            return
        }

        var request = URLRequest(url: url)

        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()

        isConnected = true
        broadcastEvent(.connected)
        logger.info("WebSocket connected")

        // Start receiving messages
        await receiveMessages()
    }

    /// Disconnect from WebSocket server
    func disconnect() {
        shouldReconnect = false
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        broadcastEvent(.disconnected(reason: nil))
        logger.info("WebSocket disconnected")
    }

    /// Subscribe to WebSocket events
    func events() -> AsyncStream<WebSocketEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            eventContinuations[id] = continuation

            continuation.onTermination = { @Sendable [weak self] _ in
                Task { await self?.removeSubscription(id: id) }
            }
        }
    }

    // MARK: - Private Implementation

    private func removeSubscription(id: UUID) {
        eventContinuations.removeValue(forKey: id)
    }

    private func receiveMessages() async {
        guard let task = webSocketTask else { return }

        do {
            while isConnected {
                let message = try await task.receive()

                switch message {
                case .string(let text):
                    await handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        await handleMessage(text)
                    }
                @unknown default:
                    break
                }
            }
        } catch {
            logger.error("WebSocket receive error: \(error.localizedDescription)")
            isConnected = false
            broadcastEvent(.disconnected(reason: error.localizedDescription))

            // Attempt reconnection
            if shouldReconnect {
                await attemptReconnect()
            }
        }
    }

    private func handleMessage(_ text: String) async {
        guard let data = text.data(using: .utf8) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let wsMessage = try decoder.decode(WebSocketMessage.self, from: data)
            let event = try parseEvent(from: wsMessage)
            broadcastEvent(event)
        } catch {
            logger.error("Failed to parse WebSocket message: \(error.localizedDescription)")
        }
    }

    private func parseEvent(from message: WebSocketMessage) throws -> WebSocketEvent {
        switch message.type {
        case "tab_created":
            guard case .tab(let tab) = message.payload else {
                throw WebSocketError.invalidPayload
            }
            return .tabCreated(ServerTab(fromResponse: tab))

        case "tab_updated":
            guard case .tab(let tab) = message.payload else {
                throw WebSocketError.invalidPayload
            }
            return .tabUpdated(ServerTab(fromResponse: tab))

        case "tab_deleted":
            guard case .deletion(let deletion) = message.payload else {
                throw WebSocketError.invalidPayload
            }
            return .tabDeleted(serverId: deletion.serverId)

        case "message_created":
            guard case .message(let msg) = message.payload else {
                throw WebSocketError.invalidPayload
            }
            return .messageCreated(ServerMessage(fromResponse: msg))

        case "message_updated":
            guard case .message(let msg) = message.payload else {
                throw WebSocketError.invalidPayload
            }
            return .messageUpdated(ServerMessage(fromResponse: msg))

        case "message_deleted":
            guard case .deletion(let deletion) = message.payload else {
                throw WebSocketError.invalidPayload
            }
            return .messageDeleted(serverId: deletion.serverId)

        case "message_moved":
            guard case .move(let move) = message.payload else {
                throw WebSocketError.invalidPayload
            }
            return .messageMoved(serverId: move.serverId, newTabServerId: move.newTabServerId)

        case "sync_required":
            return .syncRequired

        default:
            logger.warning("Unknown WebSocket event type: \(message.type)")
            throw WebSocketError.unknownEventType(message.type)
        }
    }

    private func broadcastEvent(_ event: WebSocketEvent) {
        for continuation in eventContinuations.values {
            continuation.yield(event)
        }
    }

    private func attemptReconnect() async {
        guard shouldReconnect, reconnectAttempts < maxReconnectAttempts else {
            logger.warning("Max reconnect attempts reached")
            return
        }

        reconnectAttempts += 1
        let delay = min(30.0, pow(2.0, Double(reconnectAttempts)))  // Exponential backoff

        let currentAttempt = reconnectAttempts
        logger.info("Attempting reconnect in \(delay) seconds (attempt \(currentAttempt))")

        try? await Task.sleep(for: .seconds(delay))

        guard shouldReconnect else { return }

        do {
            try await connect()
        } catch {
            logger.error("Reconnect failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Sending Messages

    /// Send a ping to keep connection alive
    func sendPing() async {
        guard let task = webSocketTask, isConnected else { return }

        task.sendPing { [weak self] error in
            if let error = error {
                Task { await self?.handlePingError(error) }
            }
        }
    }

    private func handlePingError(_ error: Error) {
        logger.warning("Ping failed: \(error.localizedDescription)")
    }
}

// MARK: - Errors

enum WebSocketError: LocalizedError {
    case invalidPayload
    case unknownEventType(String)
    case connectionFailed

    var errorDescription: String? {
        switch self {
        case .invalidPayload:
            return "Invalid WebSocket payload"
        case .unknownEventType(let type):
            return "Unknown event type: \(type)"
        case .connectionFailed:
            return "WebSocket connection failed"
        }
    }
}
