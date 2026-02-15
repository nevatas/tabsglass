//
//  TabBarView.swift
//  tabsglass
//
//  Telegram-style horizontal tab bar with unified glass container
//  Note: Index 0 = Inbox (virtual), Index 1+ = real tabs
//

import SwiftUI
import UIKit

// MARK: - Tab Display Item (Virtual Inbox + Real Tabs)

/// Type alias to avoid conflict with SwiftUI.Tab
typealias AppTab = Tab

/// Represents Search, virtual Inbox, or a real Tab for display in tab bar
enum TabDisplayItem: Identifiable {
    case search
    case inbox
    case realTab(AppTab)

    var id: String {
        switch self {
        case .search: return "search"
        case .inbox: return "inbox"
        case .realTab(let tab): return tab.id.uuidString
        }
    }

    var title: String {
        switch self {
        case .search: return ""  // Icon only
        case .inbox: return AppSettings.shared.inboxTitle
        case .realTab(let tab): return tab.title
        }
    }

    var isSearch: Bool {
        if case .search = self { return true }
        return false
    }

    var isInbox: Bool {
        if case .inbox = self { return true }
        return false
    }

    var tab: AppTab? {
        if case .realTab(let tab) = self { return tab }
        return nil
    }
}

// MARK: - Tab Bar View

struct TabBarView: View {
    let tabs: [Tab]
    var inboxTitle: String = AppSettings.shared.inboxTitle
    @AppStorage("spaceName") private var spaceName = "Taby"
    @Binding var selectedIndex: Int
    @Binding var switchFraction: CGFloat  // -1.0 ... 0 ... 1.0 при свайпе
    let onAddTap: () -> Void
    let onMenuTap: () -> Void
    let onRenameTab: (Tab) -> Void
    let onRenameInbox: () -> Void
    let onReorderTabs: () -> Void
    let onDeleteTab: (Tab) -> Void
    var onGoToInbox: (() -> Void)? = nil  // Called when arrow button tapped on Search

    @Environment(\.colorScheme) private var colorScheme
    private var themeManager: ThemeManager { ThemeManager.shared }

    private var isOnSearch: Bool { selectedIndex == 0 }

    private var iconColor: Color {
        themeManager.currentTheme.accentColor ?? (colorScheme == .dark ? .white : .black)
    }

    /// Progress toward Search screen (0 = not on Search, 1 = fully on Search)
    /// Interpolates during swipe for smooth title/button transition
    private var searchProgress: CGFloat {
        if selectedIndex == 0 {
            // On Search, swiping right toward Inbox: 1 → 0
            return max(0, 1 - switchFraction)
        } else if selectedIndex == 1 && switchFraction < 0 {
            // On Inbox, swiping left toward Search: 0 → 1
            return min(1, -switchFraction)
        }
        return 0
    }

    var body: some View {
        HStack(spacing: 8) {
            // Settings button (left) - circular liquid glass
            Button(action: onMenuTap) {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)

            // Middle: Tab bar ↔ "Search" cross-fade
            ZStack {
                ScrollingTabBar(
                    tabs: tabs,
                    inboxTitle: inboxTitle,
                    selectedIndex: $selectedIndex,
                    switchFraction: $switchFraction,
                    onRenameTab: onRenameTab,
                    onRenameInbox: onRenameInbox,
                    onReorderTabs: onReorderTabs,
                    onDeleteTab: onDeleteTab
                )
                .opacity(1 - searchProgress)
                .allowsHitTesting(searchProgress < 0.5)

                Text(spaceName)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .opacity(searchProgress)
                    .scaleEffect(0.8 + searchProgress * 0.2)
                    .allowsHitTesting(false)
            }
            .frame(height: 46)

            // Right button - icon morphs between plus and arrow during swipe
            Button {
                if searchProgress >= 0.5 {
                    onGoToInbox?()
                } else {
                    onAddTap()
                }
            } label: {
                ZStack {
                    Image(systemName: "plus")
                        .opacity(1 - searchProgress)
                        .scaleEffect(1 - searchProgress * 0.5)

                    Image(systemName: "chevron.right")
                        .opacity(searchProgress)
                        .scaleEffect(0.5 + searchProgress * 0.5)
                }
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 10)
        // No material background — ChatTopFadeGradientView in MessageListViewController
        // provides a theme-colored gradient behind the header area
    }
}

// MARK: - Scrolling Tab Bar (UIKit Engine)

private struct ScrollingTabBar: View {
    let tabs: [Tab]
    let inboxTitle: String
    @Binding var selectedIndex: Int
    @Binding var switchFraction: CGFloat
    let onRenameTab: (Tab) -> Void
    let onRenameInbox: () -> Void
    let onReorderTabs: () -> Void
    let onDeleteTab: (Tab) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var allItems: [TabDisplayItem] {
        // Reference inboxTitle so SwiftUI tracks it as a dependency
        _ = inboxTitle
        var items: [TabDisplayItem] = [.search, .inbox]
        items.append(contentsOf: tabs.map { TabDisplayItem.realTab($0) })
        return items
    }

    var body: some View {
        ScrollingTabBarRepresentable(
            items: allItems,
            selectedIndex: $selectedIndex,
            switchFraction: $switchFraction,
            colorScheme: colorScheme,
            showReorder: tabs.count > 1,
            onRenameTab: onRenameTab,
            onRenameInbox: onRenameInbox,
            onReorderTabs: onReorderTabs,
            onDeleteTab: onDeleteTab
        )
        .frame(height: 46)
        .clipShape(Capsule())
        .background {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular, in: .capsule)
                .id("tabbar-v2-glass-\(colorScheme)")
        }
    }
}

