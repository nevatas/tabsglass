//
//  OnboardingView.swift
//  tabsglass
//
//  Onboarding flow shown on first launch
//

import SwiftUI

struct OnboardingView: View {
    @Environment(\.colorScheme) private var colorScheme
    let onComplete: () -> Void

    @State private var currentPage = 0
    @State private var titleVisible = false
    @State private var buttonVisible = false

    private var buttonBackground: Color {
        colorScheme == .dark ? .white : .black
    }

    private var buttonForeground: Color {
        colorScheme == .dark ? .black : .white
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top: Title + subtitle
            VStack(spacing: 10) {
                Text(L10n.Onboarding.title)
                    .font(.system(.title, design: .rounded))
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text(L10n.Onboarding.subtitle)
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)
            .opacity(titleVisible ? 1 : 0)
            .offset(y: titleVisible ? 0 : 20)

            Spacer()

            // Bottom: Continue button
            Button {
                AppSettings.shared.hasCompletedOnboarding = true
                onComplete()
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
            .opacity(buttonVisible ? 1 : 0)
            .offset(y: buttonVisible ? 0 : 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground).ignoresSafeArea())
        .onAppear {
            animateAppearance()
        }
    }

    private func animateAppearance() {
        withAnimation(.easeOut(duration: 0.4)) {
            titleVisible = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.4)) {
                buttonVisible = true
            }
        }
    }
}
