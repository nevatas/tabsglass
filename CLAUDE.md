# TabsGlass Project Notes

## Project Overview
iOS notes app with messenger-like UI/UX and tabs. SwiftUI + UIKit hybrid, SwiftData, iOS 26+.

## Architecture

### Data Models (`Models/`)
- **Tab** — вкладка с `title`, `position`, cascade delete сообщений
- **Message** — сообщение с полями:
  - `content`, `tabId` (nil = Inbox), `position`
  - `entities: [TextEntity]?` — Telegram-style форматирование
  - `linkPreview: LinkPreview?` — превью ссылок
  - `photoFileNames: [String]`, `photoAspectRatios: [Double]` — фото
  - `todoItems: [TodoItem]?`, `todoTitle: String?` — чеклисты
- **Inbox** — виртуальная вкладка (сообщения с `tabId = nil`)

### View Hierarchy (`Views/`)
```
ContentView
└── MainContainerView (оркестратор состояния)
    ├── TabBarView (Telegram-style навигация, Liquid Glass)
    └── UnifiedChatView (UIViewControllerRepresentable)
        └── UnifiedChatViewController
            ├── UIPageViewController (свайп между вкладками)
            │   └── MessageListViewController (инвертированный UITableView)
            │       └── MessageTableCell
            │           ├── MosaicMediaView (сетка фото)
            │           ├── UITextView (форматированный текст)
            │           └── TodoBubbleView (чекбоксы)
            └── SwiftUIComposerContainer
                └── EmbeddedComposerView (ввод + фото)
```

### Services (`Services/`)
- **ThemeManager** — 8 тем (system, light, dark, pink, beige, green, blue)
- **ImageCache** — NSCache + downsampling, async loading
- **DeletedMessageStore** — shake-to-undo (30 сек)

### Key Files
| File | Purpose |
|------|---------|
| `MainContainerView.swift` | State management, CRUD operations |
| `TabBarView.swift` | Tab navigation with swipe tracking |
| `UnifiedChatViewController.swift` | Page controller + composer |
| `MessageListViewController.swift` | Message list, context menu |
| `MessengerView.swift` | Composer UI, ComposerState |
| `FormattingTextView.swift` | Rich text editing |
| `MosaicLayout.swift` | Photo grid calculations |
| `TodoBubbleView.swift` | Todo list rendering |

### Features
- До 10 фото на сообщение (хранятся в `Documents/MessagePhotos/`)
- Telegram-style форматирование (bold, italic, links, code, spoiler)
- Todo-списки с опциональным заголовком
- Link previews
- Локализация: en, de, es, fr, ru

## Liquid Glass (iOS 26+)

### Basic Usage
```swift
import SwiftUI

// Wrap content in GlassEffectContainer for morphing animations
GlassEffectContainer {
    YourContent()
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
}
```

### Glass Variants
- `.regular` - standard Liquid Glass
- `.clear` - transparent glass
- `.identity` - no effect (passthrough)

### Customization with .tint()
Control opacity/color of the glass:
```swift
.glassEffect(.regular.tint(.white.opacity(0.9)), in: .rect(cornerRadius: 24))  // less transparent, white
.glassEffect(.regular.tint(.white.opacity(0.5)), in: .rect(cornerRadius: 24))  // more transparent
.glassEffect(.regular.tint(.blue.opacity(0.3)), in: .rect(cornerRadius: 24))   // blue tinted
```

### Interactivity
Make glass respond to touch/pointer:
```swift
.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
.glassEffect(.regular.tint(.orange).interactive(), in: .rect(cornerRadius: 24))
```

### Shapes
```swift
.glassEffect(.regular, in: .rect(cornerRadius: 24))  // rounded rectangle
.glassEffect(.regular, in: .capsule)                  // capsule (default)
.glassEffect(.regular, in: .circle)                   // circle
```

### Animation with glassEffectID
```swift
@Namespace var namespace

view1.glassEffectID("myEffect", in: namespace)
view2.glassEffectID("myEffect", in: namespace)  // will morph between them
```

### Important Notes
- Always use `GlassEffectContainer` as parent for morphing animations
- `.prominent` does NOT exist - use `.regular.tint()` for less transparency
- For thick/ultraThick presets, consider UniversalGlass library (backports to iOS 18+)
