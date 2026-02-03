//
//  SearchTabsView.swift
//  tabsglass
//
//  Tab buttons grid for Search screen
//

import SwiftUI

struct SearchTabsView: View {
    let tabs: [Tab]
    let onTabSelected: (Int) -> Void  // Index to navigate to (2+ = real tabs)

    var body: some View {
        // Centered buttons - only the button shapes are interactive
        GeometryReader { geometry in
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
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
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

// MARK: - Preview

#Preview {
    SearchTabsView(tabs: []) { _ in }
        .background(Color.gray.opacity(0.2))
}
