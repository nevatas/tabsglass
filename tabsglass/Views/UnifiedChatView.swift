//  UnifiedChatView.swift
//  tabsglass
//
//  Single input bar with swipeable message tabs
//

import SwiftUI
import SwiftData
import UIKit
import PhotosUI
import AVFoundation
import UniformTypeIdentifiers

// MARK: - SwiftUI Bridge

struct UnifiedChatView: UIViewControllerRepresentable {
    let tabs: [Tab]  // Real tabs only (Inbox is virtual)
    let messages: [Message]  // All messages
    @Binding var selectedIndex: Int  // 0 = Inbox, 1+ = real tabs
    @Binding var messageText: String
    @Binding var switchFraction: CGFloat  // -1.0 to 1.0 swipe progress
    @Binding var attachedImages: [UIImage]
    @Binding var attachedVideos: [AttachedVideo]
    @Binding var formattingEntities: [TextEntity]  // Entities from formatting
    let onSend: () -> Void
    var onDeleteMessage: ((Message) -> Void)?
    var onMoveMessage: ((Message, UUID?) -> Void)?  // UUID? = target tabId (nil = Inbox)
    var onEditMessage: ((Message) -> Void)?
    var onRestoreMessage: (() -> Void)?
    var onShowTaskList: (() -> Void)?
    var onToggleTodoItem: ((Message, UUID, Bool) -> Void)?
    var onToggleReminder: ((Message) -> Void)?

    // Selection mode
    @Binding var isSelectionMode: Bool
    @Binding var selectedMessageIds: Set<UUID>
    var onEnterSelectionMode: ((Message) -> Void)?
    var onToggleMessageSelection: ((UUID, Bool) -> Void)?

    /// Incremented to force UIKit reload when SwiftData mutations aren't detectable via reference comparison
    var reloadTrigger: Int = 0

    func makeUIViewController(context: Context) -> UnifiedChatViewController {
        let vc = UnifiedChatViewController()
        vc.tabs = tabs
        vc.allMessages = messages
        vc.selectedIndex = selectedIndex
        vc.onSend = onSend
        vc.onDeleteMessage = onDeleteMessage
        vc.onMoveMessage = onMoveMessage
        vc.onEditMessage = onEditMessage
        vc.onRestoreMessage = onRestoreMessage
        vc.onShowTaskList = onShowTaskList
        vc.onToggleTodoItem = onToggleTodoItem
        vc.onToggleReminder = onToggleReminder
        vc.onIndexChange = { newIndex in
            selectedIndex = newIndex
        }
        vc.onAnimatedIndexChange = { newIndex in
            withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                selectedIndex = newIndex
            }
        }
        vc.onTextChange = { text in
            messageText = text
        }
        vc.onSwitchFraction = { fraction in
            switchFraction = fraction
        }
        vc.onImagesChange = { images in
            attachedImages = images
        }
        vc.onVideosChange = { videos in
            attachedVideos = videos
        }
        vc.onEntitiesExtracted = { entities in
            formattingEntities = entities
        }
        // Selection mode
        vc.isSelectionMode = isSelectionMode
        vc.selectedMessageIds = selectedMessageIds
        vc.onEnterSelectionMode = onEnterSelectionMode
        vc.onToggleMessageSelection = onToggleMessageSelection
        return vc
    }

    private func makeMessagesContentHash(_ items: [Message]) -> Int {
        var hasher = Hasher()
        hasher.combine(items.count)
        for message in items {
            hasher.combine(message.id)
            hasher.combine(message.tabId)
            hasher.combine(message.content)
            hasher.combine(message.todoTitle)
            hasher.combine(message.todoItems?.count ?? -1)
            hasher.combine(message.hasReminder)
            hasher.combine(message.photoFileNames.count)
            hasher.combine(message.videoFileNames.count)
        }
        return hasher.finalize()
    }

    func updateUIViewController(_ uiViewController: UnifiedChatViewController, context: Context) {
        // Update callbacks (cheap)
        uiViewController.onDeleteMessage = onDeleteMessage
        uiViewController.onMoveMessage = onMoveMessage
        uiViewController.onEditMessage = onEditMessage
        uiViewController.onRestoreMessage = onRestoreMessage
        uiViewController.onShowTaskList = onShowTaskList
        uiViewController.onToggleTodoItem = onToggleTodoItem
        uiViewController.onToggleReminder = onToggleReminder
        uiViewController.onEnterSelectionMode = onEnterSelectionMode
        uiViewController.onToggleMessageSelection = onToggleMessageSelection

        // Selection mode
        if uiViewController.isSelectionMode != isSelectionMode {
            uiViewController.isSelectionMode = isSelectionMode
            uiViewController.selectedMessageIds = selectedMessageIds
        } else if uiViewController.selectedMessageIds != selectedMessageIds {
            uiViewController.updateSelectedMessageIds(selectedMessageIds)
        }

        // MARK: - Performance: Only reload if data actually changed
        // Compare raw counts to detect deletions (don't filter - deleted objects still count)
        let tabCountChanged = uiViewController.tabs.count != tabs.count
        // For content comparison, filter deleted objects to avoid crashes
        let validOldTabs = uiViewController.tabs.filter { $0.modelContext != nil }
        let tabsContentChanged = !validOldTabs.elementsEqual(tabs, by: { $0.id == $1.id && $0.title == $1.title })
        let tabsChanged = tabCountChanged || tabsContentChanged

        // Check if messages changed (IDs compared without filtering — .id is safe on deleted objects)
        let oldIds = Set(uiViewController.allMessages.map { $0.id })
        let newIds = Set(messages.map { $0.id })
        let idsChanged = oldIds != newIds

        // Quick content hash check (catches todo toggles, edits, reminders, etc.)
        // Compare against stored hash from previous reload — NOT recomputed from old array,
        // because SwiftData uses reference types: old and new arrays contain the same objects,
        // so recomputing the hash from the old array would reflect the already-mutated state.
        let newContentHash = makeMessagesContentHash(messages)
        let contentChanged = newContentHash != uiViewController.lastContentHash

        // Explicit reload trigger for bulk operations (move/delete) where reference-type
        // mutations make change detection via hash comparison impossible
        let forceReload = uiViewController.reloadTrigger != reloadTrigger

        // Update tab/message data BEFORE changing page selection so totalTabCount is correct
        if tabsChanged || idsChanged || contentChanged || forceReload {
            uiViewController.tabs = tabs
            uiViewController.allMessages = messages
            uiViewController.lastContentHash = newContentHash
            uiViewController.reloadTrigger = reloadTrigger
        }

        // Tab selection change (after data update so totalTabCount is current)
        let indexChanged = uiViewController.selectedIndex != selectedIndex
        if indexChanged {
            uiViewController.selectedIndex = selectedIndex
        }

        if tabsChanged {
            // Tabs structure changed - reset page view controller (handles selection too)
            uiViewController.handleTabsStructureChange()
        } else if indexChanged {
            uiViewController.updatePageSelection(animated: true)
        } else if idsChanged || contentChanged || forceReload {
            uiViewController.reloadCurrentTab()
        }
    }
}

// MARK: - Unified Chat View Controller

final class UnifiedChatViewController: UIViewController {
    var tabs: [Tab] = []  // Real tabs only (Inbox is virtual)
    var allMessages: [Message] = []  // All messages from SwiftUI
    var selectedIndex: Int = 1  // 0 = Search, 1 = Inbox, 2+ = real tabs
    var reloadTrigger: Int = 0
    var lastContentHash: Int = 0
    var onSend: (() -> Void)?
    var onEntitiesExtracted: (([TextEntity]) -> Void)?

    /// Total tab count including Search and virtual Inbox
    private var totalTabCount: Int { 2 + tabs.count }

    /// Check if currently on Search tab
    private var isOnSearch: Bool { selectedIndex == 0 }
    var onIndexChange: ((Int) -> Void)?
    var onAnimatedIndexChange: ((Int) -> Void)?  // For animated tab switches (e.g., edge swipe to Search)
    var onTextChange: ((String) -> Void)?
    var onSwitchFraction: ((CGFloat) -> Void)?  // -1.0 to 1.0
    private var lastReportedFraction: CGFloat = 0  // For filtering micro-fluctuations
    var onDeleteMessage: ((Message) -> Void)?
    var onMoveMessage: ((Message, UUID?) -> Void)?  // UUID? = target tabId (nil = Inbox)
    var onEditMessage: ((Message) -> Void)?
    var onImagesChange: (([UIImage]) -> Void)?
    var onVideosChange: (([AttachedVideo]) -> Void)?
    var onRestoreMessage: (() -> Void)?
    var onShowTaskList: (() -> Void)?
    var onToggleTodoItem: ((Message, UUID, Bool) -> Void)?
    var onToggleReminder: ((Message) -> Void)?

    // Selection mode
    var isSelectionMode: Bool = false {
        didSet {
            if oldValue != isSelectionMode {
                updateSelectionModeUI()
            }
        }
    }
    var selectedMessageIds: Set<UUID> = []
    var onEnterSelectionMode: ((Message) -> Void)?
    var onToggleMessageSelection: ((UUID, Bool) -> Void)?

    private var pageViewController: UIPageViewController!
    private var messageControllers: [Int: MessageListViewController] = [:]
    let inputContainer = SwiftUIComposerContainer()
    private var searchInputHostingController: UIHostingController<SearchInputWrapper>?
    private var searchText: String = ""
    private var pageScrollView: UIScrollView?
    private var isUserSwiping: Bool = false

    // MARK: - Input Container (Auto Layout)
    private var hasAutoFocused: Bool = false
    private var inputBottomToKeyboard: NSLayoutConstraint?
    private var inputBottomToSafeArea: NSLayoutConstraint?
    private let bottomFadeView = BottomFadeGradientView()
    private var fadeTopAboveComposer: NSLayoutConstraint?  // Top follows above composer

