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

        // Initialize model container and ensure Inbox exists
        do {
            let container = try ModelContainer(for: Tab.self, Message.self)
            self.modelContainer = container

            // Ensure Inbox tab exists on startup
            let context = container.mainContext
            let descriptor = FetchDescriptor<Tab>(predicate: #Predicate { $0.isInbox == true })
            let inboxTabs = try context.fetch(descriptor)

            if inboxTabs.isEmpty {
                let inboxTab = Tab(title: "Inbox", sortOrder: 0, isInbox: true)
                context.insert(inboxTab)
                try context.save()
            }
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
