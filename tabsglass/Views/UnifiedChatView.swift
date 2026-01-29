//  СмотUnifiedChatView.swift
//  tabsglass
//
//  Single input bar with swipeable message tabs
//

import SwiftUI
import UIKit
import PhotosUI

// MARK: - SwiftUI Bridge

struct UnifiedChatView: UIViewControllerRepresentable {
    let tabs: [Tab]  // Real tabs only (Inbox is virtual)
    let messages: [Message]  // All messages
    @Binding var selectedIndex: Int  // 0 = Inbox, 1+ = real tabs
    @Binding var messageText: String
    @Binding var switchFraction: CGFloat  // -1.0 to 1.0 swipe progress
    @Binding var attachedImages: [UIImage]
    @Binding var formattingEntities: [TextEntity]  // Entities from formatting
    let onSend: () -> Void
    var onDeleteMessage: ((Message) -> Void)?
    var onMoveMessage: ((Message, UUID?) -> Void)?  // UUID? = target tabId (nil = Inbox)
    var onEditMessage: ((Message) -> Void)?
    var onRestoreMessage: (() -> Void)?
    var onShowTaskList: (() -> Void)?
    var onToggleTodoItem: ((Message, UUID, Bool) -> Void)?
    var onToggleReminder: ((Message) -> Void)?

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
        vc.onTextChange = { text in
            messageText = text
        }
        vc.onSwitchFraction = { fraction in
            switchFraction = fraction
        }
        vc.onImagesChange = { images in
            attachedImages = images
        }
        vc.onEntitiesExtracted = { entities in
            formattingEntities = entities
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UnifiedChatViewController, context: Context) {
        uiViewController.tabs = tabs
        uiViewController.allMessages = messages
        uiViewController.onDeleteMessage = onDeleteMessage
        uiViewController.onMoveMessage = onMoveMessage
        uiViewController.onEditMessage = onEditMessage
        uiViewController.onRestoreMessage = onRestoreMessage
        uiViewController.onShowTaskList = onShowTaskList
        uiViewController.onToggleTodoItem = onToggleTodoItem
        uiViewController.onToggleReminder = onToggleReminder
        if uiViewController.selectedIndex != selectedIndex {
            uiViewController.selectedIndex = selectedIndex
            uiViewController.updatePageSelection(animated: true)
        }
        uiViewController.reloadCurrentTab()
    }
}

// MARK: - Unified Chat View Controller

final class UnifiedChatViewController: UIViewController {
    var tabs: [Tab] = []  // Real tabs only (Inbox is virtual)
    var allMessages: [Message] = []  // All messages from SwiftUI
    var selectedIndex: Int = 0  // 0 = Inbox, 1+ = real tabs
    var onSend: (() -> Void)?
    var onEntitiesExtracted: (([TextEntity]) -> Void)?

    /// Total tab count including virtual Inbox
    private var totalTabCount: Int { 1 + tabs.count }
    var onIndexChange: ((Int) -> Void)?
    var onTextChange: ((String) -> Void)?
    var onSwitchFraction: ((CGFloat) -> Void)?  // -1.0 to 1.0
    var onDeleteMessage: ((Message) -> Void)?
    var onMoveMessage: ((Message, UUID?) -> Void)?  // UUID? = target tabId (nil = Inbox)
    var onEditMessage: ((Message) -> Void)?
    var onImagesChange: (([UIImage]) -> Void)?
    var onRestoreMessage: (() -> Void)?
    var onShowTaskList: (() -> Void)?
    var onToggleTodoItem: ((Message, UUID, Bool) -> Void)?
    var onToggleReminder: ((Message) -> Void)?

    private var pageViewController: UIPageViewController!
    private var messageControllers: [Int: MessageListViewController] = [:]
    let inputContainer = SwiftUIComposerContainer()
    private var pageScrollView: UIScrollView?
    private var isUserSwiping: Bool = false