    private let searchInputState = SearchInputState()
    private var searchInputContainer: UIView?
    private var searchBottomToKeyboard: NSLayoutConstraint?
    private var searchBottomToSafeArea: NSLayoutConstraint?

    // Track focus state for keyboard constraint switching
    private var isComposerFocused: Bool = false
    private var isSearchFocused: Bool = false

    // MARK: - Performance Optimization: Cached filtered messages
    private var cachedFilteredMessages: [Message]?
    private var cachedSearchQuery: String = ""
    private var cachedMessagesHash: Int = 0

    private func makeCacheHash(from messages: [Message]) -> Int {
        var hasher = Hasher()
        hasher.combine(messages.count)
        for message in messages where message.modelContext != nil {
            hasher.combine(message.id)
            hasher.combine(message.tabId)
            hasher.combine(message.content)
            hasher.combine(message.todoTitle)
            hasher.combine(message.todoItems?.count ?? -1)
            hasher.combine(message.hasReminder)
            hasher.combine(message.photoFileNames.count)
            hasher.combine(message.videoFileNames.count)
        }
        return hasher.finalize()
    }

    /// Messages matching the current search query (case-insensitive, all tabs) - cached for performance
    private var filteredMessages: [Message] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            cachedFilteredMessages = nil
            cachedSearchQuery = ""
            return []
        }

        // Return cached result if query and messages haven't changed
        let currentHash = makeCacheHash(from: allMessages)
        if query == cachedSearchQuery && currentHash == cachedMessagesHash,
           let cached = cachedFilteredMessages {
            return cached
        }

        // Compute and cache (filter out deleted SwiftData objects)
        let result = allMessages.filter { message in
            // Skip deleted objects
            guard message.modelContext != nil else { return false }
            // Search in text content
            if message.content.localizedCaseInsensitiveContains(query) {
                return true
            }
            // Search in todo title
            if let todoTitle = message.todoTitle,
               todoTitle.localizedCaseInsensitiveContains(query) {
                return true
            }
            // Search in todo items
            if let todoItems = message.todoItems {
                for item in todoItems {
                    if item.text.localizedCaseInsensitiveContains(query) {
                        return true
                    }
                }
            }
            return false
        }

        cachedFilteredMessages = result
        cachedSearchQuery = query
        cachedMessagesHash = currentHash
        return result
    }

    /// Invalidate filtered messages cache (call when messages change)
    private func invalidateFilteredMessagesCache() {
        cachedFilteredMessages = nil
        cachedSearchQuery = ""
        cachedMessagesHash = 0
    }

    // MARK: - Performance Optimization: Cached per-tab messages
    private var cachedTabMessages: [UUID?: [Message]] = [:]
    private var cachedTabMessagesHash: Int = 0

    /// Get messages for a specific tab (cached for performance during swipes)
    private func messagesForTab(_ tabId: UUID?) -> [Message] {
        let currentHash = makeCacheHash(from: allMessages)

        // Invalidate cache if messages count changed
        if currentHash != cachedTabMessagesHash {
            cachedTabMessages.removeAll()
            cachedTabMessagesHash = currentHash
        }

        // Return cached result if available
        if let cached = cachedTabMessages[tabId] {
            return cached
        }

        // Compute and cache (filter out deleted SwiftData objects)
        let result = allMessages.filter { $0.modelContext != nil && $0.tabId == tabId }
        cachedTabMessages[tabId] = result
        return result
    }

    /// Invalidate per-tab messages cache
    private func invalidateTabMessagesCache() {
        cachedTabMessages.removeAll()
        cachedTabMessagesHash = 0
    }

    /// Update search tab with filtered messages
    private func updateSearchResults() {
        guard let searchVC = messageControllers[0] else { return }
        searchVC.messages = filteredMessages
        searchVC.reloadMessages()

        // Always show when no search text (tips/tabs handle keyboard state internally)
        searchVC.setSearchTabsVisible(searchText.isEmpty, animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.clipsToBounds = false
        setupPageViewController()
        setupInputView()
        setupSearchInput()
        setupEdgeSwipeToSearch()
        // Search tabs are now embedded in MessageListViewController for the search tab
        // This allows swipe gestures to work properly
        updateInputVisibility(animated: false)
    }

    /// Setup left edge swipe gesture to navigate to Search from any tab
    private func setupEdgeSwipeToSearch() {
        let edgeSwipe = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleLeftEdgeSwipe(_:)))
        edgeSwipe.edges = .left
        edgeSwipe.delegate = self
        view.addGestureRecognizer(edgeSwipe)

        // Make page scroll view's pan gesture require edge swipe to fail first
        if let scrollView = pageScrollView {
            for gesture in scrollView.gestureRecognizers ?? [] {
                if let panGesture = gesture as? UIPanGestureRecognizer {
                    panGesture.require(toFail: edgeSwipe)
                }
            }
        }
    }

    @objc private func handleLeftEdgeSwipe(_ gesture: UIScreenEdgePanGestureRecognizer) {
        // Navigate to Search on swipe completion (same as tapping search icon in tab bar)
        guard gesture.state == .ended else { return }
        guard selectedIndex != 0 else { return }

        let translation = gesture.translation(in: view).x
        let velocity = gesture.velocity(in: view).x

        // Complete navigation if swiped enough or with enough velocity
        if translation > 50 || velocity > 300 {
            // Use animated callback to trigger SwiftUI animation (same as tapping search icon)
            onAnimatedIndexChange?(0)
        }
    }

    private func setupPageViewController() {
        pageViewController = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal
        )
        pageViewController.dataSource = self
        pageViewController.delegate = self

        addChild(pageViewController)
        view.addSubview(pageViewController.view)
        pageViewController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            pageViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        pageViewController.didMove(toParent: self)

        // Find the scroll view inside UIPageViewController to track swipe progress
        // Also disable clipping to allow reminder badges to extend outside cell bounds
        pageViewController.view.clipsToBounds = false
        for subview in pageViewController.view.subviews {
            subview.clipsToBounds = false
            if let scrollView = subview as? UIScrollView {
                pageScrollView = scrollView
                scrollView.delegate = self
                // Disable clipping on all scroll view subviews (page containers)
                for pageContainer in scrollView.subviews {
                    pageContainer.clipsToBounds = false
                }
            }
        }

        // Set initial page (always show Inbox at index 1, Search is at index 0)
        let initialVC = getMessageController(for: selectedIndex)
        pageViewController.setViewControllers([initialVC], direction: .forward, animated: false)

        // Preload adjacent tabs for smooth initial swiping
        preloadAdjacentTabs()
    }

    private func setupInputView() {
        inputContainer.translatesAutoresizingMaskIntoConstraints = false
        inputContainer.onTextChange = { [weak self] text in
            self?.onTextChange?(text)
        }

        // Height changes now handled by Auto Layout + intrinsicContentSize
        inputContainer.onHeightChange = { [weak self] _ in
            self?.updateAllContentInsets()
        }

        inputContainer.onSend = { [weak self] in
            guard let self = self else { return }
            // Extract formatting entities before clearing
            self.onEntitiesExtracted?(self.inputContainer.extractEntities())
            self.onSend?()
            self.inputContainer.clearText()
            self.reloadCurrentTab()
            DispatchQueue.main.async {
                self.updateAllContentInsets()
                self.scrollToBottom(animated: true)
            }
        }

        inputContainer.onFocusChange = { [weak self] isFocused in
            guard let self = self else { return }
            self.isComposerFocused = isFocused
            self.updateKeyboardConstraint(followKeyboard: isFocused)
        }

        inputContainer.onShowPhotoPicker = { [weak self] in
            self?.showPhotoPicker()
        }

        inputContainer.onShowCamera = { [weak self] in
            self?.showCamera()
        }

        inputContainer.onShowTaskList = { [weak self] in
            self?.onShowTaskList?()
        }

        inputContainer.onImagesChange = { [weak self] images in
            self?.onImagesChange?(images)
        }

        inputContainer.onVideosChange = { [weak self] videos in
            self?.onVideosChange?(videos)
        }

        // Bottom fade gradient (behind inputContainer, at screen/keyboard bottom)
        bottomFadeView.translatesAutoresizingMaskIntoConstraints = false
        bottomFadeView.isUserInteractionEnabled = false
        view.addSubview(bottomFadeView)

        view.addSubview(inputContainer)

        // Create bottom constraints for input container
        inputBottomToKeyboard = inputContainer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        inputBottomToSafeArea = inputContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)

        // Create constraint for fade gradient top (follows above composer)
        fadeTopAboveComposer = bottomFadeView.topAnchor.constraint(equalTo: inputContainer.topAnchor, constant: -15)

        // Auto Layout: pin leading, trailing, and bottom (start with safe area)
        NSLayoutConstraint.activate([
            inputContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            // Bottom fade gradient constraints - extends beyond safe area to screen edge
            bottomFadeView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomFadeView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomFadeView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 50)
        ])
        inputBottomToSafeArea?.isActive = true
        fadeTopAboveComposer?.isActive = true
    }

    /// Switch between keyboard-following and safe-area-anchored modes
    private func updateKeyboardConstraint(followKeyboard: Bool) {
        if followKeyboard {
            inputBottomToSafeArea?.isActive = false
            inputBottomToKeyboard?.isActive = true
        } else {
            inputBottomToKeyboard?.isActive = false
            inputBottomToSafeArea?.isActive = true
        }
        // Gradient top follows composer via fadeTopAboveComposer constraint
        // Bottom is always at screen edge
    }

    private func setupSearchInput() {
        let searchInputView = SearchInputWrapper(state: searchInputState)
        let hostingController = UIHostingController(rootView: searchInputView)
        hostingController.view.backgroundColor = .clear

        addChild(hostingController)

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .clear
        container.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(container)

        // Create bottom constraints (similar to composer)
        searchBottomToKeyboard = container.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        searchBottomToSafeArea = container.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: container.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        searchBottomToSafeArea?.isActive = true

        hostingController.didMove(toParent: self)

        searchInputHostingController = hostingController
        searchInputContainer = container

        // Track focus changes to follow keyboard
        searchInputState.onFocusChange = { [weak self] isFocused in
            guard let self = self else { return }
            self.isSearchFocused = isFocused
            self.updateSearchKeyboardConstraint(followKeyboard: isFocused)
        }

        // Track text changes to update search results
        searchInputState.onTextChange = { [weak self] newText in
            guard let self = self else { return }
            self.searchText = newText
            self.updateSearchResults()
        }

        // Search input starts with interaction disabled - updateInputVisibility will enable when on Search
        container.isUserInteractionEnabled = false
        hostingController.view.isUserInteractionEnabled = false
    }

    /// Switch search input between keyboard-following and safe-area-anchored modes
    private func updateSearchKeyboardConstraint(followKeyboard: Bool) {
        if followKeyboard {
            searchBottomToSafeArea?.isActive = false
            searchBottomToKeyboard?.isActive = true
        } else {
            searchBottomToKeyboard?.isActive = false
            searchBottomToSafeArea?.isActive = true
        }
        // Always show when no search text (tips/tabs handle keyboard state internally)
        if let searchVC = messageControllers[0] {
            searchVC.setSearchTabsVisible(searchText.isEmpty, animated: true)
        }
    }

    /// Update input positions based on swipe fraction (-1 to 1)
    /// Called during page swipe to sync input sliding with page transition
    func updateInputPositions(fraction: CGFloat) {
        guard !isSelectionMode else { return }

        let screenWidth = view.bounds.width
        guard screenWidth > 0 else { return }

        // Calculate positions based on current tab and swipe direction
        // selectedIndex: 0 = Search, 1 = Inbox, 2+ = tabs
        // fraction: negative = swiping toward previous (lower index), positive = toward next (higher index)
        // Search is LEFT of Inbox, so:
        //   - Swiping from Search to Inbox: search slides left, composer slides in from right
        //   - Swiping from Inbox to Search: composer slides right, search slides in from left

        let composerOffset: CGFloat
        let searchOffset: CGFloat

        if selectedIndex == 0 {
            // On Search tab, swiping right (fraction > 0) → to Inbox
            // Search slides left (off-screen), composer comes from right
            composerOffset = (1 - fraction) * screenWidth  // screenWidth → 0
            searchOffset = -fraction * screenWidth         // 0 → -screenWidth
        } else if selectedIndex == 1 && fraction < 0 {
            // On Inbox, swiping left (fraction < 0) → to Search
            // Composer slides right (off-screen), search comes from left
            composerOffset = -fraction * screenWidth              // 0 → screenWidth
            searchOffset = -(1 + fraction) * screenWidth          // -screenWidth → 0
        } else {
            // On Inbox swiping right (to real tabs) OR on real tabs
            // Composer doesn't move, search stays off-screen left
            composerOffset = 0
            searchOffset = -screenWidth
        }

        inputContainer.transform = CGAffineTransform(translationX: composerOffset, y: 0)
        searchInputContainer?.transform = CGAffineTransform(translationX: searchOffset, y: 0)
        searchInputContainer?.alpha = 1  // Always visible, position determines visibility
    }

    /// Finalize input visibility after swipe completes
    private func updateInputVisibility(animated: Bool) {
        guard !isSelectionMode else {
            // In selection mode, hide both inputs immediately
            inputContainer.isUserInteractionEnabled = false
            searchInputContainer?.isUserInteractionEnabled = false
            searchInputHostingController?.view.isUserInteractionEnabled = false

            let changes = {
                self.inputContainer.alpha = 0
                self.searchInputContainer?.alpha = 0
            }
            if animated {
                UIView.animate(withDuration: 0.25, animations: changes)
            } else {
                changes()
            }
            return
        }

        // Use screen width as fallback if view hasn't laid out yet
        let screenWidth = view.bounds.width > 0 ? view.bounds.width : (view.window?.windowScene?.screen.bounds.width ?? 390)
        let showSearch = isOnSearch

        // Set interaction state immediately (not in animation block)
        inputContainer.isUserInteractionEnabled = !showSearch
        searchInputContainer?.isUserInteractionEnabled = showSearch
        searchInputHostingController?.view.isUserInteractionEnabled = showSearch

        let changes = {
            // Composer slides off-screen right when on Search, otherwise stays in place
            self.inputContainer.transform = showSearch
                ? CGAffineTransform(translationX: screenWidth, y: 0)
                : .identity

            // Search input slides off-screen left when not on Search, otherwise stays in place
            self.searchInputContainer?.transform = showSearch
                ? .identity
                : CGAffineTransform(translationX: -screenWidth, y: 0)

            // Both stay visible (alpha = 1), position determines visibility
            self.inputContainer.alpha = 1
            self.searchInputContainer?.alpha = 1
        }

        if animated {
            UIView.animate(withDuration: 0.25, animations: changes)
        } else {
            changes()
        }
    }

    private func updateAllContentInsets(animated: Bool = false) {
        // Calculate bottom padding from actual input container position
        view.layoutIfNeeded() // Ensure layout is up to date
        let inputBottom = view.bounds.height - inputContainer.frame.minY
        let safeAreaBottom = view.safeAreaInsets.bottom
        messageControllers.values.forEach {
            $0.updateContentInset(bottomPadding: inputBottom, safeAreaBottom: safeAreaBottom, animated: animated)
        }
    }

    private func resetComposerPosition() {
        // Just dismiss keyboard - Auto Layout handles positioning
        view.endEditing(true)
        updateAllContentInsets()
    }

    // MARK: - Scroll to Bottom

    private func scrollToBottom(animated: Bool) {
        if let currentVC = pageViewController.viewControllers?.first as? MessageListViewController {
            currentVC.scrollToBottom(animated: animated)
        }
    }

    /// Calculate tabId for given index: 0 = Search (nil), 1 = Inbox (nil), 2+ = real tab ID
    private func tabId(for index: Int) -> UUID? {
        guard index > 1 && index <= tabs.count + 1 else { return nil }
        return tabs[index - 2].id
    }

    // MARK: - Performance Logging
    private let perfLogEnabled = false
    private func perfLog(_ message: String, duration: CFAbsoluteTime? = nil) {
        guard perfLogEnabled else { return }
        if let duration = duration {
            let ms = duration * 1000
            if ms > 1 { // Only log if > 1ms
                print("⏱️ [PERF] \(message): \(String(format: "%.2f", ms))ms")
            }
        } else {
            print("📍 [PERF] \(message)")
        }
    }

    private func getMessageController(for index: Int) -> MessageListViewController {
        let start = CFAbsoluteTimeGetCurrent()

        let currentTabId = tabId(for: index)
        // Search tab (index 0) shows filtered search results
        let tabMessages = index == 0 ? filteredMessages : messagesForTab(currentTabId)

        if let existing = messageControllers[index] {
            existing.allTabs = tabs
            existing.currentTabId = currentTabId
            existing.messages = tabMessages
            existing.onContextMenuWillShow = { [weak self] in
                self?.resetComposerPosition()
            }
            // Update search tabs if this is the search tab
            if index == 0 {
                existing.updateSearchTabs(tabs: tabs)
            }
            perfLog("getMessageController(cached) index=\(index) msgs=\(tabMessages.count)", duration: CFAbsoluteTimeGetCurrent() - start)
            return existing
        }

        let vc = MessageListViewController()
        vc.pageIndex = index
        vc.isSearchTab = (index == 0)
        vc.currentTabId = currentTabId
        vc.allTabs = tabs
        vc.messages = tabMessages
        vc.onTap = { [weak self] in
            self?.view.endEditing(true)
        }
        vc.onContextMenuWillShow = { [weak self] in
            self?.resetComposerPosition()
        }
        vc.getBottomPadding = { [weak self] in
            guard let self = self else { return 80 }
            return self.view.bounds.height - self.inputContainer.frame.minY
        }
        vc.getSafeAreaBottom = { [weak self] in
            self?.view.safeAreaInsets.bottom ?? 0
        }
        vc.onDeleteMessage = { [weak self] message in
            self?.onDeleteMessage?(message)
        }
        vc.onMoveMessage = { [weak self] message, targetTabId in
            self?.onMoveMessage?(message, targetTabId)
        }
        vc.onEditMessage = { [weak self] message in
            self?.onEditMessage?(message)
        }
        vc.onOpenGallery = { [weak self] message, startIndex, sourceFrame in
            self?.presentGallery(message: message, startIndex: startIndex, sourceFrame: sourceFrame)
        }
        vc.onToggleTodoItem = { [weak self] message, itemId, isCompleted in
            self?.onToggleTodoItem?(message, itemId, isCompleted)
        }
        vc.onToggleReminder = { [weak self] message in
            self?.onToggleReminder?(message)
        }
        // Selection mode
        vc.isSelectionMode = isSelectionMode
        vc.selectedMessageIds = selectedMessageIds
        vc.onEnterSelectionMode = onEnterSelectionMode
        vc.onToggleMessageSelection = onToggleMessageSelection

        // Search tab: callback for when a tab button is tapped
        if index == 0 {
            vc.onTabSelected = { [weak self] tabIndex, messageId in
                guard let self = self else { return }
                self.selectedIndex = tabIndex
                self.onIndexChange?(tabIndex)
                self.updatePageSelection(animated: true)

                // Scroll to specific message after navigation completes
                if let messageId = messageId {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        if let targetVC = self.messageControllers[tabIndex] {
                            targetVC.scrollToMessage(id: messageId, animated: true)
                        }
                    }
                }
            }
        }

        messageControllers[index] = vc
        perfLog("getMessageController(NEW) index=\(index) msgs=\(tabMessages.count)", duration: CFAbsoluteTimeGetCurrent() - start)
        return vc
    }

    // MARK: - Performance Optimization: Preload adjacent tabs

    /// Preload view controllers for adjacent tabs to ensure smooth swiping
    private func preloadAdjacentTabs() {
        // Skip preloading during active swipe to avoid competing with animation
        guard !isUserSwiping else { return }

        // Preload in next run loop to avoid blocking current frame
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isUserSwiping else { return }

            let bounds = self.pageViewController.view.bounds
            let indicesToPreload = [
                self.selectedIndex - 1,
                self.selectedIndex + 1
            ].filter { $0 >= 0 && $0 < self.totalTabCount }

            for index in indicesToPreload {
                let vc: MessageListViewController
                if let existing = self.messageControllers[index] {
                    vc = existing
                } else {
                    vc = self.getMessageController(for: index)
                }
                vc.prewarmCells(in: bounds)
            }
        }
    }

    func updatePageSelection(animated: Bool) {
        guard selectedIndex < totalTabCount else { return }
        let vc = getMessageController(for: selectedIndex)

        // Determine direction based on current position
        if let currentVC = pageViewController.viewControllers?.first as? MessageListViewController {
            let previousIndex = currentVC.pageIndex
            let direction: UIPageViewController.NavigationDirection = selectedIndex > previousIndex ? .forward : .reverse

            // For programmatic changes, animate input positions in sync with page transition
            if animated && (previousIndex <= 1 || selectedIndex <= 1) {
                // Animate inputs when transitioning to/from Search or Inbox
                UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                    self.updateInputVisibility(animated: false)
                }
            } else {
                updateInputVisibility(animated: animated)
            }

            if animated {
                // Disable interaction during programmatic page transition
                // to prevent user from interrupting the animation and causing
                // desync between tab bar selection and displayed content
                pageViewController.view.isUserInteractionEnabled = false
                pageViewController.setViewControllers([vc], direction: direction, animated: true) { [weak self] _ in
                    self?.pageViewController.view.isUserInteractionEnabled = true
                }
            } else {
                pageViewController.setViewControllers([vc], direction: direction, animated: false)
            }
        } else {
            pageViewController.setViewControllers([vc], direction: .forward, animated: false)
            updateInputVisibility(animated: false)
        }
        preloadAdjacentTabs()
    }

    func reloadCurrentTab() {
        // Invalidate caches when reloading (data may have changed)
        invalidateTabMessagesCache()
        invalidateFilteredMessagesCache()

        if let currentVC = pageViewController.viewControllers?.first as? MessageListViewController {
            let currentIndex = currentVC.pageIndex
            if currentIndex < totalTabCount {
                currentVC.currentTabId = tabId(for: currentIndex)
                currentVC.allTabs = tabs
                let msgs = currentIndex == 0 ? filteredMessages : messagesForTab(currentVC.currentTabId)
                currentVC.messages = msgs
                currentVC.reloadMessages(invalidateHeights: true)
            }

            // Also refresh adjacent cached controllers (UIPageViewController may serve them
            // from its internal cache without calling the data source)
            for adjacentIndex in [currentIndex - 1, currentIndex + 1] {
                guard adjacentIndex >= 0, adjacentIndex < totalTabCount,
                      let cachedVC = messageControllers[adjacentIndex] else { continue }
                let adjTabId = tabId(for: adjacentIndex)
                cachedVC.currentTabId = adjTabId
                cachedVC.allTabs = tabs
                cachedVC.messages = adjacentIndex == 0 ? filteredMessages : messagesForTab(adjTabId)
                cachedVC.reloadMessages(invalidateHeights: true)
            }
        } else {
        }
    }

    /// Called when tabs are added or removed - clears caches and resets page view controller
    func handleTabsStructureChange() {
        // Invalidate all caches
        invalidateTabMessagesCache()

        // Clear cached controllers for indexes that no longer exist
        let maxValidIndex = totalTabCount - 1
        messageControllers = messageControllers.filter { $0.key <= maxValidIndex }

        // Ensure selectedIndex is within bounds
        if selectedIndex >= totalTabCount {
            selectedIndex = max(1, totalTabCount - 1)  // Go to last valid tab or Inbox
            onIndexChange?(selectedIndex)
        }

        // Update search tab's tabs list
        if let searchVC = messageControllers[0] {
            searchVC.allTabs = tabs
            searchVC.reloadMessages()
        }

        // Reset page view controller to current valid index
        let vc = getMessageController(for: selectedIndex)
        pageViewController.setViewControllers([vc], direction: .forward, animated: false)

        // Update current tab
        reloadCurrentTab()
    }

    // MARK: - Selection Mode

    private func updateSelectionModeUI() {
        // Update composer/search input visibility
        updateInputVisibility(animated: true)

        // Block/unblock page swiping
        pageScrollView?.isScrollEnabled = !isSelectionMode

        // Update all visible message controllers
        for (_, vc) in messageControllers {
            vc.isSelectionMode = isSelectionMode
            vc.selectedMessageIds = selectedMessageIds
            vc.onEnterSelectionMode = onEnterSelectionMode
            vc.onToggleMessageSelection = onToggleMessageSelection
            vc.updateSelectionMode(isSelectionMode)
        }
    }

    func updateSelectedMessageIds(_ ids: Set<UUID>) {
        selectedMessageIds = ids
        for (_, vc) in messageControllers {
            vc.updateSelectedMessageIds(ids)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateAllContentInsets()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Auto-focus composer on first appearance (if enabled in settings)
        if !hasAutoFocused && AppSettings.shared.autoFocusInput {
            hasAutoFocused = true
            // Small delay to ensure view is fully laid out
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.inputContainer.focus()
            }
        }
    }

    // MARK: - Shake to Undo

    override var canBecomeFirstResponder: Bool { true }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        guard motion == .motionShake else { return }

        // Check if we can undo in current tab
        guard selectedIndex < totalTabCount else { return }
        let currentTabId = tabId(for: selectedIndex)

        guard DeletedMessageStore.shared.canUndo(forTabId: currentTabId) else { return }

        // Show confirmation alert
        let alert = UIAlertController(
            title: L10n.Menu.restoreTitle,
            message: L10n.Menu.restoreMessage,
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: L10n.Tab.cancel, style: .cancel))
        alert.addAction(UIAlertAction(title: L10n.Menu.restore, style: .default) { [weak self] _ in
            self?.onRestoreMessage?()
        })

        present(alert, animated: true)
    }

    // MARK: - Media Picker

    private func showPhotoPicker() {
        var config = PHPickerConfiguration()
        config.selectionLimit = 10 - inputContainer.totalMediaCount
        config.filter = .any(of: [.images, .videos])  // Support both photos and videos
        config.preferredAssetRepresentationMode = .current  // Avoid unnecessary conversion

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    // MARK: - Camera

    private func showCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return }

        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        present(picker, animated: true)
    }

    // MARK: - Gallery

    private func presentGallery(message: Message, startIndex: Int, sourceFrame: CGRect) {
        let totalMedia = message.totalMediaCount
        guard totalMedia > 0, startIndex < totalMedia else { return }

        // Load all media asynchronously
        let group = DispatchGroup()
        var loadedMedia: [Int: GalleryMediaItem] = [:]

        // Load photos
        for (index, fileName) in message.photoFileNames.enumerated() {
            group.enter()
            ImageCache.shared.loadFullImage(for: fileName) { image in
                if let image = image {
                    loadedMedia[index] = .photo(image: image)
                }
                group.leave()
            }
        }

        // Load video thumbnails and prepare video items
        let photoCount = message.photoFileNames.count
        for (videoIndex, videoFileName) in message.videoFileNames.enumerated() {
            let mediaIndex = photoCount + videoIndex
            let videoURL = SharedVideoStorage.videoURL(for: videoFileName)

            // Load thumbnail if available
            if videoIndex < message.videoThumbnailFileNames.count {
                let thumbFileName = message.videoThumbnailFileNames[videoIndex]
                group.enter()
                ImageCache.shared.loadFullImage(for: thumbFileName) { thumbnail in
                    loadedMedia[mediaIndex] = .video(url: videoURL, thumbnail: thumbnail)
                    group.leave()
                }
            } else {
                loadedMedia[mediaIndex] = .video(url: videoURL, thumbnail: nil)
            }
        }

        group.notify(queue: .main) { [weak self] in
            // Convert to ordered array
            let mediaItems = (0..<totalMedia).compactMap { loadedMedia[$0] }
            guard !mediaItems.isEmpty, startIndex < mediaItems.count else { return }

            // Get source image for transition
            let sourceImage = mediaItems[startIndex].thumbnail

            let galleryVC = GalleryViewController(
                mediaItems: mediaItems,
                startIndex: startIndex,
                sourceFrame: sourceFrame,
                sourceImage: sourceImage
            )
            self?.present(galleryVC, animated: true)
        }
    }

}

