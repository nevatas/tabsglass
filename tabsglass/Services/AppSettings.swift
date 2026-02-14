//
//  AppSettings.swift
//  tabsglass
//
//  User preferences storage
//

import Foundation
import SwiftUI
import UIKit
import Combine
import WidgetKit

// MARK: - App Theme

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    case pink = "pink"
    case beige = "beige"
    case green = "green"
    case blue = "blue"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return L10n.Theme.system
        case .light: return L10n.Theme.light
        case .dark: return L10n.Theme.dark
        case .pink: return L10n.Theme.pink
        case .beige: return L10n.Theme.beige
        case .green: return L10n.Theme.green
        case .blue: return L10n.Theme.blue
        }
    }

    var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        case .pink: return "heart.fill"
        case .beige: return "cup.and.saucer.fill"
        case .green: return "leaf.fill"
        case .blue: return "drop.fill"
        }
    }

    /// Standard themes (system, light, dark)
    static var standardThemes: [AppTheme] {
        [.system, .light, .dark]
    }

    /// Color themes (pink, beige, green, blue)
    static var colorThemes: [AppTheme] {
        [.pink, .beige, .green, .blue]
    }

    /// Background color for the theme
    var backgroundColor: Color {
        switch self {
        case .system, .light:
            return .white
        case .dark:
            return Color(red: 0x19/255, green: 0x1A/255, blue: 0x1A/255)
        case .pink:
            return Color(red: 0xFF/255, green: 0xC8/255, blue: 0xE0/255)
        case .beige:
            return Color(red: 0xF0/255, green: 0xDC/255, blue: 0xC0/255)
        case .green:
            return Color(red: 0xC8/255, green: 0xE8/255, blue: 0xC8/255)
        case .blue:
            return Color(red: 0xC8/255, green: 0xE0/255, blue: 0xF8/255)
        }
    }

    /// Dark background for dark mode variants
    var backgroundColorDark: Color {
        switch self {
        case .system, .dark, .light:
            return Color(red: 0x19/255, green: 0x1A/255, blue: 0x1A/255)
        case .pink:
            return Color(red: 0x3C/255, green: 0x18/255, blue: 0x28/255)
        case .beige:
            return Color(red: 0x38/255, green: 0x2C/255, blue: 0x1C/255)
        case .green:
            return Color(red: 0x18/255, green: 0x30/255, blue: 0x18/255)
        case .blue:
            return Color(red: 0x18/255, green: 0x28/255, blue: 0x3C/255)
        }
    }

    /// Bubble color for messages (lighter than background for color themes)
    var bubbleColor: UIColor {
        switch self {
        case .system, .light:
            return UIColor(white: 0.96, alpha: 1)
        case .dark:
            return UIColor(red: 0x24/255, green: 0x25/255, blue: 0x29/255, alpha: 1)
        case .pink:
            return UIColor(red: 0xFF/255, green: 0xE8/255, blue: 0xF2/255, alpha: 1)
        case .beige:
            return UIColor(red: 0xFA/255, green: 0xF4/255, blue: 0xE8/255, alpha: 1)
        case .green:
            return UIColor(red: 0xE8/255, green: 0xF8/255, blue: 0xE8/255, alpha: 1)
        case .blue:
            return UIColor(red: 0xE8/255, green: 0xF4/255, blue: 0xFF/255, alpha: 1)
        }
    }

    /// Bubble color for dark mode (lighter than dark background for color themes)
    var bubbleColorDark: UIColor {
        switch self {
        case .system, .dark, .light:
            return UIColor(red: 0x24/255, green: 0x25/255, blue: 0x29/255, alpha: 1)
        case .pink:
            return UIColor(red: 0x50/255, green: 0x28/255, blue: 0x38/255, alpha: 1)
        case .beige:
            return UIColor(red: 0x4C/255, green: 0x3C/255, blue: 0x28/255, alpha: 1)
        case .green:
            return UIColor(red: 0x28/255, green: 0x48/255, blue: 0x28/255, alpha: 1)
        case .blue:
            return UIColor(red: 0x28/255, green: 0x3C/255, blue: 0x54/255, alpha: 1)
        }
    }

    /// Whether this theme forces a specific appearance
    var colorSchemeOverride: ColorScheme? {
        switch self {
        case .system: return nil
        case .light, .pink, .beige, .green, .blue: return .light
        case .dark: return .dark
        }
    }

    /// Accent color for buttons, icons, links (nil = use system blue)
    var accentColor: Color? {
        switch self {
        case .system, .light, .dark:
            return nil
        case .pink:
            return Color(red: 0xD7/255, green: 0x33/255, blue: 0x82/255)
        case .beige:
            return Color(red: 0xA6/255, green: 0x7C/255, blue: 0x52/255)
        case .green:
            return Color(red: 0x2E/255, green: 0x7D/255, blue: 0x32/255)
        case .blue:
            return Color(red: 0x1E/255, green: 0x88/255, blue: 0xE5/255)
        }
    }

    /// Link color - saturated darker version of theme color (UIColor version)
    var linkColor: UIColor {
        switch self {
        case .system, .light, .dark:
            return .link
        case .pink:
            return UIColor(red: 0xD7/255, green: 0x33/255, blue: 0x82/255, alpha: 1)
        case .beige:
            return UIColor(red: 0xA6/255, green: 0x7C/255, blue: 0x52/255, alpha: 1)
        case .green:
            return UIColor(red: 0x2E/255, green: 0x7D/255, blue: 0x32/255, alpha: 1)
        case .blue:
            return UIColor(red: 0x1E/255, green: 0x88/255, blue: 0xE5/255, alpha: 1)
        }
    }

    /// Composer glass tint color (light mode)
    var composerTintColor: Color {
        switch self {
        case .system, .light:
            return .white.opacity(0.9)
        case .dark:
            return Color(white: 0.1).opacity(0.9)
        case .pink:
            return Color(red: 0xFF/255, green: 0xE0/255, blue: 0xEC/255).opacity(0.95)
        case .beige:
            return Color(red: 0xF4/255, green: 0xE8/255, blue: 0xD8/255).opacity(0.95)
        case .green:
            return Color(red: 0xE0/255, green: 0xF0/255, blue: 0xE0/255).opacity(0.95)
        case .blue:
            return Color(red: 0xE0/255, green: 0xEC/255, blue: 0xFA/255).opacity(0.95)
        }
    }

    /// Composer glass tint color (dark mode)
    var composerTintColorDark: Color {
        switch self {
        case .system, .light, .dark:
            return Color(white: 0.1).opacity(0.9)
        case .pink:
            return Color(red: 0x40/255, green: 0x1C/255, blue: 0x2C/255).opacity(0.95)
        case .beige:
            return Color(red: 0x3C/255, green: 0x30/255, blue: 0x20/255).opacity(0.95)
        case .green:
            return Color(red: 0x1C/255, green: 0x34/255, blue: 0x1C/255).opacity(0.95)
        case .blue:
            return Color(red: 0x1C/255, green: 0x2C/255, blue: 0x40/255).opacity(0.95)
        }
    }

    /// Placeholder text color - tinted for colored themes
    var placeholderColor: UIColor {
        switch self {
        case .system, .light, .dark:
            return .placeholderText
        case .pink:
            // Desaturated pink, darker for better visibility
            return UIColor(red: 0xA0/255, green: 0x70/255, blue: 0x85/255, alpha: 1)
        case .beige:
            // Warm brown-gray
            return UIColor(red: 0x9A/255, green: 0x88/255, blue: 0x70/255, alpha: 1)
        case .green:
            // Muted green-gray
            return UIColor(red: 0x60/255, green: 0x85/255, blue: 0x60/255, alpha: 1)
        case .blue:
            // Soft blue-gray
            return UIColor(red: 0x60/255, green: 0x7A/255, blue: 0x98/255, alpha: 1)
        }
    }
}