private struct ScrollingTabBarRepresentable: UIViewRepresentable {
    let items: [TabDisplayItem]
    @Binding var selectedIndex: Int
    @Binding var switchFraction: CGFloat
    let colorScheme: ColorScheme
    let showReorder: Bool
    let onRenameTab: (Tab) -> Void
    let onRenameInbox: () -> Void
    let onReorderTabs: () -> Void
    let onDeleteTab: (Tab) -> Void

    func makeUIView(context: Context) -> ScrollingTabBarEngine {
        ScrollingTabBarEngine()
    }

    func updateUIView(_ uiView: ScrollingTabBarEngine, context: Context) {
        let selectedBinding = _selectedIndex
        uiView.onSelectIndex = { index in
            guard selectedBinding.wrappedValue != index else { return }
            selectedBinding.wrappedValue = index
        }

        uiView.onRenameItem = { item in
            if item.isInbox {
                onRenameInbox()
            } else if let tab = item.tab {
                onRenameTab(tab)
            }
        }

        uiView.onReorderItem = { item in
            guard !item.isInbox else { return }
            onReorderTabs()
        }

        uiView.onDeleteItem = { item in
            if let tab = item.tab {
                onDeleteTab(tab)
            }
        }

        uiView.apply(
            items: items,
            selectedIndex: selectedIndex,
            switchFraction: switchFraction,
            colorScheme: colorScheme,
            showReorder: showReorder
        )
    }
}

private final class ScrollingTabBarEngine: UIView, UIScrollViewDelegate {
    var onSelectIndex: ((Int) -> Void)?
    var onRenameItem: ((TabDisplayItem) -> Void)?
    var onReorderItem: ((TabDisplayItem) -> Void)?
    var onDeleteItem: ((TabDisplayItem) -> Void)?

    private enum UpdateReason {
        case none
        case tap
        case swipe
        case appendSelection
        case selectionChange
        case contentChange
    }

    private struct LayoutState {
        let framesByID: [String: CGRect]
        let framesByIndex: [Int: CGRect]
        let contentWidth: CGFloat
    }

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let indicatorHostingController = UIHostingController(rootView: IndicatorGlassCapsuleView())

    private var itemNodes: [String: TabHostedNode] = [:]
    private var orderedIDs: [String] = []
    private var itemsByID: [String: TabDisplayItem] = [:]
    private var snapshotTitlesByID: [String: String] = [:]

    private var selectedIndex: Int = 1
    private var switchFraction: CGFloat = 0
    private var colorScheme: ColorScheme = .dark
    private var showReorder = false

    private var contextMenuActiveItemID: String?
    private var contextMenuPressingItemID: String?

    private var transitionAnimator: UIViewPropertyAnimator?
    private var isUserInteracting = false
    private var lastKnownBoundsSize: CGSize = .zero
    private var pendingTapSelectionIndex: Int?
    private var pendingRemovedNodes: [TabHostedNode] = []

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.backgroundColor = .clear
        self.clipsToBounds = false

        self.scrollView.backgroundColor = .clear
        self.scrollView.showsHorizontalScrollIndicator = false
        self.scrollView.showsVerticalScrollIndicator = false
        self.scrollView.alwaysBounceHorizontal = true
        self.scrollView.alwaysBounceVertical = false
        self.scrollView.contentInsetAdjustmentBehavior = .never
        self.scrollView.delaysContentTouches = false
        self.scrollView.clipsToBounds = false
        self.scrollView.delegate = self
        self.addSubview(self.scrollView)

        self.contentView.backgroundColor = .clear
        self.scrollView.addSubview(self.contentView)