// MARK: - PHPickerViewControllerDelegate

extension UnifiedChatViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        guard !results.isEmpty else { return }

        Task { @MainActor in
            for result in results {
                let provider = result.itemProvider

                // Check for video first
                if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    await loadVideo(from: provider)
                }
                // Then check for images
                else if provider.canLoadObject(ofClass: UIImage.self) {
                    await loadImage(from: provider)
                }
            }
        }
    }

    @MainActor
    private func loadImage(from provider: NSItemProvider) async {
        await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                if let image = object as? UIImage {
                    DispatchQueue.main.async {
                        self?.inputContainer.addImages([image])
                        self?.onImagesChange?(self?.inputContainer.attachedImages ?? [])
                    }
                }
                continuation.resume()
            }
        }
    }

    @MainActor
    private func loadVideo(from provider: NSItemProvider) async {
        // Use loadFileRepresentation to avoid loading video into memory
        await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, error in
                guard let url = url else {
                    continuation.resume()
                    return
                }

                // Copy to temporary directory (url will be deleted after callback)
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + ".mp4")
                do {
                    try FileManager.default.copyItem(at: url, to: tempURL)
                } catch {
                    continuation.resume()
                    return
                }

                Task { @MainActor in
                    // Generate thumbnail and get metadata
                    let asset = AVURLAsset(url: tempURL)

                    // Check duration limit
                    let duration = await SharedVideoStorage.loadDuration(asset)
                    guard duration > 0 && duration <= SharedVideoStorage.maxVideoDuration else {
                        try? FileManager.default.removeItem(at: tempURL)
                        continuation.resume()
                        return
                    }

                    // Generate thumbnail
                    guard let thumbnail = await SharedVideoStorage.generateThumbnail(asset) else {
                        try? FileManager.default.removeItem(at: tempURL)
                        continuation.resume()
                        return
                    }

                    let video = AttachedVideo(
                        url: tempURL,
                        thumbnail: thumbnail,
                        duration: duration
                    )

                    self?.inputContainer.addVideo(video)
                    self?.onVideosChange?(self?.inputContainer.attachedVideos ?? [])
                    continuation.resume()
                }
            }
        }
    }
}

