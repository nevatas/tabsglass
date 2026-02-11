//
//  MainContainerView.swift
//  tabsglass
//

import SwiftUI
import SwiftData
import StoreKit
import UIKit

struct MainContainerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.requestReview) private var requestReview
    @Query(sort: \Tab.position) private var tabs: [Tab]
    @Query(sort: \Message.createdAt) private var allMessages: [Message]
    @State private var selectedTabIndex = 1  // 0 = Search, 1 = Inbox (virtual), 2+ = real tabs
    @State private var showNewTabAlert = false
    @State private var showRenameAlert = false
    @State private var showRenameInboxAlert = false
    @State private var showDeleteAlert = false
    @State private var showSettings = false
    @State private var showReorderTabs = false
    @State private var tabToRename: Tab?
    @State private var tabToDelete: Tab?
    @State private var messageToEdit: Message?
    @State private var showTaskListSheet = false
    @State private var taskListToEdit: Message?
    @State private var messageForReminder: Message?
    @State private var newTabTitle = ""
    @State private var renameTabTitle = ""
    @State private var renameInboxTitle = ""
    @State private var messageText = ""
    @State private var switchFraction: CGFloat = 0  // -1.0 to 1.0 swipe progress
    @State private var attachedImages: [UIImage] = []
    @State private var attachedVideos: [AttachedVideo] = []
    @State private var formattingEntities: [TextEntity] = []

    // Selection mode
    @State private var isSelectionMode = false
    @State private var selectedMessageIds: Set<UUID> = []
    @State private var showMoveSheet = false
    @State private var showDeleteSelectedAlert = false
    @State private var reloadTrigger = 0

    /// Total number of tabs including Search and virtual Inbox
    private var totalTabCount: Int {
        2 + tabs.count  // Search + Inbox + real tabs
    }

    /// Get tabId for current selection (nil = Inbox or Search)
    private var currentTabId: UUID? {
        guard selectedTabIndex > 1 && selectedTabIndex <= tabs.count + 1 else { return nil }
        return tabs[selectedTabIndex - 2].id
    }

    /// Check if currently on Search
    private var isOnSearch: Bool {
        selectedTabIndex == 0
    }

    /// TabBar opacity - fades out when arriving at Search screen
    private var tabBarOpacity: CGFloat {
        if selectedTabIndex == 0 {
            // On Search: hidden, but visible when swiping toward Inbox
            return switchFraction  // 0 when on Search, increases toward 1 when swiping to Inbox
        } else if selectedTabIndex == 1 && switchFraction < 0 {
            // On Inbox, swiping toward Search: fade out
            return 1 + switchFraction  // 1 → 0 as fraction goes -1
        }
        return 1  // Fully visible on other tabs
    }

    // Note: tabBarOffset removed - now using opacity instead

    /// Check if currently on Inbox
    private var isOnInbox: Bool {
        selectedTabIndex == 1
    }

    /// Check if messages can be moved (there are other destinations)
    private var canMoveMessages: Bool {
        // Can move if: we're in a tab (can move to Inbox) OR there are other tabs to move to
        if isOnInbox {
            return !tabs.isEmpty  // From Inbox, can move to any tab
        } else {
            return true  // From any tab, can at least move to Inbox
        }
    }

    private var chatView: UnifiedChatView {
        UnifiedChatView(
            tabs: tabs,
            messages: allMessages,
            selectedIndex: $selectedTabIndex,
            messageText: $messageText,
            switchFraction: $switchFraction,
            attachedImages: $attachedImages,
            attachedVideos: $attachedVideos,
            formattingEntities: $formattingEntities,
            onSend: { sendMessage() },
            onDeleteMessage: { message in
                deleteMessage(message)
            },
            onMoveMessage: { message, targetTabId in
                moveMessage(message, toTabId: targetTabId)
            },
            onEditMessage: { message in
                if message.isTodoList {
                    taskListToEdit = message
                } else {
                    messageToEdit = message
                }
            },
            onRestoreMessage: {
                restoreDeletedMessage()
            },
            onShowTaskList: {
                showTaskListSheet = true
            },
            onToggleTodoItem: { message, itemId, isCompleted in
                toggleTodoItem(message: message, itemId: itemId, isCompleted: isCompleted)
            },
            onToggleReminder: { message in
                messageForReminder = message
            },
            isSelectionMode: $isSelectionMode,
            selectedMessageIds: $selectedMessageIds,
            onEnterSelectionMode: { message in
                selectedMessageIds = [message.id]
                withAnimation(.easeOut(duration: 0.25)) {
                    isSelectionMode = true
                }
            },
            onToggleMessageSelection: { messageId, selected in
                if selected {
                    selectedMessageIds.insert(messageId)
                } else {
                    selectedMessageIds.remove(messageId)
                }
            },
            reloadTrigger: reloadTrigger
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Content layer (full screen)
            // Always show chat view (Inbox is always available as virtual tab)
            chatView
            .ignoresSafeArea(.keyboard)

            // Header layer (floating on top).
            // Keep it mounted to avoid UIKit tab bar re-creation glitches after selection mode.
            TabBarView(
                tabs: tabs,
                selectedIndex: $selectedTabIndex,
                switchFraction: $switchFraction,
                tabsOffset: 0,
                tabsOpacity: tabBarOpacity,
                onAddTap: {
                    newTabTitle = ""
                    showNewTabAlert = true
                },
                onMenuTap: { showSettings = true },
                onRenameTab: { tab in
                    tabToRename = tab
                    renameTabTitle = tab.title
                    showRenameAlert = true
                },
                onRenameInbox: {
                    renameInboxTitle = AppSettings.shared.inboxTitle
                    showRenameInboxAlert = true
                },
                onReorderTabs: {
                    showReorderTabs = true
                },
                onDeleteTab: { tab in
                    tabToDelete = tab
                    showDeleteAlert = true
                },
                onGoToInbox: {
                    withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                        selectedTabIndex = 1  // Go to Inbox
                    }
                }
            )
            .offset(y: isSelectionMode ? -24 : 0)
            .opacity(isSelectionMode ? 0 : 1)
            .allowsHitTesting(!isSelectionMode)

            // Selection UI - shown in selection mode
            if isSelectionMode {
                // Cancel bar at top
                VStack {
                    SelectionCancelBar(
                        selectedCount: selectedMessageIds.count,
                        onCancel: { exitSelectionMode() }
                    )
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))

                // Action bar at bottom
                VStack {
                    Spacer()
                    SelectionActionBar(
                        selectedCount: selectedMessageIds.count,
                        canMove: canMoveMessages,
                        onMove: { showMoveSheet = true },
                        onDelete: { showDeleteSelectedAlert = true }
                    )
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Tab input dialogs (overlays, not sheets — keyboard appears instantly)
            if showNewTabAlert {
                TabInputSheet(
                    title: L10n.Tab.new,
                    subtitle: L10n.Tab.newHint,
                    buttonTitle: L10n.Tab.create,
                    initialText: ""
                ) { result in
                    createTab(title: result)
                } onDismiss: {
                    withAnimation(.easeOut(duration: 0.1)) { showNewTabAlert = false }
                }
                .transition(.opacity.combined(with: .offset(y: 10)))
            }

            if showRenameAlert {
                TabInputSheet(
                    title: L10n.Tab.rename,
                    buttonTitle: L10n.Tab.save,
                    initialText: renameTabTitle
                ) { result in
                    if let tab = tabToRename {
                        renameTab(tab, to: result)
                    }
                } onDismiss: {
                    withAnimation(.easeOut(duration: 0.1)) { showRenameAlert = false }
                }
                .transition(.opacity.combined(with: .offset(y: 10)))
            }

            if showRenameInboxAlert {
                TabInputSheet(
                    title: L10n.Tab.renameInbox,
                    buttonTitle: L10n.Tab.save,
                    initialText: renameInboxTitle
                ) { result in
                    AppSettings.shared.inboxTitle = result
                } onDismiss: {
                    withAnimation(.easeOut(duration: 0.1)) { showRenameInboxAlert = false }
                }
                .transition(.opacity.combined(with: .offset(y: 10)))
            }
        }
        .animation(.easeOut(duration: 0.25), value: isSelectionMode)
        .sheet(isPresented: $showMoveSheet) {
            MoveMessagesSheet(tabs: tabs, currentTabId: currentTabId) { targetTabId in
                moveSelectedMessages(to: targetTabId)
            }
        }
        .alert(L10n.Tab.deleteTitle, isPresented: $showDeleteAlert) {
            Button(L10n.Tab.cancel, role: .cancel) { }
            Button(L10n.Tab.delete, role: .destructive) {
                if let tab = tabToDelete {
                    withAnimation(.spring(duration: 0.3, bounce: 0.1)) {
                        deleteTab(tab)
                    }
                }
            }
        } message: {
            if let tab = tabToDelete {
                Text(L10n.Tab.deleteMessage(tab.title))
            }
        }
        .alert(L10n.Selection.deleteTitle, isPresented: $showDeleteSelectedAlert) {
            Button(L10n.Tab.cancel, role: .cancel) { }
            Button(L10n.Selection.delete, role: .destructive) {
                deleteSelectedMessages()
            }
        } message: {
            Text(L10n.Selection.deleteMessage(selectedMessageIds.count))
        }
        .onChange(of: tabs.count) { oldValue, newValue in
            if newValue > oldValue {
                // New tab created - select it with animation
                // Index model: 0 = Search, 1 = Inbox, 2+ = real tabs
                withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                    selectedTabIndex = newValue + 1  // Last real tab index
                    switchFraction = 0
                }
            }
            // Ensure selected index is valid
            let maxValidIndex = newValue + 1
            if selectedTabIndex > maxValidIndex {
                selectedTabIndex = maxValidIndex
            }
        }
        .onChange(of: selectedTabIndex) { _, _ in
            // Reset fraction when tab changes (from tap or swipe completion)
            if abs(switchFraction) > 0.01 {
                switchFraction = 0
            }
        }
        .sheet(item: $messageToEdit) { message in
            EditMessageSheet(
                originalText: message.content,
                originalEntities: message.entities,
                originalPhotoFileNames: message.photoFileNames,
                originalVideoFileNames: message.videoFileNames,
                originalVideoThumbnailFileNames: message.videoThumbnailFileNames,
                originalVideoDurations: message.videoDurations,
                onSave: { newText, newEntities, newPhotoFileNames, newVideoFileNames, newVideoThumbnailFileNames, newVideoDurations in
                    let originalPhotoFileNames = message.photoFileNames
                    let originalPhotoAspectRatios = message.photoAspectRatios
                    let originalVideoFileNames = message.videoFileNames
                    let originalVideoAspectRatios = message.videoAspectRatios
                    let originalVideoThumbnailFileNames = message.videoThumbnailFileNames

                    // Delete removed photos from disk
                    let removedPhotos = originalPhotoFileNames.filter { !newPhotoFileNames.contains($0) }
                    for fileName in removedPhotos {
                        let url = Message.photosDirectory.appendingPathComponent(fileName)
                        try? FileManager.default.removeItem(at: url)
                    }

                    // Delete removed videos from disk
                    let removedVideos = originalVideoFileNames.filter { !newVideoFileNames.contains($0) }
                    for fileName in removedVideos {
                        SharedVideoStorage.deleteVideo(fileName)
                    }
                    // Delete removed video thumbnails
                    let removedThumbnails = originalVideoThumbnailFileNames.filter { !newVideoThumbnailFileNames.contains($0) }
                    for fileName in removedThumbnails {
                        SharedPhotoStorage.deletePhoto(fileName)
                    }

                    // Update aspect ratios - keep existing for old photos, calculate for new ones
                    let newPhotoAspectRatios: [Double] = newPhotoFileNames.map { fileName in
                        if let index = originalPhotoFileNames.firstIndex(of: fileName),
                           index < originalPhotoAspectRatios.count {
                            return originalPhotoAspectRatios[index]
                        }
                        let url = Message.photosDirectory.appendingPathComponent(fileName)
                        if let data = try? Data(contentsOf: url),
                           let image = UIImage(data: data) {
                            return Double(image.size.width / image.size.height)
                        }
                        return 1.0
                    }

                    // Keep existing video aspect ratios
                    let newVideoAspectRatios: [Double] = newVideoFileNames.map { fileName in
                        if let index = originalVideoFileNames.firstIndex(of: fileName),
                           index < originalVideoAspectRatios.count {
                            return originalVideoAspectRatios[index]
                        }
                        return 1.0
                    }

                    // Update message
                    message.content = newText
                    message.entities = newEntities
                    message.photoFileNames = newPhotoFileNames
                    message.photoAspectRatios = newPhotoAspectRatios
                    message.videoFileNames = newVideoFileNames
                    message.videoAspectRatios = newVideoAspectRatios
                    message.videoDurations = newVideoDurations
                    message.videoThumbnailFileNames = newVideoThumbnailFileNames
                    try? modelContext.save()
                    reloadTrigger += 1

                    messageToEdit = nil
                },
                onCancel: {
                    messageToEdit = nil
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showReorderTabs) {
            NavigationStack {
                ReorderTabsView()
            }
        }
        .sheet(isPresented: $showTaskListSheet) {
            TaskListSheet(
                onSave: { title, items in
                    sendTaskListMessage(title: title, items: items)
                    showTaskListSheet = false
                },
                onCancel: {
                    showTaskListSheet = false
                }
            )
        }
        .sheet(item: $taskListToEdit) { message in
            TaskListSheet(
                existingTitle: message.todoTitle,
                existingItems: message.todoItems ?? [],
                onSave: { title, items in
                    updateTaskList(message: message, newTitle: title, newItems: items)
                    taskListToEdit = nil
                },
                onCancel: {
                    taskListToEdit = nil
                }
            )
        }
        .sheet(item: $messageForReminder) { message in
            ReminderSheet(
                message: message,
                onSave: { date, repeatInterval in
                    saveReminder(message: message, date: date, repeatInterval: repeatInterval)
                },
                onRemove: message.hasReminder ? {
                    removeReminder(message: message)
                } : nil
            )
        }
        .task {
            // Sync tabs to extension on app launch
            TabsSync.saveTabs(Array(tabs))
        }
    }

    private func sendMessage() {
        let trimmedText = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasMedia = !attachedImages.isEmpty || !attachedVideos.isEmpty
        // Allow sending if there's text OR media
        guard !trimmedText.isEmpty || hasMedia else { return }

        // Capture all data BEFORE clearing (for async Task)
        let imagesToSave = attachedImages
        let videosToSave = attachedVideos
        let entitiesToSave = formattingEntities
        let originalText = messageText
        let tabId = currentTabId

        // Clear UI immediately for responsiveness
        messageText = ""
        attachedImages = []
        attachedVideos = []
        formattingEntities = []

        // Save photos synchronously (they're already in memory)
        var photoFileNames: [String] = []
        var photoAspectRatios: [Double] = []
        for image in imagesToSave {
            if let result = Message.savePhoto(image) {
                photoFileNames.append(result.fileName)
                photoAspectRatios.append(result.aspectRatio)
            }
        }

        // Save videos asynchronously (file I/O)
        Task {
            var videoFileNames: [String] = []
            var videoAspectRatios: [Double] = []
            var videoDurations: [Double] = []
            var videoThumbnailFileNames: [String] = []

            for video in videosToSave {
                if let result = await SharedVideoStorage.saveVideo(from: video.url) {
                    videoFileNames.append(result.fileName)
                    videoAspectRatios.append(result.aspectRatio)
                    videoDurations.append(result.duration)
                    videoThumbnailFileNames.append(result.thumbnailFileName)
                }
                // Clean up temp file
                try? FileManager.default.removeItem(at: video.url)
            }

            await MainActor.run {
                // Calculate leading whitespace offset for entity adjustment
                let leadingWhitespaceUTF16 = originalText
                    .prefix(while: { $0.isWhitespace || $0.isNewline })
                    .utf16
                    .count
                let trimmedTextUTF16Count = trimmedText.utf16.count

                // Adjust formatting entity offsets for trimmed text
                var allEntities: [TextEntity] = []
                for entity in entitiesToSave {
                    let newOffset = entity.offset - leadingWhitespaceUTF16
                    // Only include entities that are within the trimmed text bounds
                    if newOffset >= 0 && newOffset + entity.length <= trimmedTextUTF16Count {
                        allEntities.append(TextEntity(
                            type: entity.type,
                            offset: newOffset,
                            length: entity.length,
                            url: entity.url
                        ))
                    }
                }

                // Add URL entities (already relative to trimmed text)
                let urlEntities = TextEntity.detectURLs(in: trimmedText)
                allEntities.append(contentsOf: urlEntities)

                // tabId = nil for Inbox, or actual tab ID
                let message = Message(
                    content: trimmedText,
                    tabId: tabId,
                    entities: allEntities.isEmpty ? nil : allEntities,
                    photoFileNames: photoFileNames,
                    photoAspectRatios: photoAspectRatios,
                    videoFileNames: videoFileNames,
                    videoAspectRatios: videoAspectRatios,
                    videoDurations: videoDurations,
                    videoThumbnailFileNames: videoThumbnailFileNames
                )
                modelContext.insert(message)
                try? modelContext.save()
            }
        }
    }

    private func deleteMessage(_ message: Message) {
        // Clean up previous deleted message's media (if any)
        if let previousDeleted = DeletedMessageStore.shared.lastDeleted {
            // Delete photos
            for fileName in previousDeleted.photoFileNames {
                let url = Message.photosDirectory.appendingPathComponent(fileName)
                try? FileManager.default.removeItem(at: url)
            }
            // Delete videos and their thumbnails
            for fileName in previousDeleted.videoFileNames {
                SharedVideoStorage.deleteVideo(fileName)
            }
            for fileName in previousDeleted.videoThumbnailFileNames {
                SharedPhotoStorage.deletePhoto(fileName)
            }
        }

        // Cancel any scheduled reminder notification
        if let notificationId = message.notificationId {
            NotificationService.shared.cancelReminder(notificationId: notificationId)
        }

        // Store for undo (don't delete media yet)
        DeletedMessageStore.shared.store(message)

        // Delete from database (media kept for potential restore)
        modelContext.delete(message)
        try? modelContext.save()
    }

    private func moveMessage(_ message: Message, toTabId targetTabId: UUID?) {
        message.tabId = targetTabId
        try? modelContext.save()
        reloadTrigger += 1
    }

    private func sendTaskListMessage(title: String?, items: [TodoItem]) {
        guard !items.isEmpty else { return }

        let message = Message(content: "", tabId: currentTabId)
        message.todoTitle = title
        message.todoItems = items
        modelContext.insert(message)
        try? modelContext.save()
    }

    private func updateTaskList(message: Message, newTitle: String?, newItems: [TodoItem]) {
        if newItems.isEmpty {
            // Delete message if all items removed
            modelContext.delete(message)
        } else {
            message.todoTitle = newTitle
            message.todoItems = newItems
        }
        try? modelContext.save()
        reloadTrigger += 1
    }

    private func toggleTodoItem(message: Message, itemId: UUID, isCompleted: Bool) {
        guard var items = message.todoItems,
              let index = items.firstIndex(where: { $0.id == itemId }) else { return }
        items[index].isCompleted = isCompleted
        message.todoItems = items
        try? modelContext.save()
        reloadTrigger += 1
    }

    private func saveReminder(message: Message, date: Date, repeatInterval: ReminderRepeatInterval) {
        // Schedule new notification first to avoid losing an existing one on failure.
        Task {
            if let notificationId = await NotificationService.shared.scheduleReminder(
                for: message,
                date: date,
                repeatInterval: repeatInterval
            ) {
                await MainActor.run {
                    if let existingId = message.notificationId, existingId != notificationId {
                        NotificationService.shared.cancelReminder(notificationId: existingId)
                    }
                    message.reminderDate = date
                    message.reminderRepeatInterval = repeatInterval
                    message.notificationId = notificationId
                    try? modelContext.save()
                }
            }
        }
    }

    private func removeReminder(message: Message) {
        if let notificationId = message.notificationId {
            NotificationService.shared.cancelReminder(notificationId: notificationId)
        }
        message.reminderDate = nil
        message.reminderRepeatInterval = nil
        message.notificationId = nil
        try? modelContext.save()
    }

    private func restoreDeletedMessage() {
        guard let snapshot = DeletedMessageStore.shared.popSnapshot() else { return }

        // Create new message with the snapshot data
        // tabId can be nil (Inbox) or a real tab ID
        let message = Message(
            content: snapshot.content,
            tabId: snapshot.tabId,
            entities: snapshot.entities,
            photoFileNames: snapshot.photoFileNames,
            photoAspectRatios: snapshot.photoAspectRatios,
            videoFileNames: snapshot.videoFileNames,
            videoAspectRatios: snapshot.videoAspectRatios,
            videoDurations: snapshot.videoDurations,
            videoThumbnailFileNames: snapshot.videoThumbnailFileNames,
            position: snapshot.position,
            sourceUrl: snapshot.sourceUrl,
            linkPreview: snapshot.linkPreview,
            mediaGroupId: snapshot.mediaGroupId
        )
        // Restore original creation date
        message.createdAt = snapshot.createdAt
        message.todoItems = snapshot.todoItems
        message.todoTitle = snapshot.todoTitle
        message.reminderDate = nil
        message.reminderRepeatInterval = nil
        message.notificationId = nil

        modelContext.insert(message)
        try? modelContext.save()

        if let reminderDate = snapshot.reminderDate, reminderDate > Date() {
            saveReminder(
                message: message,
                date: reminderDate,
                repeatInterval: snapshot.reminderRepeatInterval ?? .never
            )
        }
    }

    private func createTab(title: String) {
        let maxPosition = tabs.map(\.position).max() ?? -1
        let newTab = Tab(title: title, position: maxPosition + 1)
        modelContext.insert(newTab)
        try? modelContext.save()
        syncTabsToExtension()

        let key = "hasRequestedReviewAfterTabCreate"
        if !UserDefaults.standard.bool(forKey: key) {
            UserDefaults.standard.set(true, forKey: key)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                requestReview()
            }
        }
    }

    private func renameTab(_ tab: Tab, to newTitle: String) {
        tab.title = newTitle
        try? modelContext.save()
        syncTabsToExtension()
    }

    private func deleteTab(_ tab: Tab) {
        // Delete all messages from this tab
        let tabId = tab.id
        let descriptor = FetchDescriptor<Message>(predicate: #Predicate { $0.tabId == tabId })
        if let messages = try? modelContext.fetch(descriptor) {
            // Collect all data we need BEFORE deleting to avoid SwiftData detachment crash
            var photoFilesToDelete: [String] = []
            var videoFilesToDelete: [String] = []
            var thumbnailFilesToDelete: [String] = []
            var notificationIdsToCancel: [String] = []

            for message in messages {
                photoFilesToDelete.append(contentsOf: message.photoFileNames)
                videoFilesToDelete.append(contentsOf: message.videoFileNames)
                thumbnailFilesToDelete.append(contentsOf: message.videoThumbnailFileNames)
                if let notificationId = message.notificationId {
                    notificationIdsToCancel.append(notificationId)
                }
            }

            // Cancel notifications
            NotificationService.shared.cancelReminders(notificationIds: notificationIdsToCancel)

            // Delete messages from context
            for message in messages {
                modelContext.delete(message)
            }

            // Adjust selected index if needed (account for Inbox at index 0)
            if let index = tabs.firstIndex(where: { $0.id == tab.id }) {
                let tabIndex = index + 2  // +2 because 0=Search, 1=Inbox
                if selectedTabIndex >= tabIndex {
                    selectedTabIndex = max(1, selectedTabIndex - 1)
                }
            }

            // Delete tab and save
            modelContext.delete(tab)
            try? modelContext.save()

            // Clean up media files AFTER saving context
            for fileName in photoFilesToDelete {
                SharedPhotoStorage.deletePhoto(fileName)
            }
            for fileName in videoFilesToDelete {
                SharedVideoStorage.deleteVideo(fileName)
            }
            for fileName in thumbnailFilesToDelete {
                SharedPhotoStorage.deletePhoto(fileName)
            }
        } else {
            // No messages, just delete the tab
            if let index = tabs.firstIndex(where: { $0.id == tab.id }) {
                let tabIndex = index + 2
                if selectedTabIndex >= tabIndex {
                    selectedTabIndex = max(1, selectedTabIndex - 1)
                }
            }
            modelContext.delete(tab)
            try? modelContext.save()
        }

        syncTabsToExtension()
    }

    // MARK: - Selection Mode

    private func exitSelectionMode() {
        withAnimation(.easeOut(duration: 0.25)) {
            isSelectionMode = false
            selectedMessageIds.removeAll()
        }
    }

    private func deleteSelectedMessages() {
        let idsToDelete = selectedMessageIds
        let messagesToDelete = allMessages.filter { idsToDelete.contains($0.id) }
        guard !messagesToDelete.isEmpty else {
            exitSelectionMode()
            return
        }
        // Start exit animation immediately so remaining rows can expand while deletion animates.
        exitSelectionMode()

        // Clean up previous deleted message's media (if any)
        if let previousDeleted = DeletedMessageStore.shared.lastDeleted {
            for fileName in previousDeleted.photoFileNames {
                let url = Message.photosDirectory.appendingPathComponent(fileName)
                try? FileManager.default.removeItem(at: url)
            }
            for fileName in previousDeleted.videoFileNames {
                SharedVideoStorage.deleteVideo(fileName)
            }
            for fileName in previousDeleted.videoThumbnailFileNames {
                SharedPhotoStorage.deletePhoto(fileName)
            }
        }

        for message in messagesToDelete {
            if let notificationId = message.notificationId {
                NotificationService.shared.cancelReminder(notificationId: notificationId)
            }
            DeletedMessageStore.shared.store(message)
            modelContext.delete(message)
        }
        try? modelContext.save()
        reloadTrigger += 1
    }

    private func moveSelectedMessages(to targetTabId: UUID?) {
        let messagesToMove = allMessages.filter { selectedMessageIds.contains($0.id) }
        for message in messagesToMove {
            message.tabId = targetTabId
        }
        try? modelContext.save()
        reloadTrigger += 1
        exitSelectionMode()
    }

    /// Sync tabs list to App Group for Share Extension
    private func syncTabsToExtension() {
        // Delay slightly to ensure SwiftData has updated
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
            TabsSync.saveTabs(Array(tabs))
        }
    }
}