        let indicatorView = self.indicatorHostingController.view!
        indicatorView.backgroundColor = .clear
        indicatorView.isOpaque = false
        self.contentView.addSubview(indicatorView)
        self.contentView.sendSubviewToBack(indicatorView)
        self.updateIndicatorAppearance(for: .dark)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.scrollView.frame = self.bounds
        let sizeChanged = self.bounds.size != self.lastKnownBoundsSize
        self.lastKnownBoundsSize = self.bounds.size
        if sizeChanged {
            self.applyLayout(reason: .contentChange, animated: false)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if self.window == nil {
            self.stopTransitionAnimation()
            return
        }
        self.stopTransitionAnimation()
        self.refreshNodeViews()
        self.applyLayout(reason: .contentChange, animated: false)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            self.stopTransitionAnimation()
            if self.needsNodeRecovery() {
                self.rebuildNodesFromCurrentState()
                self.refreshNodeViews()
            }
            self.applyLayout(reason: .contentChange, animated: false)
        }
    }

    func apply(
        items: [TabDisplayItem],
        selectedIndex: Int,
        switchFraction: CGFloat,
        colorScheme: ColorScheme,
        showReorder: Bool
    ) {
        let previousSwitchFraction = self.switchFraction
        let clampedSelectedIndex = max(0, min(selectedIndex, max(items.count - 1, 0)))
        if let pendingTapSelectionIndex, pendingTapSelectionIndex >= items.count {
            self.pendingTapSelectionIndex = nil
        }
        let resolvedSelectedIndex: Int
        if let pendingTapSelectionIndex = self.pendingTapSelectionIndex {
            if clampedSelectedIndex == pendingTapSelectionIndex {
                self.pendingTapSelectionIndex = nil
                resolvedSelectedIndex = clampedSelectedIndex
            } else {
                resolvedSelectedIndex = pendingTapSelectionIndex
            }
        } else {
            resolvedSelectedIndex = clampedSelectedIndex
        }
        let previousIDs = self.orderedIDs
        let previousCount = previousIDs.count
        let previousSelected = self.selectedIndex

        let idsChanged = previousIDs != items.map(\.id)
        let contentMetricsChanged = self.hasContentMetricsChange(
            newItems: items
        )
        let switchChanged = abs(previousSwitchFraction - switchFraction) > 0.0005
        let selectedChanged = previousSelected != resolvedSelectedIndex
        let appendedAndSelectedLast = items.count > previousCount && resolvedSelectedIndex == max(items.count - 1, 0)

        self.itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        self.snapshotTitlesByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.title) })
        self.orderedIDs = items.map(\.id)
        self.showReorder = showReorder
        self.switchFraction = switchFraction
        self.selectedIndex = resolvedSelectedIndex
        if self.colorScheme != colorScheme {
            self.colorScheme = colorScheme
            self.updateIndicatorAppearance(for: colorScheme)
        }

        let syncResult = self.syncNodes(for: items)
        self.trimContextMenuStateIfNeeded(validIDs: Set(self.orderedIDs))
        self.refreshNodeViews()

        let reason: UpdateReason
        if abs(switchFraction) > 0.001 && self.pendingTapSelectionIndex == nil {
            reason = .swipe
        } else if selectedChanged && self.pendingTapSelectionIndex != nil {
            reason = .tap
        } else if appendedAndSelectedLast {
            reason = .appendSelection
        } else if selectedChanged {
            reason = .selectionChange
        } else if idsChanged || contentMetricsChanged {
            reason = .contentChange
        } else {
            reason = .none
        }

        let hasLayoutAffectingChange =
            syncResult.hasChanges ||
            selectedChanged ||
            idsChanged ||
            contentMetricsChanged ||
            switchChanged
        guard hasLayoutAffectingChange else {
            if self.needsNodeRecovery() {
                self.rebuildNodesFromCurrentState()
                self.refreshNodeViews()
                self.applyLayout(reason: .contentChange, animated: false)
            }
            return
        }

        let shouldAnimate =
            syncResult.hasChanges ||
            selectedChanged ||
            idsChanged ||
            contentMetricsChanged
        self.applyLayout(
            reason: reason,
            animated: shouldAnimate,
            insertedIDs: syncResult.insertedIDs,
            removedNodes: syncResult.removedNodes
        )
    }

    private func hasContentMetricsChange(
        newItems: [TabDisplayItem]
    ) -> Bool {
        for item in newItems {
            guard let oldTitle = self.snapshotTitlesByID[item.id] else { continue }
            if oldTitle != item.title { return true }
        }
        return false
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        self.stopTransitionAnimation()
        self.isUserInteracting = true
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            self.isUserInteracting = false
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        self.isUserInteracting = false
    }

    private func syncNodes(for items: [TabDisplayItem]) -> (insertedIDs: Set<String>, removedNodes: [TabHostedNode], hasChanges: Bool) {
        let newIDs = Set(items.map(\.id))
        var removedNodes: [TabHostedNode] = []
        var insertedIDs = Set<String>()

        for (id, node) in self.itemNodes where !newIDs.contains(id) {
            removedNodes.append(node)
            self.itemNodes.removeValue(forKey: id)
        }

        for item in items where self.itemNodes[item.id] == nil {
            let node = TabHostedNode(item: item)
            self.itemNodes[item.id] = node
            self.contentView.addSubview(node.containerView)
            insertedIDs.insert(item.id)
        }

        for id in self.orderedIDs {
            if let node = self.itemNodes[id] {
                self.contentView.bringSubviewToFront(node.containerView)
            }
        }
        self.contentView.sendSubviewToBack(self.indicatorHostingController.view)

        let hasChanges = !removedNodes.isEmpty || !insertedIDs.isEmpty
        return (insertedIDs: insertedIDs, removedNodes: removedNodes, hasChanges: hasChanges)
    }

    private func refreshNodeViews() {
        let count = self.orderedIDs.count
        guard count > 0 else { return }

        for (index, id) in self.orderedIDs.enumerated() {
            guard let item = self.itemsByID[id], let node = self.itemNodes[id] else { continue }
            let progress = self.selectionProgress(for: index, itemCount: count)
            node.overrideStyle(for: self.colorScheme)
            node.update(
                item: item,
                selectionProgress: progress,
                isContextMenuHighlighted: self.contextMenuActiveItemID == id,
                isContextMenuPressing: self.contextMenuPressingItemID == id,
                showReorder: self.showReorder,
                onTap: { [weak self] in
                    self?.handleTap(for: id)
                },
                onRename: { [weak self] in
                    self?.handleRename(for: id)
                },
                onReorder: { [weak self] in
                    self?.handleReorder(for: id)
                },
                onDelete: { [weak self] in
                    self?.handleDelete(for: id)
                },
                onContextMenuPressBegan: { [weak self] in
                    self?.setContextMenuPressing(id: id, active: true)
                },
                onContextMenuPressEnded: { [weak self] in
                    self?.setContextMenuPressing(id: id, active: false)
                },
                onContextMenuWillShow: { [weak self] in
                    self?.setContextMenuActive(id: id, active: true)
                },
                onContextMenuDidHide: { [weak self] in
                    self?.setContextMenuActive(id: id, active: false)
                }
            )
        }
    }

    private func applyLayout(
        reason: UpdateReason,
        animated: Bool,
        insertedIDs: Set<String> = [],
        removedNodes: [TabHostedNode] = []
    ) {
        guard !self.orderedIDs.isEmpty else {
            self.contentView.frame = CGRect(origin: .zero, size: self.bounds.size)
            self.scrollView.contentSize = self.contentView.bounds.size
            self.indicatorHostingController.view?.isHidden = true
            for node in removedNodes {
                node.containerView.removeFromSuperview()
            }
            return
        }

        let layoutState = self.computeLayoutState()
        let finalContentWidth = layoutState.contentWidth
        let previousContentWidth = max(self.scrollView.contentSize.width, self.bounds.width)
        let shouldKeepPreviousWidthDuringRemovalAnimation =
            animated &&
            !removedNodes.isEmpty &&
            previousContentWidth > finalContentWidth + 0.5
        let activeContentWidth =
            shouldKeepPreviousWidthDuringRemovalAnimation ? previousContentWidth : finalContentWidth
        self.contentView.frame = CGRect(
            origin: .zero,
            size: CGSize(width: activeContentWidth, height: self.bounds.height)
        )
        self.scrollView.contentSize = CGSize(width: activeContentWidth, height: self.bounds.height)

        let selectedFrame = layoutState.framesByIndex[self.selectedIndex]
        let indicatorFrame = self.interpolatedSelectionFrame(framesByIndex: layoutState.framesByIndex) ?? selectedFrame
        let currentOffset = self.scrollView.contentOffset.x
        let targetOffset: CGFloat
        switch reason {
        case .tap, .selectionChange:
            if let selectedFrame {
                targetOffset = self.centeredOffset(for: selectedFrame.midX, contentWidth: finalContentWidth)
            } else {
                targetOffset = self.clampedOffset(currentOffset, contentWidth: finalContentWidth)
            }
        case .appendSelection:
            if let selectedFrame {
                targetOffset = self.offsetEnsuringVisible(
                    frame: selectedFrame,
                    currentOffset: currentOffset,
                    contentWidth: finalContentWidth
                )
            } else {
                targetOffset = self.clampedOffset(currentOffset, contentWidth: finalContentWidth)
            }
        case .swipe:
            if let indicatorFrame {
                targetOffset = self.centeredOffset(for: indicatorFrame.midX, contentWidth: finalContentWidth)
            } else {
                targetOffset = self.clampedOffset(currentOffset, contentWidth: finalContentWidth)
            }
        case .contentChange:
            if let selectedFrame {
                targetOffset = self.centeredOffset(for: selectedFrame.midX, contentWidth: finalContentWidth)
            } else {
                targetOffset = self.clampedOffset(currentOffset, contentWidth: finalContentWidth)
            }
        case .none:
            targetOffset = self.clampedOffset(currentOffset, contentWidth: finalContentWidth)
        }

        let shouldAnimate = animated && reason != .swipe && !self.isUserInteracting
        if shouldAnimate {
            self.animateTransition(
                reason: reason,
                toFrames: layoutState.framesByID,
                toOffsetX: targetOffset,
                indicatorFrame: indicatorFrame,
                insertedIDs: insertedIDs,
                removedNodes: removedNodes,
                finalContentWidth: finalContentWidth
            )
        } else {
            self.stopTransitionAnimation()
            self.applyFrames(layoutState.framesByID)
            self.scrollView.contentOffset = CGPoint(x: targetOffset, y: 0)
            self.applyIndicatorFrame(indicatorFrame)
            for id in insertedIDs {
                self.itemNodes[id]?.containerView.alpha = 1
                self.itemNodes[id]?.containerView.transform = .identity
            }
            for node in removedNodes {
                node.containerView.removeFromSuperview()
            }
            self.finalizeScrollableGeometry(contentWidth: finalContentWidth)
        }
    }

    private func animateTransition(
        reason: UpdateReason,
        toFrames: [String: CGRect],
        toOffsetX: CGFloat,
        indicatorFrame: CGRect?,
        insertedIDs: Set<String>,
        removedNodes: [TabHostedNode],
        finalContentWidth: CGFloat
    ) {
        self.stopTransitionAnimation()

        for id in insertedIDs {
            guard let node = self.itemNodes[id] else { continue }
            if let frame = toFrames[id] {
                node.containerView.frame = frame
            }
            node.containerView.alpha = 0
            node.containerView.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        }

        for node in removedNodes {
            node.containerView.alpha = 1
            node.containerView.transform = .identity
        }
        self.appendPendingRemovedNodes(removedNodes)

        let animator: UIViewPropertyAnimator
        if !insertedIDs.isEmpty || !removedNodes.isEmpty {
            animator = UIViewPropertyAnimator(duration: 0.30, dampingRatio: 0.9)
        } else if reason == .appendSelection {
            animator = UIViewPropertyAnimator(duration: 0.34, dampingRatio: 0.88)
        } else if reason == .tap {
            animator = UIViewPropertyAnimator(duration: 0.28, dampingRatio: 0.9)
        } else {
            animator = UIViewPropertyAnimator(duration: 0.24, curve: .easeInOut)
        }

        animator.addAnimations {
            self.applyFrames(toFrames)
            self.scrollView.contentOffset = CGPoint(x: toOffsetX, y: 0)
            self.applyIndicatorFrame(indicatorFrame)
            for id in insertedIDs {
                self.itemNodes[id]?.containerView.alpha = 1
                self.itemNodes[id]?.containerView.transform = .identity
            }
            for node in removedNodes {
                node.containerView.alpha = 0
                node.containerView.transform = CGAffineTransform(scaleX: 0.86, y: 0.86)
            }
        }
        animator.addCompletion { _ in
            self.removePendingRemovedNodes(removedNodes)
            self.finalizeScrollableGeometry(contentWidth: finalContentWidth)
        }
        self.transitionAnimator = animator
        animator.startAnimation()
    }

    private func finalizeScrollableGeometry(contentWidth: CGFloat) {
        let resolvedWidth = max(self.bounds.width, contentWidth)
        if abs(self.contentView.bounds.width - resolvedWidth) > 0.5 ||
            abs(self.scrollView.contentSize.width - resolvedWidth) > 0.5 {
            self.contentView.frame = CGRect(
                origin: .zero,
                size: CGSize(width: resolvedWidth, height: self.bounds.height)
            )
            self.scrollView.contentSize = CGSize(width: resolvedWidth, height: self.bounds.height)
        }

        let clampedOffsetX = self.clampedOffset(self.scrollView.contentOffset.x, contentWidth: resolvedWidth)
        if abs(clampedOffsetX - self.scrollView.contentOffset.x) > 0.5 {
            self.scrollView.contentOffset = CGPoint(x: clampedOffsetX, y: 0)
        }
    }

    private func applyFrames(_ framesByID: [String: CGRect]) {
        for id in self.orderedIDs {
            guard let node = self.itemNodes[id], let frame = framesByID[id] else { continue }
            node.containerView.frame = frame
        }
    }

    private func computeLayoutState() -> LayoutState {
        let itemHeight = max(self.bounds.height - 8, 1)
        let originY = floor((self.bounds.height - itemHeight) * 0.5)
        var x: CGFloat = 4
        var framesByID: [String: CGRect] = [:]
        var framesByIndex: [Int: CGRect] = [:]

        for (index, id) in self.orderedIDs.enumerated() {
            guard let item = self.itemsByID[id] else { continue }
            let width = self.width(for: item)
            let frame = CGRect(x: x, y: originY, width: width, height: itemHeight)
            framesByID[id] = frame
            framesByIndex[index] = frame
            x += width
        }

        let contentWidth = max(self.bounds.width, x + 4)
        return LayoutState(framesByID: framesByID, framesByIndex: framesByIndex, contentWidth: contentWidth)
    }

    private func width(for item: TabDisplayItem) -> CGFloat {
        if item.isSearch {
            return 43
        }
        let font = UIFont.systemFont(ofSize: 15, weight: .medium)
        let textWidth = ceil((item.title as NSString).size(withAttributes: [.font: font]).width)
        return textWidth + 28
    }

    private func clampedOffset(_ offset: CGFloat, contentWidth: CGFloat) -> CGFloat {
        let maxOffsetX = max(0, contentWidth - self.scrollView.bounds.width)
        return max(0, min(maxOffsetX, offset))
    }

    private func centeredOffset(for midpointX: CGFloat, contentWidth: CGFloat) -> CGFloat {
        self.clampedOffset(midpointX - self.scrollView.bounds.width * 0.5, contentWidth: contentWidth)
    }

    private func offsetEnsuringVisible(frame: CGRect, currentOffset: CGFloat, contentWidth: CGFloat) -> CGFloat {
        let visibleMinX = currentOffset
        let visibleMaxX = currentOffset + self.scrollView.bounds.width
        var nextOffset = currentOffset
        if frame.minX < visibleMinX {
            nextOffset = frame.minX - 6
        } else if frame.maxX > visibleMaxX {
            nextOffset = frame.maxX - self.scrollView.bounds.width + 6
        }
        return self.clampedOffset(nextOffset, contentWidth: contentWidth)
    }

    private func selectionProgress(for index: Int, itemCount: Int) -> CGFloat {
        if self.switchFraction == 0 {
            return index == self.selectedIndex ? 1 : 0
        }

        let targetIndex = self.switchFraction > 0 ? self.selectedIndex + 1 : self.selectedIndex - 1
        let fraction = abs(self.switchFraction)
        if index == self.selectedIndex {
            return 1 - fraction
        } else if targetIndex >= 0 && targetIndex < itemCount && index == targetIndex {
            return fraction
        }
        return 0
    }

    private func interpolatedSelectionFrame(framesByIndex: [Int: CGRect]) -> CGRect? {
        guard let currentFrame = framesByIndex[self.selectedIndex] else {
            return nil
        }
        if self.switchFraction == 0 {
            return currentFrame
        }
        let targetIndex = self.switchFraction > 0 ? self.selectedIndex + 1 : self.selectedIndex - 1
        guard targetIndex >= 0,
              let targetFrame = framesByIndex[targetIndex] else {
            return currentFrame
        }

        let t = abs(self.switchFraction)
        return CGRect(
            x: currentFrame.minX * (1 - t) + targetFrame.minX * t,
            y: currentFrame.minY,
            width: currentFrame.width * (1 - t) + targetFrame.width * t,
            height: currentFrame.height
        )
    }

    private func applyIndicatorFrame(_ frame: CGRect?) {
        guard let indicatorView = self.indicatorHostingController.view else { return }
        guard let frame else {
            indicatorView.isHidden = true
            return
        }
        indicatorView.isHidden = false
        indicatorView.frame = frame
    }

    private func updateIndicatorAppearance(for colorScheme: ColorScheme) {
        self.indicatorHostingController.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
    }

    private func stopTransitionAnimation() {
        self.transitionAnimator?.stopAnimation(false)
        self.transitionAnimator?.finishAnimation(at: .current)
        self.transitionAnimator = nil
        for node in self.itemNodes.values {
            node.containerView.alpha = 1
            node.containerView.transform = .identity
        }
        self.removeAllPendingRemovedNodes()
    }

    private func appendPendingRemovedNodes(_ nodes: [TabHostedNode]) {
        guard !nodes.isEmpty else { return }
        for node in nodes where !self.pendingRemovedNodes.contains(where: { $0 === node }) {
            self.pendingRemovedNodes.append(node)
        }
    }

    private func removePendingRemovedNodes(_ nodes: [TabHostedNode]) {
        guard !nodes.isEmpty else { return }
        for node in nodes {
            node.containerView.removeFromSuperview()
        }
        let removedIDs = Set(nodes.map { ObjectIdentifier($0) })
        self.pendingRemovedNodes.removeAll { removedIDs.contains(ObjectIdentifier($0)) }
    }

    private func removeAllPendingRemovedNodes() {
        guard !self.pendingRemovedNodes.isEmpty else { return }
        for node in self.pendingRemovedNodes {
            node.containerView.removeFromSuperview()
        }
        self.pendingRemovedNodes.removeAll()
    }

    private func needsNodeRecovery() -> Bool {
        if self.itemNodes.count != self.orderedIDs.count {
            return true
        }
        for id in self.orderedIDs {
            guard let node = self.itemNodes[id] else { return true }
            if node.containerView.superview !== self.contentView {
                return true
            }
            let frame = node.containerView.frame
            let frameIsFinite =
                frame.minX.isFinite &&
                frame.minY.isFinite &&
                frame.width.isFinite &&
                frame.height.isFinite
            if !frameIsFinite || frame.width <= 0 || frame.height <= 0 {
                return true
            }
        }
        return false
    }

    private func rebuildNodesFromCurrentState() {
        for node in self.itemNodes.values {
            node.containerView.removeFromSuperview()
        }
        self.itemNodes.removeAll(keepingCapacity: true)

        let currentItems = self.orderedIDs.compactMap { self.itemsByID[$0] }
        let _ = self.syncNodes(for: currentItems)
    }

    private func trimContextMenuStateIfNeeded(validIDs: Set<String>) {
        if let activeID = self.contextMenuActiveItemID, !validIDs.contains(activeID) {
            self.contextMenuActiveItemID = nil
        }
        if let pressingID = self.contextMenuPressingItemID, !validIDs.contains(pressingID) {
            self.contextMenuPressingItemID = nil
        }
    }

    private func setContextMenuActive(id: String, active: Bool) {
        self.contextMenuPressingItemID = nil
        self.contextMenuActiveItemID = active ? id : nil
        self.refreshNodeViews()
    }

    private func setContextMenuPressing(id: String, active: Bool) {
        if active {
            self.contextMenuPressingItemID = id
        } else if self.contextMenuPressingItemID == id {
            self.contextMenuPressingItemID = nil
        }
        self.refreshNodeViews()
    }

    private func handleTap(for id: String) {
        guard let index = self.orderedIDs.firstIndex(of: id) else { return }
        self.pendingTapSelectionIndex = index
        self.contextMenuActiveItemID = nil
        self.contextMenuPressingItemID = nil
        self.switchFraction = 0
        if self.selectedIndex != index {
            self.selectedIndex = index
        }
        self.refreshNodeViews()
        self.applyLayout(reason: .tap, animated: true)
        self.onSelectIndex?(index)
    }

    private func handleRename(for id: String) {
        self.contextMenuActiveItemID = nil
        self.contextMenuPressingItemID = nil
        guard let item = self.itemsByID[id] else { return }
        self.onRenameItem?(item)
        self.refreshNodeViews()
    }

    private func handleReorder(for id: String) {
        self.contextMenuActiveItemID = nil
        self.contextMenuPressingItemID = nil
        guard let item = self.itemsByID[id] else { return }
        self.onReorderItem?(item)
        self.refreshNodeViews()
    }

    private func handleDelete(for id: String) {
        self.contextMenuActiveItemID = nil
        self.contextMenuPressingItemID = nil
        guard let item = self.itemsByID[id] else { return }
        self.onDeleteItem?(item)
        self.refreshNodeViews()
    }
}

