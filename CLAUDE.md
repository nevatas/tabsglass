# Taby — iOS Notes App

## ⚠️ Data Safety — Critical Rule

User data is the most valuable thing in this app. **NEVER** make changes that could corrupt, lose, or break data for users upgrading from a previous version. This includes:

- No destructive SwiftData schema migrations (renaming/removing fields, changing types) without a proper lightweight migration path
- No changes to file storage paths or naming conventions that would orphan existing photos/videos
- No modifications to export/import formats that break backward compatibility
- No changes to App Group shared data that would desync the share extension

When in doubt, always preserve backward compatibility. New fields should have defaults. Old fields should never be removed — only deprecated. Test every change against the assumption that a user has existing data from the previous version.

## Git Policy

**NEVER** commit or push without an explicit user request. Only run `git commit` and `git push` when the user directly asks for it.

## Overview
Messenger-style notes app with tabs. SwiftUI + UIKit hybrid, SwiftData, iOS 26+.

**Bundle ID:** `company.thecool.taby`

## Project Structure

```
tabsglass/
├── tabsglassApp.swift      # App entry, GlassEffectWarmer, KeyboardWarmer
├── ContentView.swift       # Root view (ZStack: main + paywall overlay)
├── Models/
│   ├── Tab.swift           # Tab model (SwiftData)
│   ├── Message.swift       # Message model (SwiftData)
│   └── ExportableModels.swift  # Codable versions for export
├── Views/
│   ├── MainContainerView.swift     # State orchestrator, CRUD, alerts/sheets
│   ├── TabBarView.swift            # Telegram-style tab bar (Liquid Glass, UIKit engine)
│   ├── UnifiedChatView.swift       # UIPageViewController host + tab paging coordinator
│   ├── MessageListViewController.swift  # Per-tab list controller, context menu, search tab
│   ├── ComposerComponents.swift    # Composer state/container + SwiftUI composer views
│   ├── MessageCells.swift          # MessageTableCell, SearchResultCell, EmptyTableCell
│   ├── SearchInputView.swift       # Search text field (UITextField wrapper)
│   ├── SearchTabsView.swift        # Tab filter buttons on Search screen
│   ├── FormattingTextView.swift    # Rich text editing (UITextView)
│   ├── TodoBubbleView.swift        # Checklist rendering in chat
│   ├── MosaicLayout.swift          # Photo grid calculations
│   ├── SettingsView.swift          # Settings screen
│   ├── OnboardingView.swift        # Onboarding flow
│   ├── PaywallView.swift           # Paywall screen (Taby Unlimited)
│   ├── EditMessageSheet.swift      # Edit message
│   ├── ReminderSheet.swift         # Set reminder
│   ├── MoveMessagesSheet.swift     # Move messages between tabs
│   ├── SelectionActionBar.swift    # Bulk selection toolbar (Liquid Glass)
│   ├── ExportProgressView.swift    # Export/import progress indicator
│   ├── ImportPreviewView.swift     # Import preview with mode selection
│   ├── GalleryViewController.swift # Full-screen photo viewer (Liquid Glass controls)
│   └── VideoPlayerViewController.swift  # Video player
├── Services/
│   ├── AppSettings.swift           # ThemeManager, AppTheme enum
│   ├── ImageCache.swift            # NSCache + downsampling
│   ├── DeletedMessageStore.swift   # Shake-to-undo (30 sec)
│   ├── ExportImportService.swift   # Backup/restore (.taby files)
│   ├── NotificationService.swift   # Reminders
│   ├── SharedVideoStorage.swift    # Video file management
│   └── Localization.swift          # L10n helper
├── Shared/                 # Shared with Share Extension
│   ├── SharedConstants.swift
│   ├── SharedPhotoStorage.swift
│   ├── SharedVideoStorage.swift
│   ├── SharedModelContainer.swift
│   ├── TabsSync.swift
│   └── PendingShareItem.swift
└── Resources/
    ├── en.lproj/Localizable.strings
    ├── ru.lproj/Localizable.strings
    ├── de.lproj/Localizable.strings
    ├── es.lproj/Localizable.strings
    └── fr.lproj/Localizable.strings
```

