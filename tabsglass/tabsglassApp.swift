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

        // Keyboard warmup is deferred until after paywall dismissal (see ContentView)

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
            Self.migrateTodoMessagesIfNeeded(in: container)
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

        // Build all messages for batch insert
        var insertedMessages: [(message: Message, itemId: UUID)] = []
        for item in pendingItems {
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
            insertedMessages.append((message, item.id))
        }

        // Try single batch save
        do {
            try context.save()
            // All succeeded — remove all pending items
            for (_, itemId) in insertedMessages {
                PendingShareStorage.remove(id: itemId)
            }
        } catch {
            // Batch failed — roll back and retry one-by-one
            for (message, _) in insertedMessages {
                context.delete(message)
            }

            for item in pendingItems {
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
                do {
                    try context.save()
                    PendingShareStorage.remove(id: item.id)
                } catch {
                    // Keep item in queue for retry on next foreground launch.
                    context.delete(message)
                }
            }
        }
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

    static func migrateTodoMessagesIfNeeded(in container: ModelContainer) {
        let key = "hasCompletedTodoMigration_v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        let context = container.mainContext
        let descriptor = FetchDescriptor<Message>()
        guard let messages = try? context.fetch(descriptor) else { return }

        for message in messages {
            guard message.isTodoList && !message.hasContentBlocks else { continue }

            var blocks: [ContentBlock] = []

            // Title → bold text block
            if let title = message.todoTitle, !title.isEmpty {
                let titleUTF16Length = (title as NSString).length
                let boldEntity = TextEntity(type: "bold", offset: 0, length: titleUTF16Length)
                blocks.append(ContentBlock(type: "text", text: title, entities: [boldEntity]))
            }

            // TodoItems → todo blocks (preserve original IDs)
            if let items = message.todoItems {
                for item in items {
                    blocks.append(ContentBlock(
                        id: item.id,
                        type: "todo",
                        text: item.text,
                        isCompleted: item.isCompleted
                    ))
                }
            }

            message.contentBlocks = blocks
            message.content = message.todoTitle ?? ""
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
                    // Warm interactive+tinted glass as it's used throughout the app.
                    .glassEffect(.regular.tint(.white.opacity(0.9)).interactive(), in: .rect(cornerRadius: 12))
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

    private var didWarmUp = false
    private var isWarmingUp = false
    private var attemptCount = 0
    private let maxAttempts = 60

    private weak var dummyTextField: UITextField?
    private var keyboardWillShowObserver: NSObjectProtocol?
    private var fallbackWorkItem: DispatchWorkItem?

    private init() {}

    func warmUp() {
        guard !didWarmUp else { return }
        // Start shortly after launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.performWarmUp()
        }
    }

    private func performWarmUp() {
        guard !didWarmUp, !isWarmingUp else { return }
        attemptCount += 1
        guard attemptCount <= maxAttempts else { return }

        // Only warm while app is active; otherwise the first responder / keyboard subsystem is flaky.
        guard UIApplication.shared.applicationState == .active else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.performWarmUp()
            }
            return
        }

        // If something is already focused, keyboard path is already warm.
        if UIResponder.currentFirstResponder() != nil {
            didWarmUp = true
            return
        }

        guard let keyWindow = Self.keyWindow() else {
            // Retry with small delay until we have a key window.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.performWarmUp()
            }
            return
        }

        isWarmingUp = true

        // IMPORTANT: warming in an off-screen, non-key window often does not trigger the full
        // keyboard initialization. We attach to the real key window, but keep the view invisible.
        let textField = UITextField(frame: CGRect(x: -2000, y: -2000, width: 1, height: 1))
        textField.autocorrectionType = .default
        textField.spellCheckingType = .default
        textField.keyboardType = .default
        textField.returnKeyType = .default
        textField.textContentType = .none
        textField.font = .systemFont(ofSize: 16)
        textField.isUserInteractionEnabled = true
        textField.alpha = 0.01
        textField.backgroundColor = .clear
        keyWindow.addSubview(textField)
        dummyTextField = textField

        // Prefer a "silent" warmup: resign as soon as keyboard is about to show.
        keyboardWillShowObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.finishWarmUp(after: 0.0)
        }

        let didFocus = textField.becomeFirstResponder()
        if !didFocus {
            teardownWarmUp()
            isWarmingUp = false
            // Retry quickly if focus fails.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.performWarmUp()
            }
            return
        }

        // Fallback: if we never get keyboardWillShow (e.g., hardware keyboard), stop quickly.
        let workItem = DispatchWorkItem { [weak self] in
            self?.finishWarmUp(after: 0.0)
        }
        fallbackWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func finishWarmUp(after delay: TimeInterval) {
        guard isWarmingUp else { return }
        isWarmingUp = false

        fallbackWorkItem?.cancel()
        fallbackWorkItem = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            self.dummyTextField?.resignFirstResponder()
            self.teardownWarmUp()
            self.didWarmUp = true
        }
    }

    private func teardownWarmUp() {
        if let token = keyboardWillShowObserver {
            NotificationCenter.default.removeObserver(token)
            keyboardWillShowObserver = nil
        }
        dummyTextField?.removeFromSuperview()
        dummyTextField = nil
    }

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}

private extension UIResponder {
    private static weak var _currentFirstResponder: UIResponder?

    static func currentFirstResponder() -> UIResponder? {
        _currentFirstResponder = nil
        UIApplication.shared.sendAction(#selector(_trapFirstResponder(_:)), to: nil, from: nil, for: nil)
        return _currentFirstResponder
    }

    @objc private func _trapFirstResponder(_ sender: Any) {
        UIResponder._currentFirstResponder = self
    }
}
