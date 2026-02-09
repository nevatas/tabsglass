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
    @State private var ctaVisible = false
    @State private var selectedPlan = 0 // 0 = yearly, 1 = monthly

    private let backgroundColor = Color.black

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack(alignment: .trailing) {
                    Text("Taby Unlimited")
                        .font(.system(.largeTitle, design: .rounded))
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)

                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.2))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .opacity(titleVisible ? 1 : 0)
                .offset(y: titleVisible ? 0 : 20)

                Text("Make Your Own Space")
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(.gray)
                    .padding(.top, 6)
                    .padding(.bottom, 28)
                    .opacity(titleVisible ? 1 : 0)
                    .offset(y: titleVisible ? 0 : 20)

                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        AnimatedCardTimeline { elapsed in
                            TabsFeatureCard(elapsed: elapsed)
                        }
                        .opacity(cardsVisible[0] ? 1 : 0)
                        .offset(y: cardsVisible[0] ? 0 : 30)

                        AnimatedCardTimeline { elapsed in
                            TasksFeatureCard(elapsed: elapsed)
                        }
                        .opacity(cardsVisible[1] ? 1 : 0)
                        .offset(y: cardsVisible[1] ? 0 : 30)
                    }

                    HStack(spacing: 12) {
                        RemindersFeatureCard()
                            .opacity(cardsVisible[2] ? 1 : 0)
                            .offset(y: cardsVisible[2] ? 0 : 30)

                        AnimatedCardTimeline { elapsed in
                            ThemesFeatureCard(elapsed: elapsed)
                        }
                        .opacity(cardsVisible[3] ? 1 : 0)
                        .offset(y: cardsVisible[3] ? 0 : 30)
                    }
                }
                .padding(.horizontal, 16)

                Spacer()

                // CTA
                VStack(spacing: 12) {
                    // Plan picker
                    PlanPicker(selectedPlan: $selectedPlan)

                    Button {
                        // TODO: Start purchase
                    } label: {
                        VStack(spacing: 2) {
                            Text("Try 7 Days Free")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                            Text(selectedPlan == 0 ? "then $29.99/year" : "then $9.99/month")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .opacity(0.7)
                                .contentTransition(.numericText())
                                .animation(.easeInOut(duration: 0.3), value: selectedPlan)
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.white)
                        .clipShape(Capsule())
                        .contentTransition(.numericText())
                    }

                    HStack(spacing: 0) {
                        Button {
                            // TODO: Restore purchases
                        } label: {
                            Text("Restore")
                        }

                        Text("  ·  ")

                        Button {
                            // TODO: Open terms
                        } label: {
                            Text("Terms")
                        }

                        Text("  ·  ")

                        Button {
                            // TODO: Open privacy
                        } label: {
                            Text("Privacy")
                        }
                    }
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.3))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .opacity(ctaVisible ? 1 : 0)
                .offset(y: ctaVisible ? 0 : 20)
            }
            .opacity(contentReady ? 1 : 0.001)

        }
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea(.keyboard)
        .onAppear {
            // Let TimelineView render a few frames off-screen first
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                contentReady = true
                animateAppearance()
            }
        }
    }

    private func animateAppearance() {
        withAnimation(.easeOut(duration: 0.4)) {
            titleVisible = true
        }

        for index in 0..<4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 + Double(index) * 0.1) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    cardsVisible[index] = true
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            withAnimation(.easeOut(duration: 0.4)) {
                ctaVisible = true
            }
        }
    }
}

// MARK: - Plan Picker

private struct PlanPicker: View {
    @Binding var selectedPlan: Int

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 5
            let segmentWidth = (geo.size.width - inset * 2) / 2

