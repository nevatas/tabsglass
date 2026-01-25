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
    let tabs: [Tab]
    @Binding var selectedIndex: Int
    @Binding var messageText: String
    @Binding var scrollProgress: CGFloat
    @Binding var attachedImages: [UIImage]
    let onSend: () -> Void
    var onDeleteMessage: ((Message) -> Void)?
    var onMoveMessage: ((Message, Tab) -> Void)?
    var onEditMessage: ((Message) -> Void)?

    func makeUIViewController(context: Context) -> UnifiedChatViewController {
        let vc = UnifiedChatViewController()
        vc.tabs = tabs
        vc.selectedIndex = selectedIndex
        vc.onSend = onSend
        vc.onDeleteMessage = onDeleteMessage
        vc.onMoveMessage = onMoveMessage
        vc.onEditMessage = onEditMessage
        vc.onIndexChange = { newIndex in
            selectedIndex = newIndex
        }
        vc.onTextChange = { text in
            messageText = text
        }
        vc.onScrollProgress = { progress in
            scrollProgress = progress
        }
        vc.onImagesChange = { images in
            attachedImages = images
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: UnifiedChatViewController, context: Context) {
        uiViewController.tabs = tabs
        uiViewController.onDeleteMessage = onDeleteMessage
        uiViewController.onMoveMessage = onMoveMessage
        uiViewController.onEditMessage = onEditMessage
        if uiViewController.selectedIndex != selectedIndex {
            uiViewController.selectedIndex = selectedIndex
            uiViewController.updatePageSelection(animated: true)
        }
        uiViewController.reloadCurrentTab()
    }
}

// MARK: - Unified Chat View Controller

final class UnifiedChatViewController: UIViewController {
    var tabs: [Tab] = []
    var selectedIndex: Int = 0
    var onSend: (() -> Void)?
    var onIndexChange: ((Int) -> Void)?
    var onTextChange: ((String) -> Void)?
    var onScrollProgress: ((CGFloat) -> Void)?
    var onDeleteMessage: ((Message) -> Void)?
    var onMoveMessage: ((Message, Tab) -> Void)?
    var onEditMessage: ((Message) -> Void)?
    var onImagesChange: (([UIImage]) -> Void)?

    private var pageViewController: UIPageViewController!
    private var messageControllers: [Int: MessageListViewController] = [:]
    let inputContainer = SwiftUIComposerContainer()
    private var pageScrollView: UIScrollView?
    private var isUserSwiping: Bool = false

    // MARK: - Input Container (Auto Layout)
    private var hasAutoFocused: Bool = false
    private var inputBottomToKeyboard: NSLayoutConstraint?
    private var inputBottomToSafeArea: NSLayoutConstraint?

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

        // Set initial page
        if !tabs.isEmpty {
            let initialVC = getMessageController(for: 0)
            pageViewController.setViewControllers([initialVC], direction: .forward, animated: false)
        }
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

        inputContainer.onImagesChange = { [weak self] images in
            self?.onImagesChange?(images)
        }

        view.addSubview(inputContainer)

