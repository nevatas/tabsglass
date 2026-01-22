//
//  TabBarView.swift
//  tabsglass
//

import SwiftUI

struct TabBarView: View {
    let tabs: [Tab]
    @Binding var selectedIndex: Int
    let scrollProgress: CGFloat
    let onAddTap: () -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                        TabChipView(
                            title: tab.title,
                            selectionProgress: selectionProgress(for: index)
                        )
                        .id(index)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedIndex = index
                            }
                        }
                    }

                    Button(action: onAddTap) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .onChange(of: selectedIndex) { _, newValue in
                withAnimation {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
        .background(.bar)
    }

    /// Calculate selection progress for a tab (0 = not selected, 1 = fully selected)
    private func selectionProgress(for index: Int) -> CGFloat {
        let distance = abs(scrollProgress - CGFloat(index))
        return max(0, 1 - distance)
    }
}

struct TabChipView: View {
    let title: String
    let selectionProgress: CGFloat  // 0 = not selected, 1 = fully selected

    var body: some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(selectionProgress > 0.5 ? .semibold : .regular)
            .foregroundStyle(selectionProgress > 0.5 ? .primary : .secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.2 * selectionProgress))
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.accentColor.opacity(selectionProgress), lineWidth: 1.5)
            )
    }
}

#Preview {
    TabBarView(
        tabs: [],
        selectedIndex: .constant(0),
        scrollProgress: 0,
        onAddTap: {}
    )
}
