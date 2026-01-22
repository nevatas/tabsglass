//
//  TabPagerView.swift
//  tabsglass
//

import SwiftUI
import SwiftData

struct TabPagerView: View {
    let tabs: [Tab]
    @Binding var selectedIndex: Int
    var bottomInset: CGFloat = 0
    var onTapContent: (() -> Void)? = nil

    var body: some View {
        TabView(selection: $selectedIndex) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                ChatView(tab: tab, bottomInset: bottomInset, onTapContent: onTapContent)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }
}

#Preview {
    TabPagerView(tabs: [], selectedIndex: .constant(0))
        .modelContainer(for: [Tab.self, Message.self], inMemory: true)
}
