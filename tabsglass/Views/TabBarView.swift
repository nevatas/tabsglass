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
    let onMenuTap: () -> Void
    let onRenameTab: (Tab) -> Void
    let onDeleteTab: (Tab) -> Void

    var body: some View {
        VStack(spacing: 6) {
            // Header buttons row
            HStack {
                // Burger menu button (left) - circular liquid glass
                Button(action: onMenuTap) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .shadow(color: .clear, radius: 0)

                Spacer()

                // Title
                Text("Serejen's Space")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                // Plus button (right) - circular liquid glass
                Button(action: onAddTap) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .shadow(color: .clear, radius: 0)
            }
            .padding(.horizontal, 12)

            // Tabs scroll view
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
                            .contextMenu {
                                Button {
                                    onRenameTab(tab)
                                } label: {
                                    Label("Переименовать", systemImage: "pencil")
                                }

                                Button(role: .destructive) {
                                    onDeleteTab(tab)
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            } preview: {
                                // Always show selected style in preview
                                TabChipView(title: tab.title, selectionProgress: 1.0)
                                    .padding(8)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6) // Space for shadow
                }
                .scrollClipDisabled() // Allow shadow to render outside
                .scrollContentBackground(.hidden)
                .onChange(of: scrollProgress) { _, newValue in
                    // Scroll to nearest tab during swipe
                    let nearestIndex = Int(newValue.rounded())
                    if nearestIndex >= 0 && nearestIndex < tabs.count {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(nearestIndex, anchor: .center)
                        }
                    }
                }
            }
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

    /// Calculate selection progress for a tab (0 = not selected, 1 = fully selected)
    private func selectionProgress(for index: Int) -> CGFloat {
        let distance = abs(scrollProgress - CGFloat(index))
        return max(0, 1 - distance)
    }
}

struct TabChipView: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let selectionProgress: CGFloat  // 0 = not selected, 1 = fully selected

    private var shadowColor: Color {
        colorScheme == .dark ? .black : Color(red: 0.945, green: 0.945, blue: 0.945)
    }

    // Inverse progress for shadows (visible when not selected)
    private var shadowOpacity: CGFloat {
        1 - selectionProgress
    }

    // Glass opacity: 0.3 when not selected, 1.0 when selected
    private var glassOpacity: CGFloat {
        0.3 + (selectionProgress * 0.7)
    }

    var body: some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(colorScheme == .dark ? .white : .black)
            // Shadows fade out as tab becomes selected
            .shadow(color: shadowColor.opacity(shadowOpacity), radius: 12, y: 0)
            .shadow(color: shadowColor.opacity(shadowOpacity), radius: 8, y: 0)
            .shadow(color: shadowColor.opacity(shadowOpacity), radius: 4, y: 0)
            .shadow(color: shadowColor.opacity(shadowOpacity), radius: 2, y: 0)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background {
                // Glass background - semi-transparent when inactive, full when active
                Capsule()
                    .fill(.clear)
                    .glassEffect(.regular, in: .capsule)
                    .opacity(glassOpacity)
            }
            .animation(.easeOut(duration: 0.15), value: selectionProgress)
    }
}

#Preview {
    TabBarView(
        tabs: [],
        selectedIndex: .constant(0),
        scrollProgress: 0,
        onAddTap: {},
        onMenuTap: {},
        onRenameTab: { _ in },
        onDeleteTab: { _ in }
    )
}