// MARK: - UIImagePickerControllerDelegate

extension UnifiedChatViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true)

        if let image = info[.originalImage] as? UIImage {
            inputContainer.addImages([image])
            onImagesChange?(inputContainer.attachedImages)
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

// MARK: - UIPageViewController DataSource & Delegate

extension UnifiedChatViewController: UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let vc = viewController as? MessageListViewController else { return nil }
        let index = vc.pageIndex - 1
        guard index >= 0 else { return nil }
        return getMessageController(for: index)
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let vc = viewController as? MessageListViewController else { return nil }
        let index = vc.pageIndex + 1
        guard index < totalTabCount else { return nil }
        return getMessageController(for: index)
    }

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed,
              let currentVC = pageViewController.viewControllers?.first as? MessageListViewController else { return }

        // IMPORTANT: Reset switchFraction BEFORE changing selectedIndex
        // This prevents the tab bar indicator from jumping to wrong position
        // (e.g., when selectedIndex=1 and fraction=0.99, it would calculate targetIndex=2)
        onSwitchFraction?(0)

        selectedIndex = currentVC.pageIndex
        onIndexChange?(selectedIndex)
        updateInputVisibility(animated: true)
        preloadAdjacentTabs()
    }
}

// MARK: - UIGestureRecognizerDelegate (Edge Swipe)

