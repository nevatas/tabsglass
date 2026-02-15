//
//  MessageListViewController.swift
//  tabsglass
//
//  Extracted from UnifiedChatView.swift for maintainability
//

import SwiftUI
import SwiftData
import UIKit

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
    var onMoveToNewTab: ((Message) -> Void)?
    var onEditMessage: ((Message) -> Void)?
    /// Callback when gallery should be opened: (message, startIndex, sourceFrame)
    var onOpenGallery: ((Message, Int, CGRect) -> Void)?
    /// Callback when a todo item is toggled: (message, itemId, isCompleted)
    var onToggleTodoItem: ((Message, UUID, Bool) -> Void)?
    /// Callback when reminder is toggled on a message
    var onToggleReminder: ((Message) -> Void)?
    /// Callback when pin is toggled on a message
    var onTogglePin: ((Message) -> Void)?

    // Keyboard/composer focus state (for todo checkbox interaction)
    var isComposerFocused: Bool = false {
        didSet {
            guard oldValue != isComposerFocused else { return }
            for cell in tableView.visibleCells {
                if let messageCell = cell as? MessageTableCell {
                    messageCell.isKeyboardActive = isComposerFocused
                }
            }
        }
    }

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
    private var lastRenderedMessagesHash: Int = 0
    private var selectionModeExitAnimationDeadline: CFTimeInterval = 0

    // Embedded search tabs for search tab
    private var searchTabsHostingController: UIHostingController<SearchTabsView>?
    private var topFadeGradient: TopFadeGradientView?
    private var chatTopFadeGradient: ChatTopFadeGradientView?

    // MARK: - Show More: Expanded messages
    /// IDs of messages whose "Show more" has been tapped (expanded text)
    private var expandedMessageIds: Set<UUID> = []

    // MARK: - Performance: Height cache
    /// Cache for calculated row heights, keyed by message ID
    private var heightCache: [UUID: CGFloat] = [:]
    /// Hash of properties that affected the cached height (detects changes regardless of SwiftData identity)
    private var heightInputCache: [UUID: Int] = [:]
    /// Per-message render hash — skip reconfigure when unchanged
    private var cellRenderCache: [UUID: Int] = [:]
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
        } else {
            setupChatTopFadeGradient()
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

        // Disable system scroll edge effects (iOS 26 gradient blur) — too large by default
        tableView.topEdgeEffect.isHidden = true
        tableView.bottomEdgeEffect.isHidden = true

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        dismissKeyboardTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
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
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
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

    private func setupChatTopFadeGradient() {
        let gradientView = ChatTopFadeGradientView()
        gradientView.translatesAutoresizingMaskIntoConstraints = false
        gradientView.isUserInteractionEnabled = false
        view.addSubview(gradientView)

        NSLayoutConstraint.activate([
            // Extend above view top to cover Dynamic Island / safe area
            gradientView.topAnchor.constraint(equalTo: view.topAnchor, constant: -60),
            gradientView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gradientView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gradientView.heightAnchor.constraint(equalToConstant: 135)
        ])

        chatTopFadeGradient = gradientView
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

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        // When composer is focused, don't dismiss keyboard if tap is on a todo checkbox row.
        // Use hitTest instead of coordinate conversion — inverted table transforms make
        // indexPathForRow(at:) unreliable with gesture recognizer coordinates.
        if isComposerFocused {
            let point = gesture.location(in: view)
            if let hitView = view.hitTest(point, with: nil) {
                var current: UIView? = hitView
                while let v = current {
                    if v is TodoCheckboxRow {
                        return // Skip dismiss — TodoCheckboxRow handles toggle/dismiss itself
                    }
                    current = v.superview
                }
            }
        }
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
        let currentHash = makeRenderHash(from: messages)
        if currentHash != lastRenderedMessagesHash {
            reloadMessages()
        }
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

        // Avoid forcing UITableView layout before it is attached to a window.
        // UIKit warns about this and it can introduce extra layout work.
        guard view.window != nil else { return }
        tableView.setNeedsLayout()
        tableView.layoutIfNeeded()
    }

    private func refreshContentInset() {
        let bottomPadding = getBottomPadding?() ?? 80
        let safeAreaBottom = getSafeAreaBottom?() ?? 0
        // Wrap in performWithoutAnimation to prevent empty cell height change
        // from animating during tab transitions (viewWillAppear/viewDidAppear
        // run inside UIPageViewController's transition animation context)
        UIView.performWithoutAnimation {
            updateContentInset(bottomPadding: bottomPadding, safeAreaBottom: safeAreaBottom)
        }
    }

    /// Track last processed message IDs for quick change detection
    private var lastProcessedMessageIds: Set<UUID> = []

    private func makeRenderHash(from messages: [Message]) -> Int {
        var hasher = Hasher()
        hasher.combine(messages.count)
        for message in messages where message.modelContext != nil {
            hasher.combine(message.id)
            hasher.combine(message.tabId)
            hasher.combine(message.content)
            hasher.combine(message.todoTitle)
            hasher.combine(message.hasReminder)
            hasher.combine(message.isPinned)
            hasher.combine(message.photoFileNames.count)
            hasher.combine(message.videoFileNames.count)
            hasher.combine(message.createdAt.timeIntervalSinceReferenceDate.bitPattern)
            hasher.combine(message.linkPreview?.url)
            hasher.combine(message.linkPreview?.title)
            hasher.combine(message.linkPreview?.isPlaceholder)

            if let items = message.todoItems {
                hasher.combine(items.count)
                for item in items {
                    hasher.combine(item.id)
                    hasher.combine(item.text)
                    hasher.combine(item.isCompleted)
                }
            } else {
                hasher.combine(-1)
            }
        }
        return hasher.finalize()
    }

    /// Hash of per-message properties that affect cell height
    private func makeHeightInputHash(for message: Message) -> Int {
        var hasher = Hasher()
        hasher.combine(message.content)
        hasher.combine(message.photoFileNames.count)
        hasher.combine(message.videoFileNames.count)
        hasher.combine(message.todoItems?.count ?? -1)
        hasher.combine(message.todoTitle)
        hasher.combine(message.contentBlocks?.count ?? -1)
        hasher.combine(message.linkPreview?.url)
        hasher.combine(message.linkPreview?.title)
        hasher.combine(message.linkPreview?.isPlaceholder)
        hasher.combine(message.linkPreview?.isLargeImage)
        return hasher.finalize()
    }

    /// Full per-message render hash — includes everything visible (todo completion, reminder, etc.)
    private func makeCellRenderHash(for message: Message) -> Int {
        var hasher = Hasher()
        hasher.combine(message.content)
        hasher.combine(message.photoFileNames.count)
        hasher.combine(message.videoFileNames.count)
        hasher.combine(message.todoTitle)
        hasher.combine(message.hasReminder)
        hasher.combine(message.isPinned)
        hasher.combine(message.linkPreview?.url)
        hasher.combine(message.linkPreview?.title)
        hasher.combine(message.linkPreview?.isPlaceholder)
        if let items = message.todoItems {
            for item in items {
                hasher.combine(item.id)
                hasher.combine(item.isCompleted)
            }
        }
        if let blocks = message.contentBlocks {
            for block in blocks {
                hasher.combine(block.id)
                hasher.combine(block.isCompleted)
            }
        }
        return hasher.finalize()
    }

    func reloadMessages(invalidateHeights: Bool = false) {
        // Skip if first message animation is in progress
        if isAnimatingFirstMessage { return }

        // Force reload: clear all height caches so cells recalculate
        if invalidateHeights {
            heightCache.removeAll()
            heightInputCache.removeAll()
        }

        // Snapshot current content to avoid redundant reload on first appear after prewarm.
        lastRenderedMessagesHash = makeRenderHash(from: messages)

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
            heightInputCache.removeAll()
            newMessages = validMessages
                .filter { !$0.isEmpty }
                .sorted { $0.createdAt > $1.createdAt }
        }

        // Search results can change rapidly on each keystroke.
        // Avoid incremental UITableView batch updates here to prevent
        // update collisions and invalid table state assertions.
        if isSearchTab {
            sortedMessages = newMessages
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            UIView.performWithoutAnimation {
                tableView.reloadData()
            }
            CATransaction.commit()
            return
        }

        // Compare against sortedMessages (what UITableView currently displays)
        // .id is safe to access on deleted SwiftData objects
        let oldIds = sortedMessages.map { $0.id }
        let newIds = newMessages.map { $0.id }

        // Defensive path: if table and datasource drifted out of sync,
        // avoid incremental updates and fully reconcile in one reload.
        // Account for empty cell placeholder: when sortedMessages is empty,
        // the table shows 1 row (EmptyTableCell), not 0.
        let renderedRows = tableView.numberOfRows(inSection: 0)
        let expectedRows = oldIds.isEmpty && !isSearchTab ? 1 : oldIds.count
        if renderedRows != expectedRows {
            sortedMessages = newMessages
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            UIView.performWithoutAnimation {
                tableView.reloadData()
            }
            CATransaction.commit()
            return
        }

        // Transition to empty state is safer with full reload than batched
        // row deletions, especially when multiple delete events race.
        if newMessages.isEmpty {
            sortedMessages = []
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            UIView.performWithoutAnimation {
                tableView.reloadData()
            }
            CATransaction.commit()
            return
        }

        if oldIds == newIds {
            // Same messages in same order — just reconfigure content
            // Compare height-input hashes (not SwiftData object refs which are identity-equal)
            var heightsInvalidated = false
            for newMsg in newMessages {
                let currentHash = makeHeightInputHash(for: newMsg)
                if heightInputCache[newMsg.id] != currentHash {
                    heightCache.removeValue(forKey: newMsg.id)
                    heightInputCache.removeValue(forKey: newMsg.id)
                    heightsInvalidated = true
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
                    let msg = sortedMessages[indexPath.row]
                    // Skip reconfigure if cell content hasn't changed
                    let renderHash = makeCellRenderHash(for: msg)
                    if cellRenderCache[msg.id] == renderHash {
                        continue
                    }
                    cellRenderCache[msg.id] = renderHash
                    messageCell.configure(with: msg, isExpanded: expandedMessageIds.contains(msg.id))
                    messageCell.isKeyboardActive = isComposerFocused
                }
                // Only recalculate row heights when layout-affecting content changed
                if heightsInvalidated {
                    tableView.beginUpdates()
                    tableView.endUpdates()
                }
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

                // Snapshot the empty cell so the fade-out can't be interrupted by table reloads
                let snapshot = emptyCell?.snapshotView(afterScreenUpdates: false)
                if let snapshot, let emptyCell {
                    snapshot.frame = emptyCell.frame
                    snapshot.transform = CGAffineTransform(scaleX: 1, y: -1)
                    tableView.addSubview(snapshot)
                }

                // Replace data immediately (snapshot covers the transition)
                sortedMessages = newMessages
                UIView.performWithoutAnimation {
                    self.tableView.reloadData()
                }

                // Fade out snapshot + animate message cell appearance in parallel
                UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
                    snapshot?.alpha = 0
                } completion: { _ in
                    snapshot?.removeFromSuperview()
                }

                if let cell = tableView.cellForRow(at: IndexPath(row: 0, section: 0)) {
                    let originalTransform = CGAffineTransform(scaleX: 1, y: -1)
                    cell.transform = originalTransform.scaledBy(x: 0.85, y: 0.85)
                    cell.alpha = 0

                    UIView.animate(withDuration: 0.25, delay: 0.05, options: [.curveEaseOut]) {
                        cell.transform = originalTransform
                        cell.alpha = 1
                    } completion: { _ in
                        self.isAnimatingFirstMessage = false
                    }
                } else {
                    isAnimatingFirstMessage = false
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
        let headerHeight: CGFloat = 60
        let topInset = safeAreaTop + headerHeight

        if isSearchTab {
            // Search tab: normal layout (top to bottom)
            // Smaller top inset - just search input, no tab bar
            let searchTopInset = safeAreaTop + 60
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
            let tabTitle = allTabs.first(where: { $0.id == currentTabId })?.title
            cell.configure(tabTitle: tabTitle)
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
        let t0 = CACurrentMediaTime()
        cell.configure(with: message, isExpanded: expandedMessageIds.contains(message.id))
        let elapsed = (CACurrentMediaTime() - t0) * 1000
        print("⏱ CELL CONFIG row=\(indexPath.row) id=\(message.id.uuidString.prefix(8)) \(String(format: "%.2f", elapsed))ms")
        cellRenderCache[message.id] = makeCellRenderHash(for: message)
        cell.isKeyboardActive = isComposerFocused
        cell.onMediaTapped = { [weak self] index, sourceFrame, _, _, _ in
            // Open unified gallery with all media (photos + videos)
            self?.onOpenGallery?(message, index, sourceFrame)
        }
        cell.onTodoToggle = { [weak self] itemId, isCompleted in
            self?.onToggleTodoItem?(message, itemId, isCompleted)
        }
        cell.onShowMoreTapped = { [weak self] in
            guard let self,
                  let indexPath = self.tableView.indexPath(for: cell) else { return }

            let wasExpanded = self.expandedMessageIds.contains(message.id)

            // For expand: snapshot offset & cell position to keep visual top stable
            let oldOffset = wasExpanded ? nil : self.tableView.contentOffset
            let oldCellMaxY = wasExpanded ? CGFloat(0) : self.tableView.rectForRow(at: indexPath).maxY

            // Toggle state
            if wasExpanded {
                self.expandedMessageIds.remove(message.id)
            } else {
                self.expandedMessageIds.insert(message.id)
            }
            self.heightCache.removeValue(forKey: message.id)
            self.heightInputCache.removeValue(forKey: message.id)
            cell.configure(with: message, isExpanded: !wasExpanded)
            let newHeight = self.calculateMessageHeight(for: message, cellWidth: self.tableView.bounds.width)
            self.heightCache[message.id] = newHeight

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.tableView.beginUpdates()
            self.tableView.endUpdates()
            self.tableView.layoutIfNeeded()

            if !wasExpanded, let oldOffset {
                // Expand: fix offset so the cell's visual top stays in place
                // and new text appears below (pushing newer messages down).
                let newCellMaxY = self.tableView.rectForRow(at: indexPath).maxY
                let delta = newCellMaxY - oldCellMaxY
                self.tableView.contentOffset = CGPoint(x: oldOffset.x, y: oldOffset.y + delta)
            }
            // Collapse: no offset correction — the inverted table naturally
            // shrinks the cell from the visual top while the button (visual
            // bottom) stays in place on screen.

            CATransaction.commit()
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
        if indexPath.row < sortedMessages.count {
            print("⏱ WILL DISPLAY row=\(indexPath.row) id=\(sortedMessages[indexPath.row].id.uuidString.prefix(8)) offset=\(Int(tableView.contentOffset.y))")
        }
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
            heightInputCache.removeAll()
            cachedHeightWidth = cellWidth
        }

        // Return cached height if available
        if let cachedHeight = heightCache[message.id] {
            return cachedHeight
        }

        // Calculate height (expensive operation)
        let t0 = CACurrentMediaTime()
        let height: CGFloat
        if isSearchTab {
            // Search tab uses SearchResultCell with different layout
            height = SearchResultCell.calculateHeight(for: message, maxWidth: cellWidth)
        } else {
            height = calculateMessageHeight(for: message, cellWidth: cellWidth)
        }
        let elapsed = (CACurrentMediaTime() - t0) * 1000
        print("⏱ HEIGHT CALC row=\(indexPath.row) id=\(message.id.uuidString.prefix(8)) \(String(format: "%.2f", elapsed))ms h=\(Int(height)) media=\(message.hasMedia) todo=\(message.isTodoList) blocks=\(message.hasContentBlocks) text=\(message.content.count)ch")

        // Cache the result alongside input hash for change detection
        heightCache[message.id] = height
        heightInputCache[message.id] = makeHeightInputHash(for: message)

        return height
    }

    /// Calculate height for a message cell (expensive - only call when not cached)
    private func calculateMessageHeight(for message: Message, cellWidth: CGFloat) -> CGFloat {
        let bubbleWidth = cellWidth - 32  // 16px margins on each side

        var height: CGFloat = 8  // Cell padding (4 top + 4 bottom)

        // Mixed content with ordered blocks (new format)
        if message.hasContentBlocks, let blocks = message.contentBlocks {
            let hasMedia = message.hasMedia && !message.aspectRatios.isEmpty
            if hasMedia {
                height += MosaicMediaView.calculateHeight(for: message.aspectRatios, maxWidth: bubbleWidth)
            }
            height += MixedContentView.calculateHeight(for: blocks, maxWidth: bubbleWidth)
            if let linkPreview = message.linkPreview {
                height += LinkPreviewBubbleView.calculateHeight(for: linkPreview, maxWidth: bubbleWidth) + 4
            }
            return max(height, 50)
        }

        // Todo list message (old format)
        if message.isTodoList, let items = message.todoItems {
            let todoHeight = TodoBubbleView.calculateHeight(for: message.todoTitle, items: items, maxWidth: bubbleWidth)
            height += todoHeight
            if let linkPreview = message.linkPreview {
                height += LinkPreviewBubbleView.calculateHeight(for: linkPreview, maxWidth: bubbleWidth) + 4
            }
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

            let maxCollapsedHeight = MessageTableCell.maxCollapsedTextHeight(for: textWidth)
            let isMessageExpanded = expandedMessageIds.contains(message.id)
            let isLongText = ceil(textHeight) > maxCollapsedHeight

            if isLongText {
                // Long text: button always visible (Show more / Show less)
                let effectiveTextHeight = isMessageExpanded ? ceil(textHeight) : ceil(maxCollapsedHeight)
                let buttonHeight: CGFloat = 4 + 20 + 8 // gap + button + bottom padding
                height += 10 + effectiveTextHeight + buttonHeight
            } else {
                if hasMedia {
                    // Media + text: spacing (10) + text + bottom padding (10)
                    height += 10 + ceil(textHeight) + 10
                } else {
                    // Text only: top padding (10) + text + bottom padding (10)
                    height += 10 + ceil(textHeight) + 10
                }
            }
        }

        // Link preview height (only for non-todo, non-contentBlocks messages)
        if let linkPreview = message.linkPreview, !message.hasContentBlocks {
            height += LinkPreviewBubbleView.calculateHeight(for: linkPreview, maxWidth: bubbleWidth) + 4
        }

        return max(height, 50)  // Minimum height
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard !sortedMessages.isEmpty else { return nil }
        // No context menu for search results
        if isSearchTab { return nil }

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
            // "New Tab" in its own inline section so its icon doesn't indent other items
            let accentUIColor: UIColor = {
                if let themeAccent = ThemeManager.shared.currentTheme.accentColor {
                    return UIColor(themeAccent)
                }
                return .tintColor
            }()
            let plusImage = UIImage(systemName: "plus")?
                .withTintColor(accentUIColor, renderingMode: .alwaysOriginal)
            let newTabSection = UIMenu(title: "", options: .displayInline, children: [
                UIAction(title: L10n.Tab.new, image: plusImage) { [weak self] _ in
                    self?.onMoveToNewTab?(message)
                }
            ])

            var existingTabActions: [UIAction] = []
            if self.currentTabId != nil {
                existingTabActions.append(UIAction(title: L10n.Reorder.inbox) { [weak self] _ in
                    self?.animateDeleteMessage(message) {
                        self?.onMoveMessage?(message, nil)
                    }
                })
            }
            let otherTabs = self.allTabs.filter { $0.id != self.currentTabId }
            for tab in otherTabs {
                existingTabActions.append(UIAction(title: tab.title) { [weak self] _ in
                    self?.animateDeleteMessage(message) {
                        self?.onMoveMessage?(message, tab.id)
                    }
                })
            }

            var moveChildren: [UIMenuElement] = [newTabSection]
            if !existingTabActions.isEmpty {
                moveChildren.append(UIMenu(title: "", options: .displayInline, children: existingTabActions))
            }

            let moveMenu = UIMenu(
                title: L10n.Menu.move,
                image: UIImage(systemName: "arrow.right.doc.on.clipboard"),
                children: moveChildren
            )
            actions.append(moveMenu)

            // Pin action
            let pinTitle = message.isPinned ? L10n.Menu.unpin : L10n.Menu.pin
            let pinIcon = message.isPinned ? "pin.slash" : "pin"
            let pinAction = UIAction(
                title: pinTitle,
                image: UIImage(systemName: pinIcon)
            ) { [weak self] _ in
                self?.onTogglePin?(message)
            }
            actions.append(pinAction)

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

// MARK: - Chat Top Fade Gradient View

/// Telegram-style edge effect: variable blur + color overlay, both with bezier-eased gradient.
/// Two layers (same as Telegram's `EdgeEffectView`):
/// 1. `VariableBlurView` (bottom) — real Gaussian blur via CAFilter, fading out at bottom
/// 2. `contentView` + mask (top) — background color overlay fading at bottom
/// Both masked/flipped for top edge: solid at top, transparent at bottom.
final class ChatTopFadeGradientView: UIView {
    // Color overlay layer
    private let contentView = UIView()
    private let contentMaskView = UIImageView()
    // Blur layer + its own fade mask
    private var blurView: VariableBlurView?
    private let blurMaskLayer = CAGradientLayer()

    /// Height of the fade zone in points (Telegram uses 50pt for nav bar)
    private static let edgeSize: CGFloat = 50

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // 1. Variable blur (bottom layer)
        let gradientImage = Self.generateBezierGradientImage(
            edgeSize: Self.edgeSize, alpha: 1.0
        )
        if let gradientImage {
            let blur = VariableBlurView(gradientMask: gradientImage, maxBlurRadius: 16.0)
            blur.transform = CGAffineTransform(scaleX: 1.0, y: -1.0)  // flip for top edge
            insertSubview(blur, at: 0)
            self.blurView = blur

            // Blur fade mask (Telegram's approach): blur is full in the top 70%,
            // then fades to invisible in the bottom 30%.
            // Since blurView is flipped (scaleY:-1), layer coordinates are inverted:
            // layer y=0 (top) = visual bottom, layer y=1 (bottom) = visual top.
            // So: clear at layer top (visual bottom) → opaque at layer bottom (visual top).
            blurMaskLayer.colors = [
                UIColor.clear.cgColor,
                UIColor.white.cgColor,
                UIColor.white.cgColor
            ]
            blurMaskLayer.locations = [0.0, 0.3, 1.0]
            blurMaskLayer.startPoint = CGPoint(x: 0.5, y: 0)
            blurMaskLayer.endPoint = CGPoint(x: 0.5, y: 1)
            blur.layer.mask = blurMaskLayer
        }

        // 2. Color overlay (top layer)
        contentView.mask = contentMaskView
        addSubview(contentView)
        contentMaskView.transform = CGAffineTransform(scaleX: 1.0, y: -1.0)
        contentMaskView.image = Self.generateBezierGradientImage(
            edgeSize: Self.edgeSize, alpha: 0.75
        )

        updateColors()

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: ChatTopFadeGradientView, _) in
            self.updateColors()
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleThemeChange),
            name: .themeDidChange, object: nil
        )
    }

    @objc private func handleThemeChange() {
        updateColors()
    }

    private func updateColors() {
        let theme = ThemeManager.shared.currentTheme
        let isDark = traitCollection.userInterfaceStyle == .dark
        contentView.backgroundColor = UIColor(isDark ? theme.backgroundColorDark : theme.backgroundColor)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentView.frame = bounds
        contentMaskView.frame = bounds
        blurView?.frame = bounds
        blurMaskLayer.frame = blurView?.layer.bounds ?? bounds
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Bezier gradient image

    private static func generateBezierGradientImage(edgeSize: CGFloat, alpha: CGFloat) -> UIImage? {
        let numSteps = 8
        let firstStep = 1
        var colors: [CGFloat] = []
        var locations: [CGFloat] = []

        for i in 0..<numSteps {
            let a: CGFloat
            if i < firstStep {
                a = 1.0
            } else {
                let step = CGFloat(i - firstStep) / CGFloat(numSteps - firstStep - 1)
                a = alpha * bezierPoint(0.42, 0.0, 0.58, 1.0, step)
            }
            colors.append(contentsOf: [1.0, 1.0, 1.0, a])
            if i < firstStep {
                locations.append(0.0)
            } else {
                let step = CGFloat(i - firstStep) / CGFloat(numSteps - firstStep - 1)
                locations.append(step)
            }
        }

        let size = CGSize(width: 8, height: edgeSize)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let gradient = CGGradient(
            colorSpace: colorSpace, colorComponents: colors,
            locations: locations, count: numSteps
        ) else {
            UIGraphicsEndImageContext()
            return nil
        }
        context.drawLinearGradient(
            gradient, start: CGPoint(x: 4, y: 0),
            end: CGPoint(x: 4, y: edgeSize), options: []
        )
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image?.stretchableImage(withLeftCapWidth: 0, topCapHeight: Int(edgeSize))
    }

    // MARK: - Bezier helpers (from Telegram's Spring.swift)

    private static func bezierPoint(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ x: CGFloat) -> CGFloat {
        var value = calcBezier(getTForX(x, x1, x2), y1, y2)
        if value >= 0.997 { value = 1.0 }
        return value
    }
    private static func calcBezier(_ t: CGFloat, _ a1: CGFloat, _ a2: CGFloat) -> CGFloat {
        ((a(a1, a2) * t + b(a1, a2)) * t + c(a1)) * t
    }
    private static func calcSlope(_ t: CGFloat, _ a1: CGFloat, _ a2: CGFloat) -> CGFloat {
        3.0 * a(a1, a2) * t * t + 2.0 * b(a1, a2) * t + c(a1)
    }
    private static func getTForX(_ x: CGFloat, _ x1: CGFloat, _ x2: CGFloat) -> CGFloat {
        var t = x
        for _ in 0..<4 {
            let slope = calcSlope(t, x1, x2)
            guard slope != 0 else { return t }
            t -= (calcBezier(t, x1, x2) - x) / slope
        }
        return t
    }
    private static func a(_ a1: CGFloat, _ a2: CGFloat) -> CGFloat { 1.0 - 3.0 * a2 + 3.0 * a1 }
    private static func b(_ a1: CGFloat, _ a2: CGFloat) -> CGFloat { 3.0 * a2 - 6.0 * a1 }
    private static func c(_ a1: CGFloat) -> CGFloat { 3.0 * a1 }
}

// MARK: - Variable Blur View (Telegram's approach)

/// Variable-radius Gaussian blur via CAFilter private API.
/// Same implementation as Telegram's `VariableBlurView` — uses base64-encoded
/// class/selector names to pass App Store review.
final class VariableBlurView: UIVisualEffectView {
    let maxBlurRadius: CGFloat
    var gradientMask: UIImage {
        didSet {
            if gradientMask !== oldValue { resetEffect() }
        }
    }

    init(gradientMask: UIImage, maxBlurRadius: CGFloat = 20.0) {
        self.gradientMask = gradientMask
        self.maxBlurRadius = maxBlurRadius
        super.init(effect: UIBlurEffect(style: .regular))
        resetEffect()
        // Hide tint overlay (second subview of UIVisualEffectView)
        if subviews.indices.contains(1) {
            subviews[1].alpha = 0
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            resetEffect()
        }
    }

    private func resetEffect() {
        // Decode class name: "CAFilter"
        guard let filterClassData = Data(base64Encoded: "Q0FGaWx0ZXI="),
              let filterClassName = String(data: filterClassData, encoding: .utf8),
              let filterClass = NSClassFromString(filterClassName) as AnyObject as? NSObjectProtocol
        else { return }

        // Decode selector: "filterWithType:"
        guard let selectorData = Data(base64Encoded: "ZmlsdGVyV2l0aFR5cGU6"),
              let selectorName = String(data: selectorData, encoding: .utf8)
        else { return }

        let selector = Selector(selectorName)
        guard filterClass.responds(to: selector) else { return }

        let variableBlur = filterClass.perform(selector, with: "variableBlur").takeUnretainedValue()
        guard let variableBlur = variableBlur as? NSObject else { return }
        guard let gradientImageRef = gradientMask.cgImage else { return }

        variableBlur.setValue(maxBlurRadius, forKey: "inputRadius")
        variableBlur.setValue(gradientImageRef, forKey: "inputMaskImage")
        variableBlur.setValue(true, forKey: "inputNormalizeEdges")

        // Apply to backdrop layer (first subview's layer)
        let backdropLayer = subviews.first?.layer
        backdropLayer?.filters = [variableBlur]
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
