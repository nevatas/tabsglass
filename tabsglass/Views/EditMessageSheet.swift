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
    let originalPhotoFileNames: [String]
    let onSave: (String, [TextEntity]?, [String]) -> Void
    let onCancel: () -> Void

    @State private var text: String = ""
    @State private var holder = EditTextViewHolder()
    @State private var photoFileNames: [String] = []
    @State private var photos: [UIImage] = []

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(L10n.Tab.cancel) {
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
                        onSave(trimmed, adjustedEntities.isEmpty ? nil : adjustedEntities, photoFileNames)
                    } else if !photoFileNames.isEmpty {
                        // Allow saving with only photos (no text)
                        onSave("", nil, photoFileNames)
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

            // Attached photos (if any)
            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { index, image in
                            EditAttachedImageView(image: image) {
                                removePhoto(at: index)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: 92)
                .padding(.bottom, 12)
            }

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
        .onAppear {
            text = originalText
            photoFileNames = originalPhotoFileNames
            loadPhotos()
        }
    }

    private var canSave: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty || !photoFileNames.isEmpty
    }

    private func loadPhotos() {
        photos = photoFileNames.compactMap { fileName in
            let url = Message.photosDirectory.appendingPathComponent(fileName)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        }
    }

    private func removePhoto(at index: Int) {
        guard index < photoFileNames.count && index < photos.count else { return }
        photoFileNames.remove(at: index)
        photos.remove(at: index)
    }
}

// MARK: - Edit Attached Image View

struct EditAttachedImageView: View {
    let image: UIImage
    let onRemove: () -> Void

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .topTrailing) {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 20)
                        .background(Color.black.opacity(0.6))
                        .clipShape(Circle())
                }
                .padding(4)
            }
    }
}

// MARK: - Edit Formatting Text View

struct EditFormattingTextView: UIViewRepresentable {
    @Binding var text: String
    let originalText: String
    let originalEntities: [TextEntity]?
    let holder: EditTextViewHolder
    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> FormattingTextView {
        let textView = FormattingTextView()
        textView.font = .systemFont(ofSize: 16)
        textView.isScrollEnabled = true
        textView.placeholder = ""  // No placeholder for edit mode
        textView.textColor = colorScheme == .dark ? .white : .black

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
        // Update text color for theme
        uiView.textColor = colorScheme == .dark ? .white : .black
    }

    private func createAttributedString(text: String, entities: [TextEntity]?) -> NSAttributedString {
        let textColor: UIColor = colorScheme == .dark ? .white : .black
        let attributedString = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: UIFont.systemFont(ofSize: 16),
                .foregroundColor: textColor
            ]
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
        originalPhotoFileNames: [],
        onSave: { _, _, _ in },
        onCancel: { }
    )
}