private final class TabHostedNode {
    let id: String
    let containerView: UIView
    private let hostingController: UIHostingController<TabLabelView>

    init(item: TabDisplayItem) {
        self.id = item.id
        self.containerView = UIView(frame: .zero)
        self.containerView.backgroundColor = .clear
        let root = TabLabelView(
            item: item,
            selectionProgress: 0,
            isContextMenuHighlighted: false,
            isContextMenuPressing: false,
            showReorder: false,
            onTap: {},
            onRename: {},
            onReorder: {},
            onDelete: {},
            onContextMenuPressBegan: {},
            onContextMenuPressEnded: {},
            onContextMenuWillShow: {},
            onContextMenuDidHide: {}
        )
        self.hostingController = UIHostingController(rootView: root)
        let hostedView = self.hostingController.view!
        hostedView.backgroundColor = .clear
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        self.containerView.addSubview(hostedView)
        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: self.containerView.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: self.containerView.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: self.containerView.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: self.containerView.bottomAnchor)
        ])
    }

    func overrideStyle(for colorScheme: ColorScheme) {
        self.hostingController.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
    }

    func update(
        item: TabDisplayItem,
        selectionProgress: CGFloat,
        isContextMenuHighlighted: Bool,
        isContextMenuPressing: Bool,
        showReorder: Bool,
        onTap: @escaping () -> Void,
        onRename: @escaping () -> Void,
        onReorder: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onContextMenuPressBegan: @escaping () -> Void,
        onContextMenuPressEnded: @escaping () -> Void,
        onContextMenuWillShow: @escaping () -> Void,
        onContextMenuDidHide: @escaping () -> Void
    ) {
        self.hostingController.rootView = TabLabelView(
            item: item,
            selectionProgress: selectionProgress,
            isContextMenuHighlighted: isContextMenuHighlighted,
            isContextMenuPressing: isContextMenuPressing,
            showReorder: showReorder,
            onTap: onTap,
            onRename: onRename,
            onReorder: onReorder,
            onDelete: onDelete,
            onContextMenuPressBegan: onContextMenuPressBegan,
            onContextMenuPressEnded: onContextMenuPressEnded,
            onContextMenuWillShow: onContextMenuWillShow,
            onContextMenuDidHide: onContextMenuDidHide
        )
    }
}

