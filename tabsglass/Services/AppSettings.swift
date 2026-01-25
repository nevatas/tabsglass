//
//  AppSettings.swift
//  tabsglass
//
//  User preferences storage
//

import Foundation

final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let autoFocusInput = "autoFocusInput"
    }

    private init() {}

    /// Auto-focus composer input when app opens
    var autoFocusInput: Bool {
        get { defaults.bool(forKey: Keys.autoFocusInput) }
        set { defaults.set(newValue, forKey: Keys.autoFocusInput) }
    }
}