        // Create both bottom constraints
        inputBottomToKeyboard = inputContainer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        inputBottomToSafeArea = inputContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)

        // Auto Layout: pin leading, trailing, and bottom (start with safe area)
        NSLayoutConstraint.activate([
            inputContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        inputBottomToSafeArea?.isActive = true
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

    private func getMessageController(for index: Int) -> MessageListViewController {
        if let existing = messageControllers[index] {
            existing.allTabs = tabs
            existing.onContextMenuWillShow = { [weak self] in
                self?.resetComposerPosition()
            }
            return existing
        }

        let vc = MessageListViewController()
        vc.pageIndex = index
        if index < tabs.count {
            vc.currentTab = tabs[index]
        }
        vc.allTabs = tabs
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
        vc.onMoveMessage = { [weak self] message, targetTab in
            self?.onMoveMessage?(message, targetTab)
        }
        vc.onEditMessage = { [weak self] message in
            self?.onEditMessage?(message)
        }
        vc.onOpenGallery = { [weak self] startIndex, fileNames, sourceFrame in
            self?.presentGallery(startIndex: startIndex, fileNames: fileNames, sourceFrame: sourceFrame)
        }
        messageControllers[index] = vc
        return vc
    }

    func updatePageSelection(animated: Bool) {
        guard !tabs.isEmpty, selectedIndex < tabs.count else { return }
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
            if currentVC.pageIndex < tabs.count {
                currentVC.currentTab = tabs[currentVC.pageIndex]
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
        // Auto-focus composer on first appearance
        if !hasAutoFocused {
            hasAutoFocused = true
            // Small delay to ensure view is fully laid out
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.inputContainer.focus()
            }
        }
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
        guard index < tabs.count else { return nil }
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
        let progress = offset / pageWidth

        // progress: -1 = fully swiped to previous, 0 = center, +1 = fully swiped to next
        let clampedProgress = max(-1, min(1, progress))
        onScrollProgress?(CGFloat(selectedIndex) + clampedProgress)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === pageScrollView else { return }
        isUserSwiping = false
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView === pageScrollView else { return }
        if !decelerate {
            isUserSwiping = false
        }
    }
}

// MARK: - Message List View Controller

final class MessageListViewController: UIViewController {
    var pageIndex: Int = 0
    var currentTab: Tab?
    var allTabs: [Tab] = []
    var onTap: (() -> Void)?
    var onContextMenuWillShow: (() -> Void)?
    var getBottomPadding: (() -> CGFloat)?
    var getSafeAreaBottom: (() -> CGFloat)?
    var onDeleteMessage: ((Message) -> Void)?
    var onMoveMessage: ((Message, Tab) -> Void)?
    var onEditMessage: ((Message) -> Void)?
    /// Callback when a gallery should be opened: (startIndex, fileNames, sourceFrame)
    var onOpenGallery: ((Int, [String], CGRect) -> Void)?

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
        guard let tab = currentTab else {
            sortedMessages = []
            UIView.performWithoutAnimation {
                tableView.reloadData()
            }
            return
        }
        sortedMessages = tab.messages
            .filter { !$0.isEmpty }
            .sorted { $0.createdAt > $1.createdAt }
        // Disable animations to prevent glitches with flipped tableView and context menu
        UIView.performWithoutAnimation {
            tableView.reloadData()
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
        let headerHeight: CGFloat = 115 // TabBarView + extra padding
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
        cell.configure(with: sortedMessages[indexPath.row])
        cell.onPhotoTapped = { [weak self] index, sourceFrame, _, fileNames in
            self?.onOpenGallery?(index, fileNames, sourceFrame)
        }
        cell.transform = CGAffineTransform(scaleX: 1, y: -1)
        return cell
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard !sortedMessages.isEmpty else { return nil }

        let message = sortedMessages[indexPath.row]

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self = self else { return nil }

            var actions: [UIMenuElement] = []

            // Copy action
            let copyAction = UIAction(
                title: "Скопировать",
                image: UIImage(systemName: "doc.on.doc")
            ) { _ in
                UIPasteboard.general.string = message.text
            }
            actions.append(copyAction)

            // Edit action
            let editAction = UIAction(
                title: "Изменить",
                image: UIImage(systemName: "pencil")
            ) { _ in
                self.onEditMessage?(message)
            }
            actions.append(editAction)

            // Move action (only if more than one tab)
            let otherTabs = self.allTabs.filter { $0.id != self.currentTab?.id }
            if !otherTabs.isEmpty {
                let moveMenuChildren = otherTabs.map { tab in
                    UIAction(title: tab.title) { [weak self] _ in
                        // Animate removal first, then move to target tab
                        self?.animateDeleteMessage(message) {
                            self?.onMoveMessage?(message, tab)
                        }
                    }
                }
                let moveMenu = UIMenu(
                    title: "Переместить",
                    image: UIImage(systemName: "arrow.right.doc.on.clipboard"),
                    children: moveMenuChildren
                )
                actions.append(moveMenu)
            }

            // Delete action
            let deleteAction = UIAction(
                title: "Удалить",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { [weak self] _ in
                // Animate deletion first, then delete from data
                self?.animateDeleteMessage(message) {
                    self?.onDeleteMessage?(message)
                }
            }
            actions.append(deleteAction)

            return UIMenu(children: actions)
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