private struct IndicatorGlassCapsuleView: View {
    var body: some View {
        Capsule()
            .fill(.clear)
            .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Tab Label View

struct TabLabelView: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: TabDisplayItem
    let selectionProgress: CGFloat
    let isContextMenuHighlighted: Bool
    let isContextMenuPressing: Bool
    let showReorder: Bool
    let onTap: () -> Void
    let onRename: () -> Void
    let onReorder: () -> Void
    let onDelete: () -> Void
    let onContextMenuPressBegan: () -> Void
    let onContextMenuPressEnded: () -> Void
    let onContextMenuWillShow: () -> Void
    let onContextMenuDidHide: () -> Void

    // Text color interpolation: gray → white/black
    private var textColor: Color {
        if colorScheme == .dark {
            // Dark: gray (0.5) → white (1.0)
            return Color(white: 0.5 + selectionProgress * 0.5)
        } else {
            // Light: gray (0.5) → black (0.0)
            return Color(white: 0.5 - selectionProgress * 0.5)
        }
    }

    private var contextMenuHighlightColor: Color {
        if colorScheme == .dark {
            return .white.opacity(0.2)
        } else {
            return .black.opacity(0.12)
        }
    }

    var body: some View {
        let pressScale: CGFloat = isContextMenuPressing ? 0.91 : 1
        Group {
            if item.isSearch {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(ThemeManager.shared.currentTheme.placeholderColor))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .accessibilityLabel(L10n.Search.title)
            } else {
                Text(item.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(textColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
        .scaleEffect(pressScale)
        .animation(
            isContextMenuPressing
                ? .easeOut(duration: 0.12)
                : .spring(response: 0.24, dampingFraction: 0.64),
            value: isContextMenuPressing
        )
        .background {
            Capsule()
                .fill(contextMenuHighlightColor)
                .opacity(isContextMenuHighlighted ? 1 : 0)
                .animation(.easeOut(duration: 0.12), value: isContextMenuHighlighted)
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isButton)
        .overlay {
            if item.isSearch {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { onTap() }
            } else {
                TabContextMenuInteractionLayer(
                    isInbox: item.isInbox,
                    showReorder: showReorder,
                    onTap: onTap,
                    onRename: onRename,
                    onReorder: onReorder,
                    onDelete: onDelete,
                    onMenuPressBegan: onContextMenuPressBegan,
                    onMenuPressEnded: onContextMenuPressEnded,
                    onMenuWillShow: onContextMenuWillShow,
                    onMenuDidHide: onContextMenuDidHide
                )
            }
        }
    }
}

private struct TabContextMenuInteractionLayer: UIViewRepresentable {
    let isInbox: Bool
    let showReorder: Bool
    let onTap: () -> Void
    let onRename: () -> Void
    let onReorder: () -> Void
    let onDelete: () -> Void
    let onMenuPressBegan: () -> Void
    let onMenuPressEnded: () -> Void
    let onMenuWillShow: () -> Void
    let onMenuDidHide: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = ContextMenuTouchTrackingView(frame: .zero)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.clipsToBounds = false
        view.isUserInteractionEnabled = true
        view.pressDelay = 0.12
        view.onPressBegan = { [weak coordinator = context.coordinator] in
            coordinator?.beginPressIfNeeded()
        }
        view.onPressEnded = { [weak coordinator = context.coordinator] in
            coordinator?.endPressIfNeeded()
        }

        let interaction = UIContextMenuInteraction(delegate: context.coordinator)
        view.addInteraction(interaction)

        let tapRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tapRecognizer.cancelsTouchesInView = false
        tapRecognizer.delegate = context.coordinator
        view.addGestureRecognizer(tapRecognizer)
        context.coordinator.tapRecognizer = tapRecognizer

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIContextMenuInteractionDelegate, UIGestureRecognizerDelegate {
        private static let sourcePreviewIdentifier = "tab-context-source" as NSString
        private let menuAnchorYOffset: CGFloat = 4
        private let hapticGenerator = UIImpactFeedbackGenerator(style: .rigid)
        var parent: TabContextMenuInteractionLayer
        weak var tapRecognizer: UITapGestureRecognizer?
        private var isMenuVisible = false
        private var isPressing = false
        private var isInteractionLocked = false
        private var hasSignaledMenuWillShow = false

        init(parent: TabContextMenuInteractionLayer) {
            self.parent = parent
        }

        @objc
        func handleTap() {
            guard !isMenuVisible else { return }
            guard !isInteractionLocked else { return }
            parent.onTap()
        }

        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            configurationForMenuAtLocation location: CGPoint
        ) -> UIContextMenuConfiguration? {
            guard !isInteractionLocked else { return nil }
            // Fallback: if system skipped our explicit long-press recognizer path,
            // still trigger press animation right before menu is configured.
            if !isPressing {
                isPressing = true
                parent.onMenuPressBegan()
            }
            return UIContextMenuConfiguration(identifier: Self.sourcePreviewIdentifier, previewProvider: nil) { [weak self] _ in
                guard let self else { return nil }
                var children: [UIMenuElement] = []

                children.append(
                    UIAction(title: L10n.Tab.rename, image: UIImage(systemName: "pencil")) { _ in
                        self.finishMenuHide()
                        self.parent.onRename()
                    }
                )

                if !self.parent.isInbox {
                    if self.parent.showReorder {
                        children.append(
                            UIAction(title: L10n.Tab.move, image: UIImage(systemName: "arrow.up.arrow.down")) { _ in
                                self.finishMenuHide()
                                self.parent.onReorder()
                            }
                        )
                    }

                    children.append(
                        UIAction(
                            title: L10n.Tab.delete,
                            image: UIImage(systemName: "trash"),
                            attributes: .destructive
                        ) { _ in
                            self.finishMenuHide()
                            self.parent.onDelete()
                        }
                    )
                }

                return UIMenu(title: "", children: children)
            }
        }

        @available(iOS 16.0, *)
        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            configuration: UIContextMenuConfiguration,
            highlightPreviewForItemWithIdentifier identifier: any NSCopying
        ) -> UITargetedPreview? {
            guard let configIdentifier = configuration.identifier as? NSString,
                  configIdentifier == Self.sourcePreviewIdentifier else {
                return nil
            }
            return makeHighlightPreview(for: interaction.view)
        }

        @available(iOS 16.0, *)
        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            configuration: UIContextMenuConfiguration,
            dismissalPreviewForItemWithIdentifier identifier: any NSCopying
        ) -> UITargetedPreview? {
            guard let configIdentifier = configuration.identifier as? NSString,
                  configIdentifier == Self.sourcePreviewIdentifier else {
                return nil
            }
            return makeHiddenDismissPreview(for: interaction.view)
        }

        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            willDisplayMenuFor configuration: UIContextMenuConfiguration,
            animator: (any UIContextMenuInteractionAnimating)?
        ) {
            isMenuVisible = true
            isInteractionLocked = false
            if !hasSignaledMenuWillShow {
                hasSignaledMenuWillShow = true
                endPressIfNeeded()
                hapticGenerator.impactOccurred()
                parent.onMenuWillShow()
            }
        }

        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            willEndFor configuration: UIContextMenuConfiguration,
            animator: (any UIContextMenuInteractionAnimating)?
        ) {
            isInteractionLocked = true
            finishMenuHide()
            if let animator {
                animator.addCompletion { [weak self] in
                    self?.isInteractionLocked = false
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.isInteractionLocked = false
                }
            }
        }