            ZStack(alignment: .topLeading) {
                // Animated indicator
                Capsule()
                    .fill(.white.opacity(0.15))
                    .frame(width: segmentWidth, height: geo.size.height - inset * 2)
                    .offset(x: inset + CGFloat(selectedPlan) * segmentWidth, y: inset)
                    .animation(.easeInOut(duration: 0.25), value: selectedPlan)

                // Labels
                HStack(spacing: 0) {
                    PlanSegment(title: "Yearly", price: "$29.99", isSelected: selectedPlan == 0) {
                        selectedPlan = 0
                    }
                    PlanSegment(title: "Monthly", price: "$9.99", isSelected: selectedPlan == 1) {
                        selectedPlan = 1
                    }
                }
            }
        }
        .frame(height: 56)
        .glassEffect(.regular, in: .capsule)
        .overlay(alignment: .topLeading) {
            Text("-75%")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(selectedPlan == 0 ? Color.green : Color(white: 0.3))
                .clipShape(Capsule())
                .offset(x: 24, y: -10)
                .animation(.easeInOut(duration: 0.3), value: selectedPlan)
        }
    }
}

private struct PlanSegment: View {
    let title: String
    let price: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(isSelected ? 0.6 : 0.3))
                Text(price)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(isSelected ? 1 : 0.4))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tabs Card

struct TabsFeatureCard: View {
    let elapsed: TimeInterval

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

    @State private var tabs1: [String] = Array(allTabs.shuffled().prefix(10))
    @State private var tabs2: [String] = Array(allTabs.shuffled().prefix(10))
    @State private var tabs3: [String] = Array(allTabs.shuffled().prefix(10))

    private let row1Speed: CGFloat = 42
    private let row2Speed: CGFloat = 54
    private let row3Speed: CGFloat = 34