extension UnifiedChatViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Disable edge swipe on Search (index 0) and Inbox (index 1) - let normal swipe work
        if gestureRecognizer is UIScreenEdgePanGestureRecognizer {
            return selectedIndex > 1
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Edge swipe should NOT work simultaneously with page scroll - it takes priority
        if gestureRecognizer is UIScreenEdgePanGestureRecognizer {
            return false
        }
        return true
    }
}

// MARK: - UIScrollViewDelegate (Page Swipe Progress)

extension UnifiedChatViewController: UIScrollViewDelegate {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard scrollView === pageScrollView else { return }
        isUserSwiping = true
        lastReportedFraction = 0

        // Ensure all page containers have clipping disabled (for reminder badges)
        for subview in scrollView.subviews {
            subview.clipsToBounds = false
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === pageScrollView, isUserSwiping else { return }

        let pageWidth = scrollView.bounds.width
        guard pageWidth > 0 else { return }

        // contentOffset.x is pageWidth when at rest (center page)
        // < pageWidth = swiping right (to previous), > pageWidth = swiping left (to next)
        let offset = scrollView.contentOffset.x - pageWidth
        let fraction = offset / pageWidth

        // fraction: -1 = fully swiped to previous, 0 = center, +1 = fully swiped to next
        let clampedFraction = max(-1, min(1, fraction))

        // Filter out micro-fluctuations (e.g., from keyboard dismissal)
        // Only report changes larger than 1% or direction changes
        let delta = abs(clampedFraction - lastReportedFraction)
        let directionChanged = (clampedFraction > 0) != (lastReportedFraction > 0) && lastReportedFraction != 0
        if delta > 0.01 || directionChanged {
            lastReportedFraction = clampedFraction
            onSwitchFraction?(clampedFraction)
        }

        // Sync input sliding with page swipe (always update for smooth input movement)
        updateInputPositions(fraction: clampedFraction)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === pageScrollView else { return }
        isUserSwiping = false
        lastReportedFraction = 0
        onSwitchFraction?(0)  // Reset fraction when swipe completes
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView === pageScrollView else { return }
        if !decelerate {
            isUserSwiping = false
            lastReportedFraction = 0
            onSwitchFraction?(0)  // Reset fraction when drag ends without deceleration
        }
    }
}

// MARK: - Message List View Controller

final class MessageListViewController: UIViewController {
    var pageIndex: Int = 0  // 0 = Search, 1 = Inbox, 2+ = real tabs
    var isSearchTab: Bool = false  // True for Search tab (index 0)
    var currentTabId: UUID?  // nil = Inbox or Search
    var allTabs: [Tab] = []  // Real tabs only
    var messages: [Message] = []  // Messages passed from SwiftUI
    var onTap: (() -> Void)?
    var onContextMenuWillShow: (() -> Void)?
    var getBottomPadding: (() -> CGFloat)?
    var getSafeAreaBottom: (() -> CGFloat)?
    var onDeleteMessage: ((Message) -> Void)?
    var onMoveMessage: ((Message, UUID?) -> Void)?  // UUID? = target tabId (nil = Inbox)
    var onEditMessage: ((Message) -> Void)?
    /// Callback when gallery should be opened: (message, startIndex, sourceFrame)
    var onOpenGallery: ((Message, Int, CGRect) -> Void)?
    /// Callback when a todo item is toggled: (message, itemId, isCompleted)
    var onToggleTodoItem: ((Message, UUID, Bool) -> Void)?
    /// Callback when reminder is toggled on a message
    var onToggleReminder: ((Message) -> Void)?

    // Selection mode
    var isSelectionMode: Bool = false
    var selectedMessageIds: Set<UUID> = []
    var onEnterSelectionMode: ((Message) -> Void)?
    var onToggleMessageSelection: ((UUID, Bool) -> Void)?

    // Search tabs (for search tab only)
    var onTabSelected: ((Int, UUID?) -> Void)?  // Callback when a tab button is tapped (tabIndex, messageId to scroll to)

    private let tableView = UITableView()
    private var sortedMessages: [Message] = []
    private var longPressGesture: UILongPressGestureRecognizer!
    private var dismissKeyboardTapGesture: UITapGestureRecognizer!
    private var hasAppearedBefore = false
    /// IDs of messages that should animate appearance (scale + fade in)
    private var pendingAppearAnimationIds: Set<UUID> = []
    private var isAnimatingFirstMessage = false
    private var isPrewarmed = false
    private var selectionModeExitAnimationDeadline: CFTimeInterval = 0

    // Embedded search tabs for search tab
    private var searchTabsHostingController: UIHostingController<SearchTabsView>?
    private var topFadeGradient: TopFadeGradientView?

    // MARK: - Performance: Height cache
    /// Cache for calculated row heights, keyed by message ID
    private var heightCache: [UUID: CGFloat] = [:]
    /// Width used for cached heights (invalidate on width change)
    private var cachedHeightWidth: CGFloat = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.clipsToBounds = false
        setupTableView()

        // Setup embedded search tabs if this is the search tab
        if isSearchTab {
            setupSearchTabs()
            setupTopFadeGradient()
        }
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.keyboardDismissMode = .interactive
        tableView.showsVerticalScrollIndicator = false
        tableView.clipsToBounds = false
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 200
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(MessageTableCell.self, forCellReuseIdentifier: "MessageCell")
        tableView.register(EmptyTableCell.self, forCellReuseIdentifier: "EmptyCell")
        tableView.register(SearchResultCell.self, forCellReuseIdentifier: "SearchResultCell")
        // Only invert for chat tabs - search tab uses normal top-to-bottom layout
        if !isSearchTab {
            tableView.transform = CGAffineTransform(scaleX: 1, y: -1)
        }

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        dismissKeyboardTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        dismissKeyboardTapGesture.cancelsTouchesInView = false
        tableView.addGestureRecognizer(dismissKeyboardTapGesture)

