//
//  UnifiedChatView.swift
//  tabsglass
//
//  Single input bar with swipeable message tabs
//

import SwiftUI
import UIKit

// MARK: - SwiftUI Bridge

struct UnifiedChatView: UIViewControllerRepresentable {
    let tabs: [Tab]
    @Binding var selectedIndex: Int
    @Binding var messageText: String
    @Binding var scrollProgress: CGFloat
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

    private var pageViewController: UIPageViewController!
    private var messageControllers: [Int: MessageListViewController] = [:]
    let inputContainer = SwiftUIComposerContainer()
    private var pageScrollView: UIScrollView?
    private var isUserSwiping: Bool = false

    // MARK: - Input Container
    private var inputContainerHeightConstraint: NSLayoutConstraint!
    private var inputContainerBottomConstraint: NSLayoutConstraint!
    private let minInputHeight: CGFloat = 80
    private var isComposerFocused: Bool = false

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

        // Обработка изменения высоты композера (мгновенно при печати)
        inputContainer.onHeightChange = { [weak self] newHeight in
            guard let self = self else { return }

            let constrainedHeight = max(self.minInputHeight, newHeight)

            guard abs(self.inputContainerHeightConstraint.constant - constrainedHeight) > 0.5 else {
                return
            }

            // Мгновенное обновление без анимации при печати
            self.inputContainerHeightConstraint.constant = constrainedHeight

            UIView.performWithoutAnimation {
                self.view.layoutIfNeeded()
            }

            self.updateAllContentInsets()
        }

        inputContainer.onSend = { [weak self] in
            guard let self = self else { return }

            self.onSend?()

            // Очищаем текст
            self.inputContainer.clearText()

            // Анимируем изменение высоты после очистки
            self.inputContainerHeightConstraint.constant = self.minInputHeight
            UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
                self.view.layoutIfNeeded()
            }

            self.reloadCurrentTab()
            self.updateAllContentInsets()

            // Scroll after layout completes
            DispatchQueue.main.async {
                self.scrollToBottom(animated: true)
            }
        }

        // Track composer focus state for keyboard handling
        inputContainer.onFocusChange = { [weak self] isFocused in
            self?.isComposerFocused = isFocused
        }

        view.addSubview(inputContainer)

        inputContainerHeightConstraint = inputContainer.heightAnchor.constraint(equalToConstant: minInputHeight)
        inputContainerBottomConstraint = inputContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)

        NSLayoutConstraint.activate([
            inputContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputContainerBottomConstraint,
            inputContainerHeightConstraint
        ])

        // Manual keyboard handling
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let endFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval,
              let curveValue = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt else { return }

        let keyboardFrameInView = view.convert(endFrame, from: nil)
        let viewHeight = view.bounds.height
        let safeAreaBottom = view.safeAreaInsets.bottom
        let keyboardTop = keyboardFrameInView.minY

        let bottomOffset: CGFloat
        if keyboardTop < viewHeight {
            // Keyboard is showing
            // Only respond if OUR composer has focus (not alert's text field)
            if !isComposerFocused {
                return
            }
            bottomOffset = viewHeight - keyboardTop
        } else {
            // Keyboard is hiding - always reset to safe area
            bottomOffset = safeAreaBottom
        }

        let animationOptions = UIView.AnimationOptions(rawValue: curveValue << 16)

        // Update constraint relative to view bottom (not safe area when keyboard visible)
        inputContainerBottomConstraint.constant = -bottomOffset + safeAreaBottom

        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.beginFromCurrentState, animationOptions],
            animations: {
                self.view.layoutIfNeeded()
            }
        )
        updateAllContentInsets()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func updateAllContentInsets() {
        // Calculate bottom padding based on where inputContainer is positioned
        let inputBottom = view.bounds.height - inputContainer.frame.minY
        let safeAreaBottom = view.safeAreaInsets.bottom
        messageControllers.values.forEach {
            $0.updateContentInset(bottomPadding: inputBottom, safeAreaBottom: safeAreaBottom)
        }
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
        // Update content inset for all visible controllers
        updateAllContentInsets()
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
    var getBottomPadding: (() -> CGFloat)?
    var getSafeAreaBottom: (() -> CGFloat)?
    var onDeleteMessage: ((Message) -> Void)?
    var onMoveMessage: ((Message, Tab) -> Void)?
    var onEditMessage: ((Message) -> Void)?

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
            // Dismiss keyboard before context menu appears
            view.window?.endEditing(true)
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
            tableView.reloadData()
            return
        }
        sortedMessages = tab.messages.sorted { $0.createdAt > $1.createdAt }
        tableView.reloadData()
    }

    func updateContentInset(bottomPadding: CGFloat, safeAreaBottom: CGFloat) {
        // Extra spacing from last message to composer
        let extraSpacing: CGFloat = 16
        // bottomPadding already includes inputContainer height + keyboard (if visible)
        let newInset = bottomPadding + extraSpacing
        let oldInset = tableView.contentInset.top
        let delta = newInset - oldInset

        tableView.contentInset.top = newInset
        tableView.verticalScrollIndicatorInsets.top = newInset

        // Only adjust offset when inset INCREASES (keyboard appearing)
        // When keyboard hides, tableView handles scroll naturally
        if delta > 1 {
            var offset = tableView.contentOffset
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
                    UIAction(title: tab.title) { _ in
                        self.onMoveMessage?(message, tab)
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
            ) { _ in
                self.onDeleteMessage?(message)
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
