//
//  EditMessageSheet.swift
//  tabsglass
//

import SwiftUI
import UIKit

struct EditMessageSheet: View {
    let originalText: String
    let originalEntities: [TextEntity]?
    let onSave: (String, [TextEntity]?) -> Void
    let onCancel: () -> Void

    @State private var text: String = ""
    @State private var textView: FormattingTextView?

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
                        let entities = textView?.extractEntities() ?? []
                        // Also detect URLs
                        var allEntities = entities
                        allEntities.append(contentsOf: TextEntity.detectURLs(in: trimmed))
                        onSave(trimmed, allEntities.isEmpty ? nil : allEntities)
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

            // Formatting text editor
            EditFormattingTextView(
                text: $text,
                originalText: originalText,
                originalEntities: originalEntities,
                onTextViewReady: { tv in
                    textView = tv
                }
            )
            .padding(.horizontal, 16)

            Spacer()
        }
    }

    private var canSave: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
    }
}

// MARK: - Edit Formatting Text View

struct EditFormattingTextView: UIViewRepresentable {
    @Binding var text: String
    let originalText: String
    let originalEntities: [TextEntity]?
    var onTextViewReady: ((FormattingTextView) -> Void)?

    func makeUIView(context: Context) -> FormattingTextView {
        let textView = FormattingTextView()
        textView.font = .systemFont(ofSize: 16)
        textView.isScrollEnabled = true

        // Apply original text with formatting
        let attributedText = createAttributedString(text: originalText, entities: originalEntities)
        textView.attributedText = attributedText

        textView.onTextChange = { attrText in
            DispatchQueue.main.async {
                self.text = attrText.string
            }
        }

        // Focus after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            _ = textView.becomeFirstResponder()
        }

        onTextViewReady?(textView)

        return textView
    }

    func updateUIView(_ uiView: FormattingTextView, context: Context) {
        // Update handled by callbacks
    }

    private func createAttributedString(text: String, entities: [TextEntity]?) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(
            string: text,
            attributes: [.font: UIFont.systemFont(ofSize: 16)]
        )

        guard let entities = entities else {
            return attributedString
        }

        let nsString = text as NSString

        for entity in entities {
            guard entity.offset >= 0,
                  entity.length > 0,
                  entity.offset + entity.length <= nsString.length else {
                continue
            }

            let range = NSRange(location: entity.offset, length: entity.length)

            switch entity.type {
            case "bold":
                attributedString.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: 16), range: range)
            case "italic":
                attributedString.addAttribute(.font, value: UIFont.italicSystemFont(ofSize: 16), range: range)
            case "underline":
                attributedString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            case "strikethrough":
                attributedString.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            default:
                break
            }
        }

        return attributedString
    }
}

#Preview {
    @Previewable @State var text = "Test message"

    EditMessageSheet(
        originalText: text,
        originalEntities: nil,
        onSave: { _, _ in },
        onCancel: { }
    )
}
