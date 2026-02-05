//
//  TabBarView.swift
//  tabsglass
//
//  Telegram-style horizontal tab bar with unified glass container
//  Note: Index 0 = Inbox (virtual), Index 1+ = real tabs
//

import SwiftUI

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
    let onAddTap: () -> Void
    let onMenuTap: () -> Void
    let onRenameTab: (Tab) -> Void
    let onRenameInbox: () -> Void
    let onReorderTabs: () -> Void
    let onDeleteTab: (Tab) -> Void
    var onGoToInbox: (() -> Void)? = nil  // Called when arrow button tapped on Search

    private var themeManager: ThemeManager { ThemeManager.shared }
    @AppStorage("spaceName") private var spaceName = "Taby"

    private var isOnSearch: Bool { selectedIndex == 0 }

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
                        .frame(width: 32, height: 32)
                }
                .tint(themeManager.currentTheme.accentColor)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .shadow(color: .clear, radius: 0)

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
                    .frame(width: 32, height: 32)
                }
                .tint(themeManager.currentTheme.accentColor)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .shadow(color: .clear, radius: 0)
            }
            .padding(.horizontal, 8)

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

    /// Combined list: Search + Inbox (virtual) + real tabs
    private var allItems: [TabDisplayItem] {
        var items: [TabDisplayItem] = [.search, .inbox]
        items.append(contentsOf: tabs.map { TabDisplayItem.realTab($0) })
        return items
    }

    var body: some View {
        // ONE glass container for the entire tab bar
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                // ZStack with indicator INSIDE ScrollView - frames relative to content
                ZStack(alignment: .topLeading) {
                    // Selection indicator FIRST (renders under tabs)
                    SelectionIndicatorView(frame: interpolatedSelectionFrame)

                    // Tabs ABOVE the indicator
                    HStack(spacing: 0) {
                        ForEach(Array(allItems.enumerated()), id: \.element.id) { index, item in
                            TabLabelView(
                                item: item,
                                selectionProgress: selectionProgress(for: index),
                                showReorder: tabs.count > 1,
                                onTap: {
                                    withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                                        selectedIndex = index
                                    }
                                },
                                onRename: {
                                    if item.isInbox {
                                        onRenameInbox()
                                    } else if let tab = item.tab {
                                        onRenameTab(tab)
                                    }
                                },
                                onReorder: onReorderTabs,
                                onDelete: {
                                    if let tab = item.tab {
                                        onDeleteTab(tab)
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
                            .id(index)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
                    .coordinateSpace(name: "tabContent")  // Coordinate space on HStack content
                }
            }
            .onPreferenceChange(TabFramePreferenceKey.self) { frames in
                // Only update frames when not swiping to avoid jitter from keyboard dismissal
                if switchFraction == 0 {
                    tabFrames = frames
                }
            }
            .onChange(of: selectedIndex) { _, newIndex in
                withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
            .onChange(of: switchFraction) { oldValue, newValue in
                // Only scroll when swipe completes (fraction returns to 0)
                // Avoid scrolling during swipe to prevent jitter from keyboard dismissal
                if oldValue != 0 && newValue == 0 {
                    withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                        proxy.scrollTo(selectedIndex, anchor: .center)
                    }
                }
            }
        }
        .frame(height: 46)
        .background {
            // Unified glass background for the entire tab bar
            Capsule()
                .fill(.clear)
                .glassEffect(.regular, in: .capsule)
                .id("tabbar-glass-\(colorScheme)")  // Force recreation when theme changes
        }
        .clipShape(Capsule())
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

// MARK: - Selection Indicator View

struct SelectionIndicatorView: View {
    let frame: CGRect
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Capsule()
            .fill(.clear)
            .glassEffect(.regular, in: .capsule)
            .frame(width: max(frame.width, 0), height: max(frame.height, 0))
            .offset(x: frame.minX, y: frame.minY)
            .animation(.interactiveSpring, value: frame)
            .id("indicator-glass-\(colorScheme)")  // Force recreation when theme changes
    }
}

// MARK: - Tab Label View

struct TabLabelView: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: TabDisplayItem
    let selectionProgress: CGFloat
    let showReorder: Bool
    let onTap: () -> Void
    let onRename: () -> Void
    let onReorder: () -> Void
    let onDelete: () -> Void

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

    var body: some View {
        Button(action: onTap) {
            if item.isSearch {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(textColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            } else {
                Text(item.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(textColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
        .buttonStyle(TabPressStyle())
        .if(!item.isSearch) { view in
            view.contextMenu {
                // Rename available for Inbox and real tabs
                Button {
                    onRename()
                } label: {
                    Label(L10n.Tab.rename, systemImage: "pencil")
                }

                // Reorder and Delete only for real tabs (not Inbox)
                if !item.isInbox {
                    if showReorder {
                        Button {
                            onReorder()
                        } label: {
                            Label(L10n.Tab.move, systemImage: "arrow.up.arrow.down")
                        }
                    }

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label(L10n.Tab.delete, systemImage: "trash")
                    }
                }
            } preview: {
                // Fixed-size preview to prevent scaling animation
                Text(item.title)
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
    }
}

// MARK: - Tab Press Style

struct TabPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(duration: 0.15), value: configuration.isPressed)
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
