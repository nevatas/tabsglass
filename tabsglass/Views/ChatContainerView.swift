//
//  ChatContainerView.swift
//  tabsglass
//

import SwiftUI
import SwiftData

struct ChatContainerView: View {
    let tabs: [Tab]
    @Binding var selectedIndex: Int
    @Binding var messageText: String
    var isComposerFocused: FocusState<Bool>.Binding
    let onSend: () -> Void
    let onTapOutside: () -> Void

    var currentTab: Tab? {
        guard selectedIndex >= 0 && selectedIndex < tabs.count else { return nil }
        return tabs[selectedIndex]
    }

    var body: some View {
        TabView(selection: $selectedIndex) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                MessengerView(
                    tab: tab,
                    messageText: $messageText,
                    onSend: onSend,
                    onTapOutside: onTapOutside
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }
}
