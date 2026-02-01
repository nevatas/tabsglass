//
//  WebSocketEventQueue.swift
//  tabsglass
//
//  Queues WebSocket message events when the parent tab doesn't exist locally yet.
//  Retries processing when tabs are created or after a delay.
//

import Foundation
import SwiftData
import os.log

/// Queue for handling WebSocket message events when tab may not exist yet
actor WebSocketEventQueue {
    static let shared = WebSocketEventQueue()

    private let logger = Logger(subsystem: "tabsglass", category: "WebSocketEventQueue")

    private struct PendingMessage {
        let payload: ServerMessage
        var retries: Int
    }

    private var pendingMessages: [PendingMessage] = []
    private var isProcessing = false
    private var modelContainer: ModelContainer?

    private init() {}

    /// Set the model container for database operations
    func setModelContainer(_ container: ModelContainer) {
        self.modelContainer = container
    }

    /// Enqueue a message that couldn't be processed because its tab doesn't exist
    func enqueue(_ payload: ServerMessage) {
        logger.info("📥 Enqueueing message serverId=\(payload.serverId) for tab serverId=\(payload.tabServerId ?? -1)")
        pendingMessages.append(PendingMessage(payload: payload, retries: 0))
        Task { await processQueue() }
    }

    /// Called when a new tab is created - triggers queue processing
    func onTabCreated(_ tabServerId: Int) {
        logger.info("📁 Tab created notification: serverId=\(tabServerId)")
        Task { await processQueue() }
    }

    /// Process the pending message queue
    private func processQueue() async {
        guard !isProcessing else { return }
        guard let container = modelContainer else {
            logger.warning("⚠️ ModelContainer not set, cannot process queue")
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        var stillPending: [PendingMessage] = []

        for var item in pendingMessages {
            if await tryProcess(item.payload, container: container) {
                logger.info("✅ Successfully processed queued message serverId=\(item.payload.serverId)")
                continue // Success, don't add back to queue
            }

            // Failed to process
            item.retries += 1
            if item.retries < 10 {
                logger.info("⏳ Message serverId=\(item.payload.serverId) retry \(item.retries)/10")
                stillPending.append(item)
            } else {
                logger.warning("❌ Dropping message serverId=\(item.payload.serverId) after 10 retries")
            }
        }

        pendingMessages = stillPending

        // Schedule retry if there are still pending messages
        if !self.pendingMessages.isEmpty {
            logger.info("⏰ Scheduling retry for \(self.pendingMessages.count) pending messages in 3 seconds")
            try? await Task.sleep(for: .seconds(3))
            await processQueue()
        }
    }

    /// Try to process a message, returns true if successful
    @MainActor
    private func tryProcess(_ payload: ServerMessage, container: ModelContainer) async -> Bool {
        let context = container.mainContext

        // Check if message already exists by serverId
        let serverId = payload.serverId
        let descriptor = FetchDescriptor<Message>(predicate: #Predicate { $0.serverId == serverId })
        if let existing = try? context.fetch(descriptor), !existing.isEmpty {
            logger.info("⏭️ Message already exists by serverId, skipping")
            return true // Consider it processed
        }

        // Also check by localId
        if let localId = payload.localId {
            let localDescriptor = FetchDescriptor<Message>(predicate: #Predicate { $0.id == localId })
            if let existing = try? context.fetch(localDescriptor), let msg = existing.first {
                logger.info("🔗 Linking existing local message to serverId=\(serverId)")
                msg.serverId = serverId
                try? context.save()
                return true
            }
        }

        // Try to find tab by serverId
        var tabId: UUID? = nil
        if let tabServerId = payload.tabServerId {
            let tabDescriptor = FetchDescriptor<Tab>(predicate: #Predicate { $0.serverId == tabServerId })
            if let tabs = try? context.fetch(tabDescriptor), let tab = tabs.first {
                tabId = tab.id
                logger.info("✅ Found tab: serverId=\(tabServerId) -> localId=\(tab.id)")
            } else {
                logger.info("❌ Tab not found for serverId=\(tabServerId)")
                return false // Tab not found, need to retry
            }
        }

        // Create new message
        logger.info("➕ Creating new message: serverId=\(serverId), tabId=\(String(describing: tabId))")
        let message = Message(
            content: payload.content,
            tabId: tabId,
            entities: payload.entities,
            position: payload.position,
            sourceUrl: payload.sourceUrl,
            linkPreview: payload.linkPreview
        )
        message.serverId = payload.serverId
        message.createdAt = payload.createdAt
        message.todoItems = payload.todoItems
        message.todoTitle = payload.todoTitle
        message.reminderDate = payload.reminderDate
        message.reminderRepeatInterval = payload.reminderRepeatInterval

        context.insert(message)
        do {
            try context.save()
            logger.info("✅ Queued message saved successfully")
        } catch {
            logger.error("❌ Failed to save queued message: \(error)")
            return false
        }

        // Download media if present
        if let media = payload.media, !media.isEmpty {
            await MediaSyncService.shared.downloadMedia(for: message, media: media)
        }

        return true
    }
}