        // Dismiss keyboard early on long press (before context menu appears)
        longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.3 // Fire before context menu (default ~0.5s)
        longPressGesture.cancelsTouchesInView = false
        longPressGesture.delegate = self
        tableView.addGestureRecognizer(longPressGesture)
    }

    private func setupSearchTabs() {
        let searchTabsView = SearchTabsView(tabs: allTabs) { [weak self] index in
            self?.onTabSelected?(index, nil)
        }

        let hostingController = UIHostingController(rootView: searchTabsView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        hostingController.view.clipsToBounds = false

        addChild(hostingController)
        view.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        hostingController.didMove(toParent: self)
        searchTabsHostingController = hostingController

        // Tap on empty area dismisses keyboard
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.cancelsTouchesInView = false
        hostingController.view.addGestureRecognizer(tap)
    }

    private func setupTopFadeGradient() {
        let gradientView = TopFadeGradientView()
        gradientView.translatesAutoresizingMaskIntoConstraints = false
        gradientView.isUserInteractionEnabled = false
        // Add gradient on top of all content (search tabs and table)
        view.addSubview(gradientView)

        NSLayoutConstraint.activate([
            // Extend above view top to cover full safe area (Dynamic Island, etc.)
            gradientView.topAnchor.constraint(equalTo: view.topAnchor, constant: -100),
            gradientView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gradientView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gradientView.heightAnchor.constraint(equalToConstant: 220)
        ])

        topFadeGradient = gradientView
    }

    /// Update the search tabs with new data
    func updateSearchTabs(tabs: [Tab]) {
        guard isSearchTab, let hostingController = searchTabsHostingController else { return }
        hostingController.rootView = SearchTabsView(tabs: tabs) { [weak self] index in
            self?.onTabSelected?(index, nil)
        }
    }

    /// Show or hide embedded search tabs (for keyboard focus state)
    func setSearchTabsVisible(_ visible: Bool, animated: Bool) {
        guard isSearchTab, let hostingController = searchTabsHostingController else { return }

        if animated {
            UIView.animate(withDuration: 0.25) {
                hostingController.view.alpha = visible ? 1 : 0
            }
        } else {
            hostingController.view.alpha = visible ? 1 : 0
        }
    }

    @objc private func handleTap() {
        onTap?()
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            // Dismiss keyboard and reset composer before context menu appears
            view.window?.endEditing(true)
            onContextMenuWillShow?()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadMessages()
        refreshContentInset()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshContentInset()
        // Only scroll to bottom on first appearance, preserve position on subsequent visits
        if !hasAppearedBefore {
            scrollToBottom(animated: false)
            hasAppearedBefore = true
        }
    }

    /// Pre-create table view cells so they're in the reuse pool before the swipe animation
    func prewarmCells(in bounds: CGRect) {
        guard !isPrewarmed else { return }
        isPrewarmed = true
        loadViewIfNeeded()
        view.frame = bounds
        reloadMessages()
        tableView.setNeedsLayout()
        tableView.layoutIfNeeded()
    }

    private func refreshContentInset() {
        let bottomPadding = getBottomPadding?() ?? 80
        let safeAreaBottom = getSafeAreaBottom?() ?? 0
        updateContentInset(bottomPadding: bottomPadding, safeAreaBottom: safeAreaBottom)
    }

    /// Track last processed message IDs for quick change detection
    private var lastProcessedMessageIds: Set<UUID> = []

    func reloadMessages(invalidateHeights: Bool = false) {
        // Skip if first message animation is in progress
        if isAnimatingFirstMessage { return }

        // Force reload: clear all height caches so cells recalculate
        if invalidateHeights {
            heightCache.removeAll()
        }

        // Filter out deleted SwiftData objects first
        let validMessages = messages.filter { $0.modelContext != nil }

        // Quick optimization: check if message IDs are the same before sorting
        let currentIds = Set(validMessages.map { $0.id })
        let idsMatch = currentIds == lastProcessedMessageIds && currentIds.count == sortedMessages.count
        lastProcessedMessageIds = currentIds

        let newMessages: [Message]

        if idsMatch {
            // IDs match - reuse sorted order, just update content
            let messageById = Dictionary(uniqueKeysWithValues: validMessages.map { ($0.id, $0) })
            newMessages = sortedMessages
                .compactMap { messageById[$0.id] }
                .filter { !$0.isEmpty }
        } else {
            // IDs changed - need full filter and sort, invalidate height cache
            heightCache.removeAll()
            newMessages = validMessages
                .filter { !$0.isEmpty }
                .sorted { $0.createdAt > $1.createdAt }
        }

        // Compare against sortedMessages (what UITableView currently displays)
        // .id is safe to access on deleted SwiftData objects
        let oldIds = sortedMessages.map { $0.id }
        let newIds = newMessages.map { $0.id }

        if oldIds == newIds {
            // Same messages in same order — just reconfigure content
            // (if we're here, all sortedMessages are valid since their IDs match newMessages)
            for (index, newMsg) in newMessages.enumerated() {
                let oldMsg = sortedMessages[index]
                // Check if content that affects height has changed
                if oldMsg.content != newMsg.content ||
                   oldMsg.todoItems?.count != newMsg.todoItems?.count {
                    heightCache.removeValue(forKey: newMsg.id)
                }
            }

            sortedMessages = newMessages
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            UIView.performWithoutAnimation {
                for cell in tableView.visibleCells {
                    guard let messageCell = cell as? MessageTableCell,
                          let indexPath = tableView.indexPath(for: cell),
                          indexPath.row < sortedMessages.count else { continue }
                    messageCell.configure(with: sortedMessages[indexPath.row])
                }
                // Force UITableView to recalculate row heights (e.g., after todo items change)
                tableView.beginUpdates()
                tableView.endUpdates()
            }
            CATransaction.commit()
        } else {
            // Check if this is a simple insertion of new messages at the beginning
            let oldIdSet = Set(oldIds)
            let newIdSet = Set(newIds)
            let newMessageIds = newIds.filter { !oldIdSet.contains($0) }
            let removedMessageIds = oldIds.filter { !newIdSet.contains($0) }
            let isSimpleDeletion = !removedMessageIds.isEmpty &&
                                   newMessageIds.isEmpty &&
                                   oldIds.filter({ newIdSet.contains($0) }).elementsEqual(newIds)
            let isSimpleInsertion = !newMessageIds.isEmpty &&
                                    oldIdSet.subtracting(Set(newIds)).isEmpty &&
                                    newIds.dropFirst(newMessageIds.count).elementsEqual(oldIds)

            if isSimpleDeletion {
                let removedIdSet = Set(removedMessageIds)
                let deleteIndexPaths = oldIds.enumerated().compactMap { index, id in
                    removedIdSet.contains(id) ? IndexPath(row: index, section: 0) : nil
                }

                let visibleCellsToAnimate: [(cell: UITableViewCell, transform: CGAffineTransform)] = deleteIndexPaths.compactMap { indexPath in
                    guard let cell = self.tableView.cellForRow(at: indexPath) else { return nil }
                    return (cell, cell.transform)
                }

                let performDeletion = {
                    self.sortedMessages = newMessages
                    self.tableView.performBatchUpdates({
                        self.tableView.deleteRows(at: deleteIndexPaths, with: .none)
                    }) { _ in
                        for item in visibleCellsToAnimate {
                            item.cell.isHidden = false
                            item.cell.alpha = 1
                            item.cell.transform = item.transform
                        }
                        if self.sortedMessages.isEmpty && !self.isSearchTab {
                            UIView.performWithoutAnimation {
                                self.tableView.reloadData()
                            }
                        }
                    }
                }

                guard !visibleCellsToAnimate.isEmpty else {
                    performDeletion()
                    return
                }

                UIView.animate(withDuration: 0.16, delay: 0, options: [.curveEaseOut]) {
                    for item in visibleCellsToAnimate {
                        item.cell.alpha = 0
                        item.cell.transform = item.transform.scaledBy(x: 0.9, y: 0.9)
                    }
                } completion: { _ in
                    for item in visibleCellsToAnimate {
                        // Keep removed cells hidden during table re-layout to avoid ghost reappearance.
                        item.cell.isHidden = true
                    }
                    performDeletion()
                }
            } else if isSimpleInsertion && !sortedMessages.isEmpty {
                // New messages added at the top (row 0 in inverted table = newest)
                // Mark these messages for appear animation (will be applied in cellForRowAt)
                pendingAppearAnimationIds = Set(newMessageIds)
                sortedMessages = newMessages
                let insertIndexPaths = (0..<newMessageIds.count).map { IndexPath(row: $0, section: 0) }

                // Insert rows - cells will start hidden due to pendingAppearAnimationIds
                tableView.performBatchUpdates({
                    tableView.insertRows(at: insertIndexPaths, with: .none)
                })

                // Start appear animation immediately (in parallel with insert animation)
                // Use async to ensure cells are created first
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.pendingAppearAnimationIds.removeAll()

                    for indexPath in insertIndexPaths {
                        guard let cell = self.tableView.cellForRow(at: indexPath) else { continue }
                        // Search tab uses identity, chat tabs use inverted transform
                        let originalTransform: CGAffineTransform = self.isSearchTab ? .identity : CGAffineTransform(scaleX: 1, y: -1)

                        // Set initial state: small and transparent
                        cell.transform = originalTransform.scaledBy(x: 0.85, y: 0.85)
                        cell.alpha = 0
                        cell.isHidden = false

                        // Animate to normal state (in parallel with other cells moving)
                        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
                            cell.transform = originalTransform
                            cell.alpha = 1
                        }
                    }
                }
            } else if isSimpleInsertion && sortedMessages.isEmpty && !isSearchTab {
                // First message in empty tab - fade out empty cell, then show message cell
                // (Skip for search tab - it doesn't have empty cell placeholder)
                isAnimatingFirstMessage = true
                let emptyCell = tableView.cellForRow(at: IndexPath(row: 0, section: 0))

                // Phase 1: Fade out empty cell
                UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseOut]) {
                    emptyCell?.alpha = 0
                } completion: { _ in
                    // Phase 2: Replace with message cell
                    self.sortedMessages = newMessages
                    UIView.performWithoutAnimation {
                        self.tableView.reloadData()
                    }

                    // Phase 3: Animate message cell appearance
                    guard let cell = self.tableView.cellForRow(at: IndexPath(row: 0, section: 0)) else {
                        self.isAnimatingFirstMessage = false
                        return
                    }
                    let originalTransform = CGAffineTransform(scaleX: 1, y: -1)

                    // Set initial state: small and transparent
                    cell.transform = originalTransform.scaledBy(x: 0.85, y: 0.85)
                    cell.alpha = 0

                    // Animate to normal state
                    UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
                        cell.transform = originalTransform
                        cell.alpha = 1
                    } completion: { _ in
                        self.isAnimatingFirstMessage = false
                    }
                }
            } else {
                // Structure changed significantly - full reload
                sortedMessages = newMessages
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                UIView.performWithoutAnimation {
                    tableView.reloadData()
                }
                CATransaction.commit()
            }
        }
    }

    /// Animate message deletion with smooth shrink + fade animation (like composer attachments)
    func animateDeleteMessage(_ message: Message, completion: @escaping () -> Void) {
        guard let index = sortedMessages.firstIndex(where: { $0.id == message.id }) else {
            completion()
            return
        }

        // If this is the last message, we can't animate deletion because
        // numberOfRowsInSection returns 1 for empty state (empty cell)
        // Just reload the table instead
        if sortedMessages.count == 1 {
            sortedMessages.remove(at: index)
            UIView.performWithoutAnimation {
                tableView.reloadData()
            }
            completion()
            return
        }

        let indexPath = IndexPath(row: index, section: 0)

        // Get the cell to animate (if visible)
        guard let cell = tableView.cellForRow(at: indexPath) else {
            // Cell not visible - just remove with standard animation
            sortedMessages.remove(at: index)
            tableView.performBatchUpdates({
                tableView.deleteRows(at: [indexPath], with: .fade)
            }) { _ in
                completion()
            }
            return
        }

        // Save original transform (includes flip for inverted table)
        let originalTransform = cell.transform

        // Phase 1: Shrink and fade the cell
        UIView.animate(withDuration: 0.125, delay: 0, options: [.curveEaseOut]) {
            cell.transform = originalTransform.scaledBy(x: 0.85, y: 0.85)
            cell.alpha = 0
        } completion: { _ in
            // Hide cell completely to prevent "ghost" appearing during layout animation
            cell.isHidden = true

            // Remove from data source
            self.sortedMessages.remove(at: index)

            // Phase 2: Remove cell and let performBatchUpdates animate remaining cells
            self.tableView.performBatchUpdates({
                self.tableView.deleteRows(at: [indexPath], with: .none)
            }) { _ in
                // Reset cell state for reuse
                cell.isHidden = false
                cell.transform = originalTransform
                cell.alpha = 1
                completion()
            }
        }
    }

    func updateContentInset(bottomPadding: CGFloat, safeAreaBottom: CGFloat, animated: Bool = false) {
        // Extra spacing from last message to composer
        let extraSpacing: CGFloat = 16
        // bottomPadding already includes inputContainer height + keyboard (if visible)
        let newInset = bottomPadding + extraSpacing

        // Safe area top + header content + extra padding
        let safeAreaTop = view.safeAreaInsets.top
        let headerHeight: CGFloat = 115
        let topInset = safeAreaTop + headerHeight

        if isSearchTab {
            // Search tab: normal layout (top to bottom)
            // Smaller top inset - just search input, no tab bar
            let searchTopInset = safeAreaTop + 70
            tableView.contentInset.top = searchTopInset
            tableView.verticalScrollIndicatorInsets.top = searchTopInset
            // Bottom inset for search input + keyboard
            tableView.contentInset.bottom = newInset
            tableView.verticalScrollIndicatorInsets.bottom = newInset
        } else {
            // Chat tabs: inverted layout (bottom to top)
            let oldInset = tableView.contentInset.top
            let delta = newInset - oldInset

            // Save current offset BEFORE changing inset (tableView auto-adjusts on inset change)
            let currentOffset = tableView.contentOffset

            // Visual bottom (composer area) - tableView is flipped so top = visual bottom
            tableView.contentInset.top = newInset
            tableView.verticalScrollIndicatorInsets.top = newInset

            // Visual top (header/tab bar area) - tableView is flipped so bottom = visual top
            tableView.contentInset.bottom = topInset
            tableView.verticalScrollIndicatorInsets.bottom = topInset

            // Adjust offset to keep messages in sync with keyboard
            if animated && abs(delta) > 1 {
                var offset = currentOffset
                offset.y -= delta
                tableView.contentOffset = offset
            } else if delta > 1 {
                // Non-animated: only adjust when inset increases (keyboard appearing)
                var offset = currentOffset
                offset.y -= delta
                tableView.contentOffset = offset
            }
        }

        // Recalculate empty cell height to stay centered
        if sortedMessages.isEmpty && !isSearchTab {
            tableView.beginUpdates()
            tableView.endUpdates()
        }
    }

    func scrollToBottom(animated: Bool) {
        guard !sortedMessages.isEmpty else { return }
        // Search tab doesn't scroll to bottom - results start at top
        guard !isSearchTab else { return }
        // Ensure table has updated layout
        tableView.layoutIfNeeded()
        // For flipped table: scroll to show row 0 at visual bottom (near composer)
        // Use .top because the table is flipped - .top in flipped coordinates = visual bottom
        tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: animated)
    }

    /// Scroll to a specific message by ID
    func scrollToMessage(id: UUID, animated: Bool) {
        guard let index = sortedMessages.firstIndex(where: { $0.id == id }) else { return }
        tableView.layoutIfNeeded()
        let indexPath = IndexPath(row: index, section: 0)
        // For flipped table, .top shows the row at visual bottom (near composer)
        // Use .middle to center the message on screen
        tableView.scrollToRow(at: indexPath, at: .middle, animated: animated)
    }

    // MARK: - Selection Mode

    func updateSelectionMode(_ enabled: Bool) {
        let wasEnabled = isSelectionMode
        isSelectionMode = enabled
        // Disable keyboard dismiss tap in selection mode so cell taps work
        dismissKeyboardTapGesture.isEnabled = !enabled
        if wasEnabled && !enabled {
            // Keep a short window so freshly reloaded cells can also animate
            // from selection layout to normal width after bulk operations.
            selectionModeExitAnimationDeadline = CACurrentMediaTime() + 0.35
        } else if enabled {
            selectionModeExitAnimationDeadline = 0
        }

        for cell in tableView.visibleCells {
            if let messageCell = cell as? MessageTableCell {
                messageCell.setSelectionMode(enabled, animated: true)
                // Update selection state for visible cells
                if let indexPath = tableView.indexPath(for: cell),
                   indexPath.row < sortedMessages.count {
                    let message = sortedMessages[indexPath.row]
                    messageCell.setSelected(selectedMessageIds.contains(message.id))
                }
            }
        }
    }

    func updateSelectedMessageIds(_ ids: Set<UUID>) {
        selectedMessageIds = ids
        // Update selection state for visible cells
        for cell in tableView.visibleCells {
            if let messageCell = cell as? MessageTableCell,
               let indexPath = tableView.indexPath(for: cell),
               indexPath.row < sortedMessages.count {
                let message = sortedMessages[indexPath.row]
                messageCell.setSelected(selectedMessageIds.contains(message.id))
            }
        }
    }
}

