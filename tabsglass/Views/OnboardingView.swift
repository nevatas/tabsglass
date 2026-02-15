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

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        container.clipsToBounds = true

        guard let dataAsset = NSDataAsset(name: assetName) else { return container }

        // Write to temp file for AVPlayer
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(assetName).mp4")
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

        player.play()

        context.coordinator.player = player
        context.coordinator.playerLayer = playerLayer

        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.playerLayer?.frame = uiView.bounds
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

    // Step: 0 = welcome, 1 = phone demo
    @State private var step = 0

    // Welcome step animations (sequential: title → icon → subtitle → button)
    @State private var welcomeTitleVisible = false
    @State private var welcomeIconVisible = false
    @State private var welcomeIconShadow = false
    @State private var iconPressed = false
    @State private var iconTapCount = 0
    @State private var confettiTrigger = 0
    @State private var welcomeSubtitleVisible = false
    @State private var welcomeButtonVisible = false

    // Phone step animations
    @State private var phoneVisible = false
    @State private var phoneButtonVisible = false

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
                LoopingVideoPlayer(assetName: "onboarding-video-1")
                    .aspectRatio(590.0 / 1278.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 42, style: .continuous))
                    .padding(5)
                    .background(
                        RoundedRectangle(cornerRadius: 47, style: .continuous)
                            .fill(Color(red: 0.65, green: 0.55, blue: 0.42))
                    )
                    .padding(.horizontal, 44)
                    .offset(y: -60 + (phoneVisible ? 0 : -100))
                    .opacity(step == 1 && phoneVisible ? 1 : 0)

                Spacer()
            }

            // Gradient blur — only on phone step
            if step == 1 {
                VStack {
                    ChatTopFadeGradientBridge()
                        .frame(height: 260)
                        .ignoresSafeArea(.all, edges: .top)
                    Spacer()
                }
            }

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

                Text(L10n.Onboarding.welcomeSubtitle)
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(.secondary)
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
                .opacity(step == 1 && phoneVisible ? 1 : 0)
                .offset(y: step == 1 ? (phoneVisible ? 0 : 20) : 0)

            // MARK: - Continue button (both steps)

            VStack {
                Spacer()

                Button {
                    if step == 0 {
                        advanceToPhoneStep()
                    } else {
                        AppSettings.shared.hasCompletedOnboarding = true
                        onComplete()
                    }
                } label: {
                    Text(L10n.Onboarding.continueButton)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(buttonForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(buttonBackground)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .opacity(currentButtonVisible ? 1 : 0)
                .offset(y: currentButtonVisible ? 0 : 20)
            }
        }
        .onAppear {
            animateWelcome()
        }
    }

    private var currentButtonVisible: Bool {
        step == 0 ? welcomeButtonVisible : phoneButtonVisible
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
            withAnimation(.easeOut(duration: 0.5)) {
                welcomeSubtitleVisible = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + start + 2.0) {
            withAnimation(.easeOut(duration: 0.4)) {
                welcomeButtonVisible = true
            }
        }
    }

    private func advanceToPhoneStep() {
        // Fade out welcome
        withAnimation(.easeIn(duration: 0.3)) {
            welcomeTitleVisible = false
            welcomeIconVisible = false
            welcomeIconShadow = false
            welcomeSubtitleVisible = false
            welcomeButtonVisible = false
        }

        // Switch step after welcome fades out
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            step = 1

            // Animate phone in
            withAnimation(.easeOut(duration: 0.7)) {
                phoneVisible = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeOut(duration: 0.4)) {
                    phoneButtonVisible = true
                }
            }
        }
    }
}