        func contextMenuInteractionDidEnd(_ interaction: UIContextMenuInteraction) {
            isInteractionLocked = false
            finishMenuHide()
        }

        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration
        ) -> UITargetedPreview? {
            makeHighlightPreview(for: interaction.view)
        }

        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration
        ) -> UITargetedPreview? {
            makeHiddenDismissPreview(for: interaction.view)
        }

        private func makeHighlightPreview(for view: UIView?) -> UITargetedPreview? {
            makeCapsulePreview(for: view)
        }

        private func makeHiddenDismissPreview(for view: UIView?) -> UITargetedPreview? {
            makeMinimalPreview(for: view)
        }

        private func makeMinimalPreview(for view: UIView?) -> UITargetedPreview? {
            guard let view else { return nil }
            let bounds = view.bounds.integral
            guard bounds.width > 2, bounds.height > 2 else { return nil }
            let params = UIPreviewParameters()
            params.backgroundColor = .clear
            let hiddenRect = CGRect(x: bounds.midX, y: bounds.midY, width: 1, height: 1)
            let hiddenPath = UIBezierPath(roundedRect: hiddenRect, cornerRadius: 0.5)
            params.visiblePath = hiddenPath
            params.shadowPath = UIBezierPath(rect: .zero)
            let container = view.superview ?? view
            let center = CGPoint(x: bounds.midX, y: bounds.midY + menuAnchorYOffset)
            let target = UIPreviewTarget(container: container, center: center)
            return UITargetedPreview(view: view, parameters: params, target: target)
        }

        private func makeCapsulePreview(for view: UIView?) -> UITargetedPreview? {
            guard let view else { return nil }
            let bounds = view.bounds.integral
            guard bounds.width > 2, bounds.height > 2 else { return nil }
            let params = UIPreviewParameters()
            params.backgroundColor = .clear
            let capsuleRect = bounds.insetBy(dx: 1, dy: 1)
            let capsulePath = UIBezierPath(
                roundedRect: capsuleRect,
                cornerRadius: capsuleRect.height / 2
            )
            params.visiblePath = capsulePath
            params.shadowPath = UIBezierPath(rect: .zero)
            let container = view.superview ?? view
            let center = CGPoint(x: bounds.midX, y: bounds.midY + menuAnchorYOffset)
            let target = UIPreviewTarget(container: container, center: center)
            return UITargetedPreview(view: view, parameters: params, target: target)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        private func finishMenuHide() {
            guard isMenuVisible || hasSignaledMenuWillShow else { return }
            isMenuVisible = false
            hasSignaledMenuWillShow = false
            endPressIfNeeded()
            parent.onMenuDidHide()
        }

        func endPressIfNeeded() {
            guard isPressing else { return }
            isPressing = false
            parent.onMenuPressEnded()
        }

        func beginPressIfNeeded() {
            guard !isMenuVisible else { return }
            guard !isInteractionLocked else { return }
            guard !isPressing else { return }
            isPressing = true
            parent.onMenuPressBegan()
        }
    }
}

private final class ContextMenuTouchTrackingView: UIView {
    var onPressBegan: (() -> Void)?
    var onPressEnded: (() -> Void)?
    var pressDelay: TimeInterval = 0.12

    private var pendingPressWork: DispatchWorkItem?
    private var isTouchActive = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        startPressTracking()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        endPressTracking()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        endPressTracking()
    }

    private func startPressTracking() {
        pendingPressWork?.cancel()
        isTouchActive = true
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.isTouchActive else { return }
            self.onPressBegan?()
        }
        pendingPressWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + pressDelay, execute: work)
    }

    private func endPressTracking() {
        isTouchActive = false
        pendingPressWork?.cancel()
        pendingPressWork = nil
        onPressEnded?()
    }
}

// MARK: - Conditional View Modifier

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var selectedIndex = 0
    @Previewable @State var switchFraction: CGFloat = 0

    VStack {
        TabBarView(
            tabs: [],
            selectedIndex: $selectedIndex,
            switchFraction: $switchFraction,
            onAddTap: {},
            onMenuTap: {},
            onRenameTab: { _ in },
            onRenameInbox: {},
            onReorderTabs: {},
            onDeleteTab: { _ in }
        )
        Spacer()
    }
    .background(Color.black)
}
