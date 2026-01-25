//
//  ContentView.swift
//  tabsglass
//
//  Created by Sergey Tokarev on 22.01.2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var themeManager = ThemeManager.shared

    private var backgroundColor: Color {
        let theme = themeManager.currentTheme
        if theme == .system {
            // Use system color scheme
            return colorScheme == .dark
                ? theme.backgroundColorDark
                : theme.backgroundColor
        } else {
            // Use theme's fixed color based on its preferred scheme
            return colorScheme == .dark ? theme.backgroundColorDark : theme.backgroundColor
        }
    }

    var body: some View {
        MainContainerView()
            .background(backgroundColor.ignoresSafeArea())
            .preferredColorScheme(themeManager.currentTheme.colorSchemeOverride)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Tab.self, Message.self], inMemory: true)
}
