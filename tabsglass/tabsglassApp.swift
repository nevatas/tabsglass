//
//  tabsglassApp.swift
//  tabsglass
//
//  Created by Sergey Tokarev on 22.01.2026.
//

import SwiftUI
import SwiftData
import UIKit
import os.log

@main
struct tabsglassApp: App {
    let modelContainer: ModelContainer

    init() {
        // Warm up keyboard on app launch to avoid delay on first use
        KeyboardWarmer.shared.warmUp()

        // Migrate photos to shared container (for Share Extension support)
        // Note: Database migration happens automatically in SharedModelContainer.create()
        SharedModelContainer.migratePhotosIfNeeded()

        // Initialize model container with shared store for extension support
        // Note: Inbox is virtual (messages with tabId = nil), not a real tab
        do {
            let container = try SharedModelContainer.create()
            self.modelContainer = container
            SharedModelContainer.setShared(container)  // Make accessible to services
            Self.seedWelcomeMessagesIfNeeded(in: container)
            Self.processPendingShareItems(in: container)
        } catch {
            fatalError("Failed to initialize model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    // Check auth session on app launch
                    await AuthService.shared.checkSession()

                    // If authenticated, fetch settings and data from server
                    if AuthService.shared.isAuthenticated {
                        print("🔐 User authenticated, starting sync...")
                        await SyncService.shared.fetchUserSettings()
                        let context = modelContainer.mainContext
                        await SyncService.shared.fetchDataFromServer(modelContext: context)

                        print("🔌 Connecting to WebSocket...")
                        do {
                            try await WebSocketService.shared.connect()
                            print("✅ WebSocket connect() completed")
                        } catch {
                            print("❌ WebSocket connect() failed: \(error)")
                        }

                        // Start listening to WebSocket events (using manager to prevent duplicates)
                        print("🎧 Starting WebSocket event listener...")
                        WebSocketEventListenerManager.start(in: modelContainer)
                    } else {
                        print("⚠️ User not authenticated, skipping sync and WebSocket")
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    // Cancel any pending disconnect
                    Self.cancelBackgroundDisconnect()

                    // Process any pending share items when app returns to foreground
                    Self.processPendingShareItems(in: modelContainer)

                    // Force reconnect WebSocket when returning from background
                    // (connection may be stale after sleep)
                    Task {
                        if AuthService.shared.isAuthenticated {
                            await WebSocketService.shared.forceReconnect()
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    // Schedule delayed disconnect (will be cancelled if app returns quickly)
                    Self.scheduleBackgroundDisconnect()
                }
                .onReceive(NotificationCenter.default.publisher(for: .userDidAuthenticate)) { _ in
                    // Connect WebSocket and start sync after login/registration
                    Task {
                        print("🔐 User authenticated via login/register, connecting WebSocket...")

                        // Fetch settings and initial data
                        await SyncService.shared.fetchUserSettings()
                        let context = modelContainer.mainContext
                        await SyncService.shared.fetchDataFromServer(modelContext: context)

                        // Connect WebSocket
                        do {
                            try await WebSocketService.shared.connect()
                            print("✅ WebSocket connected after auth")
                        } catch {
                            print("❌ WebSocket connection failed after auth: \(error)")
                        }

                        // Start listening to WebSocket events (using manager to prevent duplicates)
                        WebSocketEventListenerManager.start(in: modelContainer)
                    }
                }
        }
        .modelContainer(modelContainer)
    }
}

// MARK: - Background Disconnect Management

/// Manages the delayed WebSocket disconnect when app enters background
private enum BackgroundDisconnectManager {
    private static var disconnectTask: Task<Void, Never>?

    static func schedule() {
        disconnectTask = Task {
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled else { return }
            await WebSocketService.shared.disconnect()
        }
    }

    static func cancel() {
        disconnectTask?.cancel()
        disconnectTask = nil
    }
}

/// Manages the WebSocket event listener task to prevent duplicates
private enum WebSocketEventListenerManager {
    private static var eventListenerTask: Task<Void, Never>?

    static func start(in container: ModelContainer) {
        // Cancel any existing listener to prevent duplicates
        eventListenerTask?.cancel()

        // Set model container for the event queue
        Task {
            await WebSocketEventQueue.shared.setModelContainer(container)
        }

        eventListenerTask = Task {
            await tabsglassApp.handleWebSocketEvents(in: container)
        }
    }

    static func cancel() {
        eventListenerTask?.cancel()
        eventListenerTask = nil
    }
}

private extension tabsglassApp {
    static func scheduleBackgroundDisconnect() {
        BackgroundDisconnectManager.schedule()
    }

    static func cancelBackgroundDisconnect() {
        BackgroundDisconnectManager.cancel()
    }
}

// MARK: - Pending Share Items Processing

private extension tabsglassApp {
    static func processPendingShareItems(in container: ModelContainer) {
        let pendingItems = PendingShareStorage.loadAll()
        guard !pendingItems.isEmpty else { return }

        let context = container.mainContext

        for item in pendingItems {
            // Detect URLs in text
            let entities = TextEntity.detectURLs(in: item.text)

            let message = Message(
                content: item.text,
                tabId: item.tabId,
                entities: entities.isEmpty ? nil : entities,
                photoFileNames: item.photoFileNames,
                photoAspectRatios: item.photoAspectRatios,
                videoFileNames: item.videoFileNames,
                videoAspectRatios: item.videoAspectRatios,
                videoDurations: item.videoDurations,
                videoThumbnailFileNames: item.videoThumbnailFileNames
            )
            message.createdAt = item.createdAt

            context.insert(message)
        }

        try? context.save()
        PendingShareStorage.clearAll()
    }

    static func seedWelcomeMessagesIfNeeded(in container: ModelContainer) {
        let key = "hasSeededWelcomeMessages"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        let texts = [
            L10n.Welcome.message1,
            L10n.Welcome.message2,
            L10n.Welcome.message3,
            L10n.Welcome.message4,
        ]

        let context = container.mainContext
        let now = Date()

        for (index, text) in texts.enumerated() {
            let message = Message(content: text)
            // Stagger timestamps so messages appear in correct order (oldest first at top)
            message.createdAt = now.addingTimeInterval(Double(index))
            context.insert(message)
        }

        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
    }
}

// MARK: - WebSocket Event Handling

private extension tabsglassApp {
    private static let wsLogger = Logger(subsystem: "tabsglass", category: "WebSocketEvents")

    @MainActor
    static func handleWebSocketEvents(in container: ModelContainer) async {
        let context = container.mainContext
        wsLogger.info("🎧 Started listening for WebSocket events")

        for await event in await WebSocketService.shared.events() {
            wsLogger.info("📥 Received event: \(String(describing: event))")

            switch event {
            case .messageCreated(let serverMessage):
                wsLogger.info("📩 Message created: serverId=\(serverMessage.serverId), content=\(serverMessage.content.prefix(50))")
                await handleMessageCreated(serverMessage, context: context)

            case .messageUpdated(let serverMessage):
                wsLogger.info("📝 Message updated: serverId=\(serverMessage.serverId)")
                await handleMessageUpdated(serverMessage, context: context)

            case .messageDeleted(let serverId):
                wsLogger.info("🗑️ Message deleted: serverId=\(serverId)")
                handleMessageDeleted(serverId: serverId, context: context)

            case .messageMoved(let serverId, let newTabServerId):
                wsLogger.info("📦 Message moved: serverId=\(serverId) to tab=\(String(describing: newTabServerId))")
                handleMessageMoved(serverId: serverId, newTabServerId: newTabServerId, context: context)

            case .tabCreated(let serverTab):
                wsLogger.info("📁 Tab created: serverId=\(serverTab.serverId), title=\(serverTab.title)")
                await handleTabCreated(serverTab, context: context)

            case .tabUpdated(let serverTab):
                wsLogger.info("📁 Tab updated: serverId=\(serverTab.serverId)")
                handleTabUpdated(serverTab, context: context)

            case .tabDeleted(let serverId):
                wsLogger.info("🗑️ Tab deleted: serverId=\(serverId)")
                handleTabDeleted(serverId: serverId, context: context)

            case .syncRequired:
                wsLogger.info("🔄 Sync required")
                await SyncService.shared.fetchDataFromServer(modelContext: context)

            case .settingsUpdated(let settings):
                wsLogger.info("⚙️ Settings updated: theme=\(settings.theme), spaceName=\(settings.spaceName)")
                handleSettingsUpdated(settings)

            case .connected:
                wsLogger.info("✅ WebSocket connected event received")

            case .disconnected(let reason):
                wsLogger.info("❌ WebSocket disconnected: \(reason ?? "no reason")")

            case .error(let error):
                wsLogger.error("❌ WebSocket error: \(error)")
            }
        }
    }

    @MainActor
    static func handleMessageCreated(_ serverMessage: ServerMessage, context: ModelContext) async {
        wsLogger.info("🔍 handleMessageCreated: serverId=\(serverMessage.serverId), tabServerId=\(String(describing: serverMessage.tabServerId))")

        // Check if message already exists
        let serverId = serverMessage.serverId
        let descriptor = FetchDescriptor<Message>(predicate: #Predicate { $0.serverId == serverId })
        if let existing = try? context.fetch(descriptor), !existing.isEmpty {
            wsLogger.info("⏭️ Message already exists by serverId, skipping")
            return // Already exists
        }

        // Also check by localId
        if let localId = serverMessage.localId {
            let localDescriptor = FetchDescriptor<Message>(predicate: #Predicate { $0.id == localId })
            if let existing = try? context.fetch(localDescriptor), let msg = existing.first {
                wsLogger.info("🔗 Linking existing local message to serverId=\(serverId)")
                msg.serverId = serverId
                try? context.save()
                return
            }
        }

        // Find tab by serverId (single lookup - queue handles retries)
        var tabId: UUID? = nil
        if let tabServerId = serverMessage.tabServerId {
            let tabDescriptor = FetchDescriptor<Tab>(predicate: #Predicate { $0.serverId == tabServerId })
            if let tabs = try? context.fetch(tabDescriptor), let tab = tabs.first {
                tabId = tab.id
                wsLogger.info("✅ Found tab: serverId=\(tabServerId) -> localId=\(tab.id)")
            } else {
                // Tab not found - enqueue for later processing
                wsLogger.info("⏳ Tab not found for serverId=\(tabServerId), enqueueing message")
                await WebSocketEventQueue.shared.enqueue(serverMessage)
                return
            }
        }

        // Create new message
        wsLogger.info("➕ Creating new message: serverId=\(serverId), tabId=\(String(describing: tabId))")
        let message = Message(
            content: serverMessage.content,
            tabId: tabId,
            entities: serverMessage.entities,
            position: serverMessage.position,
            sourceUrl: serverMessage.sourceUrl,
            linkPreview: serverMessage.linkPreview
        )
        message.serverId = serverMessage.serverId
        message.createdAt = serverMessage.createdAt
        message.todoItems = serverMessage.todoItems
        message.todoTitle = serverMessage.todoTitle
        message.reminderDate = serverMessage.reminderDate
        message.reminderRepeatInterval = serverMessage.reminderRepeatInterval

        context.insert(message)
        do {
            try context.save()
            wsLogger.info("✅ Message saved successfully")
        } catch {
            wsLogger.error("❌ Failed to save message: \(error)")
        }

        // Download media if present
        if let media = serverMessage.media, !media.isEmpty {
            await MediaSyncService.shared.downloadMedia(for: message, media: media)
        }
    }

    @MainActor
    static func handleMessageUpdated(_ serverMessage: ServerMessage, context: ModelContext) async {
        let serverId = serverMessage.serverId
        let descriptor = FetchDescriptor<Message>(predicate: #Predicate { $0.serverId == serverId })

        guard let messages = try? context.fetch(descriptor), let message = messages.first else {
            return
        }

        message.content = serverMessage.content
        message.position = serverMessage.position
        message.entities = serverMessage.entities
        message.linkPreview = serverMessage.linkPreview
        message.todoItems = serverMessage.todoItems
        message.todoTitle = serverMessage.todoTitle
        message.reminderDate = serverMessage.reminderDate
        message.reminderRepeatInterval = serverMessage.reminderRepeatInterval

        try? context.save()
    }

    @MainActor
    static func handleMessageDeleted(serverId: Int, context: ModelContext) {
        let descriptor = FetchDescriptor<Message>(predicate: #Predicate { $0.serverId == serverId })

        guard let messages = try? context.fetch(descriptor), let message = messages.first else {
            return
        }

        message.deletePhotoFiles()
        message.deleteVideoFiles()
        context.delete(message)
        try? context.save()
    }

    @MainActor
    static func handleMessageMoved(serverId: Int, newTabServerId: Int?, context: ModelContext) {
        let descriptor = FetchDescriptor<Message>(predicate: #Predicate { $0.serverId == serverId })

        guard let messages = try? context.fetch(descriptor), let message = messages.first else {
            return
        }

        if let tabServerId = newTabServerId {
            let tabDescriptor = FetchDescriptor<Tab>(predicate: #Predicate { $0.serverId == tabServerId })
            if let tabs = try? context.fetch(tabDescriptor), let tab = tabs.first {
                message.tabId = tab.id
            }
        } else {
            message.tabId = nil // Move to Inbox
        }

        try? context.save()
    }

    @MainActor
    static func handleTabCreated(_ serverTab: ServerTab, context: ModelContext) async {
        // Check if tab already exists
        let serverId = serverTab.serverId
        let descriptor = FetchDescriptor<Tab>(predicate: #Predicate { $0.serverId == serverId })
        if let existing = try? context.fetch(descriptor), !existing.isEmpty {
            return
        }

        // Check by localId
        if let localId = serverTab.localId {
            let localDescriptor = FetchDescriptor<Tab>(predicate: #Predicate { $0.id == localId })
            if let existing = try? context.fetch(localDescriptor), let tab = existing.first {
                tab.serverId = serverId
                try? context.save()
                // Notify queue that tab was linked
                await WebSocketEventQueue.shared.onTabCreated(serverId)
                return
            }
        }

        let tab = Tab(title: serverTab.title, position: serverTab.position)
        tab.serverId = serverTab.serverId

        context.insert(tab)
        try? context.save()

        // Notify queue that new tab was created
        await WebSocketEventQueue.shared.onTabCreated(serverId)
    }

    @MainActor
    static func handleTabUpdated(_ serverTab: ServerTab, context: ModelContext) {
        let serverId = serverTab.serverId
        let descriptor = FetchDescriptor<Tab>(predicate: #Predicate { $0.serverId == serverId })

        guard let tabs = try? context.fetch(descriptor), let tab = tabs.first else {
            return
        }

        tab.title = serverTab.title
        tab.position = serverTab.position
        try? context.save()
    }

    @MainActor
    static func handleTabDeleted(serverId: Int, context: ModelContext) {
        let descriptor = FetchDescriptor<Tab>(predicate: #Predicate { $0.serverId == serverId })

        guard let tabs = try? context.fetch(descriptor), let tab = tabs.first else {
            return
        }

        context.delete(tab)
        try? context.save()
    }

    @MainActor
    static func handleSettingsUpdated(_ settings: SettingsPayload) {
        // Only apply theme if syncTheme is enabled on THIS device
        if AppSettings.shared.syncTheme {
            if let theme = AppTheme(rawValue: settings.theme) {
                ThemeManager.shared.currentTheme = theme
                wsLogger.info("🎨 Theme updated to: \(theme.rawValue)")
            }
        } else {
            wsLogger.info("⏭️ Skipping theme sync (disabled on this device)")
        }

        // Update space name (always sync)
        AppSettings.shared.spaceName = settings.spaceName

        // Update auto focus setting (always sync)
        AppSettings.shared.autoFocusInput = settings.autoFocusInput

        // Update sync theme setting (so user knows current server state)
        // Note: We don't apply it to local setting to preserve user's choice
    }
}

// MARK: - Keyboard Warmer

/// Pre-loads keyboard resources to avoid delay on first text field focus
final class KeyboardWarmer {
    static let shared = KeyboardWarmer()

    private var warmUpTextField: UITextField?
    private var warmUpWindow: UIWindow?

    private init() {}

    func warmUp() {
        // Delay slightly to ensure window scene is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.performWarmUp()
        }
    }

    private func performWarmUp() {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
            return
        }

        // Create an off-screen window
        let window = UIWindow(windowScene: windowScene)
        window.frame = CGRect(x: -100, y: -100, width: 10, height: 10)
        window.windowLevel = .init(rawValue: -1000)
        window.isHidden = false

        let textField = UITextField()
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        window.addSubview(textField)

        // Keep references to prevent deallocation
        self.warmUpWindow = window
        self.warmUpTextField = textField

        // Briefly become first responder to load keyboard
        textField.becomeFirstResponder()

        // Resign after keyboard is loaded (longer delay for full preload)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.warmUpTextField?.resignFirstResponder()

            // Clean up
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.warmUpTextField?.removeFromSuperview()
                self?.warmUpTextField = nil
                self?.warmUpWindow?.isHidden = true
                self?.warmUpWindow = nil
            }
        }
    }
}
