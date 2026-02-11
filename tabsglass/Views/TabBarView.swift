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
    @Binding var selectedIndex: Int
    @Binding var switchFraction: CGFloat  // -1.0 ... 0 ... 1.0 при свайпе
    var tabsOffset: CGFloat = 0  // Offset for tabs row only (for Search transition)
    var tabsOpacity: CGFloat = 1  // Opacity for tabs row only (fades on Search)
    let onAddTap: () -> Void
    let onMenuTap: () -> Void
    let onRenameTab: (Tab) -> Void
    let onRenameInbox: () -> Void
    let onReorderTabs: () -> Void
    let onDeleteTab: (Tab) -> Void
    var onGoToInbox: (() -> Void)? = nil  // Called when arrow button tapped on Search

    @Environment(\.colorScheme) private var colorScheme
    private var themeManager: ThemeManager { ThemeManager.shared }
    @AppStorage("spaceName") private var spaceName = "Taby"

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
        VStack(spacing: 10) {
            // Header buttons row - stays in place
            HStack {
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

                Spacer()

                // Title - changes to "Search" during swipe
                ZStack {
                    Text(spaceName)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .opacity(1 - searchProgress)
                        .scaleEffect(1 - searchProgress * 0.2)

                    Text(L10n.Search.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .opacity(searchProgress)
                        .scaleEffect(0.8 + searchProgress * 0.2)
                }

                Spacer()

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

            // Telegram-style unified tab bar - slides during Search transition
            TelegramTabBarV2(
                tabs: tabs,
                selectedIndex: $selectedIndex,
                switchFraction: $switchFraction,
                onRenameTab: onRenameTab,
                onRenameInbox: onRenameInbox,
                onReorderTabs: onReorderTabs,
                onDeleteTab: onDeleteTab
            )
            .padding(.horizontal, 12)
            .offset(x: tabsOffset)
            .opacity(tabsOpacity)
        }
        .padding(.top, 4)
        .padding(.bottom, 16)
        .background {
            // Gradient blur - extends below header, fades out on Search
            GeometryReader { geo in
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .frame(height: geo.size.height + 80)
                    .mask {
                        LinearGradient(
                            stops: [
                                .init(color: .white, location: 0),
                                .init(color: .white, location: 0.4),
                                .init(color: .clear, location: 1)
                        ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .opacity(1 - searchProgress)
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()
        }
    }
}

// MARK: - Telegram Tab Bar V2 (Custom UIKit Engine)

private struct TelegramTabBarV2: View {
    let tabs: [Tab]
    @Binding var selectedIndex: Int
    @Binding var switchFraction: CGFloat
    let onRenameTab: (Tab) -> Void
    let onRenameInbox: () -> Void
    let onReorderTabs: () -> Void
    let onDeleteTab: (Tab) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var allItems: [TabDisplayItem] {
        var items: [TabDisplayItem] = [.search, .inbox]
        items.append(contentsOf: tabs.map { TabDisplayItem.realTab($0) })
        return items
    }

    var body: some View {
        TelegramTabBarRepresentable(
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

private struct TelegramTabBarRepresentable: UIViewRepresentable {
    let items: [TabDisplayItem]
    @Binding var selectedIndex: Int
    @Binding var switchFraction: CGFloat
    let colorScheme: ColorScheme
    let showReorder: Bool
    let onRenameTab: (Tab) -> Void
    let onRenameInbox: () -> Void
    let onReorderTabs: () -> Void
    let onDeleteTab: (Tab) -> Void

    func makeUIView(context: Context) -> TelegramTabBarEngineView {
        TelegramTabBarEngineView()
    }

    func updateUIView(_ uiView: TelegramTabBarEngineView, context: Context) {
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

private final class TelegramTabBarEngineView: UIView, UIScrollViewDelegate {
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
                targetOffset = self.offsetEnsuringVisible(
                    frame: selectedFrame,
                    currentOffset: currentOffset,
                    contentWidth: finalContentWidth
                )
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

// MARK: - Tab Frame Preference Key

struct TabFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

// MARK: - Telegram Tab Bar

struct TelegramTabBar: View {
    let tabs: [Tab]
    @Binding var selectedIndex: Int
    @Binding var switchFraction: CGFloat
    let onRenameTab: (Tab) -> Void
    let onRenameInbox: () -> Void
    let onReorderTabs: () -> Void
    let onDeleteTab: (Tab) -> Void

    @Environment(\.colorScheme) private var colorScheme

    // Track frames of each tab for selection indicator positioning
    @State private var tabFrames: [Int: CGRect] = [:]
    @State private var userScrollAdjustment: CGFloat = 0
    @State private var animateNextScrollUpdate = false
    @State private var contextMenuActiveItemID: String?
    @State private var contextMenuPressingItemID: String?
    @State private var scrollOffsetBounds: ScrollOffsetBounds?
    @State private var needsPostLayoutRecentering = false
    @State private var tapTargetOffsetX: CGFloat?
    @State private var activeTapTransition: TapTransitionDebug?
    @State private var tapTransitionSerial = 0

    private struct TapTransitionDebug {
        let id: Int
        let fromIndex: Int
        let toIndex: Int
    }

    private struct ScrollOffsetBounds {
        let minX: CGFloat
        let maxX: CGFloat
    }

    /// Combined list: Search + Inbox (virtual) + real tabs
    private var allItems: [TabDisplayItem] {
        var items: [TabDisplayItem] = [.search, .inbox]
        items.append(contentsOf: tabs.map { TabDisplayItem.realTab($0) })
        return items
    }

    /// Content width derived from tab frames (last tab's maxX + right padding)
    private var contentTotalWidth: CGFloat {
        (tabFrames.values.map(\.maxX).max() ?? 0) + 4
    }

    private var contentIdentity: [String] {
        allItems.map(\.id)
    }

    var body: some View {
        GeometryReader { container in
            let containerWidth = container.size.width
            let isSwipeInProgress = abs(switchFraction) > 0.001
            let baseOffsetX = baseContentOffsetX(in: containerWidth)
            let resolvedBaseOffsetX = tapTargetOffsetX ?? (baseOffsetX + userScrollAdjustment)
            let targetOffsetX = clampedContentOffsetX(resolvedBaseOffsetX, in: containerWidth)

            TabBarNativeScrollView(
                targetOffsetX: targetOffsetX,
                animateTarget: animateNextScrollUpdate && (!isSwipeInProgress || activeTapTransition != nil),
                selectionIndex: selectedIndex,
                allowSelectionDrivenAnimation: !isSwipeInProgress || activeTapTransition != nil,
                onOffsetChanged: { offsetX in
                    let proposedAdjustment = offsetX - baseOffsetX
                    let clampedAdjustment = clampedScrollAdjustment(
                        proposedAdjustment,
                        in: containerWidth,
                        baseOffsetX: baseOffsetX
                    )
                    if abs(clampedAdjustment - userScrollAdjustment) > 0.5 {
                        userScrollAdjustment = clampedAdjustment
                    }
                },
                onDebugOffsetSample: { offsetX, isProgrammatic in
                    guard let transition = activeTapTransition else { return }
                    guard isProgrammatic else { return }
                    TabBarMotionLogger.logTabsOffset(
                        transitionID: transition.id,
                        offsetX: offsetX
                    )
                },
                onOffsetBoundsChanged: { minX, maxX in
                    let next = ScrollOffsetBounds(minX: minX, maxX: maxX)
                    if let current = scrollOffsetBounds,
                       abs(current.minX - next.minX) <= 0.5,
                       abs(current.maxX - next.maxX) <= 0.5 {
                        return
                    }
                    scrollOffsetBounds = next
                    triggerPostLayoutRecenteringIfReady()
                },
                onProgrammaticScrollSettled: { finalOffsetX in
                    if let transition = activeTapTransition {
                        TabBarMotionLogger.logTapTransitionFinish(
                            transitionID: transition.id,
                            finalSelectedIndex: selectedIndex,
                            finalOffsetX: finalOffsetX
                        )
                        activeTapTransition = nil
                    }
                    tapTargetOffsetX = nil
                    animateNextScrollUpdate = false
                }
            ) {
                ZStack(alignment: .topLeading) {
                    // Selection indicator FIRST (renders under tabs)
                    SelectionIndicatorView(
                        frame: interpolatedSelectionFrame,
                        debugTransitionID: activeTapTransition?.id
                    )
                        .animation(.easeInOut(duration: 0.24), value: selectedIndex)

                    // Tabs ABOVE the indicator
                    HStack(spacing: 0) {
                        ForEach(Array(allItems.enumerated()), id: \.element.id) { index, item in
                            TabLabelView(
                                item: item,
                                selectionProgress: selectionProgress(for: index),
                                isContextMenuHighlighted: contextMenuActiveItemID == item.id,
                                isContextMenuPressing: contextMenuPressingItemID == item.id,
                                showReorder: tabs.count > 1,
                                onTap: {
                                    contextMenuActiveItemID = nil
                                    contextMenuPressingItemID = nil
                                    let nextTransitionID = tapTransitionSerial + 1
                                    tapTransitionSerial = nextTransitionID
                                    activeTapTransition = TapTransitionDebug(
                                        id: nextTransitionID,
                                        fromIndex: selectedIndex,
                                        toIndex: index
                                    )
                                    TabBarMotionLogger.logTapTransitionStart(
                                        transitionID: nextTransitionID,
                                        fromIndex: selectedIndex,
                                        toIndex: index,
                                        fromIndicatorFrame: tabFrames[selectedIndex] ?? .zero,
                                        toIndicatorFrame: tabFrames[index] ?? .zero,
                                        currentOffsetX: targetOffsetX
                                    )
                                    if let targetFrame = tabFrames[index] {
                                        tapTargetOffsetX = clampedContentOffsetX(
                                            targetFrame.midX - (containerWidth / 2),
                                            in: containerWidth
                                        )
                                    } else {
                                        tapTargetOffsetX = nil
                                    }
                                    // Arm centering animation before selection changes, otherwise
                                    // first layout pass may jump to centered offset without animation.
                                    userScrollAdjustment = 0
                                    animateNextScrollUpdate = true
                                    withAnimation(.easeInOut(duration: 0.24)) {
                                        selectedIndex = index
                                    }
                                },
                                onRename: {
                                    contextMenuActiveItemID = nil
                                    contextMenuPressingItemID = nil
                                    if item.isInbox {
                                        onRenameInbox()
                                    } else if let tab = item.tab {
                                        onRenameTab(tab)
                                    }
                                },
                                onReorder: {
                                    contextMenuActiveItemID = nil
                                    contextMenuPressingItemID = nil
                                    onReorderTabs()
                                },
                                onDelete: {
                                    contextMenuActiveItemID = nil
                                    contextMenuPressingItemID = nil
                                    if let tab = item.tab {
                                        onDeleteTab(tab)
                                    }
                                },
                                onContextMenuPressBegan: {
                                    contextMenuPressingItemID = item.id
                                },
                                onContextMenuPressEnded: {
                                    if contextMenuPressingItemID == item.id {
                                        contextMenuPressingItemID = nil
                                    }
                                },
                                onContextMenuWillShow: {
                                    contextMenuPressingItemID = nil
                                    contextMenuActiveItemID = item.id
                                },
                                onContextMenuDidHide: {
                                    if contextMenuPressingItemID == item.id {
                                        contextMenuPressingItemID = nil
                                    }
                                    if contextMenuActiveItemID == item.id {
                                        contextMenuActiveItemID = nil
                                    }
                                }
                            )
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: TabFramePreferenceKey.self,
                                        value: [index: geo.frame(in: .named("tabContent"))]
                                    )
                                }
                            )
                            .id(item.id)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.9)),
                                removal: .opacity.combined(with: .scale(scale: 0.85))
                            ))
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                    .fixedSize(horizontal: true, vertical: false)
                    .coordinateSpace(name: "tabContent")
                    .animation(.snappy(duration: 0.28, extraBounce: 0.08), value: contentIdentity)
                }
                .onPreferenceChange(TabFramePreferenceKey.self) { frames in
                    if framesDiffer(frames, tabFrames) {
                        tabFrames = frames
                    }
                    triggerPostLayoutRecenteringIfReady()
                }
            }
        }
        .frame(height: 46)
        .contentShape(Capsule())
        .onChange(of: selectedIndex) { _, _ in
            contextMenuActiveItemID = nil
            contextMenuPressingItemID = nil
            let shouldDeferCentering = tabFrames[selectedIndex] == nil || scrollOffsetBounds == nil
            if shouldDeferCentering {
                needsPostLayoutRecentering = true
            }
            if activeTapTransition == nil {
                userScrollAdjustment = 0
                tapTargetOffsetX = nil
                animateNextScrollUpdate = !shouldDeferCentering
            }
            triggerPostLayoutRecenteringIfReady()
        }
        .onChange(of: contentIdentity) { oldValue, newValue in
            guard oldValue != newValue else { return }
            if let transition = activeTapTransition {
                TabBarMotionLogger.logTapTransitionCancelled(
                    transitionID: transition.id,
                    reason: "Tab list changed"
                )
            }
            activeTapTransition = nil
            tabFrames = [:]
            scrollOffsetBounds = nil
            needsPostLayoutRecentering = true
            userScrollAdjustment = 0
            tapTargetOffsetX = nil
            animateNextScrollUpdate = false
        }
        .onChange(of: switchFraction) { oldValue, newValue in
            let wasSwiping = abs(oldValue) > 0.001
            let isSwiping = abs(newValue) > 0.001
            if isSwiping && !wasSwiping {
                if let transition = activeTapTransition {
                    TabBarMotionLogger.logTapTransitionCancelled(
                        transitionID: transition.id,
                        reason: "Swipe started"
                    )
                    activeTapTransition = nil
                }
                // Keep swipe-driven centering deterministic: once page swipe starts,
                // manual tab bar displacement is reset and indicator follows finger.
                contextMenuActiveItemID = nil
                contextMenuPressingItemID = nil
                userScrollAdjustment = 0
                tapTargetOffsetX = nil
                animateNextScrollUpdate = false
            }
        }
        .clipShape(Capsule())
        .background {
            // Unified glass background for the entire tab bar
            Capsule()
                .fill(.clear)
                .glassEffect(.regular, in: .capsule)
                .id("tabbar-glass-\(colorScheme)")  // Force recreation when theme changes
        }
    }

    private func minimumContentOffsetX(in containerWidth: CGFloat) -> CGFloat {
        offsetBounds(in: containerWidth).minX
    }

    private func maximumContentOffsetX(in containerWidth: CGFloat) -> CGFloat {
        offsetBounds(in: containerWidth).maxX
    }

    private func clampedContentOffsetX(_ rawOffsetX: CGFloat, in containerWidth: CGFloat) -> CGFloat {
        let bounds = offsetBounds(in: containerWidth)
        return max(bounds.minX, min(bounds.maxX, rawOffsetX))
    }

    private func baseContentOffsetX(in containerWidth: CGFloat) -> CGFloat {
        guard containerWidth > 0, contentTotalWidth > 0 else { return 0 }
        let frame = interpolatedSelectionFrame
        guard frame != .zero else { return clampedContentOffsetX(0, in: containerWidth) }
        let rawOffsetX = frame.midX - (containerWidth / 2)
        return clampedContentOffsetX(rawOffsetX, in: containerWidth)
    }

    private func clampedScrollAdjustment(
        _ adjustment: CGFloat,
        in containerWidth: CGFloat,
        baseOffsetX: CGFloat
    ) -> CGFloat {
        let bounds = offsetBounds(in: containerWidth)
        let minAdjustment = minimumContentOffsetX(in: containerWidth) - baseOffsetX
        let maxAdjustment = maximumContentOffsetX(in: containerWidth) - baseOffsetX
        if bounds.maxX <= bounds.minX {
            return 0
        }
        return max(minAdjustment, min(maxAdjustment, adjustment))
    }

    private func triggerPostLayoutRecenteringIfReady() {
        guard needsPostLayoutRecentering else { return }
        guard tabFrames[selectedIndex] != nil else { return }
        guard scrollOffsetBounds != nil else { return }
        userScrollAdjustment = 0
        tapTargetOffsetX = nil
        animateNextScrollUpdate = true
        needsPostLayoutRecentering = false
    }

    private func offsetBounds(in containerWidth: CGFloat) -> (minX: CGFloat, maxX: CGFloat) {
        let derivedBounds: ScrollOffsetBounds? = {
            guard containerWidth > 0, contentTotalWidth > 0 else { return nil }
            let inset = max((containerWidth - contentTotalWidth) / 2, 0)
            return ScrollOffsetBounds(
                minX: -inset,
                maxX: max(contentTotalWidth - containerWidth, 0) + inset
            )
        }()

        switch (scrollOffsetBounds, derivedBounds) {
        case let (.some(scroll), .some(derived)):
            // Telegram-like robustness: trust the widest valid range while layout settles.
            return (
                minX: min(scroll.minX, derived.minX),
                maxX: max(scroll.maxX, derived.maxX)
            )
        case let (.some(scroll), .none):
            return (minX: scroll.minX, maxX: scroll.maxX)
        case let (.none, .some(derived)):
            return (minX: derived.minX, maxX: derived.maxX)
        case (.none, .none):
            return (minX: 0, maxX: 0)
        }
    }

    private func framesDiffer(_ lhs: [Int: CGRect], _ rhs: [Int: CGRect], tolerance: CGFloat = 0.5) -> Bool {
        guard lhs.count == rhs.count else { return true }
        for (index, newFrame) in lhs {
            guard let oldFrame = rhs[index] else { return true }
            if abs(oldFrame.minX - newFrame.minX) > tolerance ||
                abs(oldFrame.minY - newFrame.minY) > tolerance ||
                abs(oldFrame.width - newFrame.width) > tolerance ||
                abs(oldFrame.height - newFrame.height) > tolerance {
                return true
            }
        }
        return false
    }

    // Calculate selection progress for each tab (0 = not selected, 1 = fully selected)
    private func selectionProgress(for index: Int) -> CGFloat {
        if switchFraction == 0 {
            return index == selectedIndex ? 1.0 : 0.0
        }

        // During swipe, interpolate between current and target tab
        let targetIndex = switchFraction > 0 ? selectedIndex + 1 : selectedIndex - 1
        let fraction = abs(switchFraction)

        if index == selectedIndex {
            return 1.0 - fraction  // Current tab loses selection
        } else if index == targetIndex && targetIndex >= 0 && targetIndex < allItems.count {
            return fraction  // Target tab gains selection
        }
        return 0.0
    }

    // Calculate interpolated frame for selection indicator
    private var interpolatedSelectionFrame: CGRect {
        guard let currentFrame = tabFrames[selectedIndex] else {
            return .zero
        }

        // If not swiping, return current tab frame
        if switchFraction == 0 {
            return currentFrame
        }

        // Find target tab based on swipe direction
        let targetIndex = switchFraction > 0 ? selectedIndex + 1 : selectedIndex - 1
        guard targetIndex >= 0 && targetIndex < allItems.count,
              let targetFrame = tabFrames[targetIndex] else {
            return currentFrame
        }

        // Linear interpolation between current and target frame
        let fraction = abs(switchFraction)
        let x = currentFrame.minX * (1.0 - fraction) + targetFrame.minX * fraction
        let width = currentFrame.width * (1.0 - fraction) + targetFrame.width * fraction

        return CGRect(
            x: x,
            y: currentFrame.minY,
            width: width,
            height: currentFrame.height
        )
    }
}

private struct TabBarNativeScrollView<Content: View>: UIViewRepresentable {
    let targetOffsetX: CGFloat
    let animateTarget: Bool
    let selectionIndex: Int
    let allowSelectionDrivenAnimation: Bool
    let onOffsetChanged: (CGFloat) -> Void
    let onDebugOffsetSample: ((CGFloat, Bool) -> Void)?
    let onOffsetBoundsChanged: ((CGFloat, CGFloat) -> Void)?
    let onProgrammaticScrollSettled: (CGFloat) -> Void
    let content: Content

    init(
        targetOffsetX: CGFloat,
        animateTarget: Bool,
        selectionIndex: Int,
        allowSelectionDrivenAnimation: Bool,
        onOffsetChanged: @escaping (CGFloat) -> Void,
        onDebugOffsetSample: ((CGFloat, Bool) -> Void)? = nil,
        onOffsetBoundsChanged: ((CGFloat, CGFloat) -> Void)? = nil,
        onProgrammaticScrollSettled: @escaping (CGFloat) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.targetOffsetX = targetOffsetX
        self.animateTarget = animateTarget
        self.selectionIndex = selectionIndex
        self.allowSelectionDrivenAnimation = allowSelectionDrivenAnimation
        self.onOffsetChanged = onOffsetChanged
        self.onDebugOffsetSample = onDebugOffsetSample
        self.onOffsetBoundsChanged = onOffsetBoundsChanged
        self.onProgrammaticScrollSettled = onProgrammaticScrollSettled
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(content: content)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.alwaysBounceVertical = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.clipsToBounds = false
        scrollView.delaysContentTouches = false

        let hostedView = context.coordinator.hostingController.view!
        context.coordinator.attachHostedView(hostedView)
        hostedView.backgroundColor = .clear
        hostedView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.addSubview(hostedView)
        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hostedView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.hostingController.rootView = content
        if let hostedView = coordinator.hostingController.view {
            coordinator.attachHostedView(hostedView)
        }
        coordinator.onOffsetChanged = onOffsetChanged
        coordinator.onDebugOffsetSample = onDebugOffsetSample
        coordinator.onOffsetBoundsChanged = onOffsetBoundsChanged
        coordinator.onProgrammaticScrollSettled = onProgrammaticScrollSettled
        let selectionChanged = coordinator.lastSelectionIndex != selectionIndex
        coordinator.lastSelectionIndex = selectionIndex

        scrollView.layoutIfNeeded()
        let horizontalInset = max((scrollView.bounds.width - scrollView.contentSize.width) / 2, 0)
        let currentInsets = scrollView.contentInset
        if abs(currentInsets.left - horizontalInset) > 0.5 || abs(currentInsets.right - horizontalInset) > 0.5 {
            scrollView.contentInset = UIEdgeInsets(top: currentInsets.top, left: horizontalInset, bottom: currentInsets.bottom, right: horizontalInset)
        }

        let minOffsetX = -scrollView.contentInset.left
        let maxOffsetX = max(scrollView.contentSize.width - scrollView.bounds.width + scrollView.contentInset.right, minOffsetX)
        coordinator.reportOffsetBoundsIfNeeded(minOffsetX: minOffsetX, maxOffsetX: maxOffsetX)
        coordinator.scheduleDeferredBoundsReport(for: scrollView)
        let clampedTargetX = max(minOffsetX, min(maxOffsetX, targetOffsetX))

        if coordinator.isUserInteracting {
            return
        }

        let previousOffsetX = scrollView.contentOffset.x
        let delta = abs(previousOffsetX - clampedTargetX)
        let shouldAnimateSelectionChange = selectionChanged && allowSelectionDrivenAnimation && !animateTarget
        let shouldAnimate = animateTarget || shouldAnimateSelectionChange
        if delta <= 0.5 {
            if shouldAnimate {
                coordinator.reportProgrammaticSettledIfNeeded(finalOffsetX: scrollView.contentOffset.x)
            } else {
                coordinator.resetProgrammaticSettleTracking()
            }
            return
        }

        if shouldAnimate {
            coordinator.resetProgrammaticSettleTracking()
            if coordinator.isProgrammaticScroll,
                let activeTarget = coordinator.activeAnimatedTarget,
                abs(activeTarget - clampedTargetX) <= 0.5 {
                return
            }

            coordinator.animateProgrammaticScroll(
                in: scrollView,
                fromOffsetX: previousOffsetX,
                toOffsetX: clampedTargetX,
                duration: 0.24
            )
        } else {
            coordinator.cancelAdditiveAnimation(resetTransform: true)
            coordinator.isProgrammaticScroll = true
            scrollView.setContentOffset(CGPoint(x: clampedTargetX, y: scrollView.contentOffset.y), animated: false)
            coordinator.isProgrammaticScroll = false
            coordinator.activeAnimatedTarget = nil
            coordinator.resetProgrammaticSettleTracking()
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let hostingController: UIHostingController<Content>
        var onOffsetChanged: ((CGFloat) -> Void)?
        var onDebugOffsetSample: ((CGFloat, Bool) -> Void)?
        var onOffsetBoundsChanged: ((CGFloat, CGFloat) -> Void)?
        var onProgrammaticScrollSettled: ((CGFloat) -> Void)?
        var isProgrammaticScroll = false
        var isUserInteracting = false
        var activeAnimatedTarget: CGFloat?
        var lastSelectionIndex: Int?
        private weak var hostedView: UIView?
        private var additiveAnimator: UIViewPropertyAnimator?
        private var deferredBoundsWorkItem: DispatchWorkItem?
        private var lastReportedMinOffsetX: CGFloat?
        private var lastReportedMaxOffsetX: CGFloat?
        private var didReportProgrammaticSettled = false

        init(content: Content) {
            self.hostingController = UIHostingController(rootView: content)
        }

        func attachHostedView(_ view: UIView) {
            self.hostedView = view
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            cancelAdditiveAnimation(resetTransform: true)
            isUserInteracting = true
            isProgrammaticScroll = false
            activeAnimatedTarget = nil
            reportOffsetBounds(for: scrollView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            reportOffsetBounds(for: scrollView)
            onDebugOffsetSample?(scrollView.contentOffset.x, isProgrammaticScroll)
            guard !isProgrammaticScroll else { return }
            onOffsetChanged?(scrollView.contentOffset.x)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                isUserInteracting = false
            }
            reportOffsetBounds(for: scrollView)
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            isUserInteracting = false
            reportOffsetBounds(for: scrollView)
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            isProgrammaticScroll = false
            activeAnimatedTarget = nil
            reportOffsetBounds(for: scrollView)
            reportProgrammaticSettledIfNeeded(finalOffsetX: scrollView.contentOffset.x)
        }

        func reportProgrammaticSettledIfNeeded(finalOffsetX: CGFloat) {
            guard !didReportProgrammaticSettled else { return }
            didReportProgrammaticSettled = true
            DispatchQueue.main.async { [weak self] in
                self?.onProgrammaticScrollSettled?(finalOffsetX)
            }
        }

        func resetProgrammaticSettleTracking() {
            didReportProgrammaticSettled = false
        }

        func cancelAdditiveAnimation(resetTransform: Bool) {
            additiveAnimator?.stopAnimation(true)
            additiveAnimator = nil
            deferredBoundsWorkItem?.cancel()
            deferredBoundsWorkItem = nil
            if resetTransform {
                hostedView?.transform = .identity
            }
        }

        func scheduleDeferredBoundsReport(for scrollView: UIScrollView) {
            deferredBoundsWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self, weak scrollView] in
                guard let self, let scrollView else { return }
                scrollView.layoutIfNeeded()
                self.reportOffsetBounds(for: scrollView)
            }
            deferredBoundsWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: workItem)
        }

        func animateProgrammaticScroll(
            in scrollView: UIScrollView,
            fromOffsetX: CGFloat,
            toOffsetX: CGFloat,
            duration: TimeInterval
        ) {
            cancelAdditiveAnimation(resetTransform: true)
            isProgrammaticScroll = true
            activeAnimatedTarget = toOffsetX

            scrollView.setContentOffset(
                CGPoint(x: toOffsetX, y: scrollView.contentOffset.y),
                animated: false
            )

            guard let hostedView else {
                completeProgrammaticScroll(in: scrollView)
                return
            }

            let additiveOffsetX = toOffsetX - fromOffsetX
            guard abs(additiveOffsetX) > 0.5 else {
                completeProgrammaticScroll(in: scrollView)
                return
            }

            hostedView.transform = CGAffineTransform(translationX: additiveOffsetX, y: 0)
            let animator = UIViewPropertyAnimator(duration: duration, curve: .easeInOut) {
                hostedView.transform = .identity
            }
            additiveAnimator = animator
            animator.addCompletion { [weak self, weak scrollView] _ in
                guard let self, let scrollView else { return }
                self.completeProgrammaticScroll(in: scrollView)
            }
            animator.startAnimation()
        }

        func reportOffsetBoundsIfNeeded(minOffsetX: CGFloat, maxOffsetX: CGFloat) {
            let shouldReport: Bool
            if let lastMin = lastReportedMinOffsetX, let lastMax = lastReportedMaxOffsetX {
                shouldReport = abs(lastMin - minOffsetX) > 0.5 || abs(lastMax - maxOffsetX) > 0.5
            } else {
                shouldReport = true
            }
            guard shouldReport else { return }

            lastReportedMinOffsetX = minOffsetX
            lastReportedMaxOffsetX = maxOffsetX
            DispatchQueue.main.async { [weak self] in
                self?.onOffsetBoundsChanged?(minOffsetX, maxOffsetX)
            }
        }

        private func reportOffsetBounds(for scrollView: UIScrollView) {
            let minOffsetX = -scrollView.contentInset.left
            let maxOffsetX = max(
                scrollView.contentSize.width - scrollView.bounds.width + scrollView.contentInset.right,
                minOffsetX
            )
            reportOffsetBoundsIfNeeded(minOffsetX: minOffsetX, maxOffsetX: maxOffsetX)
        }

        private func completeProgrammaticScroll(in scrollView: UIScrollView) {
            hostedView?.transform = .identity
            additiveAnimator = nil
            isProgrammaticScroll = false
            activeAnimatedTarget = nil
            reportOffsetBounds(for: scrollView)
            reportProgrammaticSettledIfNeeded(finalOffsetX: scrollView.contentOffset.x)
        }
    }
}

// MARK: - Selection Indicator View

struct SelectionIndicatorView: View {
    private var x: CGFloat
    private let y: CGFloat
    private var width: CGFloat
    private let height: CGFloat
    private let debugTransitionID: Int?
    @Environment(\.colorScheme) private var colorScheme

    init(frame: CGRect, debugTransitionID: Int? = nil) {
        self.x = frame.minX
        self.y = frame.minY
        self.width = frame.width
        self.height = frame.height
        self.debugTransitionID = debugTransitionID
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(x, width) }
        set {
            x = newValue.first
            width = newValue.second
            if let debugTransitionID {
                TabBarMotionLogger.logIndicator(
                    transitionID: debugTransitionID,
                    x: x,
                    width: width
                )
            }
        }
    }

    var body: some View {
        Capsule()
            .fill(.clear)
            .glassEffect(.regular, in: .capsule)
            .frame(width: max(width, 0), height: max(height, 0))
            .offset(x: x, y: y)
            .id("indicator-glass-\(colorScheme)")  // Force recreation when theme changes
    }
}

private enum TabBarMotionLogger {
    static func logTapTransitionStart(
        transitionID: Int,
        fromIndex: Int,
        toIndex: Int,
        fromIndicatorFrame: CGRect,
        toIndicatorFrame: CGRect,
        currentOffsetX: CGFloat
    ) {
        print(
            "[TabBarMotion][Tap#\(transitionID)] start from=\(fromIndex) to=\(toIndex) " +
            "offsetX=\(f(currentOffsetX)) indicatorFrom=\(frame(fromIndicatorFrame)) indicatorTo=\(frame(toIndicatorFrame))"
        )
    }

    static func logTabsOffset(transitionID: Int, offsetX: CGFloat) {
        print("[TabBarMotion][Tap#\(transitionID)] tabs offsetX=\(f(offsetX))")
    }

    static func logIndicator(transitionID: Int, x: CGFloat, width: CGFloat) {
        print("[TabBarMotion][Tap#\(transitionID)] indicator x=\(f(x)) width=\(f(width))")
    }

    static func logTapTransitionFinish(
        transitionID: Int,
        finalSelectedIndex: Int,
        finalOffsetX: CGFloat
    ) {
        print(
            "[TabBarMotion][Tap#\(transitionID)] finish selectedIndex=\(finalSelectedIndex) offsetX=\(f(finalOffsetX))"
        )
    }

    static func logTapTransitionCancelled(transitionID: Int, reason: String) {
        print("[TabBarMotion][Tap#\(transitionID)] cancelled reason=\(reason)")
    }

    private static func f(_ value: CGFloat) -> String {
        String(format: "%.2f", value)
    }

    private static func frame(_ rect: CGRect) -> String {
        "(x:\(f(rect.minX)), y:\(f(rect.minY)), w:\(f(rect.width)), h:\(f(rect.height)))"
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
