//
//  SearchInputView.swift
//  tabsglass
//
//  Search input with Liquid Glass style
//

import SwiftUI
import UIKit

// MARK: - UIKit TextField Wrapper

/// Fast UITextField wrapper that avoids SwiftUI FocusState delays
struct FastTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let placeholder: String
    let placeholderColor: UIColor

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.font = .systemFont(ofSize: 17, weight: .medium)
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: placeholderColor,
                .font: UIFont.systemFont(ofSize: 17, weight: .medium)
            ]
        )
        textField.delegate = context.coordinator
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        textField.autocorrectionType = .default
        textField.spellCheckingType = .default
        textField.returnKeyType = .done
        textField.clearButtonMode = .never // We handle clear button ourselves
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        if textField.text != text {
            textField.text = text
        }

        // Update placeholder color when theme changes
        textField.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: placeholderColor,
                .font: UIFont.systemFont(ofSize: 17, weight: .medium)
            ]
        )

        // Handle focus changes from SwiftUI
        if isFocused && !textField.isFirstResponder {
            textField.becomeFirstResponder()
        } else if !isFocused && textField.isFirstResponder {
            textField.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: FastTextField

        init(_ parent: FastTextField) {
            self.parent = parent
        }

        @objc func textChanged(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            DispatchQueue.main.async {
                self.parent.isFocused = true
            }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            DispatchQueue.main.async {
                self.parent.isFocused = false
            }
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}

// MARK: - Search Input View

struct SearchInputView: View {
    @Binding var searchText: String
    @Binding var isFocused: Bool

    @Environment(\.colorScheme) private var colorScheme
    private var themeManager: ThemeManager { ThemeManager.shared }

    private var composerTint: Color {
        let theme = themeManager.currentTheme
        return colorScheme == .dark ? theme.composerTintColorDark : theme.composerTintColor
    }

    private var placeholderColor: UIColor {
        themeManager.currentTheme.placeholderColor
    }

    /// Unique ID that changes with theme to force glassEffect refresh
    private var glassId: String {
        "\(themeManager.currentTheme.rawValue)-\(colorScheme == .dark ? "dark" : "light")"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color(placeholderColor))

            FastTextField(text: $searchText, isFocused: $isFocused, placeholder: L10n.Search.placeholder, placeholderColor: placeholderColor)
                .frame(height: 24)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(.capsule)
        .onTapGesture {
            isFocused = true
        }
        .glassEffect(
            .regular.interactive(),
            in: .capsule
        )
        .id(glassId)  // Force recreation when theme changes
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

// MARK: - UIKit Wrapper

/// Observable wrapper for search text binding in UIKit
@Observable
final class SearchInputState {
    var text: String = ""
    var isFocused: Bool = false
    var onTextChange: ((String) -> Void)?
    var onFocusChange: ((Bool) -> Void)?

    func updateText(_ newText: String) {
        text = newText
        onTextChange?(newText)
    }

    func focus() {
        isFocused = true
    }

    func blur() {
        isFocused = false
    }
}

/// SwiftUI view that can be hosted in UIKit
struct SearchInputWrapper: View {
    @Bindable var state: SearchInputState

    var body: some View {
        SearchInputView(
            searchText: Binding(
                get: { state.text },
                set: { state.updateText($0) }
            ),
            isFocused: Binding(
                get: { state.isFocused },
                set: { newValue in
                    state.isFocused = newValue
                    state.onFocusChange?(newValue)
                }
            )
        )
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var isFocused = false

        var body: some View {
            VStack {
                Spacer()
                SearchInputView(searchText: .constant(""), isFocused: $isFocused)
            }
            .background(Color.gray.opacity(0.2))
        }
    }

    return PreviewWrapper()
}
