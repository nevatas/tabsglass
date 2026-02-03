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
        // Pre-warm singletons to avoid lazy initialization delays on first use
        _ = AppSettings.shared
        _ = ThemeManager.shared
        _ = ImageCache.shared

        // Warm up keyboard on app launch to avoid delay on first use
        KeyboardWarmer.shared.warmUp()

        // Warm up Liquid Glass effects to avoid delay on first render
        GlassEffectWarmer.shared.warmUp()

        // Migrate photos to shared container (for Share Extension support)
        // Note: Database migration happens automatically in SharedModelContainer.create()
        SharedModelContainer.migratePhotosIfNeeded()

        // Initialize model container with shared store for extension support
        // Note: Inbox is virtual (messages with tabId = nil), not a real tab
        do {
            let container = try SharedModelContainer.create()
            self.modelContainer = container
            Self.seedWelcomeMessagesIfNeeded(in: container)
            Self.processPendingShareItems(in: container)
        } catch {
            fatalError("Failed to initialize model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    // Process any pending share items when app returns to foreground
                    Self.processPendingShareItems(in: modelContainer)
                }
        }
        .modelContainer(modelContainer)
    }
}

// MARK: - Pending Share Items Processing

private extension tabsglassApp {
    static func processPendingShareItems(in container: ModelContainer) {
        let pendingItems = PendingShareStorage.loadAll()
        guard !pendingItems.isEmpty else { return }

        let context = container.mainContext

        for item in pendingItems {
            // Detect URLs in text
            let entities = TextEntity.detectURLs(in: item.text)

            let message = Message(
                content: item.text,
                tabId: item.tabId,
                entities: entities.isEmpty ? nil : entities,
                photoFileNames: item.photoFileNames,
                photoAspectRatios: item.photoAspectRatios,
                videoFileNames: item.videoFileNames,
                videoAspectRatios: item.videoAspectRatios,
                videoDurations: item.videoDurations,
                videoThumbnailFileNames: item.videoThumbnailFileNames
            )
            message.createdAt = item.createdAt

            context.insert(message)
        }

        try? context.save()
        PendingShareStorage.clearAll()
    }

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

// MARK: - Glass Effect Warmer

/// Pre-loads Liquid Glass rendering pipeline to avoid delay on first use
final class GlassEffectWarmer {
    static let shared = GlassEffectWarmer()

    private var warmUpWindow: UIWindow?
    private var warmUpHostingController: UIHostingController<AnyView>?

    private init() {}

    func warmUp() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.performWarmUp()
        }
    }

    private func performWarmUp() {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
            // Retry if not ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.performWarmUp()
            }
            return
        }

        // Create off-screen window with GlassEffect view
        let window = UIWindow(windowScene: windowScene)
        window.frame = CGRect(x: -500, y: -500, width: 100, height: 100)
        window.windowLevel = .init(rawValue: -1000)
        window.isHidden = false

        // Create a SwiftUI view with GlassEffect to trigger pipeline initialization
        let glassView = AnyView(
            GlassEffectContainer {
                Color.clear
                    .frame(width: 50, height: 50)
                    .glassEffect(.regular, in: .rect(cornerRadius: 12))
            }
        )

        let hostingController = UIHostingController(rootView: glassView)
        hostingController.view.frame = window.bounds
        window.rootViewController = hostingController

        self.warmUpWindow = window
        self.warmUpHostingController = hostingController

        // Force layout to trigger glass effect rendering
        hostingController.view.layoutIfNeeded()

        // Clean up after rendering is complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.warmUpHostingController?.view.removeFromSuperview()
            self?.warmUpHostingController = nil
            self?.warmUpWindow?.isHidden = true
            self?.warmUpWindow = nil
        }
    }
}

/// Pre-loads keyboard resources to avoid delay on first text field focus
final class KeyboardWarmer {
    static let shared = KeyboardWarmer()

    private var warmUpTextView: FormattingTextView?
    private var warmUpTextField: UITextField?
    private var warmUpWindow: UIWindow?
    private var retryCount = 0
    private let maxRetries = 5

    private init() {}

    func warmUp() {
        // Start immediately, retry if window scene not ready yet
        performWarmUp()
    }

    private func performWarmUp() {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else {
            // Retry with small delay if window scene not ready
            retryCount += 1
            if retryCount < maxRetries {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.performWarmUp()
                }
            }
            return
        }

        // Create an off-screen window
        let window = UIWindow(windowScene: windowScene)
        window.frame = CGRect(x: -100, y: -100, width: 200, height: 100)
        window.windowLevel = .init(rawValue: -1000)
        window.isHidden = false

        // Use FormattingTextView (actual composer class) for accurate warmup
        // This ensures all FormattingTextView initialization code runs:
        // - setup() method with observers and UIEditMenuInteraction
        // - ThemeManager access and link text attributes
        let textView = FormattingTextView()
        textView.frame = CGRect(x: 0, y: 0, width: 100, height: 50)
        window.addSubview(textView)

        // Also warm up UITextField for search input
        let textField = UITextField()
        textField.frame = CGRect(x: 100, y: 0, width: 100, height: 50)
        textField.autocorrectionType = .default
        textField.spellCheckingType = .default
        textField.font = .systemFont(ofSize: 16)
        window.addSubview(textField)

        // Keep references to prevent deallocation
        self.warmUpWindow = window
        self.warmUpTextView = textView
        self.warmUpTextField = textField

        // Briefly become first responder to load keyboard (use FormattingTextView first)
        textView.becomeFirstResponder()

        // After a short time, switch to TextField to warm it up too
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.warmUpTextView?.resignFirstResponder()
            self?.warmUpTextField?.becomeFirstResponder()
        }

        // Keep keyboard up for full preload (including autocomplete, emoji keyboard, etc.)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.warmUpTextField?.resignFirstResponder()

            // Clean up after keyboard is fully dismissed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.warmUpTextView?.removeFromSuperview()
                self?.warmUpTextView = nil
                self?.warmUpTextField?.removeFromSuperview()
                self?.warmUpTextField = nil
                self?.warmUpWindow?.isHidden = true
                self?.warmUpWindow = nil
            }
        }
    }
}
