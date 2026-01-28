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
    let modelContainer: ModelContainer

    init() {
        // Warm up keyboard on app launch to avoid delay on first use
        KeyboardWarmer.shared.warmUp()

        // Initialize model container
        // Note: Inbox is virtual (messages with tabId = nil), not a real tab
        do {
            let container = try ModelContainer(for: Tab.self, Message.self)
            self.modelContainer = container
            Self.seedWelcomeMessagesIfNeeded(in: container)
        } catch {
            fatalError("Failed to initialize model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}

// MARK: - Welcome Messages Seeding

private extension tabsglassApp {
    static func seedWelcomeMessagesIfNeeded(in container: ModelContainer) {
        let key = "hasSeededWelcomeMessages"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        let texts = [
            L10n.Welcome.message1,
            L10n.Welcome.message2,
            L10n.Welcome.message3,
            L10n.Welcome.message4,
        ]

        let context = container.mainContext
        let now = Date()

        for (index, text) in texts.enumerated() {
            let message = Message(content: text)
            // Stagger timestamps so messages appear in correct order (oldest first at top)
            message.createdAt = now.addingTimeInterval(Double(index))
            context.insert(message)
        }

        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
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
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
            return
        }

        // Create an off-screen window
        let window = UIWindow(windowScene: windowScene)
        window.frame = CGRect(x: -100, y: -100, width: 10, height: 10)
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
