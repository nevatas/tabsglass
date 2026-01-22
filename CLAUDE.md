# TabsGlass Project Notes

## Project Overview
iOS notes app with messenger-like UI/UX and tabs. SwiftUI + SwiftData, iOS 26+.

## Architecture
- `Tab` -> `Message` (SwiftData models, cascade delete)
- MainContainerView -> TabBarView -> TabPagerView -> ChatView -> MessageBubbleView
- ComposerView - floating input bar with Liquid Glass effect

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
