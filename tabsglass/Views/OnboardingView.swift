//
//  OnboardingView.swift
//  tabsglass
//
//  Onboarding flow shown on first launch
//

import SwiftUI
import AVKit
import ConfettiSwiftUI

// MARK: - Looping Video Player

private struct LoopingVideoPlayer: UIViewRepresentable {
    let assetName: String
    var isPlaying: Bool

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        container.clipsToBounds = true

        guard let dataAsset = NSDataAsset(name: assetName) else { return container }

        // Write to temp file for AVPlayer
        let safeName = assetName.replacingOccurrences(of: "/", with: "-")
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName).mp4")
        try? dataAsset.data.write(to: tempURL)

        let player = AVPlayer(url: tempURL)
        player.isMuted = true

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill
        container.layer.addSublayer(playerLayer)

        // Loop
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }

        context.coordinator.player = player
        context.coordinator.playerLayer = playerLayer

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.playerLayer?.frame = uiView.bounds
        }
        if isPlaying {
            context.coordinator.player?.play()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var player: AVPlayer?
        var playerLayer: AVPlayerLayer?
    }
}

// MARK: - Variable Blur Bridge

private struct ChatTopFadeGradientBridge: UIViewRepresentable {
    private static let beigeLight = UIColor(red: 0xF0/255, green: 0xDC/255, blue: 0xC0/255, alpha: 1)
    private static let beigeDark = UIColor(red: 0x38/255, green: 0x2C/255, blue: 0x1C/255, alpha: 1)

