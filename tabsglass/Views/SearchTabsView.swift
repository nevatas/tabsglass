//
//  SearchTabsView.swift
//  tabsglass
//
//  Tab buttons grid for Search screen
//

import SwiftUI
import Combine

struct SearchTabsView: View {
    let tabs: [Tab]
    let onTabSelected: (Int) -> Void  // Index to navigate to (2+ = real tabs)

    private var themeManager: ThemeManager { ThemeManager.shared }
    @Environment(\.colorScheme) private var colorScheme

    private var backgroundColor: Color {
        colorScheme == .dark
            ? themeManager.currentTheme.backgroundColorDark
            : themeManager.currentTheme.backgroundColor
    }

    @State private var contentHeight: CGFloat = 0
    @State private var keyboardHeight: CGFloat = 0

    /// Show tips when no tabs, or keyboard is up
    private var showTips: Bool { tabs.isEmpty || keyboardHeight > 0 }

    var body: some View {
        GeometryReader { geometry in
            let availableHeight = geometry.size.height - 80 - 120  // minus top and bottom padding
            let shouldCenter = contentHeight > 0 && contentHeight < availableHeight

            ZStack {
                // Tips: when no tabs OR keyboard is up
                if showTips {
                    SearchTipsView(keyboardHeight: keyboardHeight)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Scrollable content (tab chips — fade out when keyboard is up)
                ScrollView {
                    if !tabs.isEmpty {
                        FlowLayout(spacing: 12) {
                            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                                TabChipButton(title: tab.title) {
                                    onTabSelected(index + 2)  // +2 because 0=Search, 1=Inbox
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 20)
                        .background(
                            GeometryReader { contentGeo in
                                Color.clear.onAppear {
                                    contentHeight = contentGeo.size.height
                                }
                                .onChange(of: tabs.count) { _, _ in
                                    contentHeight = contentGeo.size.height
                                }
                            }
                        )
                        .padding(.top, shouldCenter ? (availableHeight - contentHeight) / 2 + 80 : 80)
                        .padding(.bottom, 120)  // Space for search input + bottom gradient
                    }
                }
                .scrollIndicators(.hidden)
                .opacity(keyboardHeight > 0 ? 0 : 1)
                .allowsHitTesting(keyboardHeight == 0)

                // Gradients overlay
                VStack(spacing: 0) {
                    // Top fade gradient - positioned to fade within header area
                    LinearGradient(
                        stops: [
                            .init(color: backgroundColor, location: 0),
                            .init(color: backgroundColor, location: 0.5),
                            .init(color: backgroundColor.opacity(0), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 70)

                    Spacer()

                    // Bottom fade gradient
                    LinearGradient(
                        stops: [
                            .init(color: backgroundColor.opacity(0), location: 0),
                            .init(color: backgroundColor, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 100)
                }
                .allowsHitTesting(false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                withAnimation(.easeInOut(duration: 0.25)) {
                    keyboardHeight = frame.height
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                keyboardHeight = 0
            }
        }
    }
}

// MARK: - Tab Chip Button

struct TabChipButton: View {
    let title: String
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var themeManager: ThemeManager { ThemeManager.shared }

    private var chipTint: Color {
        let theme = themeManager.currentTheme
        return colorScheme == .dark ? theme.composerTintColorDark : theme.composerTintColor
    }

    /// Unique ID that changes with theme to force glassEffect refresh
    private var glassId: String {
        "\(themeManager.currentTheme.rawValue)-\(colorScheme == .dark ? "dark" : "light")"
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .medium))  // 15 * 1.2 = 18
                .lineLimit(1)
                .padding(.horizontal, 19)  // 16 * 1.2 ≈ 19
                .padding(.vertical, 12)    // 10 * 1.2 = 12
        }
        .buttonStyle(.plain)
        .glassEffect(
            .regular.tint(chipTint).interactive(),
            in: .capsule
        )
        .id(glassId)  // Force recreation when theme changes
    }
}

// MARK: - Flow Layout (Centered)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return CGSize(width: proposal.width ?? result.contentWidth, height: result.totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)

        for (index, position) in result.positions.enumerated() {
            // Center each row horizontally
            let lineIndex = result.lineIndices[index]
            let lineWidth = result.lineWidths[lineIndex]
            let centerOffset = (bounds.width - lineWidth) / 2

            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x + centerOffset, y: bounds.minY + position.y),
                proposal: ProposedViewSize(result.sizes[index])
            )
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var sizes: [CGSize] = []
        var lineIndices: [Int] = []
        var lineWidths: [CGFloat] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var currentLineWidth: CGFloat = 0
        var currentLineIndex = 0
        var contentWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            sizes.append(size)

            if currentX + size.width > maxWidth && currentX > 0 {
                // Save current line width before moving to next line
                lineWidths.append(currentLineWidth - spacing)
                contentWidth = max(contentWidth, currentLineWidth - spacing)

                // Move to next line
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
                currentLineWidth = 0
                currentLineIndex += 1
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineIndices.append(currentLineIndex)
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            currentLineWidth = currentX
        }

        // Save last line width
        if currentLineWidth > 0 {
            lineWidths.append(currentLineWidth - spacing)
            contentWidth = max(contentWidth, currentLineWidth - spacing)
        }

        let totalHeight = currentY + lineHeight
        return LayoutResult(
            contentWidth: contentWidth,
            totalHeight: totalHeight,
            positions: positions,
            sizes: sizes,
            lineIndices: lineIndices,
            lineWidths: lineWidths
        )
    }

    private struct LayoutResult {
        let contentWidth: CGFloat
        let totalHeight: CGFloat
        let positions: [CGPoint]
        let sizes: [CGSize]
        let lineIndices: [Int]
        let lineWidths: [CGFloat]
    }
}

// MARK: - Search Tips (Empty State)

struct SearchTipsView: View {
    let keyboardHeight: CGFloat
    @State private var currentTipIndex: Int

    private var tips: [String] {
        [
            L10n.Tips.edgeSwipe,
            L10n.Tips.shakeUndo,
            L10n.Tips.formatting,
        ]
    }

    init(keyboardHeight: CGFloat) {
        self.keyboardHeight = keyboardHeight
        _currentTipIndex = State(initialValue: Int.random(in: 0..<3))
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(L10n.Tips.title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .tracking(0.5)

            Text(tips[currentTipIndex])
                .font(.system(size: 15))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 48)
        .offset(y: keyboardHeight > 0 ? 50 - keyboardHeight / 2 : 0)
        .id(currentTipIndex)
        .transition(.blurReplace)
        .onReceive(Timer.publish(every: 8, on: .main, in: .common).autoconnect()) { _ in
            withAnimation(.easeInOut(duration: 0.6)) {
                currentTipIndex = (currentTipIndex + 1) % tips.count
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SearchTabsView(tabs: []) { _ in }
        .background(Color.gray.opacity(0.2))
}