// MARK: - Tab Input Sheet (Custom dialog replacing UIAlertController)

struct TabInputSheet: View {
    let title: String
    var subtitle: String? = nil
    let buttonTitle: String
    let initialText: String
    let onDone: (String) -> Void
    var onDismiss: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @State private var text = ""
    @State private var shouldShake = false
    @FocusState private var isFocused: Bool

    @ViewBuilder
    private func controlBackground() -> some View {
        if colorScheme == .light {
            Capsule().fill(Color.black.opacity(0.12))
        } else {
            Capsule().fill(.ultraThinMaterial)
        }
    }

    var body: some View {
        ZStack {
            Color.clear
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismissWithKeyboard() }

            VStack(spacing: 16) {
                // Title
                Text(title)
                    .font(.body.weight(.semibold))

                // Subtitle
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Text field
                TextField(L10n.Tab.titlePlaceholder, text: $text)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background { controlBackground() }
                    .focused($isFocused)
                    .shake(trigger: $shouldShake)
                    .onSubmit { validateAndSubmit() }
                    .onChange(of: text) { oldValue, newValue in
                        var corrected = newValue

                        // Auto-space after leading emoji
                        if oldValue.isEmpty,
                           corrected.count == 1,
                           let first = corrected.first,
                           first.isEmoji {
                            corrected += " "
                        }

                        // Auto-capitalize first letter after "emoji "
                        if corrected.count >= 3,
                           let first = corrected.first, first.isEmoji,
                           corrected.dropFirst().first == " " {
                            let rest = corrected.dropFirst(2)
                            if let letter = rest.first, letter.isLowercase {
                                corrected = String(corrected.prefix(2)) + letter.uppercased() + rest.dropFirst()
                            }
                        }

                        // Length limit
                        if corrected.count > 24 {
                            corrected = String(corrected.prefix(24))
                        }

                        if corrected != newValue {
                            text = corrected
                        }
                    }

                // Buttons
                HStack(spacing: 12) {
                    Button {
                        dismissWithKeyboard()
                    } label: {
                        Text(L10n.Tab.cancel)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(colorScheme == .light ? Color.primary : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .background { controlBackground() }

                    Button {
                        validateAndSubmit()
                    } label: {
                        Text(buttonTitle)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(colorScheme == .light ? Color.primary : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .background { controlBackground() }
                }
            }
            .padding(24)
            .background {
                RoundedRectangle(cornerRadius: 36)
                    .fill(.clear)
                    .glassEffect(.regular, in: .rect(cornerRadius: 36))
            }
            .padding(.horizontal, 40)
        }
        .onAppear {
            text = initialText
            isFocused = true
        }
    }

    private func dismissWithKeyboard() {
        isFocused = false
        onDismiss()
    }

    private func validateAndSubmit() {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        guard !trimmed.isEmpty else {
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
            shouldShake = true
            return
        }
        isFocused = false
        onDismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            onDone(trimmed)
        }
    }
}

// MARK: - Character Emoji Detection

extension Character {
    var isEmoji: Bool {
        guard let firstScalar = unicodeScalars.first else { return false }
        // Single emoji scalar (exclude ASCII digits/symbols that technically have isEmoji)
        if firstScalar.properties.isEmoji && firstScalar.value > 0x238C { return true }
        // Combined emoji (flags, skin tones, ZWJ sequences)
        return unicodeScalars.count > 1 && firstScalar.properties.isEmoji
    }
}

#Preview {
    MainContainerView()
        .modelContainer(for: [Tab.self, Message.self], inMemory: true)
}