    private static var beigeColor: UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? beigeDark : beigeLight
        }
    }

    func makeUIView(context: Context) -> UIView {
        let view = ChatTopFadeGradientView()
        for subview in view.subviews {
            subview.backgroundColor = Self.beigeColor
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        for subview in uiView.subviews {
            if !(subview is UIVisualEffectView) {
                subview.backgroundColor = Self.beigeColor
            }
        }
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @Environment(\.colorScheme) private var colorScheme
    let onComplete: () -> Void

    // Step: 0 = welcome, 1 = phone demo, 2 = tabs, 3 = reminders, 4 = name space, 5 = tab picker
    @State private var step = 0

    // Welcome step animations (sequential: title → icon → subtitle → button)
    @State private var welcomeTitleVisible = false
    @State private var welcomeIconVisible = false
    @State private var welcomeIconShadow = false
    @State private var iconPressed = false
    @State private var iconTapCount = 0
    @State private var confettiTrigger = 0
    @State private var welcomeSubtitleVisible = false
    @State private var revealedCount = 0
    @State private var typewriterTimer: Timer?
    @State private var welcomeButtonVisible = false

    // Phone step animations
    @State private var phoneVisible = false
    @State private var phoneTitleVisible = false
    @State private var phoneButtonVisible = false
    @State private var videoPlaying = false
    @State private var phoneShadow = false
    @State private var fadeToBlack = false

    // Tabs step animations
    @State private var phoneDropped = false
    @State private var tabsTitleVisible = false
    @State private var tabsButtonVisible = false

    // Reminders step animations
    @State private var phoneRaised = false
    @State private var remindersTitleVisible = false
    @State private var remindersButtonVisible = false

    // Name space step animations
    @State private var spaceTitleVisible = false
    @State private var spaceContentVisible = false
    @State private var spaceButtonVisible = false
    @State private var spaceNameInput = ""
    @State private var keyboardHeight: CGFloat = 0
    @FocusState private var spaceFieldFocused: Bool

    // Tab picker step animations
    @State private var phoneHidden = false
    @State private var pickerTitleVisible = false
    @State private var pickerContentVisible = false
    @State private var pickerButtonVisible = false
    @State private var selectedStarterTabs: Set<String> = []

    private static let starterTabKeys = [
        "onboarding.tab.ideas", "onboarding.tab.todo", "onboarding.tab.work", "onboarding.tab.study",
        "onboarding.tab.shopping", "onboarding.tab.gym", "onboarding.tab.reading", "onboarding.tab.recipes",
        "onboarding.tab.finance", "onboarding.tab.travel", "onboarding.tab.links", "onboarding.tab.watchlist",
        "onboarding.tab.journal", "onboarding.tab.home", "onboarding.tab.wishlist", "onboarding.tab.pets",
    ]

    private var starterTabs: [String] {
        Self.starterTabKeys.map { NSLocalizedString($0, comment: "") }
    }

    private let warmDark = Color(red: 0x33/255, green: 0x2F/255, blue: 0x24/255)

    private var buttonBackground: Color {
        colorScheme == .dark ? .white : warmDark
    }

    private var buttonForeground: Color {
        colorScheme == .dark ? warmDark : .white
    }

    var body: some View {
        ZStack {
            (colorScheme == .dark
                ? Color(red: 0x38/255, green: 0x2C/255, blue: 0x1C/255)
                : Color(red: 0xF0/255, green: 0xDC/255, blue: 0xC0/255)
            ).ignoresSafeArea()

            // Video player — always mounted for prerendering, hidden until step 1
            VStack {
                LoopingVideoPlayer(assetName: "onboarding/onboarding-video", isPlaying: videoPlaying)
                    .aspectRatio(590.0 / 1278.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 42, style: .continuous))
                    .padding(5)
                    .background(
                        RoundedRectangle(cornerRadius: 47, style: .continuous)
                            .fill(Color(red: 0.65, green: 0.55, blue: 0.42))
                    )
                    .shadow(
                        color: Color(red: 0.45, green: 0.3, blue: 0.15)
                            .opacity(phoneShadow ? 0.4 : 0),
                        radius: 20, y: 10
                    )
                    .padding(.horizontal, 44)
                    .offset(y: -30 + (phoneVisible ? 0 : -100) + (phoneDropped ? 210 : 0) + (phoneRaised ? -120 : 0))
                    .opacity(step >= 1 && phoneVisible && !phoneHidden ? 1 : 0)

                Spacer()
            }

            // Top gradient blur
            if step >= 1 && step <= 3 {
                VStack {
                    ChatTopFadeGradientBridge()
                        .frame(height: 260)
                        .offset(y: -20)
                        .ignoresSafeArea(.all, edges: .top)
                    Spacer()
                }
            }

            // Bottom gradient blur (mirrored, for tabs step)
            VStack {
                Spacer()
                ChatTopFadeGradientBridge()
                    .frame(height: 240)
                    .scaleEffect(y: -1)
            }
            .ignoresSafeArea(.all, edges: .bottom)
            .opacity(phoneDropped ? 1 : 0)

            // MARK: - Step 0: Welcome

            VStack(spacing: 0) {
                Spacer()
                Spacer()

                Image("AppIconImage")
                    .resizable()
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .shadow(
                        color: Color(red: 0.45, green: 0.3, blue: 0.15)
                            .opacity(welcomeIconShadow ? (iconPressed ? 0.15 : 0.4) : 0),
                        radius: iconPressed ? 6 : 20,
                        y: iconPressed ? 3 : 10
                    )
                    .scaleEffect(iconPressed ? 0.92 : 1.0)
                    .offset(y: iconPressed ? 4 : 0)
                    .confettiCannon(
                        trigger: $confettiTrigger,
                        num: 50,
                        openingAngle: Angle(degrees: 0),
                        closingAngle: Angle(degrees: 360),
                        radius: 200
                    )
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                guard !iconPressed else { return }
                                iconPressed = true
                                UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.4)
                            }
                            .onEnded { _ in
                                iconTapCount += 1
                                if iconTapCount >= 10 {
                                    confettiTrigger += 1
                                    iconTapCount = 0
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                }
                                withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                                    iconPressed = false
                                }
                            }
                    )
                    .opacity(welcomeIconVisible ? 1 : 0)
                    .offset(y: welcomeIconVisible ? 0 : 20)
                    .padding(.bottom, 20)

                Text(L10n.Onboarding.welcomeTitle)
                    .font(.system(.largeTitle, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(colorScheme == .dark ? .white : warmDark)
                    .multilineTextAlignment(.center)
                    .opacity(welcomeTitleVisible ? 1 : 0)
                    .offset(y: welcomeTitleVisible ? 0 : 20)
                    .padding(.bottom, 8)

                Text(typewriterAttributedSubtitle)
                    .font(.system(.title3, design: .rounded))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .opacity(welcomeSubtitleVisible ? 1 : 0)
                    .offset(y: welcomeSubtitleVisible ? 0 : 20)

                Spacer()
                Spacer()
                Spacer()
            }
            .opacity(step == 0 ? 1 : 0)
            .offset(y: step == 0 ? 0 : -40)

            // MARK: - Step 1: Phone title

            Text(L10n.Onboarding.title)
                .font(.system(.title, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(colorScheme == .dark ? .white : warmDark)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .opacity(phoneTitleVisible ? 1 : 0)
                .offset(y: phoneTitleVisible ? 0 : 20)

            // MARK: - Step 2: Tabs title

            Text(L10n.Onboarding.tabsTitle)
                .font(.system(.title, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(colorScheme == .dark ? .white : warmDark)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .opacity(tabsTitleVisible ? 1 : 0)
                .offset(y: tabsTitleVisible ? 0 : 20)

            // MARK: - Step 3: Reminders title

            Text(L10n.Onboarding.remindersTitle)
                .font(.system(.title, design: .rounded))
                .fontWeight(.bold)
                .foregroundStyle(colorScheme == .dark ? .white : warmDark)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .opacity(remindersTitleVisible ? 1 : 0)
                .offset(y: remindersTitleVisible ? 0 : 20)

            // MARK: - Step 4: Name your space

            VStack(spacing: 0) {
                Spacer()
                Spacer()

                Text("💎")
                    .font(.system(size: 56))
                    .opacity(spaceTitleVisible ? 1 : 0)
                    .offset(y: spaceTitleVisible ? 0 : 20)

                TextField("", text: $spaceNameInput, prompt: Text(L10n.Onboarding.spacePlaceholder)
                    .foregroundStyle((colorScheme == .dark ? Color.white : warmDark).opacity(0.3)))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(colorScheme == .dark ? .white : warmDark)
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($spaceFieldFocused)
                    .onChange(of: spaceNameInput) { _, newValue in
                        if newValue.count > 20 {
                            spaceNameInput = String(newValue.prefix(20))
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 24)
                    .opacity(spaceContentVisible ? 1 : 0)
                    .offset(y: spaceContentVisible ? 0 : 20)

                Spacer()
                Spacer()
                Spacer()
            }
            .opacity(step == 4 ? 1 : 0)
            .allowsHitTesting(step == 4)

            // MARK: - Step 5: Tab picker

            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text(L10n.Onboarding.pickerTitle)
                        .font(.system(.title, design: .rounded))
                        .fontWeight(.bold)
                        .foregroundStyle(colorScheme == .dark ? .white : warmDark)
                        .multilineTextAlignment(.center)

                    Text(L10n.Onboarding.pickerSubtitle)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .padding(.top, 32)
                .opacity(pickerTitleVisible ? 1 : 0)
                .offset(y: pickerTitleVisible ? 0 : 20)

                Spacer()

                FlowLayout(spacing: 12) {
                    ForEach(starterTabs, id: \.self) { tab in
                        let isSelected = selectedStarterTabs.contains(tab)
                        OnboardingTabChip(
                            title: tab,
                            isSelected: isSelected,
                            warmDark: warmDark,
                            colorScheme: colorScheme
                        ) {
                            if isSelected {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedStarterTabs.remove(tab)
                                }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
                            } else if selectedStarterTabs.count < 5 {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedStarterTabs.insert(tab)
                                }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.5)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)

                Spacer()
                Spacer()
            }
            .opacity(pickerContentVisible ? 1 : 0)

            // MARK: - Continue button

            VStack {
                Spacer()

                // Progress dots
                HStack(spacing: 8) {
                    ForEach(0..<6) { index in
                        Circle()
                            .fill(index == step
                                  ? (colorScheme == .dark ? Color.white : warmDark)
                                  : (colorScheme == .dark ? Color.white.opacity(0.25) : warmDark.opacity(0.25)))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.bottom, 16)
                .opacity(step >= 1 && step != 4 && step != 5 ? 1 : 0)
                .animation(.easeOut(duration: 0.3), value: step)

                Button {
                    if step == 0 {
                        advanceToPhoneStep()
                    } else if step == 1 {
                        advanceToTabsStep()
                    } else if step == 2 {
                        advanceToRemindersStep()
                    } else if step == 3 {
                        advanceToSpaceStep()
                    } else if step == 4 {
                        advanceToPickerStep()
                    } else {
                        withAnimation(.easeIn(duration: 0.6)) {
                            fadeToBlack = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            AppSettings.shared.hasCompletedOnboarding = true
                            onComplete()
                        }
                    }
                } label: {
                    Text(step == 5 && selectedStarterTabs.isEmpty
                         ? L10n.Onboarding.skipButton
                         : L10n.Onboarding.continueButton)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(buttonForeground.opacity(spaceButtonDisabled ? 0.4 : 1))
                        .contentTransition(.interpolate)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(buttonBackground.opacity(spaceButtonDisabled ? 0.4 : 1))
                        .clipShape(Capsule())
                }
                .disabled(spaceButtonDisabled)
                .padding(.horizontal, 16)
                .padding(.bottom, keyboardHeight > 0 ? keyboardHeight - 20 : 8)
                .animation(.easeOut(duration: 0.25), value: keyboardHeight)
                .opacity(currentButtonVisible ? 1 : 0)
                .offset(y: currentButtonVisible ? 0 : 20)
            }
            .ignoresSafeArea(.keyboard)

            // Fade to black before paywall
            Color.black
                .ignoresSafeArea()
                .opacity(fadeToBlack ? 1 : 0)
                .allowsHitTesting(false)
        }
        .onAppear {
            animateWelcome()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                keyboardHeight = frame.height
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
    }

    private var spaceButtonDisabled: Bool {
        step == 4 && spaceNameInput.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var currentButtonVisible: Bool {
        switch step {
        case 0: return welcomeButtonVisible
        case 1: return phoneButtonVisible
        case 2: return tabsButtonVisible
        case 3: return remindersButtonVisible
        case 4: return spaceButtonVisible
        default: return pickerButtonVisible
        }
    }

    private var typewriterAttributedSubtitle: AttributedString {
        let full = L10n.Onboarding.welcomeSubtitle
        var result = AttributedString(full)
        let chars = Array(full)
        var offset = result.startIndex
        for i in 0..<chars.count {
            let next = result.index(afterCharacter: offset)
            if i < revealedCount {
                result[offset..<next].foregroundColor = .secondary
            } else {
                result[offset..<next].foregroundColor = .clear
            }
            offset = next
        }
        return result
    }

    // MARK: - Animations

    private func animateWelcome() {
        // Delay to let layout settle and avoid teleport glitch
        let start: Double = 0.4
        DispatchQueue.main.asyncAfter(deadline: .now() + start) {
            withAnimation(.easeOut(duration: 0.8)) {
                welcomeIconVisible = true
            }
            withAnimation(.easeOut(duration: 1.2).delay(0.4)) {
                welcomeIconShadow = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + start + 0.8) {
            withAnimation(.easeOut(duration: 0.5)) {
                welcomeTitleVisible = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + start + 1.3) {
            withAnimation(.easeOut(duration: 0.3)) {
                welcomeSubtitleVisible = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                startTypewriter()
            }
        }
    }

    private func startTypewriter() {
        let total = L10n.Onboarding.welcomeSubtitle.count
        let haptic = UIImpactFeedbackGenerator(style: .soft)
        haptic.prepare()
        typewriterTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { timer in
            if revealedCount < total {
                revealedCount += 1
                haptic.impactOccurred(intensity: 0.4)
            } else {
                timer.invalidate()
                typewriterTimer = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeOut(duration: 0.4)) {
                        welcomeButtonVisible = true
                    }
                }
            }
        }
    }

    private func advanceToPhoneStep() {
        typewriterTimer?.invalidate()
        typewriterTimer = nil
        // Fade out welcome
        withAnimation(.easeIn(duration: 0.25)) {
            welcomeTitleVisible = false
            welcomeIconVisible = false
            welcomeIconShadow = false
            welcomeSubtitleVisible = false
            welcomeButtonVisible = false
        }

        // Switch step after welcome fades out
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            step = 1

            // Animate phone in with spring
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                phoneVisible = true
                phoneTitleVisible = true
            }

            // Start video and fade in shadow slightly before phone settles
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                videoPlaying = true
                withAnimation(.easeOut(duration: 0.6)) {
                    phoneShadow = true
                }
            }

            // Button appears quickly
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.easeOut(duration: 0.3)) {
                    phoneButtonVisible = true
                }
            }
        }
    }

    private func advanceToTabsStep() {
        // Fade out button and step 1 title
        withAnimation(.easeIn(duration: 0.25)) {
            phoneButtonVisible = false
            phoneTitleVisible = false
        }

        // Drop phone, show bottom gradient, new title, new button
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            step = 2

            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                phoneDropped = true
            }

            withAnimation(.easeOut(duration: 0.4).delay(0.15)) {
                tabsTitleVisible = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeOut(duration: 0.3)) {
                    tabsButtonVisible = true
                }
            }
        }
    }

    private func advanceToRemindersStep() {
        // Fade out button and tabs title
        withAnimation(.easeIn(duration: 0.25)) {
            tabsButtonVisible = false
            tabsTitleVisible = false
        }

        // Raise phone, fade bottom gradient, show new title and button
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            step = 3

            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                phoneRaised = true
            }

            withAnimation(.easeOut(duration: 0.4).delay(0.15)) {
                remindersTitleVisible = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeOut(duration: 0.3)) {
                    remindersButtonVisible = true
                }
            }
        }
    }

    private func advanceToSpaceStep() {
        // Fade out reminders UI and phone
        withAnimation(.easeIn(duration: 0.25)) {
            remindersButtonVisible = false
            remindersTitleVisible = false
            phoneHidden = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            step = 4

            withAnimation(.easeOut(duration: 0.4)) {
                spaceTitleVisible = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeOut(duration: 0.4)) {
                    spaceContentVisible = true
                }
                spaceFieldFocused = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeOut(duration: 0.3)) {
                    spaceButtonVisible = true
                }
            }
        }
    }

    private func advanceToPickerStep() {
        spaceFieldFocused = false
        // Save space name
        let trimmed = spaceNameInput.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            AppSettings.shared.spaceName = trimmed
        }

        // Fade out space UI
        withAnimation(.easeIn(duration: 0.25)) {
            spaceButtonVisible = false
            spaceTitleVisible = false
            spaceContentVisible = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            step = 5

            withAnimation(.easeOut(duration: 0.4)) {
                pickerContentVisible = true
                pickerTitleVisible = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.easeOut(duration: 0.3)) {
                    pickerButtonVisible = true
                }
            }
        }
    }
}

// MARK: - Onboarding Tab Chip

private struct OnboardingTabChip: View {
    let title: String
    let isSelected: Bool
    let warmDark: Color
    let colorScheme: ColorScheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 19)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .opacity(isSelected ? 1 : 0.45)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}
