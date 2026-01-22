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

    func makeUIViewController(context: Context) -> UnifiedChatViewController {
        let vc = UnifiedChatViewController()
        vc.tabs = tabs
        vc.selectedIndex = selectedIndex
        vc.onSend = onSend
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

    private var pageViewController: UIPageViewController!
    private var messageControllers: [Int: MessageListViewController] = [:]
    private let inputContainer = SwiftUIComposerContainer()
    private var pageScrollView: UIScrollView?
    private var isUserSwiping: Bool = false

    // MARK: - Keyboard State Tracking
    private var keyboardHeight: CGFloat = 0
    private var inputContainerBottomConstraint: NSLayoutConstraint!
    private var inputContainerHeightConstraint: NSLayoutConstraint!
    private let minInputHeight: CGFloat = 80
    private var isKeyboardVisible: Bool = false

    // MARK: - Pan Gesture for Interactive Dismiss
    private var panGestureRecognizer: UIPanGestureRecognizer!
    private var keyboardPanStartY: CGFloat = 0
    private let dismissThreshold: CGFloat = 3.0
    private let dismissVelocityThreshold: CGFloat = 100.0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setupPageViewController()
        setupInputView()
        setupKeyboardObservers()
        setupPanGesture()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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

            // Очищаем текст (это вызовет onHeightChange с минимальной высотой)
            self.inputContainer.clearText()

            // Анимируем изменение высоты после очистки
            self.inputContainerHeightConstraint.constant = self.minInputHeight
            UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
                self.view.layoutIfNeeded()
            }

            self.reloadCurrentTab()
            self.updateAllContentInsets()
            self.scrollToBottom(animated: true)
        }

        view.addSubview(inputContainer)

        inputContainerBottomConstraint = inputContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        inputContainerHeightConstraint = inputContainer.heightAnchor.constraint(equalToConstant: minInputHeight)

        NSLayoutConstraint.activate([
            inputContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputContainerBottomConstraint,
            inputContainerHeightConstraint
        ])
    }


    // MARK: - Keyboard Handling

    private func setupKeyboardObservers() {
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

        // Convert keyboard frame to view coordinates
        let keyboardFrameInView = view.convert(endFrame, from: nil)
        let viewHeight = view.bounds.height

        // Calculate keyboard height (0 if keyboard below view)
        let newKeyboardHeight: CGFloat
        if keyboardFrameInView.minY < viewHeight {
            newKeyboardHeight = viewHeight - keyboardFrameInView.minY
        } else {
            newKeyboardHeight = 0
        }

        isKeyboardVisible = newKeyboardHeight > 0
        keyboardHeight = newKeyboardHeight

        // Bottom inset: keyboard height when visible, safe area when hidden
        let bottomInset = isKeyboardVisible ? keyboardHeight : view.safeAreaInsets.bottom

        let animationOptions = UIView.AnimationOptions(rawValue: curveValue << 16)

        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.beginFromCurrentState, animationOptions],
            animations: {
                self.inputContainerBottomConstraint.constant = -bottomInset
                self.view.layoutIfNeeded()
                self.updateAllContentInsets()
            }
        )
    }

    private func updateAllContentInsets() {
        let safeAreaBottom = view.safeAreaInsets.bottom
        messageControllers.values.forEach {
            $0.updateContentInset(keyboardHeight: keyboardHeight, safeAreaBottom: safeAreaBottom)
        }
    }

    // MARK: - Pan Gesture for Interactive Keyboard Dismiss

    private func setupPanGesture() {
        panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGestureRecognizer.delegate = self
        view.addGestureRecognizer(panGestureRecognizer)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard isKeyboardVisible else { return }

        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)

        switch gesture.state {
        case .began:
            keyboardPanStartY = keyboardHeight

        case .changed:
            // Only handle downward drags past threshold
            guard translation.y > dismissThreshold else { return }

            // Calculate new keyboard offset interactively
            let dragOffset = translation.y - dismissThreshold
            let newOffset = min(keyboardPanStartY, max(0, keyboardPanStartY - dragOffset))
            let adjustedOffset = keyboardPanStartY - newOffset

            inputContainerBottomConstraint.constant = -(keyboardPanStartY - adjustedOffset)
            messageControllers.values.forEach { $0.updateContentInset(keyboardHeight: keyboardPanStartY - adjustedOffset, safeAreaBottom: 0) }

        case .ended, .cancelled:
            if velocity.y > dismissVelocityThreshold || translation.y > keyboardPanStartY / 2 {
                // Dismiss keyboard
                view.endEditing(true)
            } else {
                // Snap back to keyboard position
                UIView.animate(
                    withDuration: 0.25,
                    delay: 0,
                    usingSpringWithDamping: 0.9,
                    initialSpringVelocity: 0,
                    options: .beginFromCurrentState,
                    animations: {
                        self.inputContainerBottomConstraint.constant = -self.keyboardPanStartY
                        self.view.layoutIfNeeded()
                        self.messageControllers.values.forEach { $0.updateContentInset(keyboardHeight: self.keyboardPanStartY, safeAreaBottom: 0) }
                    }
                )
            }

        default:
            break
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
            return existing
        }

        let vc = MessageListViewController()
        vc.pageIndex = index
        if index < tabs.count {
            vc.currentTab = tabs[index]
        }
        vc.onTap = { [weak self] in
            self?.view.endEditing(true)
        }
        vc.inputContainerHeight = { [weak self] in
            self?.inputContainerHeightConstraint.constant ?? 80
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

// MARK: - UIGestureRecognizerDelegate

extension UnifiedChatViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow pan gesture to work simultaneously with page view controller scroll
        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer == panGestureRecognizer else { return true }
        // Only begin pan for vertical gestures when keyboard is visible
        let velocity = panGestureRecognizer.velocity(in: view)
        return abs(velocity.y) > abs(velocity.x) && isKeyboardVisible
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
    var onTap: (() -> Void)?
    var inputContainerHeight: (() -> CGFloat)?

    private let tableView = UITableView()
    private var sortedMessages: [Message] = []

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
    }

    @objc private func handleTap() {
        onTap?()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadMessages()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Scroll to latest messages after layout is complete
        scrollToBottom(animated: false)
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

    func updateContentInset(keyboardHeight: CGFloat = 0, safeAreaBottom: CGFloat = 0) {
        let inputHeight = inputContainerHeight?() ?? 80
        // When keyboard visible, it already covers safe area; when hidden, add safe area
        let bottomPadding = keyboardHeight > 0 ? keyboardHeight : safeAreaBottom
        // Extra spacing from last message to composer (2x the spacing between messages)
        let extraSpacing: CGFloat = 8
        let totalInset = inputHeight + bottomPadding + extraSpacing
        tableView.contentInset.top = totalInset
        tableView.verticalScrollIndicatorInsets.top = totalInset
    }

    func scrollToBottom(animated: Bool) {
        guard !sortedMessages.isEmpty else { return }
        // Ensure table has updated layout
        tableView.layoutIfNeeded()
        // Since table is flipped, scroll to row 0 (newest message)
        tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .bottom, animated: animated)
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
}
