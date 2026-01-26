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

// MARK: - App Theme

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    case pink = "pink"
    case beige = "beige"
    case green = "green"
    case brown = "brown"
    case blue = "blue"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "Системная"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        case .pink: return "Розовая"
        case .beige: return "Бежевая"
        case .green: return "Зелёная"
        case .brown: return "Коричневая"
        case .blue: return "Голубая"
        }
    }

    var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        case .pink: return "heart"
        case .beige: return "leaf"
        case .green: return "leaf.fill"
        case .brown: return "cup.and.saucer"
        case .blue: return "drop"
        }
    }

    /// Standard themes (system, light, dark)
    static var standardThemes: [AppTheme] {
        [.system, .light, .dark]
    }

    /// Color themes (pink, beige, green, brown, blue)
    static var colorThemes: [AppTheme] {
        [.pink, .beige, .green, .brown, .blue]
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
        case .brown:
            return Color(red: 0xE8/255, green: 0xD8/255, blue: 0xC8/255)
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
        case .brown:
            return Color(red: 0x32/255, green: 0x24/255, blue: 0x18/255)
        case .blue:
            return Color(red: 0x18/255, green: 0x28/255, blue: 0x3C/255)
        }
    }

    /// Bubble color for messages
    var bubbleColor: UIColor {
        switch self {
        case .system, .light:
            return UIColor(white: 0.96, alpha: 1)
        case .dark:
            return UIColor(red: 0x24/255, green: 0x25/255, blue: 0x29/255, alpha: 1)
        case .pink:
            return UIColor(red: 0xFF/255, green: 0xB8/255, blue: 0xD4/255, alpha: 1)
        case .beige:
            return UIColor(red: 0xE4/255, green: 0xD0/255, blue: 0xB4/255, alpha: 1)
        case .green:
            return UIColor(red: 0xB4/255, green: 0xDC/255, blue: 0xB4/255, alpha: 1)
        case .brown:
            return UIColor(red: 0xD8/255, green: 0xC4/255, blue: 0xAC/255, alpha: 1)
        case .blue:
            return UIColor(red: 0xB8/255, green: 0xD4/255, blue: 0xF4/255, alpha: 1)
        }
    }

    /// Bubble color for dark mode
    var bubbleColorDark: UIColor {
        switch self {
        case .system, .dark, .light:
            return UIColor(red: 0x24/255, green: 0x25/255, blue: 0x29/255, alpha: 1)
        case .pink:
            return UIColor(red: 0x4C/255, green: 0x24/255, blue: 0x38/255, alpha: 1)
        case .beige:
            return UIColor(red: 0x48/255, green: 0x3C/255, blue: 0x28/255, alpha: 1)
        case .green:
            return UIColor(red: 0x24/255, green: 0x44/255, blue: 0x24/255, alpha: 1)
        case .brown:
            return UIColor(red: 0x44/255, green: 0x34/255, blue: 0x24/255, alpha: 1)
        case .blue:
            return UIColor(red: 0x24/255, green: 0x38/255, blue: 0x50/255, alpha: 1)
        }
    }

    /// Whether this theme forces a specific appearance
    var colorSchemeOverride: ColorScheme? {
        switch self {
        case .system: return nil
        case .light, .pink, .beige, .green, .brown, .blue: return .light
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
        case .brown:
            return Color(red: 0x6D/255, green: 0x4C/255, blue: 0x41/255)
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
        case .brown:
            return UIColor(red: 0x6D/255, green: 0x4C/255, blue: 0x41/255, alpha: 1)
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
        case .brown:
            return Color(red: 0xF0/255, green: 0xE4/255, blue: 0xD8/255).opacity(0.95)
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
        case .brown:
            return Color(red: 0x38/255, green: 0x2C/255, blue: 0x1C/255).opacity(0.95)
        case .blue:
            return Color(red: 0x1C/255, green: 0x2C/255, blue: 0x40/255).opacity(0.95)
        }
    }
}

// MARK: - Theme Manager

extension Notification.Name {
    static let themeDidChange = Notification.Name("themeDidChange")
}

final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var currentTheme: AppTheme {
        didSet {
            AppSettings.shared.theme = currentTheme
            // Notify UIKit components about theme change
            NotificationCenter.default.post(name: .themeDidChange, object: nil)
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
    }

    private init() {}

    /// Custom title for virtual Inbox tab (default: "Inbox")
    var inboxTitle: String {
        get { defaults.string(forKey: Keys.inboxTitle) ?? "Inbox" }
        set { defaults.set(newValue, forKey: Keys.inboxTitle) }
    }

    /// Auto-focus composer input when app opens
    var autoFocusInput: Bool {
        get { defaults.bool(forKey: Keys.autoFocusInput) }
        set { defaults.set(newValue, forKey: Keys.autoFocusInput) }
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
        }
    }
}