## Data Models

### Tab
```swift
@Model class Tab {
    var id: UUID
    var title: String
    var position: Int
    var serverId: Int?        // Backend sync
    var createdAt: Date
    @Relationship(deleteRule: .cascade) var messages: [Message]
}
```

### Message
```swift
@Model class Message {
    var id: UUID
    var content: String
    var tabId: UUID?              // nil = Inbox
    var position: Int
    var createdAt: Date
    var serverId: Int?            // Backend sync
    var sourceUrl: String?

    // Formatting
    var entities: [TextEntity]?   // bold, italic, links, code, spoiler
    var linkPreview: LinkPreview?

    // Media
    var photoFileNames: [String]
    var photoAspectRatios: [Double]
    var videoFileNames: [String]
    var videoAspectRatios: [Double]
    var videoDurations: [Double]
    var videoThumbnailFileNames: [String]
    var mediaGroupId: String?

    // Tasks
    var todoItems: [TodoItem]?
    var todoTitle: String?
    var isTodoList: Bool { todoItems != nil && !todoItems!.isEmpty }

    // Reminders
    var reminderDate: Date?
    var reminderRepeatInterval: ReminderRepeatInterval?
    var notificationId: String?

    // Computed
    var hasReminder: Bool { ... }
    var hasMedia: Bool { ... }
    var totalMediaCount: Int { ... }
}
```

### Inbox
Virtual tab — messages with `tabId = nil`.

## View Architecture

```
ContentView (ZStack: MainContainerView always mounted, paywall overlay on top)
└── MainContainerView (state, CRUD, alerts/sheets)
    ├── TabBarView (SwiftUI shell)
    │   ├── Header: settings button + title + add button (glass circles)
    │   └── TelegramTabBarV2 → TelegramTabBarEngineView (UIKit UIScrollView)
    │       ├── TabLabelNode (UIHostingController per tab)
    │       ├── TabContextMenuInteractionLayer (long press → context menu)
    │       └── Glass capsule indicator (selection + morphing)
    └── UnifiedChatView (UIViewControllerRepresentable)
        └── UnifiedChatViewController
            ├── UIPageViewController (swipe between tabs)
            │   └── MessageListViewController (one per visible tab)
            │       ├── UITableView (inverted for chat, normal for search)
            │       ├── MessageTableCell / SearchResultCell / EmptyTableCell
            │       ├── TopFadeGradientView (search tab only)
            │       └── SearchTabsView (embedded, search tab only)
            ├── SwiftUIComposerContainer (message input, glass effect)
            ├── SearchInputContainer (search input, glass capsule)
            └── BottomFadeGradientView (fade above composer)
```

**ContentView pattern:** Use ZStack with MainContainerView always in hierarchy. Paywall/onboarding layers on top. This ensures all GeometryReaders measure frames and UIKit components initialize before overlays dismiss. Never use if/else to swap between paywall and main content — causes visual glitches (tab bar indicator jumps from .zero).

## Tab Navigation

**Index mapping:**
- `0` = Search screen
- `1` = Inbox (virtual)
- `2+` = Real tabs

**switchFraction:** `-1.0` to `1.0` during swipe for smooth tab bar animations.

## Key Behaviors

### Inverted UITableView (Chat Tabs)
Chat tabs use `tableView.transform = CGAffineTransform(scaleX: 1, y: -1)` — newest messages at bottom. This means:
- Visual top (header/tab bar) = `contentInset.bottom` in code
- Visual bottom (composer) = `contentInset.top` in code
- `headerHeight = 115` (safe area + header + tab bar)
- Each cell also has inverted transform to display correctly

### Message Insertion Animations (MessageListViewController.swift `reloadMessages()`)
Three paths in `reloadMessages()`:

1. **Subsequent messages** (`sortedMessages` not empty): `insertRows` with scale+fade animation (0.85→1.0, alpha 0→1, 0.25s)
2. **First message** (`sortedMessages` empty): 3-phase — fade out EmptyTableCell (0.15s) → `reloadData()` → scale+fade in message (0.25s)
3. **Search tab**: instant `reloadData()` without animation

