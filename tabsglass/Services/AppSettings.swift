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
            return Color(red: 0xFF/255, green: 0xF0/255, blue: 0xF5/255)
        case .beige:
            return Color(red: 0xF5/255, green: 0xF0/255, blue: 0xE6/255)
        case .green:
            return Color(red: 0xF0/255, green: 0xF5/255, blue: 0xF0/255)
        case .brown:
            return Color(red: 0xF5/255, green: 0xF0/255, blue: 0xEB/255)
        case .blue:
            return Color(red: 0xF0/255, green: 0xF5/255, blue: 0xFA/255)
        }
    }

    /// Dark background for dark mode variants
    var backgroundColorDark: Color {
        switch self {
        case .system, .dark, .light:
            return Color(red: 0x19/255, green: 0x1A/255, blue: 0x1A/255)
        case .pink:
            return Color(red: 0x2D/255, green: 0x1F/255, blue: 0x26/255)
        case .beige:
            return Color(red: 0x2A/255, green: 0x27/255, blue: 0x20/255)
        case .green:
            return Color(red: 0x1A/255, green: 0x24/255, blue: 0x1A/255)
        case .brown:
            return Color(red: 0x24/255, green: 0x20/255, blue: 0x1A/255)
        case .blue:
            return Color(red: 0x1A/255, green: 0x20/255, blue: 0x28/255)
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
            return UIColor(red: 0xFF/255, green: 0xE4/255, blue: 0xEC/255, alpha: 1)
        case .beige:
            return UIColor(red: 0xEA/255, green: 0xE4/255, blue: 0xD5/255, alpha: 1)
        case .green:
            return UIColor(red: 0xE0/255, green: 0xEE/255, blue: 0xE0/255, alpha: 1)
        case .brown:
            return UIColor(red: 0xE8/255, green: 0xE0/255, blue: 0xD5/255, alpha: 1)
        case .blue:
            return UIColor(red: 0xE0/255, green: 0xEB/255, blue: 0xF5/255, alpha: 1)
        }
    }

    /// Bubble color for dark mode
    var bubbleColorDark: UIColor {
        switch self {
        case .system, .dark, .light:
            return UIColor(red: 0x24/255, green: 0x25/255, blue: 0x29/255, alpha: 1)
        case .pink:
            return UIColor(red: 0x3D/255, green: 0x2A/255, blue: 0x33/255, alpha: 1)
        case .beige:
            return UIColor(red: 0x3A/255, green: 0x36/255, blue: 0x2C/255, alpha: 1)
        case .green:
            return UIColor(red: 0x28/255, green: 0x38/255, blue: 0x28/255, alpha: 1)
        case .brown:
            return UIColor(red: 0x38/255, green: 0x30/255, blue: 0x28/255, alpha: 1)
        case .blue:
            return UIColor(red: 0x28/255, green: 0x30/255, blue: 0x3D/255, alpha: 1)
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
