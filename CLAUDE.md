# Taby — iOS Notes App

## Overview
Messenger-style notes app with tabs. SwiftUI + UIKit hybrid, SwiftData, iOS 26+.

**Bundle ID:** `company.thecool.taby`

## Project Structure

```
tabsglass/
├── tabsglassApp.swift      # App entry, warmup (glass)
├── ContentView.swift       # Root view (ZStack: main + paywall overlay)
├── Views/PaywallView.swift # Paywall screen (Taby Unlimited)
├── Models/
│   ├── Tab.swift           # Tab model (SwiftData)
│   ├── Message.swift       # Message model (SwiftData)
│   └── ExportableModels.swift  # Codable versions for export
├── Views/
│   ├── MainContainerView.swift     # State orchestrator, CRUD
│   ├── TabBarView.swift            # Telegram-style tab bar (Liquid Glass)
│   ├── UnifiedChatView.swift       # UIPageViewController + composer
│   ├── MessengerView.swift         # Message cells, composer UI
│   ├── SearchInputView.swift       # Search field
│   ├── SearchTabsView.swift        # Tab buttons on Search screen
│   ├── FormattingTextView.swift    # Rich text editing (UITextView)
│   ├── TodoBubbleView.swift        # Checklist rendering
│   ├── MosaicLayout.swift          # Photo grid calculations
│   ├── SettingsView.swift          # Settings screen
│   ├── TaskListSheet.swift         # Create/edit task list
│   ├── EditMessageSheet.swift      # Edit message
│   ├── ReminderSheet.swift         # Set reminder
│   ├── MoveMessagesSheet.swift     # Move messages between tabs
│   ├── SelectionActionBar.swift    # Bulk selection toolbar
│   ├── GalleryViewController.swift # Full-screen photo viewer
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

    // Tasks
    var todoItems: [TodoItem]?
    var todoTitle: String?
    var isTodoList: Bool { todoItems != nil && !todoItems!.isEmpty }

    // Reminders
    var reminderDate: Date?
    var reminderRepeatInterval: ReminderRepeatInterval?
    var notificationId: String?
}
```

### Inbox
Virtual tab — messages with `tabId = nil`.

## View Architecture

```
ContentView (ZStack: MainContainerView always mounted, paywall/onboarding overlay on top)
└── MainContainerView (state, CRUD)
    ├── TabBarView (Liquid Glass tabs)
    │   ├── Header buttons (onTapGesture + .glassEffect, NOT Button+.buttonStyle(.glass))
    │   └── TelegramTabBar (horizontal scroll, selection indicator)
    └── UnifiedChatView (UIViewControllerRepresentable)
        └── UnifiedChatViewController
            ├── UIPageViewController (swipe between tabs)
            │   └── MessageListViewController
            │       ├── UITableView (inverted for chat, normal for search)
            │       ├── MessageTableCell / SearchResultCell
            │       └── SearchTabsView (embedded, for search tab only)
            ├── SwiftUIComposerContainer (message input)
            └── SearchInputContainer (search input)
```

**ContentView pattern:** Use ZStack with MainContainerView always in hierarchy. Paywall/onboarding layers on top. This ensures all GeometryReaders measure frames and UIKit components initialize before overlays dismiss. Never use if/else to swap between paywall and main content — causes visual glitches (tab bar indicator jumps from .zero).

## Tab Navigation

**Index mapping:**
- `0` = Search screen
- `1` = Inbox (virtual)
- `2+` = Real tabs

**switchFraction:** `-1.0` to `1.0` during swipe for smooth animations.

## Key Features

### Search
- Full-text search across all messages and tabs
- Searches in: content, todo titles, todo items
- Custom `SearchResultCell` with minimal design
- Shows tab name, text (3 lines), media thumbnails
- Task lists shown with round checkboxes (○/●)
- Tap result → navigate to tab + scroll to message
- Edge swipe from left → go to Search

### Messages
- Up to 10 photos per message (`Documents/MessagePhotos/`)
- Videos with thumbnails
- Telegram-style formatting (bold, italic, underline, strikethrough, links, code, spoiler)
- Link previews
- Task lists with optional title
- Reminders with repeat intervals

### Themes (AppTheme)
`system`, `light`, `dark`, `pink`, `beige`, `green`, `blue`

Each theme provides:
- `backgroundColor` / `backgroundColorDark`
- `accentColor`
- `composerTintColor` / `composerTintColorDark`
- `placeholderColor`

### Selection Mode
- Long press to enter
- Bulk move/delete
- `SelectionActionBar` at bottom

### Export/Import
- `.taby` archive (ZIP with JSON + media)
- Modes: Replace all / Merge

## UIKit Components

### MessageListViewController
- Inverted `UITableView` for chat (bottom-to-top)
- Normal layout for search results (top-to-bottom)
- Context menu with preview
- Swipe actions

### FormattingTextView
- `UITextView` subclass
- Entity-based formatting
- Placeholder support
- Theme-aware link colors

### UnifiedChatViewController
- `UIPageViewController` for tab swiping
- Manages composer and search input visibility
- Edge swipe gesture to Search
- Keyboard handling with constraints
- **Important:** `updatePageSelection(animated: true)` disables `isUserInteractionEnabled` during programmatic transitions to prevent user from interrupting the animation and causing tab bar / content desync

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

**Circular glass buttons:** Do NOT use `Button` + `.buttonStyle(.glass)` — the glass chrome extends beyond the button's hit area, making edges untappable. Instead use `onTapGesture` + `.glassEffect(.regular.interactive(), in: .circle)` with `.contentShape(Circle())` for full tap coverage.

**Icon colors:** Use `themeManager.currentTheme.accentColor ?? (colorScheme == .dark ? .white : .black)` — NOT `.accentColor` (which is system blue). The `accentColor` property is `Color?` (nil for system/light/dark themes).

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

Located in `share/` directory. Shares App Group with main app for:
- SwiftData container
- Photo/video storage
- Pending items sync

## Performance

### Warmup
- `KeyboardWarmer` — pre-initializes keyboard (called in ContentView on MainContainerView.onAppear, warms up behind paywall)
- `GlassEffectWarmer` — pre-renders glass effects (called in tabsglassApp.swift init)

### ImageCache
- `NSCache` with size limit
- Downsampling for thumbnails
- Async loading with callbacks

## Common Patterns

### Theme Change Notification
```swift
NotificationCenter.default.addObserver(
    self,
    selector: #selector(themeDidChange),
    name: .themeDidChange,
    object: nil
)
```

### Constraint Animation
```swift
UIView.animate(withDuration: 0.25) {
    self.bottomConstraint?.constant = newValue
    self.view.layoutIfNeeded()
}
```

### SwiftUI in UIKit
```swift
let hostingController = UIHostingController(rootView: SomeView())
addChild(hostingController)
view.addSubview(hostingController.view)
hostingController.didMove(toParent: self)
```
