//
//  PaywallView.swift
//  tabsglass
//
//  Paywall screen for Taby Unlimited
//

import SwiftUI

struct PaywallView: View {
    @Binding var isPresented: Bool

    @State private var contentReady = false
    @State private var titleVisible = false
    @State private var cardsVisible = [false, false, false, false]

    private let backgroundColor = Color.black

    var body: some View {
        ZStack(alignment: .topTrailing) {
            backgroundColor
                .ignoresSafeArea()

            // Content renders immediately but invisible until ready
            VStack(spacing: 32) {
                Text("Taby Unlimited")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top, 60)
                    .opacity(titleVisible ? 1 : 0)
                    .offset(y: titleVisible ? 0 : 20)

                // 2x2 grid of feature cards
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    TabsFeatureCard()
                        .opacity(cardsVisible[0] ? 1 : 0)
                        .offset(y: cardsVisible[0] ? 0 : 30)

                    TasksFeatureCard()
                        .opacity(cardsVisible[1] ? 1 : 0)
                        .offset(y: cardsVisible[1] ? 0 : 30)

                    RemindersFeatureCard()
                        .opacity(cardsVisible[2] ? 1 : 0)
                        .offset(y: cardsVisible[2] ? 0 : 30)

                    FeatureCard(title: "Themes")
                        .opacity(cardsVisible[3] ? 1 : 0)
                        .offset(y: cardsVisible[3] ? 0 : 30)
                }
                .padding(.horizontal, 16)

                Spacer()
            }
            .opacity(contentReady ? 1 : 0.001)

            // Close button
            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .glassEffect(.regular, in: .circle)
            }
            .padding(.top, 16)
            .padding(.trailing, 16)
            .opacity(titleVisible ? 1 : 0)
        }
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea(.keyboard)
        .onAppear {
            // Let TimelineView scrollers render a few frames off-screen first
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                contentReady = true
                animateAppearance()
            }
        }
    }

    private func animateAppearance() {
        // Title appears first
        withAnimation(.easeOut(duration: 0.4)) {
            titleVisible = true
        }

        // Cards appear one by one with delay
        for index in 0..<4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 + Double(index) * 0.1) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    cardsVisible[index] = true
                }
            }
        }
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
    // Full list for variety, but we only use a subset for performance
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

    // Only use 10 tabs per row for better performance (visible area + buffer)
    @State private var tabs1: [String] = Array(allTabs.shuffled().prefix(10))
    @State private var tabs2: [String] = Array(allTabs.shuffled().prefix(10))
    @State private var tabs3: [String] = Array(allTabs.shuffled().prefix(10))

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

struct RemindersFeatureCard: View {
    private let postImages = ["paywall_image_1", "paywall_image_2"]

    @State private var currentIndex = 0
    @State private var postOffset: CGSize = CGSize(width: 0, height: 300)
    @State private var showBadge = false

    var body: some View {
        VStack(spacing: 0) {
            Text("Reminders")
                .font(.system(size: 17, weight: .bold, design: .default))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            GeometryReader { geo in
                Color.clear
                    .overlay(alignment: .topTrailing) {
                        ZStack(alignment: .topTrailing) {
                            // Post bubble with image
                            Image(postImages[currentIndex])
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 340, height: 340)
                                .clipShape(RoundedRectangle(cornerRadius: 18))

                            // Reminder badge — drawingGroup rasterizes before glass
                            if showBadge {
                                ZStack {
                                    Circle()
                                        .fill(.red)
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "bell.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white)
                                }
                                .drawingGroup()
                                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                                .offset(x: 10, y: -10)
                                .transition(.scale)
                            }
                        }
                        .offset(postOffset)
                        .padding(.trailing, 28)
                        .padding(.top, 24)
                    }
                    .onAppear {
                        startCycle(areaHeight: geo.size.height)
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func startCycle(areaHeight: CGFloat) {
        // Phase 1: Slide up from bottom
        withAnimation(.easeOut(duration: 0.3)) {
            postOffset = .zero
        }

        // Phase 2: Show badge
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                showBadge = true
            }
        }

        // Phase 3: Slide out left
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeIn(duration: 0.3)) {
                postOffset = CGSize(width: -300, height: 0)
            }
        }

        // Phase 4: Reset and next
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) {
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                showBadge = false
                currentIndex = (currentIndex + 1) % postImages.count
                postOffset = CGSize(width: 0, height: areaHeight)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                startCycle(areaHeight: areaHeight)
            }
        }
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