**Defensive path** (around lines 334-336): Checks `renderedRows == expectedRows` before incremental updates. When `sortedMessages` is empty and `!isSearchTab`, expected rows = 1 (EmptyTableCell placeholder), not 0.

### Search
- Full-text search across all messages and tabs
- Searches in: content, todo titles, todo items
- `SearchResultCell` wrapped in `UIGlassEffect` glass cards (16pt corner radius)
- No context menu on search results (long press disabled)
- Shows tab name, text (3 lines), media thumbnails
- Task lists shown with round checkboxes (○/●), up to 2 items + "+N more"
- Tap result → navigate to tab + scroll to message
- Edge swipe from left → go to Search
- Keyboard return key: `.done` (always)
- **Debounce:** 150ms on non-empty text; empty text updates immediately (in `UnifiedChatViewController`)

### Tab Creation (MainContainerView.swift)
- Max 24 characters for tab title
- **Emoji auto-space:** If first character is emoji, automatically appends a space
- **Auto-capitalize:** First letter after "emoji + space" is uppercased
- `Character.isEmoji` extension defined at bottom of MainContainerView.swift

### Messages
- Up to 10 photos per message
- Videos with thumbnails
- Telegram-style formatting (bold, italic, underline, strikethrough, links, code, spoiler)
- Link previews
- Task lists with optional title
- Reminders with repeat intervals
- Shake-to-undo deletion (30 sec window)

### Themes (AppTheme)
`system`, `light`, `dark`, `pink`, `beige`, `green`, `blue`

Each theme provides:
- `backgroundColor` / `backgroundColorDark`
- `accentColor` (`Color?` — nil for system/light/dark)
- `composerTintColor` / `composerTintColorDark`
- `placeholderColor`

### Selection Mode
- Long press message to enter
- Bulk move/delete
- `SelectionActionBar` at bottom (Liquid Glass)

### Export/Import
- `.taby` archive (ZIP with JSON + media)
- Modes: Replace all / Merge
- `ExportProgressView` for progress, `ImportPreviewView` for preview

## Tab Bar (TabBarView.swift)

**Two-layer architecture:**
- `TelegramTabBarV2` (SwiftUI) — shell, delegates to UIKit
- `TelegramTabBarEngineView` (UIKit UIScrollView) — actual scrolling, layout, animations

**Key details:**
- Horizontal finger scrolling with momentum (UIScrollView)
- Tab nodes are `UIHostingController` instances (`TabLabelNode`)
- Glass capsule selection indicator with morphing animations
- Context menu via `TabContextMenuInteractionLayer` (UIContextMenuInteraction)
- `menuAnchorYOffset = 4` — controls gap between tab and context menu
- Haptic feedback on tab swipe completion (`UIImpactFeedbackGenerator`, style: `.soft`)

**Header glass buttons:** Do NOT use `Button` + `.buttonStyle(.glass)` — glass chrome extends beyond hit area. Use `onTapGesture` + `.glassEffect(.regular.interactive(), in: .circle)` with `.contentShape(Circle())`.

## Liquid Glass (iOS 26+)

```swift
// Basic usage
.glassEffect(.regular, in: .capsule)

// With tint (control opacity)
.glassEffect(.regular.tint(.white.opacity(0.9)), in: .rect(cornerRadius: 24))

// Interactive (responds to touch)
.glassEffect(.regular.interactive(), in: .capsule)

// Morphing animations - use GlassEffectContainer
GlassEffectContainer {
    content.glassEffectID("id", in: namespace)
}
```

**Note:** `.prominent` does NOT exist — use `.regular.tint()` for less transparency.

**Icon colors:** Use `themeManager.currentTheme.accentColor ?? (colorScheme == .dark ? .white : .black)` — NOT `.accentColor` (which is system blue).

### Scroll Edge Effect (iOS 26)
System automatically applies gradient+blur where scroll content meets glass elements. Controlled per-edge via `UIScrollView`:
```swift
tableView.bottomEdgeEffect.isHidden = true  // Disable for specific edge
tableView.bottomEdgeEffect.style = .soft    // .automatic, .soft, .hard
```
In SwiftUI: `.scrollEdgeEffectStyle(.none, for: .bottom)`