// MARK: - UITableViewDataSource & Delegate

extension MessageListViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // Search tab shows search results (0 when empty, no empty cell placeholder)
        if isSearchTab {
            return sortedMessages.count
        }
        return sortedMessages.isEmpty ? 1 : sortedMessages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if sortedMessages.isEmpty && !isSearchTab {
            let cell = tableView.dequeueReusableCell(withIdentifier: "EmptyCell", for: indexPath) as! EmptyTableCell
            cell.transform = CGAffineTransform(scaleX: 1, y: -1)
            return cell
        }

        let message = sortedMessages[indexPath.row]

        // Use SearchResultCell for search tab
        if isSearchTab {
            let cell = tableView.dequeueReusableCell(withIdentifier: "SearchResultCell", for: indexPath) as! SearchResultCell

            // Get tab name for display
            let tabName: String
            if let tabId = message.tabId {
                tabName = allTabs.first(where: { $0.id == tabId })?.title ?? L10n.Reorder.inbox
            } else {
                tabName = L10n.Reorder.inbox
            }

            cell.configure(with: message, tabName: tabName)
            cell.onTap = { [weak self] in
                // Navigate to the message's tab and scroll to the message
                guard let self = self else { return }
                let tabIndex: Int
                if let tabId = message.tabId {
                    // Find tab index (tab indices start at 2: 0=Search, 1=Inbox, 2+=tabs)
                    if let idx = self.allTabs.firstIndex(where: { $0.id == tabId }) {
                        tabIndex = idx + 2
                    } else {
                        tabIndex = 1 // Fallback to Inbox
                    }
                } else {
                    tabIndex = 1 // Inbox
                }
                self.onTabSelected?(tabIndex, message.id)
            }
            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: "MessageCell", for: indexPath) as! MessageTableCell
        cell.configure(with: message)
        cell.onMediaTapped = { [weak self] index, sourceFrame, _, _, _ in
            // Open unified gallery with all media (photos + videos)
            self?.onOpenGallery?(message, index, sourceFrame)
        }
        cell.onTodoToggle = { [weak self] itemId, isCompleted in
            self?.onToggleTodoItem?(message, itemId, isCompleted)
        }

        // Selection mode
        let shouldAnimateSelectionExit =
            !isSelectionMode && CACurrentMediaTime() < selectionModeExitAnimationDeadline
        if shouldAnimateSelectionExit {
            cell.setSelectionMode(true, animated: false)
            cell.setSelectionMode(false, animated: true)
        } else {
            cell.setSelectionMode(isSelectionMode, animated: false)
        }
        cell.setSelected(selectedMessageIds.contains(message.id))
        cell.onSelectionToggle = { [weak self] selected in
            self?.onToggleMessageSelection?(message.id, selected)
        }

        // Check if this message needs appear animation
        if pendingAppearAnimationIds.contains(message.id) {
            // Hide completely until animation starts
            cell.isHidden = true
        } else {
            cell.isHidden = false
            cell.alpha = 1
        }
        // Only invert cells for chat tabs - search tab uses normal layout
        cell.transform = isSearchTab ? .identity : CGAffineTransform(scaleX: 1, y: -1)

        return cell
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        // Ensure selection mode is correct for pre-fetched cells that missed updateSelectionMode
        guard let messageCell = cell as? MessageTableCell,
              indexPath.row < sortedMessages.count else { return }
        let shouldAnimateSelectionExit =
            !isSelectionMode && CACurrentMediaTime() < selectionModeExitAnimationDeadline
        if shouldAnimateSelectionExit {
            messageCell.setSelectionMode(true, animated: false)
            messageCell.setSelectionMode(false, animated: true)
        } else {
            messageCell.setSelectionMode(isSelectionMode, animated: false)
        }
        messageCell.setSelected(selectedMessageIds.contains(sortedMessages[indexPath.row].id))
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if sortedMessages.isEmpty {
            let availableHeight = tableView.bounds.height - tableView.contentInset.top - tableView.contentInset.bottom
            return max(200, availableHeight)
        }

        let message = sortedMessages[indexPath.row]
        let cellWidth = tableView.bounds.width

        // MARK: - Performance: Use cached height if available
        // Invalidate cache if width changed (rotation, etc.)
        if cellWidth != cachedHeightWidth {
            heightCache.removeAll()
            cachedHeightWidth = cellWidth
        }

        // Return cached height if available
        if let cachedHeight = heightCache[message.id] {
            return cachedHeight
        }

        // Calculate height (expensive operation)
        let height: CGFloat
        if isSearchTab {
            // Search tab uses SearchResultCell with different layout
            height = SearchResultCell.calculateHeight(for: message, maxWidth: cellWidth)
        } else {
            height = calculateMessageHeight(for: message, cellWidth: cellWidth)
        }

        // Cache the result
        heightCache[message.id] = height

        return height
    }

    /// Calculate height for a message cell (expensive - only call when not cached)
    private func calculateMessageHeight(for message: Message, cellWidth: CGFloat) -> CGFloat {
        let bubbleWidth = cellWidth - 32  // 16px margins on each side

        var height: CGFloat = 8  // Cell padding (4 top + 4 bottom)

        // Todo list message
        if message.isTodoList, let items = message.todoItems {
            let todoHeight = TodoBubbleView.calculateHeight(for: message.todoTitle, items: items, maxWidth: bubbleWidth)
            height += todoHeight
            return max(height, 50)
        }

        let hasMedia = message.hasMedia && !message.aspectRatios.isEmpty
        let hasText = !message.content.isEmpty

        // Calculate mosaic height if has media
        if hasMedia {
            let mosaicHeight = MosaicMediaView.calculateHeight(for: message.aspectRatios, maxWidth: bubbleWidth)
            height += mosaicHeight
        }

        // Calculate text height if has content
        if hasText {
            let textWidth = bubbleWidth - 28  // 14px padding on each side

            // Use same paragraph style as in createAttributedString
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 2

            let textHeight = message.content.boundingRect(
                with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [
                    .font: UIFont.systemFont(ofSize: 16),
                    .paragraphStyle: paragraphStyle
                ],
                context: nil
            ).height

            if hasMedia {
                // Media + text: spacing (10) + text + bottom padding (10)
                height += 10 + ceil(textHeight) + 10
            } else {
                // Text only: top padding (10) + text + bottom padding (10)
                height += 10 + ceil(textHeight) + 10
            }
        }

        return max(height, 50)  // Minimum height
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard !sortedMessages.isEmpty else { return nil }

        let message = sortedMessages[indexPath.row]

        return UIContextMenuConfiguration(identifier: indexPath as NSCopying, previewProvider: nil) { [weak self] _ in
            guard let self = self else { return nil }

            var actions: [UIMenuElement] = []

            // Copy action
            let copyAction = UIAction(
                title: L10n.Menu.copy,
                image: UIImage(systemName: "doc.on.doc")
            ) { _ in
                UIPasteboard.general.string = message.content
            }
            actions.append(copyAction)

            // Select action (enters bulk selection mode)
            let selectAction = UIAction(
                title: L10n.Selection.select,
                image: UIImage(systemName: "checkmark.circle")
            ) { [weak self] _ in
                self?.view.window?.endEditing(true)
                self?.onEnterSelectionMode?(message)
            }
            actions.append(selectAction)

            // Edit action
            let editAction = UIAction(
                title: L10n.Menu.edit,
                image: UIImage(systemName: "pencil")
            ) { _ in
                self.onEditMessage?(message)
            }
            actions.append(editAction)

            // Move action (show other tabs + Inbox if not already in Inbox)
            var moveMenuChildren: [UIAction] = []

            // Add Inbox option if not already in Inbox
            if self.currentTabId != nil {
                moveMenuChildren.append(UIAction(title: L10n.Reorder.inbox) { [weak self] _ in
                    self?.animateDeleteMessage(message) {
                        self?.onMoveMessage?(message, nil)
                    }
                })
            }

            // Add other real tabs
            let otherTabs = self.allTabs.filter { $0.id != self.currentTabId }
            for tab in otherTabs {
                moveMenuChildren.append(UIAction(title: tab.title) { [weak self] _ in
                    self?.animateDeleteMessage(message) {
                        self?.onMoveMessage?(message, tab.id)
                    }
                })
            }

            if !moveMenuChildren.isEmpty {
                let moveMenu = UIMenu(
                    title: L10n.Menu.move,
                    image: UIImage(systemName: "arrow.right.doc.on.clipboard"),
                    children: moveMenuChildren
                )
                actions.append(moveMenu)
            }

            // Reminder action
            let reminderTitle = message.hasReminder ? L10n.Menu.editReminder : L10n.Menu.remind
            let reminderIcon = "bell"
            let reminderAction = UIAction(
                title: reminderTitle,
                image: UIImage(systemName: reminderIcon)
            ) { [weak self] _ in
                self?.onToggleReminder?(message)
            }
            actions.append(reminderAction)

            // Delete action
            let deleteAction = UIAction(
                title: L10n.Menu.delete,
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.animateDeleteMessage(message) {
                    self?.onDeleteMessage?(message)
                }
            }
            actions.append(deleteAction)

            return UIMenu(children: actions)
        }
    }

    private func makeContextMenuPreview(for configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        guard let indexPath = configuration.identifier as? IndexPath,
              let cell = tableView.cellForRow(at: indexPath) as? MessageTableCell else {
            return nil
        }
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        return UITargetedPreview(view: cell.bubbleViewForContextMenu, parameters: parameters)
    }

    func tableView(_ tableView: UITableView, previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        makeContextMenuPreview(for: configuration)
    }

    func tableView(_ tableView: UITableView, previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        makeContextMenuPreview(for: configuration)
    }

    func tableView(_ tableView: UITableView, willEndContextMenuInteraction configuration: UIContextMenuConfiguration, animator: (any UIContextMenuInteractionAnimating)?) {
        animator?.addCompletion { [weak tableView] in
            tableView?.visibleCells.forEach { $0.alpha = 1.0 }
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension MessageListViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow long press to work with context menu interaction
        return true
    }
}

