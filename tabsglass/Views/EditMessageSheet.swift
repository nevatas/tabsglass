//
//  EditMessageSheet.swift
//  tabsglass
//

import SwiftUI
import UIKit

/// Class to hold textView reference (survives SwiftUI view updates)
@Observable
final class EditTextViewHolder {
    var textView: FormattingTextView?
}

struct EditMessageSheet: View {
    let originalText: String
    let originalEntities: [TextEntity]?
    let onSave: (String, [TextEntity]?) -> Void
    let onCancel: () -> Void

    @State private var text: String = ""
    @State private var holder = EditTextViewHolder()

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
                        // Calculate leading whitespace offset for entity adjustment
                        let leadingWhitespace = text.prefix(while: { $0.isWhitespace || $0.isNewline }).count

                        // Get entities and adjust offsets for trimmed text
                        let rawEntities = holder.textView?.extractEntities() ?? []
                        var adjustedEntities: [TextEntity] = []

                        for entity in rawEntities {
                            let newOffset = entity.offset - leadingWhitespace
                            // Only include entities that are within the trimmed text bounds
                            if newOffset >= 0 && newOffset + entity.length <= trimmed.count {
                                adjustedEntities.append(TextEntity(
                                    type: entity.type,
                                    offset: newOffset,
                                    length: entity.length,
                                    url: entity.url
                                ))
                            }
                        }

                        // Also detect URLs
                        adjustedEntities.append(contentsOf: TextEntity.detectURLs(in: trimmed))
                        onSave(trimmed, adjustedEntities.isEmpty ? nil : adjustedEntities)
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
                holder: holder
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
    let holder: EditTextViewHolder

    func makeUIView(context: Context) -> FormattingTextView {
        let textView = FormattingTextView()
        textView.font = .systemFont(ofSize: 16)
        textView.isScrollEnabled = true
        textView.placeholder = ""  // No placeholder for edit mode

        // Apply original text with formatting
        let attributedText = createAttributedString(text: originalText, entities: originalEntities)
        textView.attributedText = attributedText

        // Store reference in holder for reliable access from parent view
        holder.textView = textView

        textView.onTextChange = { attrText in
            DispatchQueue.main.async {
                self.text = attrText.string
            }
        }

        // Focus after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            _ = textView.becomeFirstResponder()
        }

        return textView
    }

    func updateUIView(_ uiView: FormattingTextView, context: Context) {
        // Keep holder reference updated
        holder.textView = uiView
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
            case "text_link":
                // Text link - hyperlinked text
                if let urlString = entity.url {
                    attributedString.addAttribute(.link, value: urlString, range: range)
                    attributedString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                    attributedString.addAttribute(.foregroundColor, value: UIColor.link, range: range)
                }
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
