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
    @Binding var mediaOrderTags: [String]
    @Binding var formattingEntities: [TextEntity]  // Entities from formatting
    @Binding var composerContent: FormattingTextView.ComposerContent?
    @Binding var linkPreview: LinkPreview?
    let onSend: () -> Void
    var onDeleteMessage: ((Message) -> Void)?
    var onMoveMessage: ((Message, UUID?) -> Void)?  // UUID? = target tabId (nil = Inbox)
    var onMoveToNewTab: ((Message) -> Void)?
    var onEditMessage: ((Message) -> Void)?
    var onRestoreMessage: (() -> Void)?
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
        vc.onMoveToNewTab = onMoveToNewTab
        vc.onEditMessage = onEditMessage
        vc.onRestoreMessage = onRestoreMessage
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
        vc.onMediaOrderChange = { tags in
            mediaOrderTags = tags
        }
        vc.onEntitiesExtracted = { entities in
            formattingEntities = entities
        }
        vc.onComposerContentExtracted = { content in
            composerContent = content
        }
        vc.onLinkPreviewExtracted = { preview in
            linkPreview = preview
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
            hasher.combine(message.contentBlocks?.count ?? -1)
            hasher.combine(message.hasReminder)
            hasher.combine(message.photoFileNames.count)
            hasher.combine(message.videoFileNames.count)
            hasher.combine(message.linkPreview?.url)
            hasher.combine(message.linkPreview?.title)
            hasher.combine(message.linkPreview?.isPlaceholder)
        }
        return hasher.finalize()
    }

    func updateUIViewController(_ uiViewController: UnifiedChatViewController, context: Context) {
        // Update callbacks (cheap)
        uiViewController.onDeleteMessage = onDeleteMessage
        uiViewController.onMoveMessage = onMoveMessage
        uiViewController.onMoveToNewTab = onMoveToNewTab
        uiViewController.onEditMessage = onEditMessage
        uiViewController.onRestoreMessage = onRestoreMessage
        uiViewController.onToggleTodoItem = onToggleTodoItem
        uiViewController.onToggleReminder = onToggleReminder
        uiViewController.onEnterSelectionMode = onEnterSelectionMode
        uiViewController.onToggleMessageSelection = onToggleMessageSelection

        // Selection mode — update selectedMessageIds BEFORE isSelectionMode
        // because isSelectionMode didSet triggers updateSelectionModeUI() which reads selectedMessageIds
        if uiViewController.isSelectionMode != isSelectionMode {
            uiViewController.selectedMessageIds = selectedMessageIds
            uiViewController.isSelectionMode = isSelectionMode
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
            if tabsChanged || idsChanged || forceReload {
                uiViewController.invalidateMediaWarmupState()
            }
        }

        // Tab selection change (after data update so totalTabCount is current)
        let previousControllerIndex = uiViewController.selectedIndex
        let indexChanged = previousControllerIndex != selectedIndex
        if indexChanged {
            uiViewController.selectedIndex = selectedIndex
        }

        if tabsChanged {
            // Tabs structure changed - keep page transition animated when selection changed
            // (e.g. deleting active tab should slide to neighbor instead of teleporting).
            uiViewController.handleTabsStructureChange(
                previousSelectedIndex: previousControllerIndex,
                animateSelectionTransition: indexChanged
            )
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
    var onComposerContentExtracted: ((FormattingTextView.ComposerContent?) -> Void)?
    var onLinkPreviewExtracted: ((LinkPreview?) -> Void)?

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
    var onMoveToNewTab: ((Message) -> Void)?
    var onEditMessage: ((Message) -> Void)?
    var onImagesChange: (([UIImage]) -> Void)?
    var onVideosChange: (([AttachedVideo]) -> Void)?
    var onMediaOrderChange: (([String]) -> Void)?
    var onRestoreMessage: (() -> Void)?
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
    private var searchDebounceWorkItem: DispatchWorkItem?
    private var pageScrollView: UIScrollView?
    private var isUserSwiping: Bool = false
    private var pendingAdjacentPreloadAfterSwipe = false
    private var didStartInteractivePageSwipe = false
    private let tabSwipeFeedbackGenerator = UIImpactFeedbackGenerator(style: .soft)

    /// When true, didFinishAnimating ignores stale transitions from interrupted swipes.
    /// Set during programmatic page changes that interrupt an active user swipe.
    private var suppressPageTransitionUpdates = false

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
            hasher.combine(message.contentBlocks?.count ?? -1)
            hasher.combine(message.hasReminder)
            hasher.combine(message.photoFileNames.count)
            hasher.combine(message.videoFileNames.count)
            hasher.combine(message.linkPreview?.url)
            hasher.combine(message.linkPreview?.title)
            hasher.combine(message.linkPreview?.isPlaceholder)
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
    private var warmedMediaTabIndices: Set<Int> = []
    private let mediaWarmupQueue = DispatchQueue(label: "com.tabsglass.mediawarmup", qos: .utility)

    private struct MediaWarmupSnapshot {
        let orderedMediaItems: [MediaItem]
        let aspectRatios: [CGFloat]
    }

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

    /// Invalidate media thumbnail warmup state (called when tab/message structure changes).
    func invalidateMediaWarmupState() {
        warmedMediaTabIndices.removeAll()
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
        tabSwipeFeedbackGenerator.prepare()
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
        let translation = gesture.translation(in: view).x
        let velocity = gesture.velocity(in: view).x

        switch gesture.state {
        case .ended:
            guard selectedIndex != 0 else { return }

            // Complete navigation if swiped enough or with enough velocity
            if translation > 50 || velocity > 300 {
                // Dismiss keyboard before navigation to avoid layout interference
                view.endEditing(true)
                tabSwipeFeedbackGenerator.impactOccurred(intensity: 0.8)
                tabSwipeFeedbackGenerator.prepare()
                onAnimatedIndexChange?(0)
            }
        default:
            break
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
                // Disable system scroll edge effects (iOS 26 gradient blur is too large)
                scrollView.topEdgeEffect.isHidden = true
                scrollView.bottomEdgeEffect.isHidden = true
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
            // Extract formatting entities, composer content, and link preview before clearing
            self.onEntitiesExtracted?(self.inputContainer.extractEntities())
            self.onComposerContentExtracted?(self.inputContainer.extractComposerContent())
            self.onLinkPreviewExtracted?(self.inputContainer.extractLinkPreview())
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
            // Update all message controllers so todo checkboxes know keyboard state
            for (_, vc) in self.messageControllers {
                vc.isComposerFocused = isFocused
            }
        }

        inputContainer.onShowPhotoPicker = { [weak self] in
            self?.showPhotoPicker()
        }

        inputContainer.onShowCamera = { [weak self] in
            self?.showCamera()
        }

        inputContainer.onImagesChange = { [weak self] images in
            self?.onImagesChange?(images)
            self?.onMediaOrderChange?(self?.inputContainer.mediaOrderTags ?? [])
        }

        inputContainer.onVideosChange = { [weak self] videos in
            self?.onVideosChange?(videos)
            self?.onMediaOrderChange?(self?.inputContainer.mediaOrderTags ?? [])
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

        // Track text changes to update search results (debounced for non-empty text)
        searchInputState.onTextChange = { [weak self] newText in
            guard let self = self else { return }
            self.searchText = newText
            self.searchDebounceWorkItem?.cancel()
            if newText.isEmpty {
                // Empty text: update immediately (show tips/tabs without delay)
                self.updateSearchResults()
            } else {
                let workItem = DispatchWorkItem { [weak self] in
                    self?.updateSearchResults()
                }
                self.searchDebounceWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: workItem)
            }
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
            // In selection mode, hide both inputs quickly
            inputContainer.isUserInteractionEnabled = false
            searchInputContainer?.isUserInteractionEnabled = false
            searchInputHostingController?.view.isUserInteractionEnabled = false

            let changes = {
                self.inputContainer.alpha = 0
                self.searchInputContainer?.alpha = 0
            }
            if animated {
                UIView.animate(withDuration: 0.2, animations: changes)
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
            existing.isComposerFocused = isComposerFocused
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
        vc.onMoveToNewTab = { [weak self] message in
            self?.onMoveToNewTab?(message)
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
        vc.isComposerFocused = isComposerFocused

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
        // If user started dragging, postpone preloading and retry after swipe completes.
        guard !isUserSwiping else {
            pendingAdjacentPreloadAfterSwipe = true
            return
        }

        // Preload in next run loop to avoid blocking current frame.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard !self.isUserSwiping else {
                self.pendingAdjacentPreloadAfterSwipe = true
                return
            }

            let bounds = self.pageViewController.view.bounds
            let preloadOrder = [-1, 1, -2, 2]
            let indicesToPreload = preloadOrder
                .map { self.selectedIndex + $0 }
                .filter { $0 >= 0 && $0 < self.totalTabCount }

            self.pendingAdjacentPreloadAfterSwipe = false

            for index in indicesToPreload {
                let vc: MessageListViewController
                if let existing = self.messageControllers[index] {
                    vc = existing
                } else {
                    vc = self.getMessageController(for: index)
                }
                vc.prewarmCells(in: bounds)
                self.prewarmMediaThumbnailsIfNeeded(for: index, viewportWidth: bounds.width)
            }
        }
    }

    private func prewarmMediaThumbnailsIfNeeded(for index: Int, viewportWidth: CGFloat) {
        guard index >= 1 && index < totalTabCount else { return } // Skip Search tab
        guard warmedMediaTabIndices.insert(index).inserted else { return }

        let tabMessages = messagesForTab(tabId(for: index))
        let snapshots = tabMessages
            .filter { $0.modelContext != nil && $0.hasMedia && !$0.aspectRatios.isEmpty }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(10)
            .map {
                MediaWarmupSnapshot(
                    orderedMediaItems: $0.orderedMediaItems,
                    aspectRatios: $0.aspectRatios
                )
            }

        guard !snapshots.isEmpty else { return }

        let resolvedViewportWidth = viewportWidth > 0 ? viewportWidth : (view.window?.windowScene?.screen.bounds.width ?? 393)
        let bubbleWidth = max(resolvedViewportWidth - 32, 1)

        mediaWarmupQueue.async {
            let maxMediaItemsPerMessage = 6
            for snapshot in snapshots {
                let calculator = MosaicLayoutCalculator(maxWidth: bubbleWidth, maxHeight: 300, spacing: 2)
                let layoutItems = calculator.calculateLayout(aspectRatios: snapshot.aspectRatios)
                guard !layoutItems.isEmpty else { continue }

                let loadLimit = min(layoutItems.count, maxMediaItemsPerMessage)

                for itemIndex in 0..<loadLimit {
                    let targetSize = layoutItems[itemIndex].frame.size
                    guard itemIndex < snapshot.orderedMediaItems.count else { continue }
                    let item = snapshot.orderedMediaItems[itemIndex]

                    if item.isVideo {
                        if let thumbFileName = item.thumbnailFileName, !thumbFileName.isEmpty {
                            ImageCache.shared.prefetchVideoThumbnails(
                                videoFileNames: [item.fileName],
                                thumbnailFileNames: [thumbFileName],
                                targetSize: targetSize
                            )
                        }
                    } else {
                        ImageCache.shared.prefetchThumbnails(
                            for: [item.fileName],
                            targetSize: targetSize
                        )
                    }
                }
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

            // If a user swipe is in progress, force non-animated transition.
            // UIPageViewController's setViewControllers(animated:true) completion handler
            // may never fire when called during an active interactive transition,
            // which would leave isUserInteractionEnabled=false permanently.
            let shouldAnimate = animated && !isUserSwiping

            if isUserSwiping {
                isUserSwiping = false
                didStartInteractivePageSwipe = false
                lastReportedFraction = 0
                onSwitchFraction?(0)

                // Suppress stale didFinishAnimating callbacks and block data source
                // from providing adjacent pages during the interrupted transition.
                suppressPageTransitionUpdates = true

                // Kill scroll view momentum
                if let scrollView = pageScrollView {
                    scrollView.isScrollEnabled = false
                    scrollView.isScrollEnabled = true
                }

                // Safety fallback: if scrollViewDidEndDecelerating never fires,
                // finalize after a short delay.
                let targetIndex = selectedIndex
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self, self.suppressPageTransitionUpdates else { return }
                    self.suppressPageTransitionUpdates = false
                    let vc = self.getMessageController(for: targetIndex)
                    self.pageViewController.setViewControllers([vc], direction: .forward, animated: false)
                    self.updateInputVisibility(animated: false)
                    self.preloadAdjacentTabs()
                }
            }

            // For programmatic changes, animate input positions in sync with page transition
            if shouldAnimate && (previousIndex <= 1 || selectedIndex <= 1) {
                // Animate inputs when transitioning to/from Search or Inbox
                UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                    self.updateInputVisibility(animated: false)
                }
            } else {
                updateInputVisibility(animated: shouldAnimate)
            }

            if shouldAnimate {
                // Disable interaction during programmatic page transition
                // to prevent user from interrupting the animation and causing
                // desync between tab bar selection and displayed content
                pageViewController.view.isUserInteractionEnabled = false
                let crossedSearch = (previousIndex == 0) != (selectedIndex == 0)
                pageViewController.setViewControllers([vc], direction: direction, animated: true) { [weak self] finished in
                    guard let self = self else { return }
                    // Dismiss keyboard after transition settles when crossing Search boundary
                    if crossedSearch {
                        self.view.endEditing(true)
                    }
                    if finished {
                        // Workaround: UIPageViewController sometimes doesn't fully complete
                        // the scroll animation, leaving adjacent pages partially visible.
                        // Re-setting without animation forces the final position.
                        DispatchQueue.main.async {
                            self.pageViewController.setViewControllers([vc], direction: direction, animated: false)
                            self.pageViewController.view.isUserInteractionEnabled = true
                        }
                    } else {
                        self.pageViewController.view.isUserInteractionEnabled = true
                    }
                }
            } else {
                pageViewController.setViewControllers([vc], direction: direction, animated: false)
                // If suppressed, DON'T clear the flag here — wait for
                // scrollViewDidEndDecelerating to finalize the page set.
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
    func handleTabsStructureChange(
        previousSelectedIndex: Int? = nil,
        animateSelectionTransition: Bool = false
    ) {
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

        let shouldAnimateSelectionTransition: Bool = {
            guard animateSelectionTransition else { return false }
            guard let previousSelectedIndex else { return false }
            return previousSelectedIndex != selectedIndex
        }()

        // Reset page view controller to current valid index.
        // Keep transition animated when selection changed with tab structure mutation.
        updatePageSelection(animated: shouldAnimateSelectionTransition)

        // Update current tab
        reloadCurrentTab()
    }

    // MARK: - Selection Mode

    private func updateSelectionModeUI() {
        if isSelectionMode {
            // Entering selection: hide composer immediately
            updateInputVisibility(animated: true)
        } else {
            // Exiting selection: delay composer reappearance to stagger after selection bars slide out
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                self.updateInputVisibility(animated: true)
            }
        }

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
        let orderedItems = message.orderedMediaItems
        guard !orderedItems.isEmpty, startIndex < orderedItems.count else { return }

        // Load all media asynchronously in display order
        let group = DispatchGroup()
        var loadedMedia: [Int: GalleryMediaItem] = [:]

        for (index, item) in orderedItems.enumerated() {
            if item.isVideo {
                let videoURL = SharedVideoStorage.videoURL(for: item.fileName)
                if let thumbFileName = item.thumbnailFileName, !thumbFileName.isEmpty {
                    group.enter()
                    ImageCache.shared.loadFullImage(for: thumbFileName) { thumbnail in
                        loadedMedia[index] = .video(url: videoURL, thumbnail: thumbnail)
                        group.leave()
                    }
                } else {
                    loadedMedia[index] = .video(url: videoURL, thumbnail: nil)
                }
            } else {
                group.enter()
                ImageCache.shared.loadFullImage(for: item.fileName) { image in
                    if let image = image {
                        loadedMedia[index] = .photo(image: image)
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            let mediaItems = (0..<orderedItems.count).compactMap { loadedMedia[$0] }
            guard !mediaItems.isEmpty, startIndex < mediaItems.count else { return }

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
        // Block adjacent page loading during programmatic page set to prevent
        // UIPageViewController from transitioning via stale scroll momentum.
        if suppressPageTransitionUpdates { return nil }
        let index = vc.pageIndex - 1
        guard index >= 0 else { return nil }
        return getMessageController(for: index)
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let vc = viewController as? MessageListViewController else { return nil }
        // Block adjacent page loading during programmatic page set to prevent
        // UIPageViewController from transitioning via stale scroll momentum.
        if suppressPageTransitionUpdates { return nil }
        let index = vc.pageIndex + 1
        guard index < totalTabCount else { return nil }
        return getMessageController(for: index)
    }

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        // Ignore stale transitions from interrupted swipes during programmatic navigation.
        if suppressPageTransitionUpdates { return }

        guard completed,
              let currentVC = pageViewController.viewControllers?.first as? MessageListViewController else {
            return
        }
        let previousIndex = (previousViewControllers.first as? MessageListViewController)?.pageIndex ?? selectedIndex

        if didStartInteractivePageSwipe, previousIndex != currentVC.pageIndex {
            tabSwipeFeedbackGenerator.impactOccurred(intensity: 0.8)
            tabSwipeFeedbackGenerator.prepare()
        }

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
        // Dismiss keyboard when leaving Search (can only swipe right from index 0)
        if selectedIndex == 0 && isSearchFocused {
            view.endEditing(true)
        }

        isUserSwiping = true
        didStartInteractivePageSwipe = true
        lastReportedFraction = 0
        tabSwipeFeedbackGenerator.prepare()

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

        // Dismiss keyboard when swiping from Inbox toward Search
        if selectedIndex == 1 && clampedFraction < -0.15 && isComposerFocused {
            view.endEditing(true)
        }

        // Sync input sliding with page swipe (always update for smooth input movement)
        updateInputPositions(fraction: clampedFraction)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === pageScrollView else { return }
        isUserSwiping = false
        didStartInteractivePageSwipe = false
        lastReportedFraction = 0
        onSwitchFraction?(0)  // Reset fraction when swipe completes

        // Finalize programmatic page set after all stale scroll momentum has settled.
        if suppressPageTransitionUpdates {
            suppressPageTransitionUpdates = false
            let vc = getMessageController(for: selectedIndex)
            pageViewController.setViewControllers([vc], direction: .forward, animated: false)
            updateInputVisibility(animated: false)
        }

        if pendingAdjacentPreloadAfterSwipe {
            preloadAdjacentTabs()
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView === pageScrollView else { return }
        if !decelerate {
            isUserSwiping = false
            didStartInteractivePageSwipe = false
            lastReportedFraction = 0
            onSwitchFraction?(0)  // Reset fraction when drag ends without deceleration

            // Finalize programmatic page set if no deceleration follows
            if suppressPageTransitionUpdates {
                suppressPageTransitionUpdates = false
                let vc = getMessageController(for: selectedIndex)
                pageViewController.setViewControllers([vc], direction: .forward, animated: false)
                updateInputVisibility(animated: false)
            }

            if pendingAdjacentPreloadAfterSwipe {
                preloadAdjacentTabs()
            }
        }
    }
}
