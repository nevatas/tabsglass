//
//  ComposerView.swift
//  tabsglass
//

import SwiftUI

struct ComposerView: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void
    let onAttach: (() -> Void)?

    init(
        text: Binding<String>,
        isFocused: FocusState<Bool>.Binding,
        onAttach: (() -> Void)? = nil,
        onSend: @escaping () -> Void
    ) {
        self._text = text
        self.isFocused = isFocused
        self.onAttach = onAttach
        self.onSend = onSend
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 12) {
                // TextField at top
                TextField("Note...", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .focused(isFocused)
                    .lineLimit(1...6)
                    .onSubmit {
                        if canSend {
                            onSend()
                        }
                    }
                    .submitLabel(.send)

                // Button row at bottom
                HStack {
                    // Attach button (left)
                    Button {
                        onAttach?()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Send button (right)
                    Button(action: onSend) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(canSend ? Color.accentColor : Color.gray.opacity(0.4))
                            .clipShape(Circle())
                    }
                    .disabled(!canSend)
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .glassEffect(.regular.tint(.white.opacity(0.9)), in: .rect(cornerRadius: 24))
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

#Preview {
    @Previewable @State var text = "Привет это текст"
    @Previewable @FocusState var focused: Bool

    VStack {
        Spacer()
        ComposerView(text: $text, isFocused: $focused, onAttach: {
            print("Attach tapped")
        }) {
            print("Send tapped")
        }
    }
    .background(Color.gray.opacity(0.2))
}
