//
//  KeyboardObserver.swift
//  tabsglass
//

import SwiftUI
import UIKit
import Combine

@Observable
final class KeyboardObserver {
    var keyboardHeight: CGFloat = 0
    var isKeyboardVisible: Bool = false
    var animationDuration: Double = 0.25
    var animationCurve: UIView.AnimationCurve = .easeInOut

    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification))
            .sink { [weak self] notification in
                self?.handleKeyboardNotification(notification, showing: true)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] notification in
                self?.handleKeyboardNotification(notification, showing: false)
            }
            .store(in: &cancellables)
    }

    private func handleKeyboardNotification(_ notification: Notification, showing: Bool) {
        guard let userInfo = notification.userInfo else { return }

        if let duration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double {
            animationDuration = duration
        }

        if let curveValue = userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int,
           let curve = UIView.AnimationCurve(rawValue: curveValue) {
            animationCurve = curve
        }

        if showing {
            if let frame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                keyboardHeight = frame.height
                isKeyboardVisible = true
            }
        } else {
            keyboardHeight = 0
            isKeyboardVisible = false
        }
    }

    var animation: Animation {
        switch animationCurve {
        case .easeIn:
            return .easeIn(duration: animationDuration)
        case .easeOut:
            return .easeOut(duration: animationDuration)
        case .easeInOut:
            return .easeInOut(duration: animationDuration)
        case .linear:
            return .linear(duration: animationDuration)
        @unknown default:
            return .easeInOut(duration: animationDuration)
        }
    }
}
