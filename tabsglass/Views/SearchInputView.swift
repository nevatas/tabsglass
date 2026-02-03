//
//  SearchInputView.swift
//  tabsglass
//
//  Search input with Liquid Glass style
//

import SwiftUI

struct SearchInputView: View {
    @Binding var searchText: String
    var isFocused: FocusState<Bool>.Binding

    @Environment(\.colorScheme) private var colorScheme
    private var themeManager: ThemeManager { ThemeManager.shared }

    private var composerTint: Color {
        let theme = themeManager.currentTheme
        return colorScheme == .dark ? theme.composerTintColorDark : theme.composerTintColor
    }

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField(L10n.Search.placeholder, text: $searchText)
                    .font(.system(size: 16))
                    .focused(isFocused)

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
            .glassEffect(
                .regular.tint(composerTint).interactive(),
                in: .capsule
            )
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

// MARK: - UIKit Wrapper

/// Observable wrapper for search text binding in UIKit
@Observable
final class SearchInputState {
    var text: String = ""
    var shouldFocus: Bool = false
    var onTextChange: ((String) -> Void)?
    var onFocusChange: ((Bool) -> Void)?

    func updateText(_ newText: String) {
        text = newText
        onTextChange?(newText)
    }

    func focus() {
        shouldFocus = true
    }

    func blur() {
        shouldFocus = false
    }
}

/// SwiftUI view that can be hosted in UIKit
struct SearchInputWrapper: View {
    @Bindable var state: SearchInputState
    @FocusState private var isFocused: Bool

    var body: some View {
        SearchInputView(searchText: Binding(
            get: { state.text },
            set: { state.updateText($0) }
        ), isFocused: $isFocused)
        .onChange(of: state.shouldFocus) { _, shouldFocus in
            if shouldFocus {
                isFocused = true
                state.shouldFocus = false  // Reset trigger
            }
        }
        .onChange(of: isFocused) { _, newValue in
            state.onFocusChange?(newValue)
        }
    }
}

struct SearchInputView_Previews: PreviewProvider {
    struct PreviewWrapper: View {
        @FocusState private var isFocused: Bool

        var body: some View {
            VStack {
                Spacer()
                SearchInputView(searchText: .constant(""), isFocused: $isFocused)
            }
            .background(Color.gray.opacity(0.2))
        }
    }

    static var previews: some View {
        PreviewWrapper()
    }
}
