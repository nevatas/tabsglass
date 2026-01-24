//
//  EditMessageSheet.swift
//  tabsglass
//

import SwiftUI

struct EditMessageSheet: View {
    let originalText: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Отмена") {
                    onCancel()
                }
                .foregroundColor(.primary)

                Spacer()

                Button {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        onSave(trimmed)
                    }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(canSave ? Color.accentColor : Color.gray.opacity(0.4))
                        .clipShape(Circle())
                }
                .disabled(!canSave)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Text editor
            TextEditor(text: $text)
                .focused($isFocused)
                .scrollContentBackground(.hidden)
                .font(.body)
                .foregroundColor(.primary)
                .padding(.horizontal, 16)

            Spacer()
        }
        .onAppear {
            text = originalText
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
    }

    private var canSave: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != originalText
    }
}

#Preview {
    @Previewable @State var text = "Test message"

    EditMessageSheet(
        originalText: text,
        onSave: { _ in },
        onCancel: { }
    )
}
