//
//  ContentView.swift
//  tabsglass
//
//  Created by Sergey Tokarev on 22.01.2026.
//

import SwiftUI
import SwiftData

struct DeepLink {
    let tabId: UUID?
    let messageId: UUID
}

struct ContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var showOnboarding = false // TODO: revert to !AppSettings.shared.hasCompletedOnboarding
    @State private var showPaywall = false // TODO: revert to AppSettings.shared.hasCompletedOnboarding
    @State private var pendingDeepLink: DeepLink?
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
            MainContainerView(pendingDeepLink: $pendingDeepLink)
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
        .onOpenURL { url in
            guard url.scheme == "taby", url.host == "task" || url.host == "message" else { return }
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            guard let messageId = components?.queryItems?.first(where: { $0.name == "message" })?.value.flatMap(UUID.init) else { return }
            let tabId = components?.queryItems?.first(where: { $0.name == "tab" })?.value.flatMap(UUID.init)
            pendingDeepLink = DeepLink(tabId: tabId, messageId: messageId)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Tab.self, Message.self], inMemory: true)
}