    var body: some View {
        VStack(spacing: 0) {
            Text("∞ Tabs")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            VStack(spacing: 8) {
                InfiniteTabsScroller(tabs: tabs1, reverse: false, scrollSpeed: row1Speed, elapsed: elapsed)
                InfiniteTabsScroller(tabs: tabs2, reverse: true, scrollSpeed: row2Speed, elapsed: elapsed)
                InfiniteTabsScroller(tabs: tabs3, reverse: false, scrollSpeed: row3Speed, elapsed: elapsed)
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

// MARK: - Tasks Card

struct TasksFeatureCard: View {
    let elapsed: TimeInterval

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
            Text("∞ Tasks")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            InfiniteTasksScroller(tasks: tasks, elapsed: elapsed)
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

// MARK: - Themes Card

struct ThemesFeatureCard: View {
    let elapsed: TimeInterval

    private let themeImages = ["paywall_theme_1", "paywall_theme_2", "paywall_theme_3", "paywall_theme_4"]
    private let scrollSpeed: CGFloat = 58
    private let spacing: CGFloat = 20

    @State private var imageWidth: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Text("Themes")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            GeometryReader { geo in
                let phoneHeight = geo.size.height * 1.2
                let cardWidth = geo.size.width
                let itemStride = imageWidth + spacing
                let loopWidth = itemStride * CGFloat(themeImages.count)

                let totalOffset = CGFloat(elapsed) * scrollSpeed
                let currentOffset = loopWidth > 0
                    ? totalOffset.truncatingRemainder(dividingBy: loopWidth)
                    : 0

                ZStack(alignment: .topLeading) {
                    let buffer = itemStride
                    ForEach(0..<(themeImages.count * 2), id: \.self) { i in
                        let imgIndex = i % themeImages.count
                        let x = CGFloat(i) * itemStride - currentOffset

                        if x > -buffer && x < cardWidth + buffer {
                            Image(themeImages[imgIndex])
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: phoneHeight)
                                .fixedSize(horizontal: true, vertical: false)
                                .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
                                .offset(x: x, y: 18)
                                .background(
                                    imageWidth == 0 ? GeometryReader { imgGeo in
                                        Color.clear.onAppear {
                                            imageWidth = imgGeo.size.width
                                        }
                                    } : nil
                                )
                        }
                    }
                }
                .frame(width: cardWidth, height: geo.size.height, alignment: .topLeading)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.5),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}

// MARK: - Reminders Card

struct RemindersFeatureCard: View {

    private enum PostKind {
        case image(String)
        case text
        case tasks
    }

    private let posts: [PostKind] = [
        .image("paywall_image_1"),
        .text,
        .image("paywall_image_2"),
        .tasks
    ]

    @State private var currentIndex = 0
    @State private var postOffset: CGSize = CGSize(width: 0, height: 300)
    @State private var showBadge = false
    @State private var isActive = false

    var body: some View {
        VStack(spacing: 0) {
            Text("Reminders")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            GeometryReader { geo in
                Color.clear
                    .overlay(alignment: .topTrailing) {
                        ZStack(alignment: .topTrailing) {
                            postView(for: posts[currentIndex])

                            if showBadge {
                                ZStack {
                                    Circle()
                                        .fill(Color(red: 1, green: 0.18, blue: 0.18))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "bell.fill")
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white)
                                }
                                .opacity(1)
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
                        guard !isActive else { return }
                        isActive = true
                        startCycle(areaHeight: geo.size.height)
                    }
                    .onDisappear {
                        isActive = false
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    @ViewBuilder
    private func postView(for post: PostKind) -> some View {
        switch post {
        case .image(let name):
            Image(name)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 340, height: 340)
                .clipShape(RoundedRectangle(cornerRadius: 18))

        case .text:
            VStack(alignment: .leading, spacing: 6) {
                Text("Don't forget to call grandma, she makes the best cookies and you promised last Sunday that you'd come over for tea and bring that photo album she's been asking about since forever 🍪")
                    .font(.system(size: 16, design: .rounded))
                    .foregroundStyle(.white)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 280, alignment: .leading)
            .background(Color.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 18))

        case .tasks:
            VStack(alignment: .leading, spacing: 0) {
                ReminderTaskRow(title: "Sleep in, no alarms", done: true)
                Divider().overlay(Color.white.opacity(0.1))
                ReminderTaskRow(title: "Finish that book", done: false)
                Divider().overlay(Color.white.opacity(0.1))
                ReminderTaskRow(title: "Cook something fancy", done: false)
                Divider().overlay(Color.white.opacity(0.1))
                ReminderTaskRow(title: "Movie night + snacks", done: true)
                Divider().overlay(Color.white.opacity(0.1))
                ReminderTaskRow(title: "Walk without phone", done: false)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(width: 280, alignment: .leading)
            .background(Color.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    private func startCycle(areaHeight: CGFloat) {
        guard isActive else { return }

        withAnimation(.easeOut(duration: 0.3)) {
            postOffset = .zero
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            guard isActive else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                showBadge = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard isActive else { return }
            withAnimation(.easeIn(duration: 0.3)) {
                postOffset = CGSize(width: -300, height: 0)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) {
            guard isActive else { return }
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                showBadge = false
                currentIndex = (currentIndex + 1) % posts.count
                postOffset = CGSize(width: 0, height: areaHeight)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                startCycle(areaHeight: areaHeight)
            }
        }
    }
}

// MARK: - Shared Components

private struct ReminderTaskRow: View {
    let title: String
    let done: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, design: .rounded))
                .foregroundStyle(done ? .green : .white.opacity(0.4))
            Text(title)
                .font(.system(size: 16, design: .rounded))
                .foregroundStyle(done ? .white.opacity(0.5) : .white.opacity(0.8))
                .strikethrough(done, color: .white.opacity(0.3))
                .lineLimit(1)
        }
        .padding(.vertical, 11)
    }
}

private struct AnimatedCardTimeline<Content: View>: View {
    let content: (TimeInterval) -> Content

    init(@ViewBuilder content: @escaping (TimeInterval) -> Content) {
        self.content = content
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            content(timeline.date.timeIntervalSinceReferenceDate)
        }
    }
}

struct InfiniteTasksScroller: View {
    let tasks: [String]
    let elapsed: TimeInterval

    private let scrollSpeed: CGFloat = 40

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
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
    let title: String
    var isCompleted: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20, design: .rounded))
                .foregroundStyle(isCompleted ? .green : .white.opacity(0.5))

            Text(title)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct InfiniteTabsScroller: View {
    let tabs: [String]
    var reverse: Bool = false
    var scrollSpeed: CGFloat = 60
    let elapsed: TimeInterval

    @State private var contentWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let offset = CGFloat(elapsed) * scrollSpeed
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
                        contentWidth = (contentGeometry.size.width + 8) / 2
                    }
                }
            )
            .offset(x: reverse ? currentOffset - loopWidth : -currentOffset)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
            .clipped()
        }
    }
}

struct TabPill: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 17, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.7))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.06))
            .clipShape(Capsule())
    }
}

#Preview {
    PaywallView(isPresented: .constant(true))
}