// MARK: - Theme Manager

extension Notification.Name {
    static let themeDidChange = Notification.Name("themeDidChange")
}

@Observable
@MainActor
final class ThemeManager {
    static let shared = ThemeManager()

    var currentTheme: AppTheme {
        didSet {
            AppSettings.shared.theme = currentTheme
            // Notify UIKit components about theme change
            NotificationCenter.default.post(name: .themeDidChange, object: nil)
            // Reload widget to reflect new theme
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private init() {
        self.currentTheme = AppSettings.shared.theme
    }
}

// MARK: - App Settings

final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let autoFocusInput = "autoFocusInput"
        static let theme = "appTheme"
        static let inboxTitle = "inboxTitle"
        static let spaceName = "spaceName"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    private init() {}

    /// Custom title for virtual Inbox tab (default: "📥 Inbox")
    var inboxTitle: String {
        get { defaults.string(forKey: Keys.inboxTitle) ?? "📥 Inbox" }
        set { defaults.set(newValue, forKey: Keys.inboxTitle) }
    }

    /// Space name displayed in the header (default: "Taby")
    var spaceName: String {
        get { defaults.string(forKey: Keys.spaceName) ?? "Taby" }
        set { defaults.set(newValue, forKey: Keys.spaceName) }
    }

    /// Auto-focus composer input when app opens
    var autoFocusInput: Bool {
        get { defaults.bool(forKey: Keys.autoFocusInput) }
        set { defaults.set(newValue, forKey: Keys.autoFocusInput) }
    }

    /// Whether the user has completed the onboarding flow
    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Keys.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Keys.hasCompletedOnboarding) }
    }

    /// Selected app theme
    var theme: AppTheme {
        get {
            guard let rawValue = defaults.string(forKey: Keys.theme),
                  let theme = AppTheme(rawValue: rawValue) else {
                return .system
            }
            return theme
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.theme)
            // Sync to shared UserDefaults so widget can read the theme
            UserDefaults(suiteName: SharedConstants.appGroupID)?.set(newValue.rawValue, forKey: Keys.theme)
        }
    }

    /// Sync current theme to shared UserDefaults (call on app launch)
    func syncThemeToSharedDefaults() {
        UserDefaults(suiteName: SharedConstants.appGroupID)?.set(theme.rawValue, forKey: Keys.theme)
    }

    // MARK: - Legacy User (Grandfathering)

    /// Records the first install date in Keychain (survives app reinstalls).
    /// Call once on every app launch — only writes if no date exists yet.
    func stampFirstInstallDateIfNeeded() {
        guard KeychainHelper.getDate(for: "firstInstallDate") == nil else { return }
        KeychainHelper.setDate(Date(), for: "firstInstallDate")
    }

    /// The date the app was first installed, or nil if never stamped.
    var firstInstallDate: Date? {
        KeychainHelper.getDate(for: "firstInstallDate")
    }
}

// MARK: - Keychain Helper

/// Minimal Keychain wrapper for storing dates (survives app reinstalls).
enum KeychainHelper {
    private static let service = "company.thecool.taby"

    static func setDate(_ date: Date, for key: String) {
        let data = String(date.timeIntervalSince1970).data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func getDate(for key: String) -> Date? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8),
              let interval = Double(string) else {
            return nil
        }
        return Date(timeIntervalSince1970: interval)
    }
}