// MARK: - Bottom Fade Gradient View

final class BottomFadeGradientView: UIView {
    private let gradientLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupGradient()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupGradient()
    }

    private func setupGradient() {
        gradientLayer.locations = [0.0, 1.0]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)  // Top (transparent)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)    // Bottom (solid)
        layer.addSublayer(gradientLayer)
        updateColors()

        // Update colors when trait collection changes
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: BottomFadeGradientView, _) in
            self.updateColors()
        }

        // Update colors when theme changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThemeChange),
            name: .themeDidChange,
            object: nil
        )
    }

    @objc private func handleThemeChange() {
        updateColors()
    }

    private func updateColors() {
        let theme = ThemeManager.shared.currentTheme
        let isDark = traitCollection.userInterfaceStyle == .dark
        let bgColor = isDark ? UIColor(theme.backgroundColorDark) : UIColor(theme.backgroundColor)

        gradientLayer.colors = [
            bgColor.withAlphaComponent(0).cgColor,
            bgColor.withAlphaComponent(0.7).cgColor,
            bgColor.cgColor
        ]
        gradientLayer.locations = [0.0, 0.25, 0.6]
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Top Fade Gradient View

final class TopFadeGradientView: UIView {
    private let gradientLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupGradient()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupGradient()
    }

    private func setupGradient() {
        gradientLayer.locations = [0.0, 0.3, 0.5, 0.7, 0.85, 1.0]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)  // Top (solid)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)    // Bottom (transparent)
        layer.addSublayer(gradientLayer)
        updateColors()

        // Update colors when trait collection changes
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: TopFadeGradientView, _) in
            self.updateColors()
        }

        // Update colors when theme changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThemeChange),
            name: .themeDidChange,
            object: nil
        )
    }

    @objc private func handleThemeChange() {
        updateColors()
    }

    private func updateColors() {
        let theme = ThemeManager.shared.currentTheme
        let isDark = traitCollection.userInterfaceStyle == .dark
        let bgColor = isDark ? UIColor(theme.backgroundColorDark) : UIColor(theme.backgroundColor)

        gradientLayer.colors = [
            bgColor.cgColor,                          // 0%: 100% opaque
            bgColor.cgColor,                          // 30%: 100% opaque
            bgColor.withAlphaComponent(0.8).cgColor,  // 50%: 80% opaque
            bgColor.withAlphaComponent(0.5).cgColor,  // 70%: 50% opaque
            bgColor.withAlphaComponent(0.2).cgColor,  // 85%: 20% opaque
            bgColor.withAlphaComponent(0).cgColor     // 100%: transparent
        ]
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Pass-Through View

/// A view that passes through touches that don't hit any subview
final class PassThroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitView = super.hitTest(point, with: event)
        // If hit view is self, pass through (return nil)
        // Otherwise return the hit subview
        return hitView === self ? nil : hitView
    }
}
