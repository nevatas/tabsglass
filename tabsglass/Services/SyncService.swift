//
//  SyncService.swift
//  tabsglass
//
//  Synchronization service for offline-first data sync with backend
//

import Foundation
import SwiftData
import os.log

/// Main synchronization service
/// Handles initial sync, incremental sync, and offline queue processing
actor SyncService {
    static let shared = SyncService()

    // MARK: - State

    private let apiClient = APIClient.shared
    private let pendingStore = PendingOperationsStore.shared
    private let logger = Logger(subsystem: "tabsglass", category: "SyncService")

    /// Last successful sync date
    private var lastSyncDate: Date? {
        get { UserDefaults.standard.object(forKey: "lastSyncDate") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastSyncDate") }
    }

    /// Whether sync is currently in progress
    private var isSyncing = false

    private init() {}

    /// Check and set syncing state atomically
    private func beginSync() -> Bool {
        if isSyncing { return false }
        isSyncing = true
        return true
    }

    private func endSync() {
        isSyncing = false
    }

    private func setLastSyncDate(_ date: Date) {
        lastSyncDate = date
    }

    private func getLastSyncDate() -> Date? {
        lastSyncDate
    }

    // MARK: - Initial Sync

    /// Perform initial sync if user hasn't completed it yet
    @MainActor
    func performInitialSyncIfNeeded(modelContext: ModelContext) async {
        guard AuthService.shared.isAuthenticated,
              let user = AuthService.shared.currentUser,
              !user.hasCompletedInitialSync else {
            return
        }

        await performInitialSync(modelContext: modelContext)
    }

    /// Fetch all data from server (called after login)
    @MainActor
    func fetchDataFromServer(modelContext: ModelContext) async {
        guard AuthService.shared.isAuthenticated else { return }

        logger.info("Fetching data from server after login")

        do {
            // Fetch tabs from server
            let tabsResponse: TabsResponse = try await apiClient.request(.getTabs)
            logger.info("Fetched \(tabsResponse.tabs.count) tabs from server")

            for tabResponse in tabsResponse.tabs {
                // Check if tab already exists locally
                let serverId = tabResponse.id
                let descriptor = FetchDescriptor<Tab>(predicate: #Predicate { $0.serverId == serverId })

                if let existingTabs = try? modelContext.fetch(descriptor), !existingTabs.isEmpty {
                    // Update existing
                    if let existingTab = existingTabs.first {
                        existingTab.title = tabResponse.title
                        existingTab.position = tabResponse.position
                    }
                } else {
                    // Create new local tab
                    let newTab = Tab(title: tabResponse.title, position: tabResponse.position)
                    newTab.serverId = tabResponse.id
                    if let localId = tabResponse.localId {
                        newTab.id = localId
                    }
                    modelContext.insert(newTab)
                }
            }

            // Fetch messages from server
            let messagesResponse: MessagesResponse = try await apiClient.request(.getMessages(tabServerId: nil, since: nil))
            logger.info("Fetched \(messagesResponse.messages.count) messages from server")

            for msgResponse in messagesResponse.messages {
                // Log media info for debugging
                if let media = msgResponse.media, !media.isEmpty {
                    logger.info("Message \(msgResponse.id) has \(media.count) media items:")
                    for item in media {
                        logger.info("  - type: \(item.mediaType), key: \(item.fileKey)")
                        if item.mediaType == "video" {
                            logger.info("    thumbnailKey: \(item.thumbnailFileKey ?? "nil"), thumbnailUrl: \(item.thumbnailDownloadUrl != nil ? "present" : "nil")")
                        }
                    }
                } else {
                    logger.info("Message \(msgResponse.id) has no media")
                }

                // Check if message already exists locally
                let serverId = msgResponse.id
                let descriptor = FetchDescriptor<Message>(predicate: #Predicate { $0.serverId == serverId })

                if let existingMessages = try? modelContext.fetch(descriptor), !existingMessages.isEmpty {
                    // Update existing
                    if let existingMessage = existingMessages.first {
                        updateMessage(existingMessage, from: msgResponse)

                        // Download media if present and not already downloaded
                        if let media = msgResponse.media, !media.isEmpty,
                           existingMessage.photoFileNames.isEmpty && existingMessage.videoFileNames.isEmpty {
                            await MediaSyncService.shared.downloadMedia(for: existingMessage, media: media)
                        }
                    }
                } else {
                    // Create new local message
                    let newMessage = createMessage(from: msgResponse, modelContext: modelContext)
                    modelContext.insert(newMessage)

                    // Download media if present
                    if let media = msgResponse.media, !media.isEmpty {
                        await MediaSyncService.shared.downloadMedia(for: newMessage, media: media)
                    }
                }
            }

            try modelContext.save()
            logger.info("Data fetch completed successfully")
        } catch let error as APIError {
            if case .httpError(let statusCode, _) = error, statusCode == 404 {
                logger.warning("Data endpoints not available (404)")
            } else {
                logger.error("Failed to fetch data: \(error.localizedDescription)")
            }
        } catch {
            logger.error("Failed to fetch data: \(error.localizedDescription)")
        }
    }

    /// Upload all local data to server (first-time sync)
    @MainActor
    func performInitialSync(modelContext: ModelContext) async {
        guard await beginSync() else {
            logger.warning("Initial sync already in progress")
            return
        }
        defer { Task { await endSync() } }

        logger.info("Starting initial sync")

        do {
            // Fetch all local data
            var tabDescriptor = FetchDescriptor<Tab>()
            tabDescriptor.sortBy = [SortDescriptor(\Tab.position)]
            let tabs = try modelContext.fetch(tabDescriptor)

            var messageDescriptor = FetchDescriptor<Message>()
            messageDescriptor.sortBy = [SortDescriptor(\Message.createdAt)]
            let messages = try modelContext.fetch(messageDescriptor)

            // Build sync request
            let syncTabs = tabs.map { InitialSyncTab(from: $0) }
            let syncMessages = messages.map { InitialSyncMessage(from: $0) }

            let request = InitialSyncRequest(tabs: syncTabs, messages: syncMessages)

            // Send to server
            let response: InitialSyncResponse = try await apiClient.request(.initialSync(request))

            // Update local models with server IDs
            for tabResult in response.tabs {
                if let tab = tabs.first(where: { $0.id == tabResult.localId }) {
                    tab.serverId = tabResult.serverId
                }
            }

            for messageResult in response.messages {
                if let message = messages.first(where: { $0.id == messageResult.localId }) {
                    message.serverId = messageResult.serverId

                    // Upload media if URLs provided
                    if let uploadUrls = messageResult.mediaUploadUrls, !uploadUrls.isEmpty {
                        await MediaSyncService.shared.uploadMedia(
                            for: message,
                            uploadUrls: uploadUrls
                        )
                    }
                }
            }

            try modelContext.save()

            // Mark initial sync as completed
            AuthService.shared.markInitialSyncCompleted()
            await setLastSyncDate(response.serverTime)

            logger.info("Initial sync completed: \(tabs.count) tabs, \(messages.count) messages")
        } catch let error as APIError {
            // Handle 404 gracefully - sync endpoint not implemented yet
            if case .httpError(let statusCode, _) = error, statusCode == 404 {
                logger.warning("Sync endpoint not available (404). Skipping initial sync.")
                // Mark as completed anyway so app doesn't keep retrying
                AuthService.shared.markInitialSyncCompleted()
            } else {
                logger.error("Initial sync failed: \(error.localizedDescription)")
            }
        } catch {
            logger.error("Initial sync failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Incremental Sync

    /// Perform incremental sync to get changes since last sync
    @MainActor
    func performIncrementalSync(modelContext: ModelContext) async {
        guard AuthService.shared.isAuthenticated,
              AuthService.shared.currentUser?.hasCompletedInitialSync == true else {
            return
        }

        guard await beginSync() else {
            logger.debug("Sync already in progress")
            return
        }
        defer { Task { await endSync() } }

        let since = await getLastSyncDate() ?? Date.distantPast

        logger.debug("Starting incremental sync since \(since)")

        do {
            // Get server changes
            let response: IncrementalSyncResponse = try await apiClient.request(.incrementalSync(since: since))

            // Apply tab changes
            await applyTabChanges(response.tabs, modelContext: modelContext)

            // Apply message changes
            await applyMessageChanges(response.messages, modelContext: modelContext)

            // Process pending queue
            await processPendingQueue(modelContext: modelContext)

            try modelContext.save()
            await setLastSyncDate(response.serverTime)

            logger.info("Incremental sync completed")
        } catch let error as APIError {
            // Handle 404 gracefully - sync endpoint not implemented yet
            if case .httpError(let statusCode, _) = error, statusCode == 404 {
                logger.warning("Sync endpoint not available (404). Skipping incremental sync.")
            } else {
                logger.error("Incremental sync failed: \(error.localizedDescription)")
            }
        } catch {
            logger.error("Incremental sync failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Apply Server Changes

    @MainActor
    private func applyTabChanges(_ changes: SyncChanges<TabResponse>, modelContext: ModelContext) async {
        // Handle deleted tabs
        for serverId in changes.deleted {
            let descriptor = FetchDescriptor<Tab>(predicate: #Predicate { $0.serverId == serverId })
            if let tabs = try? modelContext.fetch(descriptor), let tab = tabs.first {
                modelContext.delete(tab)
            }
        }

        // Handle created/updated tabs
        for tabResponse in changes.created + changes.updated {
            let serverId = tabResponse.id
            let descriptor = FetchDescriptor<Tab>(predicate: #Predicate { $0.serverId == serverId })

            if let existingTabs = try? modelContext.fetch(descriptor), let existingTab = existingTabs.first {
                // Update existing
                existingTab.title = tabResponse.title
                existingTab.position = tabResponse.position
            } else {
                // Create new
                let newTab = Tab(title: tabResponse.title, position: tabResponse.position)
                newTab.serverId = tabResponse.id
                if let localId = tabResponse.localId {
                    newTab.id = localId
                }
                modelContext.insert(newTab)
            }
        }
    }

    @MainActor
    private func applyMessageChanges(_ changes: SyncChanges<MessageResponse>, modelContext: ModelContext) async {
        // Handle deleted messages
        for serverId in changes.deleted {
            let descriptor = FetchDescriptor<Message>(predicate: #Predicate { $0.serverId == serverId })
            if let messages = try? modelContext.fetch(descriptor), let message = messages.first {
                message.deleteMediaFiles()
                modelContext.delete(message)
            }
        }

        // Handle created/updated messages
        for msgResponse in changes.created + changes.updated {
            let serverId = msgResponse.id
            let descriptor = FetchDescriptor<Message>(predicate: #Predicate { $0.serverId == serverId })

            if let existingMessages = try? modelContext.fetch(descriptor), let existingMessage = existingMessages.first {
                // Update existing message
                updateMessage(existingMessage, from: msgResponse)
            } else {
                // Create new message
                let newMessage = createMessage(from: msgResponse, modelContext: modelContext)
                modelContext.insert(newMessage)

                // Download media if present
                if let media = msgResponse.media, !media.isEmpty {
                    Task {
                        await MediaSyncService.shared.downloadMedia(for: newMessage, media: media)
                    }
                }
            }
        }
    }

    @MainActor
    private func updateMessage(_ message: Message, from response: MessageResponse) {
        message.content = response.content
        message.position = response.position
        message.entities = response.entities?.map { $0.toTextEntity() }
        message.linkPreview = response.linkPreview?.toLinkPreview()
        message.sourceUrl = response.sourceUrl
        message.mediaGroupId = response.mediaGroupId
        message.todoItems = response.todoItems?.map { $0.toTodoItem() }
        message.todoTitle = response.todoTitle
        message.reminderDate = response.reminderDate
        message.reminderRepeatInterval = response.reminderRepeatInterval.flatMap { ReminderRepeatInterval(rawValue: $0) }

        // Resolve tab from server ID
        // Note: tabId resolution handled separately
    }

    @MainActor
    private func createMessage(from response: MessageResponse, modelContext: ModelContext) -> Message {
        // Resolve local tab ID from server tab ID
        var localTabId: UUID? = nil
        if let tabServerId = response.tabServerId {
            let descriptor = FetchDescriptor<Tab>(predicate: #Predicate { $0.serverId == tabServerId })
            if let tabs = try? modelContext.fetch(descriptor), let tab = tabs.first {
                localTabId = tab.id
            }
        }

        let message = Message(
            content: response.content,
            tabId: localTabId,
            entities: response.entities?.map { $0.toTextEntity() },
            position: response.position,
            sourceUrl: response.sourceUrl,
            linkPreview: response.linkPreview?.toLinkPreview(),
            mediaGroupId: response.mediaGroupId
        )

        message.serverId = response.id
        if let localId = response.localId {
            message.id = localId
        }
        message.createdAt = response.createdAt
        message.todoItems = response.todoItems?.map { $0.toTodoItem() }
        message.todoTitle = response.todoTitle
        message.reminderDate = response.reminderDate
        message.reminderRepeatInterval = response.reminderRepeatInterval.flatMap { ReminderRepeatInterval(rawValue: $0) }

        return message
    }

    // MARK: - Pending Queue Operations

    /// Queue a create operation and immediately try to sync
    func queueCreate<T: Encodable>(_ entity: T, type: EntityType, entityId: UUID) async {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let payload = try encoder.encode(entity)
            let operation = PendingOperation(type: .create, entityType: type, entityId: entityId, payload: payload)
            pendingStore.add(operation)
            logger.debug("Queued create for \(type.rawValue) \(entityId)")

            // Try to process immediately if authenticated
            if await AuthService.shared.isAuthenticated {
                await processQueuedOperations()
            }
        } catch {
            logger.error("Failed to queue create: \(error.localizedDescription)")
        }
    }

    /// Queue an update operation and immediately try to sync
    func queueUpdate<T: Encodable>(_ entity: T, type: EntityType, entityId: UUID) async {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let payload = try encoder.encode(entity)
            let operation = PendingOperation(type: .update, entityType: type, entityId: entityId, payload: payload)
            pendingStore.add(operation)
            logger.debug("Queued update for \(type.rawValue) \(entityId)")

            // Try to process immediately if authenticated
            if await AuthService.shared.isAuthenticated {
                await processQueuedOperations()
            }
        } catch {
            logger.error("Failed to queue update: \(error.localizedDescription)")
        }
    }

    /// Queue a delete operation and immediately try to sync
    func queueDelete(type: EntityType, entityId: UUID, serverId: Int) async {
        do {
            let payload = try JSONEncoder().encode(["server_id": serverId])
            let operation = PendingOperation(type: .delete, entityType: type, entityId: entityId, payload: payload)
            pendingStore.add(operation)
            logger.debug("Queued delete for \(type.rawValue) \(entityId)")

            // Try to process immediately if authenticated
            if await AuthService.shared.isAuthenticated {
                await processQueuedOperations()
            }
        } catch {
            logger.error("Failed to queue delete: \(error.localizedDescription)")
        }
    }

    /// Process queued operations immediately (public method)
    func processQueuedOperations() async {
        await processPendingQueue(modelContext: nil)
    }

    /// Process queued operations with model context for updating server IDs
    @MainActor
    func processQueuedOperations(modelContext: ModelContext) async {
        await processPendingQueue(modelContext: modelContext)
    }

    /// Process all pending operations
    private func processPendingQueue(modelContext: ModelContext?) async {
        let allOperations = pendingStore.getAll()
        guard !allOperations.isEmpty else { return }

        // Sort operations: tabs first, then messages (so tabs get serverIds before messages need them)
        let operations = allOperations.sorted { op1, op2 in
            if op1.entityType == .tab && op2.entityType == .message { return true }
            if op1.entityType == .message && op2.entityType == .tab { return false }
            return op1.createdAt < op2.createdAt
        }

        logger.info("Processing \(operations.count) pending operations")

        for var operation in operations {
            do {
                try await processOperation(operation, modelContext: modelContext)
                pendingStore.remove(id: operation.id)
            } catch {
                operation.retryCount += 1
                operation.lastError = error.localizedDescription

                if operation.shouldRetry {
                    pendingStore.update(operation)
                    logger.warning("Operation \(operation.id) failed, will retry: \(error.localizedDescription)")
                } else {
                    pendingStore.remove(id: operation.id)
                    logger.error("Operation \(operation.id) failed permanently: \(error.localizedDescription)")
                }
            }
        }

        // Save model context if provided
        if let context = modelContext {
            try? await MainActor.run {
                try? context.save()
            }
        }
    }

    private func processOperation(_ operation: PendingOperation, modelContext: ModelContext?) async throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        switch (operation.type, operation.entityType) {
        case (.create, .tab):
            let request = try decoder.decode(CreateTabRequest.self, from: operation.payload)
            let response: TabResponse = try await apiClient.request(.createTab(title: request.title, position: request.position, localId: request.localId))

            // Update local tab with server ID
            if let context = modelContext {
                await MainActor.run {
                    let localId = operation.entityId
                    let descriptor = FetchDescriptor<Tab>(predicate: #Predicate { $0.id == localId })
                    if let tabs = try? context.fetch(descriptor), let tab = tabs.first {
                        tab.serverId = response.id
                        logger.info("Updated tab \(localId) with serverId \(response.id)")
                    }
                }
            }

        case (.create, .message):
            var request = try decoder.decode(CreateMessageRequest.self, from: operation.payload)

            // Resolve tab server ID if we have local ID but no server ID
            if request.tabServerId == nil, let tabLocalId = request.tabLocalId, let context = modelContext {
                let resolvedServerId = await MainActor.run { () -> Int? in
                    let descriptor = FetchDescriptor<Tab>(predicate: #Predicate { $0.id == tabLocalId })
                    if let tabs = try? context.fetch(descriptor), let tab = tabs.first {
                        return tab.serverId
                    }
                    return nil
                }
                if let serverId = resolvedServerId {
                    request.tabServerId = serverId
                    logger.info("Resolved tab serverId \(serverId) for message")
                }
            }

            let response: MessageResponse = try await apiClient.request(.createMessage(request))

            // Update local message with server ID
            if let context = modelContext {
                await MainActor.run {
                    let localId = operation.entityId
                    let descriptor = FetchDescriptor<Message>(predicate: #Predicate { $0.id == localId })
                    if let messages = try? context.fetch(descriptor), let message = messages.first {
                        message.serverId = response.id
                        logger.info("Updated message \(localId) with serverId \(response.id)")
                    }
                }
            }

        case (.update, .tab):
            let request = try decoder.decode(UpdateTabRequest.self, from: operation.payload)
            // Need server ID - this would be passed differently in practice
            logger.warning("Tab update not fully implemented")

        case (.update, .message):
            let request = try decoder.decode(UpdateMessageRequest.self, from: operation.payload)
            // Need server ID - this would be passed differently in practice
            logger.warning("Message update not fully implemented")

        case (.delete, .tab):
            struct DeletePayload: Decodable { let server_id: Int }
            let payload = try decoder.decode(DeletePayload.self, from: operation.payload)
            try await apiClient.requestVoid(.deleteTab(serverId: payload.server_id))

        case (.delete, .message):
            struct DeletePayload: Decodable { let server_id: Int }
            let payload = try decoder.decode(DeletePayload.self, from: operation.payload)
            try await apiClient.requestVoid(.deleteMessage(serverId: payload.server_id))
        }
    }

    // MARK: - User Settings Sync

    /// Fetch user settings from server and apply locally
    @MainActor
    func fetchUserSettings() async {
        guard AuthService.shared.isAuthenticated else { return }

        logger.info("Fetching user settings from server")

        do {
            let settings: UserSettingsResponse = try await apiClient.request(.getUserSettings)

            // Apply settings locally
            UserDefaults.standard.set(settings.spaceName, forKey: "spaceName")
            AppSettings.shared.autoFocusInput = settings.autoFocusInput

            // Apply theme
            if let theme = AppTheme.allCases.first(where: { $0.rawValue == settings.theme }) {
                ThemeManager.shared.currentTheme = theme
            }

            logger.info("User settings applied: spaceName=\(settings.spaceName), theme=\(settings.theme)")
        } catch let error as APIError {
            if case .httpError(let statusCode, _) = error, statusCode == 404 {
                logger.warning("User settings endpoint not available")
            } else {
                logger.error("Failed to fetch user settings: \(error.localizedDescription)")
            }
        } catch {
            logger.error("Failed to fetch user settings: \(error.localizedDescription)")
        }
    }

    /// Save current local settings to server
    @MainActor
    func saveUserSettings() async {
        guard AuthService.shared.isAuthenticated else { return }

        let spaceName = UserDefaults.standard.string(forKey: "spaceName") ?? "Taby"
        let theme = ThemeManager.shared.currentTheme.rawValue
        let autoFocusInput = AppSettings.shared.autoFocusInput

        let request = UpdateUserSettingsRequest(
            spaceName: spaceName,
            theme: theme,
            autoFocusInput: autoFocusInput
        )

        logger.info("Saving user settings to server")

        do {
            let _: UserSettingsResponse = try await apiClient.request(.updateUserSettings(request))
            logger.info("User settings saved successfully")
        } catch {
            logger.error("Failed to save user settings: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    /// Clear sync state (on logout)
    func clearSyncState() {
        lastSyncDate = nil
        pendingStore.clearAll()
        logger.info("Sync state cleared")
    }

    /// Get count of pending operations
    var pendingCount: Int {
        pendingStore.count
    }
}
