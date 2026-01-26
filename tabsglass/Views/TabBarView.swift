//
//  TabBarView.swift
//  tabsglass
//
//  Telegram-style horizontal tab bar with unified glass container
//

import SwiftUI

// MARK: - Tab Bar View

struct TabBarView: View {
    let tabs: [Tab]
    @Binding var selectedIndex: Int
    @Binding var switchFraction: CGFloat  // -1.0 ... 0 ... 1.0 при свайпе
    let onAddTap: () -> Void
    let onMenuTap: () -> Void
    let onRenameTab: (Tab) -> Void
    let onDeleteTab: (Tab) -> Void

    var body: some View {
        VStack(spacing: 6) {
            // Header buttons row
            HStack {
                // Settings button (left) - circular liquid glass
                Button(action: onMenuTap) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .shadow(color: .clear, radius: 0)

                Spacer()

                // Title
                Text("Taby")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                // Plus button (right) - circular liquid glass
                Button(action: onAddTap) {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .shadow(color: .clear, radius: 0)
            }
            .padding(.horizontal, 12)

            // Telegram-style unified tab bar
            TelegramTabBar(
                tabs: tabs,
                selectedIndex: $selectedIndex,
                switchFraction: $switchFraction,
                onRenameTab: onRenameTab,
                onDeleteTab: onDeleteTab
            )
            .padding(.horizontal, 12)
        }
        .padding(.top, 4)
        .padding(.bottom, 16)
        .background {
            // Gradient blur - extends below header
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
    let onDeleteTab: (Tab) -> Void

    // Track frames of each tab for selection indicator positioning
    @State private var tabFrames: [Int: CGRect] = [:]

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
                        ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                            TabLabelView(
                                tab: tab,
                                selectionProgress: selectionProgress(for: index),
                                onTap: {
                                    withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                                        selectedIndex = index
                                    }
                                },
                                onRename: { onRenameTab(tab) },
                                onDelete: { onDeleteTab(tab) }
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
                tabFrames = frames
            }
            .onChange(of: selectedIndex) { _, newIndex in
                withAnimation(.spring(duration: 0.3, bounce: 0.2)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
            .onChange(of: switchFraction) { _, _ in
                // Scroll to interpolated position during swipe
                let targetIndex = Int((CGFloat(selectedIndex) + switchFraction).rounded())
                if targetIndex >= 0 && targetIndex < tabs.count && targetIndex != selectedIndex {
                    withAnimation(.interactiveSpring) {
                        proxy.scrollTo(targetIndex, anchor: .center)
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
        } else if index == targetIndex && targetIndex >= 0 && targetIndex < tabs.count {
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
        guard targetIndex >= 0 && targetIndex < tabs.count,
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

    var body: some View {
        Capsule()
            .fill(.clear)
            .glassEffect(.regular, in: .capsule)
            .frame(width: max(frame.width, 0), height: max(frame.height, 0))
            .offset(x: frame.minX, y: frame.minY)
            .animation(.interactiveSpring, value: frame)
    }
}

// MARK: - Tab Label View

struct TabLabelView: View {
    @Environment(\.colorScheme) private var colorScheme
    let tab: Tab
    let selectionProgress: CGFloat
    let onTap: () -> Void
    let onRename: () -> Void
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
            Text(tab.title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(textColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .buttonStyle(TabPressStyle())
        .contextMenu {
            Button {
                onRename()
            } label: {
                Label("Переименовать", systemImage: "pencil")
            }

            if !tab.isInbox {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Удалить", systemImage: "trash")
                }
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
            onDeleteTab: { _ in }
        )
        Spacer()
    }
    .background(Color.black)
}