    // MARK: - Input Container (Auto Layout)
    private var hasAutoFocused: Bool = false
    private var inputBottomToKeyboard: NSLayoutConstraint?
    private var inputBottomToSafeArea: NSLayoutConstraint?
    private let bottomFadeView = BottomFadeGradientView()
    private var fadeBottomToKeyboard: NSLayoutConstraint?
    private var fadeBottomToScreen: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setupPageViewController()
        setupInputView()
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
        for subview in pageViewController.view.subviews {
            if let scrollView = subview as? UIScrollView {
                pageScrollView = scrollView
                scrollView.delegate = self
                break
            }
        }

        // Set initial page (always show Inbox at index 0)
        let initialVC = getMessageController(for: 0)
        pageViewController.setViewControllers([initialVC], direction: .forward, animated: false)
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

        // Bottom fade gradient (behind inputContainer, at screen/keyboard bottom)
        bottomFadeView.translatesAutoresizingMaskIntoConstraints = false
        bottomFadeView.isUserInteractionEnabled = false
        view.addSubview(bottomFadeView)

        view.addSubview(inputContainer)

        // Create bottom constraints for input container
        inputBottomToKeyboard = inputContainer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        inputBottomToSafeArea = inputContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)

        // Create bottom constraints for fade gradient
        fadeBottomToKeyboard = bottomFadeView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        fadeBottomToScreen = bottomFadeView.bottomAnchor.constraint(equalTo: view.bottomAnchor)

        // Auto Layout: pin leading, trailing, and bottom (start with safe area)
        NSLayoutConstraint.activate([
            inputContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            // Bottom fade gradient constraints
            bottomFadeView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomFadeView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomFadeView.heightAnchor.constraint(equalToConstant: 80)
        ])
        inputBottomToSafeArea?.isActive = true
        fadeBottomToScreen?.isActive = true
    }

    /// Switch between keyboard-following and safe-area-anchored modes
    private func updateKeyboardConstraint(followKeyboard: Bool) {
        if followKeyboard {
            inputBottomToSafeArea?.isActive = false
            inputBottomToKeyboard?.isActive = true
            fadeBottomToScreen?.isActive = false
            fadeBottomToKeyboard?.isActive = true
        } else {
            inputBottomToKeyboard?.isActive = false
            inputBottomToSafeArea?.isActive = true
            fadeBottomToKeyboard?.isActive = false
            fadeBottomToScreen?.isActive = true
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

    /// Calculate tabId for given index: 0 = nil (Inbox), 1+ = real tab ID
    private func tabId(for index: Int) -> UUID? {
        guard index > 0 && index <= tabs.count else { return nil }
        return tabs[index - 1].id
    }

    /// Filter messages for a given tabId
    private func messages(for tabId: UUID?) -> [Message] {
        allMessages.filter { $0.tabId == tabId }
    }

    private func getMessageController(for index: Int) -> MessageListViewController {
        let currentTabId = tabId(for: index)

        if let existing = messageControllers[index] {
            existing.allTabs = tabs
            existing.currentTabId = currentTabId
            existing.messages = messages(for: currentTabId)
            existing.onContextMenuWillShow = { [weak self] in
                self?.resetComposerPosition()
            }
            return existing
        }

        let vc = MessageListViewController()
        vc.pageIndex = index
        vc.currentTabId = currentTabId
        vc.allTabs = tabs
        vc.messages = messages(for: currentTabId)
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
        vc.onOpenGallery = { [weak self] startIndex, fileNames, sourceFrame in
            self?.presentGallery(startIndex: startIndex, fileNames: fileNames, sourceFrame: sourceFrame)
        }
        vc.onToggleTodoItem = { [weak self] message, itemId, isCompleted in
            self?.onToggleTodoItem?(message, itemId, isCompleted)
        }
        vc.onToggleReminder = { [weak self] message in
            self?.onToggleReminder?(message)
        }
        messageControllers[index] = vc
        return vc
    }

    func updatePageSelection(animated: Bool) {
        guard selectedIndex < totalTabCount else { return }
        let vc = getMessageController(for: selectedIndex)

        // Determine direction based on current position
        if let currentVC = pageViewController.viewControllers?.first as? MessageListViewController {
            let direction: UIPageViewController.NavigationDirection = selectedIndex > currentVC.pageIndex ? .forward : .reverse
            pageViewController.setViewControllers([vc], direction: direction, animated: animated)
        } else {
            pageViewController.setViewControllers([vc], direction: .forward, animated: false)
        }
    }

    func reloadCurrentTab() {
        if let currentVC = pageViewController.viewControllers?.first as? MessageListViewController {
            let index = currentVC.pageIndex
            if index < totalTabCount {
                currentVC.currentTabId = tabId(for: index)
                currentVC.allTabs = tabs
                currentVC.messages = messages(for: currentVC.currentTabId)
                currentVC.reloadMessages()
            }
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

    // MARK: - Photo Picker

    private func showPhotoPicker() {
        var config = PHPickerConfiguration()
        config.selectionLimit = 10 - inputContainer.attachedImages.count
        config.filter = .images

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

    private func presentGallery(startIndex: Int, fileNames: [String], sourceFrame: CGRect) {
        guard !fileNames.isEmpty, startIndex < fileNames.count else { return }

        // Load full images asynchronously
        let group = DispatchGroup()
        var loadedImages: [Int: UIImage] = [:]

        for (index, fileName) in fileNames.enumerated() {
            group.enter()
            ImageCache.shared.loadFullImage(for: fileName) { image in
                if let image = image {
                    loadedImages[index] = image
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            // Convert to ordered array
            let photos = (0..<fileNames.count).compactMap { loadedImages[$0] }
            guard !photos.isEmpty, startIndex < photos.count else { return }

            let galleryVC = GalleryViewController(
                photos: photos,
                startIndex: startIndex,
                sourceFrame: sourceFrame,
                sourceImage: photos[startIndex]
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

        let group = DispatchGroup()
        var loadedImages: [UIImage] = []

        for result in results {
            group.enter()
            result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                if let image = object as? UIImage {
                    loadedImages.append(image)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.inputContainer.addImages(loadedImages)
            self.onImagesChange?(self.inputContainer.attachedImages)
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
        selectedIndex = currentVC.pageIndex
        onIndexChange?(selectedIndex)
    }
}

// MARK: - UIScrollViewDelegate (Page Swipe Progress)

extension UnifiedChatViewController: UIScrollViewDelegate {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard scrollView === pageScrollView else { return }
        isUserSwiping = true
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
        onSwitchFraction?(clampedFraction)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === pageScrollView else { return }
        isUserSwiping = false
        onSwitchFraction?(0)  // Reset fraction when swipe completes
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView === pageScrollView else { return }
        if !decelerate {
            isUserSwiping = false
            onSwitchFraction?(0)  // Reset fraction when drag ends without deceleration
        }
    }
}

// MARK: - Message List View Controller

final class MessageListViewController: UIViewController {
    var pageIndex: Int = 0  // 0 = Inbox, 1+ = real tabs
    var currentTabId: UUID?  // nil = Inbox
    var allTabs: [Tab] = []  // Real tabs only
    var messages: [Message] = []  // Messages passed from SwiftUI
    var onTap: (() -> Void)?
    var onContextMenuWillShow: (() -> Void)?
    var getBottomPadding: (() -> CGFloat)?
    var getSafeAreaBottom: (() -> CGFloat)?
    var onDeleteMessage: ((Message) -> Void)?
    var onMoveMessage: ((Message, UUID?) -> Void)?  // UUID? = target tabId (nil = Inbox)
    var onEditMessage: ((Message) -> Void)?
    /// Callback when a gallery should be opened: (startIndex, fileNames, sourceFrame)
    var onOpenGallery: ((Int, [String], CGRect) -> Void)?
    /// Callback when a todo item is toggled: (message, itemId, isCompleted)
    var onToggleTodoItem: ((Message, UUID, Bool) -> Void)?
    /// Callback when reminder is toggled on a message
    var onToggleReminder: ((Message) -> Void)?

    private let tableView = UITableView()
    private var sortedMessages: [Message] = []
    private var longPressGesture: UILongPressGestureRecognizer!
    private var hasAppearedBefore = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setupTableView()
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.keyboardDismissMode = .interactive
        tableView.showsVerticalScrollIndicator = false
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 200
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(MessageTableCell.self, forCellReuseIdentifier: "MessageCell")
        tableView.register(EmptyTableCell.self, forCellReuseIdentifier: "EmptyCell")
        tableView.transform = CGAffineTransform(scaleX: 1, y: -1)

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.cancelsTouchesInView = false
        tableView.addGestureRecognizer(tap)

        // Dismiss keyboard early on long press (before context menu appears)
        longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.3 // Fire before context menu (default ~0.5s)
        longPressGesture.cancelsTouchesInView = false
        longPressGesture.delegate = self
        tableView.addGestureRecognizer(longPressGesture)
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

    private func refreshContentInset() {
        let bottomPadding = getBottomPadding?() ?? 80
        let safeAreaBottom = getSafeAreaBottom?() ?? 0
        updateContentInset(bottomPadding: bottomPadding, safeAreaBottom: safeAreaBottom)
    }

    func reloadMessages() {
        let oldMessages = sortedMessages
        let newMessages = messages
            .filter { !$0.isEmpty }
            .sorted { $0.createdAt > $1.createdAt }

        // Check if only content changed (same IDs, same order) - just reconfigure cells
        let oldIds = oldMessages.map { $0.id }
        let newIds = newMessages.map { $0.id }

        if oldIds == newIds {
            // Same messages, just update content - reconfigure visible cells without animation
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
            // Structure changed - full reload
            sortedMessages = newMessages
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            UIView.performWithoutAnimation {
                tableView.reloadData()
            }
            CATransaction.commit()
        }
    }

    /// Animate message deletion with smooth fade animation
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

        // Remove from local array first
        sortedMessages.remove(at: index)

        // Animate the row deletion
        tableView.performBatchUpdates {
            tableView.deleteRows(at: [IndexPath(row: index, section: 0)], with: .fade)
        } completion: { _ in
            completion()
        }
    }

    func updateContentInset(bottomPadding: CGFloat, safeAreaBottom: CGFloat, animated: Bool = false) {
        // Extra spacing from last message to composer
        let extraSpacing: CGFloat = 16
        // bottomPadding already includes inputContainer height + keyboard (if visible)
        let newInset = bottomPadding + extraSpacing
        let oldInset = tableView.contentInset.top
        let delta = newInset - oldInset

        // Save current offset BEFORE changing inset (tableView auto-adjusts on inset change)
        let currentOffset = tableView.contentOffset

        // Visual bottom (composer area) - tableView is flipped so top = visual bottom
        tableView.contentInset.top = newInset
        tableView.verticalScrollIndicatorInsets.top = newInset

        // Visual top (header/tab bar area) - tableView is flipped so bottom = visual top
        // Safe area top + header content + extra padding
        let safeAreaTop = view.safeAreaInsets.top
        let headerHeight: CGFloat = 115
        let topInset = safeAreaTop + headerHeight
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

        // Recalculate empty cell height to stay centered
        if sortedMessages.isEmpty {
            tableView.beginUpdates()
            tableView.endUpdates()
        }
    }

    func scrollToBottom(animated: Bool) {
        guard !sortedMessages.isEmpty else { return }
        // Ensure table has updated layout
        tableView.layoutIfNeeded()
        // For flipped table: scroll to show row 0 at visual bottom (near composer)
        // Use .top because the table is flipped - .top in flipped coordinates = visual bottom
        tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: animated)
    }
}

// MARK: - UITableViewDataSource & Delegate

extension MessageListViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sortedMessages.isEmpty ? 1 : sortedMessages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if sortedMessages.isEmpty {
            let cell = tableView.dequeueReusableCell(withIdentifier: "EmptyCell", for: indexPath) as! EmptyTableCell
            cell.transform = CGAffineTransform(scaleX: 1, y: -1)
            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: "MessageCell", for: indexPath) as! MessageTableCell
        let message = sortedMessages[indexPath.row]
        cell.configure(with: message)
        cell.onPhotoTapped = { [weak self] index, sourceFrame, _, fileNames in
            self?.onOpenGallery?(index, fileNames, sourceFrame)
        }
        cell.onTodoToggle = { [weak self] itemId, isCompleted in
            self?.onToggleTodoItem?(message, itemId, isCompleted)
        }
        cell.transform = CGAffineTransform(scaleX: 1, y: -1)
        return cell
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if sortedMessages.isEmpty {
            let availableHeight = tableView.bounds.height - tableView.contentInset.top - tableView.contentInset.bottom
            return max(200, availableHeight)
        }

        let message = sortedMessages[indexPath.row]
        let cellWidth = tableView.bounds.width
        let bubbleWidth = cellWidth - 32  // 16px margins on each side

        var height: CGFloat = 8  // Cell padding (4 top + 4 bottom)

        // Todo list message
        if message.isTodoList, let items = message.todoItems {
            let todoHeight = TodoBubbleView.calculateHeight(for: message.todoTitle, items: items, maxWidth: bubbleWidth)
            height += todoHeight
            return max(height, 50)
        }

        let hasPhotos = !message.photoFileNames.isEmpty && !message.aspectRatios.isEmpty
        let hasText = !message.content.isEmpty

        // Calculate mosaic height if has photos
        if hasPhotos {
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

            if hasPhotos {
                // Photos + text: spacing (10) + text + bottom padding (10)
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
                moveMenuChildren.append(UIAction(title: L10n.Reorder.inbox, image: UIImage(systemName: "tray")) { [weak self] _ in
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

    func tableView(_ tableView: UITableView, previewForHighlightingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        return makeTargetedPreview(for: configuration)
    }

    func tableView(_ tableView: UITableView, previewForDismissingContextMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        return makeTargetedPreview(for: configuration)
    }

    private func makeTargetedPreview(for configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
        guard let indexPath = configuration.identifier as? IndexPath,
              let cell = tableView.cellForRow(at: indexPath) as? MessageTableCell else {
            return nil
        }

        let bubbleView = cell.bubbleViewForContextMenu
        let bubbleFrame = bubbleView.convert(bubbleView.bounds, to: nil)
        let screenHeight = view.window?.windowScene?.screen.bounds.height ?? UIScreen.main.bounds.height
        let maxPreviewHeight = screenHeight * 0.4

        // For short cells, use standard preview (container includes bubble + reminder badge)
        if bubbleFrame.height <= maxPreviewHeight {
            let parameters = UIPreviewParameters()
            parameters.backgroundColor = .clear
            return UITargetedPreview(view: bubbleView, parameters: parameters)
        }

        // For tall cells, show top portion
        let snapshotHeight = maxPreviewHeight

        // Create container for top portion
        let containerView = UIView(frame: CGRect(x: 0, y: 0, width: bubbleView.bounds.width, height: snapshotHeight))
        containerView.backgroundColor = .clear
        containerView.clipsToBounds = true
        containerView.layer.cornerRadius = 18

        // Create snapshot positioned at top
        if let snapshot = bubbleView.snapshotView(afterScreenUpdates: false) {
            snapshot.frame = CGRect(x: 0, y: 0, width: bubbleView.bounds.width, height: bubbleView.bounds.height)
            containerView.addSubview(snapshot)
        }

        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear

        // Target at the top of the bubble view
        let center = CGPoint(x: bubbleView.bounds.midX, y: snapshotHeight / 2)
        let target = UIPreviewTarget(container: bubbleView, center: center)

        return UITargetedPreview(view: containerView, parameters: parameters, target: target)
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
            bgColor.cgColor
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
