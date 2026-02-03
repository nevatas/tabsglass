//
//  EditMessageSheet.swift
//  tabsglass
//

import SwiftUI
import UIKit
import PhotosUI

/// Class to hold textView reference (survives SwiftUI view updates)
@Observable
final class EditTextViewHolder {
    var textView: FormattingTextView?
}

struct EditMessageSheet: View {
    let originalText: String
    let originalEntities: [TextEntity]?
    let originalPhotoFileNames: [String]
    let originalVideoFileNames: [String]
    let originalVideoThumbnailFileNames: [String]
    let originalVideoDurations: [Double]
    let onSave: (String, [TextEntity]?, [String], [String], [String], [Double]) -> Void
    let onCancel: () -> Void

    init(
        originalText: String,
        originalEntities: [TextEntity]?,
        originalPhotoFileNames: [String],
        originalVideoFileNames: [String] = [],
        originalVideoThumbnailFileNames: [String] = [],
        originalVideoDurations: [Double] = [],
        onSave: @escaping (String, [TextEntity]?, [String], [String], [String], [Double]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.originalText = originalText
        self.originalEntities = originalEntities
        self.originalPhotoFileNames = originalPhotoFileNames
        self.originalVideoFileNames = originalVideoFileNames
        self.originalVideoThumbnailFileNames = originalVideoThumbnailFileNames
        self.originalVideoDurations = originalVideoDurations
        self.onSave = onSave
        self.onCancel = onCancel
    }

    @State private var text: String = ""
    @State private var holder = EditTextViewHolder()
    @State private var photoFileNames: [String] = []
    @State private var photos: [UIImage] = []
    @State private var videoFileNames: [String] = []
    @State private var videoThumbnailFileNames: [String] = []
    @State private var videoDurations: [Double] = []
    @State private var videoThumbnails: [UIImage] = []
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    private var themeManager: ThemeManager { ThemeManager.shared }
    @Environment(\.colorScheme) private var colorScheme

    private var totalMediaCount: Int {
        photos.count + videoThumbnails.count
    }

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
                        onSave(trimmed, adjustedEntities.isEmpty ? nil : adjustedEntities, photoFileNames, videoFileNames, videoThumbnailFileNames, videoDurations)
                    } else if totalMediaCount > 0 {
                        // Allow saving with only media (no text)
                        onSave("", nil, photoFileNames, videoFileNames, videoThumbnailFileNames, videoDurations)
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

            // Attached media (photos and videos)
            if totalMediaCount > 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // Photos
                        ForEach(Array(photos.enumerated()), id: \.offset) { index, image in
                            EditAttachedImageView(image: image) {
                                removePhoto(at: index)
                            }
                        }
                        // Videos
                        ForEach(Array(videoThumbnails.enumerated()), id: \.offset) { index, thumbnail in
                            EditAttachedVideoView(
                                thumbnail: thumbnail,
                                duration: index < videoDurations.count ? videoDurations[index] : 0
                            ) {
                                removeVideo(at: index)
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

            // Bottom toolbar with plus button
            HStack {
                Menu {
                    Button {
                        showCamera = true
                    } label: {
                        Label(L10n.Composer.camera, systemImage: "camera")
                    }

                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label(L10n.Composer.gallery, systemImage: "photo.on.rectangle")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(themeManager.currentTheme.accentColor ?? (colorScheme == .dark ? .white : .black))
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .onAppear {
            text = originalText
            photoFileNames = originalPhotoFileNames
            videoFileNames = originalVideoFileNames
            videoThumbnailFileNames = originalVideoThumbnailFileNames
            videoDurations = originalVideoDurations
            loadPhotos()
            loadVideoThumbnails()
        }
        .onChange(of: selectedPhotoItems) { _, newItems in
            Task {
                await loadSelectedPhotos(newItems)
                selectedPhotoItems = []
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView { image in
                addPhoto(image)
            }
            .ignoresSafeArea()
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: max(1, 10 - totalMediaCount),
            matching: .images
        )
    }

    private var canSave: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty || totalMediaCount > 0
    }

    private func loadPhotos() {
        photos = photoFileNames.compactMap { fileName in
            let url = Message.photosDirectory.appendingPathComponent(fileName)
            guard let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        }
    }

    private func loadVideoThumbnails() {
        videoThumbnails = videoThumbnailFileNames.compactMap { fileName in
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

    private func removeVideo(at index: Int) {
        guard index < videoFileNames.count else { return }
        videoFileNames.remove(at: index)
        if index < videoThumbnailFileNames.count {
            videoThumbnailFileNames.remove(at: index)
        }
        if index < videoDurations.count {
            videoDurations.remove(at: index)
        }
        if index < videoThumbnails.count {
            videoThumbnails.remove(at: index)
        }
    }

    private func addPhoto(_ image: UIImage) {
        guard totalMediaCount < 10 else { return }
        if let result = Message.savePhoto(image) {
            photoFileNames.append(result.fileName)
            photos.append(image)
        }
    }

    @MainActor
    private func loadSelectedPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard totalMediaCount < 10 else { break }
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                addPhoto(image)
            }
        }
    }
}

// MARK: - Camera View

struct CameraView: UIViewControllerRepresentable {
    let onImageCaptured: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView

        init(_ parent: CameraView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImageCaptured(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
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

// MARK: - Edit Attached Video View

struct EditAttachedVideoView: View {
    let thumbnail: UIImage
    let duration: Double
    let onRemove: () -> Void

    private var formattedDuration: String {
        let totalSeconds = Int(duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        ZStack {
            Image(uiImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            // Play icon overlay
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 28, height: 28)
                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .offset(x: 1)
            }

            // Duration badge
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text(formattedDuration)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(4)
                }
            }
        }
        .frame(width: 80, height: 80)
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
        onSave: { _, _, _, _, _, _ in },
        onCancel: { }
    )
}
