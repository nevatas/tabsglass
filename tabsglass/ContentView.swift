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
    @State private var showOnboarding = true // TODO: revert to !AppSettings.shared.hasCompletedOnboarding
    @State private var showPaywall = false // TODO: revert to AppSettings.shared.hasCompletedOnboarding
    private var themeManager: ThemeManager { ThemeManager.shared }

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
        ZStack {
            MainContainerView()
                .onAppear {
                    KeyboardWarmer.shared.warmUp()
                }

            if showPaywall {
                PaywallView(isPresented: $showPaywall)
            }

            if showOnboarding {
                OnboardingView {
                    showOnboarding = false
                    showPaywall = true
                }
            }
        }
        .background(backgroundColor.ignoresSafeArea())
        .preferredColorScheme(themeManager.currentTheme.colorSchemeOverride)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Tab.self, Message.self], inMemory: true)
}
