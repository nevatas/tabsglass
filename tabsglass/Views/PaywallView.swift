//
//  PaywallView.swift
//  tabsglass
//
//  Paywall screen for Taby Unlimited
//

import SwiftUI

struct PaywallView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isPresented: Bool

    private var themeManager: ThemeManager { ThemeManager.shared }

    private var backgroundColor: Color {
        let theme = themeManager.currentTheme
        if theme == .system {
            return colorScheme == .dark
                ? theme.backgroundColorDark
                : theme.backgroundColor
        } else {
            return colorScheme == .dark ? theme.backgroundColorDark : theme.backgroundColor
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Text("Taby Unlimited")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top, 60)

                // 2x2 grid of feature cards
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    TabsFeatureCard()
                    TasksFeatureCard()
                    FeatureCard(title: "Reminders")
                    FeatureCard(title: "Themes")
                }
                .padding(.horizontal, 16)

                Spacer()
            }

            // Close button
            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .glassEffect(.regular, in: .circle)
            }
            .padding(.top, 16)
            .padding(.trailing, 16)
        }
        .preferredColorScheme(themeManager.currentTheme.colorSchemeOverride)
        .ignoresSafeArea(.keyboard)
    }
}

struct FeatureCard: View {
    let title: String

    var body: some View {
        VStack(spacing: 0) {
            // Title area
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .default))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            // Content area
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 190)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}

struct TabsFeatureCard: View {
    private static let allTabs = [
        "📝 Journal", "🧘 Mindfulness", "🛌 Sleep Tracker", "🏋️ Fitness", "💊 Health",
        "🍽️ Recipes", "🎯 Goals", "💰 Finance", "🛒 Shopping", "🎁 Gifts",
        "🚀 Startup", "📌 To-Do", "📆 Meetings", "🎙️ Voice Notes", "🗂️ Documents",
        "🧠 Brainstorm", "📋 Research", "⌨️ Code Snippets", "💡 UX/UI", "📊 Stats",
        "🎸 Music", "📚 Books", "🎬 Movies & Series", "🎮 Games", "📷 Photography",
        "🎨 Art", "✍️ Writing", "📜 Quotes", "🃏 Fun Ideas", "🎤 Podcast Notes",
        "✈️ Travel", "🏕️ Camping", "🗺️ Bucket List", "🚘 Roadtrip", "🏨 Hotels & Airbnb",
        "🍣 Foodie", "🎭 Events", "🏝️ Beach Life", "🌌 Stargazing", "⛷️ Winter Sports",
        "🏠 Home Projects", "📦 House Move", "🌿 Garden & Plants", "🍷 Wine Notes", "🐶 Pets",
        "🛠️ DIY & Fixes", "💅 Nail Works", "🪴 Minimalism", "🕵️ Secrets", "☕ Coffee Journal"
    ]

    @State private var tabs1: [String] = allTabs.shuffled()
    @State private var tabs2: [String] = allTabs.shuffled()
    @State private var tabs3: [String] = allTabs.shuffled()

    var body: some View {
        VStack(spacing: 0) {
            // Title area
            Text("∞ Tabs")
                .font(.system(size: 17, weight: .bold, design: .default))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            // Content area - scrolling tabs
            VStack(spacing: 8) {
                InfiniteTabsScroller(tabs: tabs1, reverse: false)
                InfiniteTabsScroller(tabs: tabs2, reverse: true)
                InfiniteTabsScroller(tabs: tabs3, reverse: false)
            }
            .padding(.top, 8)
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black.opacity(0.2), location: 0.2),
                            .init(color: .black.opacity(0.5), location: 0.5),
                            .init(color: .black.opacity(0.8), location: 0.75),
                            .init(color: .black, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 60)

                    Rectangle().fill(.black)
                }
            )
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}

struct TasksFeatureCard: View {
    private static let allTasks = [
        "Drink a glass of water",
        "Reply to that one message you keep postponing",
        "Take a 10-minute walk outside",
        "Clean up your workspace",
        "Write down one good idea",
        "Stretch for 5 minutes",
        "Go to bed 30 minutes earlier"
    ]

    @State private var tasks: [String] = allTasks.shuffled()

    var body: some View {
        VStack(spacing: 0) {
            // Title area
            Text("∞ Tasks")
                .font(.system(size: 17, weight: .bold, design: .default))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            // Content area - scrolling tasks
            InfiniteTasksScroller(tasks: tasks)
                .frame(height: 110)
                .padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}

struct InfiniteTasksScroller: View {
    let tasks: [String]

    private let scrollSpeed: CGFloat = 40

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation) { timeline in
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                let offset = CGFloat(elapsed) * scrollSpeed
                let loopHeight = contentHeight > 0 ? contentHeight : CGFloat(tasks.count) * 50
                let currentOffset = offset.truncatingRemainder(dividingBy: loopHeight)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<tasks.count, id: \.self) { index in
                        TaskItem(title: tasks[index], isCompleted: index % 3 == 0)
                    }
                    ForEach(0..<tasks.count, id: \.self) { index in
                        TaskItem(title: tasks[index], isCompleted: index % 3 == 0)
                    }
                }
                .background(
                    GeometryReader { contentGeometry in
                        Color.clear.onAppear {
                            contentHeight = (contentGeometry.size.height + 8) / 2
                        }
                    }
                )
                .offset(y: -currentOffset)
                .padding(.leading, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.08),
                        .init(color: .black, location: 0.92),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}

struct TaskItem: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    var isCompleted: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            // Checkbox
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundColor(isCompleted ? .green : (colorScheme == .dark ? .white.opacity(0.5) : .black.opacity(0.5)))

            // Task text
            Text(title)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct InfiniteTabsScroller: View {
    let tabs: [String]
    var reverse: Bool = false

    private let scrollSpeed: CGFloat = 60

    @State private var contentWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation) { timeline in
                let elapsed = timeline.date.timeIntervalSinceReferenceDate
                let offset = CGFloat(elapsed) * scrollSpeed
                // Use contentWidth if measured, otherwise estimate
                let loopWidth = contentWidth > 0 ? contentWidth : CGFloat(tabs.count) * 150
                let currentOffset = offset.truncatingRemainder(dividingBy: loopWidth)

                HStack(spacing: 8) {
                    ForEach(0..<tabs.count, id: \.self) { index in
                        TabPill(title: tabs[index])
                    }
                    ForEach(0..<tabs.count, id: \.self) { index in
                        TabPill(title: tabs[index])
                    }
                }
                .background(
                    GeometryReader { contentGeometry in
                        Color.clear.onAppear {
                            // Measure actual width of one set of tabs (half the content)
                            contentWidth = (contentGeometry.size.width + 8) / 2
                        }
                    }
                )
                .offset(x: reverse ? currentOffset - loopWidth : -currentOffset)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
            .clipped()
        }
    }
}

struct TabPill: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 17, weight: .medium))
            .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.7))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.06))
            .clipShape(Capsule())
    }
}

#Preview {
    PaywallView(isPresented: .constant(true))
}
