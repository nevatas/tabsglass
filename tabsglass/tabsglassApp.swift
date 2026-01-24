//
//  tabsglassApp.swift
//  tabsglass
//
//  Created by Sergey Tokarev on 22.01.2026.
//

import SwiftUI
import SwiftData
import UIKit

@main
struct tabsglassApp: App {
    init() {
        // Warm up keyboard on app launch to avoid delay on first use
        KeyboardWarmer.shared.warmUp()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Tab.self, Message.self])
    }
}

// MARK: - Keyboard Warmer

/// Pre-loads keyboard resources to avoid delay on first text field focus
final class KeyboardWarmer {
    static let shared = KeyboardWarmer()

    private var warmUpTextField: UITextField?
    private var warmUpWindow: UIWindow?

    private init() {}

    func warmUp() {
        // Run on next run loop to not block app launch
        DispatchQueue.main.async { [weak self] in
            self?.performWarmUp()
        }
    }

    private func performWarmUp() {
        // Create an off-screen window
        let window = UIWindow(frame: CGRect(x: -100, y: -100, width: 10, height: 10))
        window.windowLevel = .init(rawValue: -1000)
        window.isHidden = false

        let textField = UITextField()
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        window.addSubview(textField)

        // Keep references to prevent deallocation
        self.warmUpWindow = window
        self.warmUpTextField = textField

        // Briefly become first responder to load keyboard
        textField.becomeFirstResponder()

        // Resign after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.warmUpTextField?.resignFirstResponder()

            // Clean up after keyboard is loaded
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.warmUpTextField?.removeFromSuperview()
                self?.warmUpTextField = nil
                self?.warmUpWindow?.isHidden = true
                self?.warmUpWindow = nil
            }
        }
    }
}
