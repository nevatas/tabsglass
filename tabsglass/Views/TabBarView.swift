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
            TelegramTabBar(
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
    @State private var tapTargetOffsetX: CGFloat?
    @State private var activeTapTransition: TapTransitionDebug?
    @State private var tapTransitionSerial = 0

    private struct TapTransitionDebug {
        let id: Int
        let fromIndex: Int
        let toIndex: Int
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
                }
            }
        }
        .frame(height: 46)
        .contentShape(Capsule())
        .onChange(of: selectedIndex) { _, _ in
            contextMenuActiveItemID = nil
            contextMenuPressingItemID = nil
            if activeTapTransition == nil {
                userScrollAdjustment = 0
                tapTargetOffsetX = nil
                animateNextScrollUpdate = true
            }
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
        guard containerWidth > 0, contentTotalWidth > 0 else { return 0 }
        let inset = max((containerWidth - contentTotalWidth) / 2, 0)
        return -inset
    }

    private func maximumContentOffsetX(in containerWidth: CGFloat) -> CGFloat {
        guard containerWidth > 0, contentTotalWidth > 0 else { return 0 }
        let inset = max((containerWidth - contentTotalWidth) / 2, 0)
        return max(contentTotalWidth - containerWidth, 0) + inset
    }

    private func clampedContentOffsetX(_ rawOffsetX: CGFloat, in containerWidth: CGFloat) -> CGFloat {
        let minX = minimumContentOffsetX(in: containerWidth)
        let maxX = maximumContentOffsetX(in: containerWidth)
        return max(minX, min(maxX, rawOffsetX))
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
        guard containerWidth > 0, contentTotalWidth > 0 else { return 0 }
        let minAdjustment = minimumContentOffsetX(in: containerWidth) - baseOffsetX
        let maxAdjustment = maximumContentOffsetX(in: containerWidth) - baseOffsetX
        return max(minAdjustment, min(maxAdjustment, adjustment))
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
    let onProgrammaticScrollSettled: (CGFloat) -> Void
    let content: Content

    init(
        targetOffsetX: CGFloat,
        animateTarget: Bool,
        selectionIndex: Int,
        allowSelectionDrivenAnimation: Bool,
        onOffsetChanged: @escaping (CGFloat) -> Void,
        onDebugOffsetSample: ((CGFloat, Bool) -> Void)? = nil,
        onProgrammaticScrollSettled: @escaping (CGFloat) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.targetOffsetX = targetOffsetX
        self.animateTarget = animateTarget
        self.selectionIndex = selectionIndex
        self.allowSelectionDrivenAnimation = allowSelectionDrivenAnimation
        self.onOffsetChanged = onOffsetChanged
        self.onDebugOffsetSample = onDebugOffsetSample
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
        coordinator.onOffsetChanged = onOffsetChanged
        coordinator.onDebugOffsetSample = onDebugOffsetSample
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
        let clampedTargetX = max(minOffsetX, min(maxOffsetX, targetOffsetX))

        if coordinator.isUserInteracting {
            return
        }

        let delta = abs(scrollView.contentOffset.x - clampedTargetX)
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

            coordinator.isProgrammaticScroll = true
            coordinator.activeAnimatedTarget = clampedTargetX
            scrollView.setContentOffset(CGPoint(x: clampedTargetX, y: scrollView.contentOffset.y), animated: true)
        } else {
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
        var onProgrammaticScrollSettled: ((CGFloat) -> Void)?
        var isProgrammaticScroll = false
        var isUserInteracting = false
        var activeAnimatedTarget: CGFloat?
        var lastSelectionIndex: Int?
        private var didReportProgrammaticSettled = false

        init(content: Content) {
            self.hostingController = UIHostingController(rootView: content)
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            isUserInteracting = true
            isProgrammaticScroll = false
            activeAnimatedTarget = nil
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            onDebugOffsetSample?(scrollView.contentOffset.x, isProgrammaticScroll)
            guard !isProgrammaticScroll else { return }
            onOffsetChanged?(scrollView.contentOffset.x)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                isUserInteracting = false
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            isUserInteracting = false
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            isProgrammaticScroll = false
            activeAnimatedTarget = nil
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
                    .foregroundStyle(textColor)
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
                .padding(.horizontal, 2)
                .padding(.vertical, 1)
                .opacity(isContextMenuHighlighted ? 1 : 0)
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
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.clipsToBounds = false
        view.isUserInteractionEnabled = true

        let interaction = UIContextMenuInteraction(delegate: context.coordinator)
        view.addInteraction(interaction)

        let tapRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tapRecognizer.cancelsTouchesInView = false
        tapRecognizer.delegate = context.coordinator
        view.addGestureRecognizer(tapRecognizer)
        context.coordinator.tapRecognizer = tapRecognizer

        let pressRecognizer = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePressState(_:))
        )
        pressRecognizer.minimumPressDuration = 0.08
        pressRecognizer.allowableMovement = 44
        pressRecognizer.cancelsTouchesInView = false
        pressRecognizer.delegate = context.coordinator
        view.addGestureRecognizer(pressRecognizer)
        context.coordinator.pressRecognizer = pressRecognizer

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIContextMenuInteractionDelegate, UIGestureRecognizerDelegate {
        private static let sourcePreviewIdentifier = "tab-context-source" as NSString
        var parent: TabContextMenuInteractionLayer
        weak var tapRecognizer: UITapGestureRecognizer?
        weak var pressRecognizer: UILongPressGestureRecognizer?
        private var isMenuVisible = false
        private var isPressing = false
        private var hasSignaledMenuWillShow = false

        init(parent: TabContextMenuInteractionLayer) {
            self.parent = parent
        }

        @objc
        func handleTap() {
            guard !isMenuVisible else { return }
            parent.onTap()
        }

        @objc
        func handlePressState(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began:
                guard !isMenuVisible else { return }
                guard !isPressing else { return }
                isPressing = true
                parent.onMenuPressBegan()
            case .ended, .cancelled, .failed:
                endPressIfNeeded()
            default:
                break
            }
        }

        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            configurationForMenuAtLocation location: CGPoint
        ) -> UIContextMenuConfiguration? {
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
            return makeTransparentPreview(for: interaction.view)
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
            if !hasSignaledMenuWillShow {
                hasSignaledMenuWillShow = true
                if let animator {
                    animator.addAnimations { [weak self] in
                        self?.endPressIfNeeded()
                        self?.parent.onMenuWillShow()
                    }
                } else {
                    endPressIfNeeded()
                    parent.onMenuWillShow()
                }
            }
        }

        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            willEndFor configuration: UIContextMenuConfiguration,
            animator: (any UIContextMenuInteractionAnimating)?
        ) {
            finishMenuHide()
        }

        func contextMenuInteractionDidEnd(_ interaction: UIContextMenuInteraction) {
            finishMenuHide()
        }

        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration
        ) -> UITargetedPreview? {
            makeTransparentPreview(for: interaction.view)
        }

        func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration
        ) -> UITargetedPreview? {
            makeHiddenDismissPreview(for: interaction.view)
        }

        private func makeTransparentPreview(for view: UIView?) -> UITargetedPreview? {
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
            return UITargetedPreview(view: view, parameters: params)
        }

        private func makeHiddenDismissPreview(for view: UIView?) -> UITargetedPreview? {
            guard let view else { return nil }
            let bounds = view.bounds.integral
            guard bounds.width > 2, bounds.height > 2 else { return nil }
            let params = UIPreviewParameters()
            params.backgroundColor = .clear
            let hiddenRect = CGRect(x: bounds.midX, y: bounds.midY, width: 1, height: 1)
            let hiddenPath = UIBezierPath(roundedRect: hiddenRect, cornerRadius: 0.5)
            params.visiblePath = hiddenPath
            params.shadowPath = UIBezierPath(rect: .zero)
            return UITargetedPreview(view: view, parameters: params)
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

        private func endPressIfNeeded() {
            guard isPressing else { return }
            isPressing = false
            parent.onMenuPressEnded()
        }
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