### UIGlassEffect in UIKit
```swift
let effect = UIGlassEffect()
let view = UIVisualEffectView(effect: effect)
view.layer.cornerRadius = 16
view.clipsToBounds = true
// Add subviews to view.contentView (not view directly)
```

## Localization

5 languages: English, Russian, German, Spanish, French

```swift
// Usage
L10n.Search.placeholder  // "Find..."
L10n.Tab.delete          // "Delete"

// In code
NSLocalizedString("search.tasks_more", comment: "")  // "+%d more"
```

## File Storage

- **Photos:** `Documents/MessagePhotos/{uuid}.jpg`
- **Videos:** `Documents/MessageVideos/{uuid}.mov`
- **Thumbnails:** `Documents/MessagePhotos/{uuid}_thumb.jpg`
- **Exports:** `Documents/Exports/taby_backup_{date}.taby`

## Share Extension

Located in `share/` directory:
- `ShareViewController.swift` — Extension entry point
- `ShareExtensionView.swift` — SwiftUI share UI
- `SharedContent.swift` — Shared models/logic
- `PendingShareItem.swift` — Pending items for sync

Shares App Group with main app for SwiftData container, photo/video storage, pending items sync.

## Legacy User Grandfathering

A `firstInstallDate` is stamped in **Keychain** (survives reinstalls) on every app launch via `AppSettings.shared.stampFirstInstallDateIfNeeded()` in `tabsglassApp.init()`. This was added before any paywall exists.

When implementing a paywall:
- Check `AppSettings.shared.firstInstallDate` against the paywall release date
- If `firstInstallDate < paywallReleaseDate` → grant lifetime full access (legacy user)
- The Keychain key is `"firstInstallDate"`, service is `"company.thecool.taby"`
- Helper: `KeychainHelper` in `AppSettings.swift`

## Performance

### Warmup (tabsglassApp.swift)
- `GlassEffectWarmer` — Creates off-screen window, renders glass view to trigger pipeline init, cleans up after 0.5s. Called in app `init`.
- `KeyboardWarmer` — Creates invisible UITextField, focuses it to init keyboard subsystem with 0.25s timeout. Called on MainContainerView `.onAppear` (warms behind paywall).

### ImageCache
- `NSCache` with size limit
- Downsampling for thumbnails
- Async loading with callbacks

### Off-Main-Thread Work
- **Photo/video saving** (`MainContainerView.sendMessage`): JPEG encoding + disk write runs inside `Task {}`, off main thread. UI is cleared before save starts for instant feedback.
- **Export file I/O** (`ExportImportService`): `exportData` converts SwiftData→DTOs and encodes JSON on MainActor, then delegates file write/copy/ZIP to `nonisolated performExport`.
- **Pending share items** (`tabsglassApp`): Batch-inserted with single `context.save()`. Falls back to per-item retry on failure.

### Cached Detectors
- `NSDataDetector` is created once as `private static let` in both `TextEntity` and `LinkPreviewService`. Do NOT create new instances per call — it's expensive.

### Hot Path Rules
- `Message.isEmpty` trusts `photoFileNames`/`videoFileNames` arrays — no `FileManager.fileExists` calls. Photos are always saved to disk before Message creation.
- Avoid `UIScreen.main` (deprecated iOS 26). Use `view.window?.windowScene?.screen` instead.

## Common Patterns

### Theme Change Notification
```swift
NotificationCenter.default.addObserver(
    self, selector: #selector(themeDidChange),
    name: .themeDidChange, object: nil
)
```

### SwiftUI in UIKit
```swift
let hostingController = UIHostingController(rootView: SomeView())
addChild(hostingController)
view.addSubview(hostingController.view)
hostingController.didMove(toParent: self)
```

### Constraint Animation
```swift
UIView.animate(withDuration: 0.25) {
    self.bottomConstraint?.constant = newValue
    self.view.layoutIfNeeded()
}
```
