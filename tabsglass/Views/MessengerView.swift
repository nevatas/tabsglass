//
//  MessengerView.swift
//  tabsglass
//
//  Shared composer and message cell components used by UnifiedChatView
//

import SwiftUI
import UIKit

// MARK: - Composer State (Observable)

@Observable
final class ComposerState {
    var text: String = ""
    var shouldFocus: Bool = false
    var attachedImages: [UIImage] = []
    var onTextChange: ((String) -> Void)?
    var onSend: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    var onAttachmentChange: (() -> Void)?
    var onShowPhotoPicker: (() -> Void)?
    var onShowCamera: (() -> Void)?

    /// Height of images section (80 when visible, 0 when hidden)
    var imagesSectionHeight: CGFloat = 0

    func removeImage(at index: Int) {
        guard index < attachedImages.count else { return }
        let isLastImage = attachedImages.count == 1

        if isLastImage {
            // For last image: remove immediately without animation
            imagesSectionHeight = 0
            attachedImages.removeAll()
            onAttachmentChange?()
        } else {
            // For non-last: just remove
            attachedImages.remove(at: index)
            onAttachmentChange?()
        }
    }

    func addImages(_ images: [UIImage]) {
        let available = 10 - attachedImages.count
        let toAdd = Array(images.prefix(available))
        attachedImages.append(contentsOf: toAdd)
        // Set height when adding first images (80 images + 12 spacing = 92)
        if imagesSectionHeight == 0 && !attachedImages.isEmpty {
            withAnimation(.easeOut(duration: 0.25)) {
                imagesSectionHeight = 92
            }
        }
        onAttachmentChange?()
    }

    func clearAttachments() {
        attachedImages.removeAll()
        imagesSectionHeight = 0
    }
}

// MARK: - SwiftUI Composer Wrapper

final class SwiftUIComposerContainer: UIView {
    var onTextChange: ((String) -> Void)?
    var onImagesChange: (([UIImage]) -> Void)?
    var onSend: (() -> Void)? {
        didSet { composerState.onSend = onSend }
    }
    var onFocusChange: ((Bool) -> Void)? {
        didSet { composerState.onFocusChange = onFocusChange }
    }
    var onShowPhotoPicker: (() -> Void)? {
        didSet { composerState.onShowPhotoPicker = onShowPhotoPicker }
    }
    var onShowCamera: (() -> Void)? {
        didSet { composerState.onShowCamera = onShowCamera }
    }

    /// Callback для уведомления о изменении высоты
    var onHeightChange: ((CGFloat) -> Void)?

    private let composerState = ComposerState()
    private var hostingController: UIHostingController<EmbeddedComposerView>?
    private var currentHeight: CGFloat = 102

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        setupHostingController()
        setupTextChangeHandler()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupTextChangeHandler() {
        composerState.onTextChange = { [weak self] newText in
            guard let self = self else { return }
            self.onTextChange?(newText)
            self.updateHeight()
        }

        composerState.onAttachmentChange = { [weak self] in
            guard let self = self else { return }
            // Notify about images change
            self.onImagesChange?(self.composerState.attachedImages)
            // Update height with small delays to catch SwiftUI layout changes
            DispatchQueue.main.async {
                self.updateHeight()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.updateHeight()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.updateHeight()
            }
        }
    }

    /// Get currently attached images
    var attachedImages: [UIImage] {
        composerState.attachedImages
    }

    /// Add images from picker
    func addImages(_ images: [UIImage]) {
        composerState.addImages(images)
    }

    private func setupHostingController() {
        let composerView = EmbeddedComposerView(state: composerState)
        let hc = UIHostingController(rootView: composerView)
        hc.view.backgroundColor = .clear
        hc.view.translatesAutoresizingMaskIntoConstraints = false

        // Let UIHostingController automatically update intrinsicContentSize
        hc.sizingOptions = .intrinsicContentSize

        // Disable UIHostingController's automatic keyboard avoidance
        hc.safeAreaRegions = .container

        addSubview(hc.view)

        // Pin to all edges
        NSLayoutConstraint.activate([
            hc.view.topAnchor.constraint(equalTo: topAnchor),
            hc.view.bottomAnchor.constraint(equalTo: bottomAnchor),
            hc.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hc.view.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        hostingController = hc
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Notify parent about height changes
        updateHeight()
    }

    /// Вычисляет текущую требуемую высоту
    func calculateHeight() -> CGFloat {
        guard let hc = hostingController else { return 102 }
        let screenWidth = window?.windowScene?.screen.bounds.width
        let targetWidth = bounds.width > 0 ? bounds.width : (screenWidth ?? bounds.width)
        let fittingSize = hc.sizeThatFits(in: CGSize(width: targetWidth, height: .greatestFiniteMagnitude))
        return max(102, fittingSize.height)
    }

    /// Обновляет высоту и уведомляет parent
    private func updateHeight() {
        let newHeight = calculateHeight()
        if abs(newHeight - currentHeight) > 1 {
            currentHeight = newHeight
            invalidateIntrinsicContentSize()
            onHeightChange?(newHeight)
        }
    }

    func clearText() {
        composerState.text = ""
        composerState.clearAttachments()

        // Принудительно обновляем hosting controller
        hostingController?.view.setNeedsLayout()
        hostingController?.view.layoutIfNeeded()

        // Collapse immediately to the base height after clearing.
        currentHeight = 102
        invalidateIntrinsicContentSize()
        onHeightChange?(currentHeight)

        // Recalculate actual height after clearing (safety for SwiftUI updates)
        DispatchQueue.main.async { [weak self] in
            self?.updateHeight()
        }
    }

    /// Focus the composer text field
    func focus() {
        composerState.shouldFocus = true
    }

    // Use intrinsicContentSize from hosting controller
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: currentHeight)
    }
}

// MARK: - Embedded Composer (without FocusState)

struct EmbeddedComposerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var state: ComposerState
    @FocusState private var isFocused: Bool

    private let maxTextLines = 7

    private var canSend: Bool {
        !state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !state.attachedImages.isEmpty
    }

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                // Spacer pushes content to bottom during shrink animation
                Spacer(minLength: 0)

                VStack(spacing: 0) {
                    // Attached images row - height includes spacing (80 + 12 = 92, or 0)
                    if !state.attachedImages.isEmpty {
                        VStack(spacing: 0) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Array(state.attachedImages.enumerated()), id: \.offset) { index, image in
                                        AttachedImageView(image: image) {
                                            state.removeImage(at: index)
                                        }
                                    }
                                }
                            }
                            .frame(height: 80)

                            Spacer().frame(height: 12) // spacing below images
                        }
                        .frame(height: state.imagesSectionHeight > 0 ? 92 : 0)
                        .clipped()
                        .opacity(state.imagesSectionHeight > 0 ? 1 : 0)
                    }

                    TextField("Note...", text: $state.text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...maxTextLines)
                    .submitLabel(.send)
                    .focused($isFocused)
                    .onSubmit {
                        if canSend {
                            state.onSend?()
                        }
                    }
                    .onChange(of: state.text) { _, newValue in
                        state.onTextChange?(newValue)
                    }
                    .onChange(of: state.shouldFocus) { _, shouldFocus in
                        if shouldFocus {
                            isFocused = true
                            state.shouldFocus = false
                        }
                    }
                    .onChange(of: isFocused) { _, newValue in
                        state.onFocusChange?(newValue)
                    }

                    Spacer().frame(height: 12) // Fixed spacing between textfield and buttons

                    HStack {
                    Menu {
                        Button {
                            state.onShowCamera?()
                        } label: {
                            Label("Камера", systemImage: "camera")
                        }

                        Button {
                            state.onShowPhotoPicker?()
                        } label: {
                            Label("Фото", systemImage: "photo.on.rectangle")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button(action: {
                        if canSend {
                            state.onSend?()
                        }
                    }) {
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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .glassEffect(
                .regular.tint(colorScheme == .dark
                    ? Color(white: 0.1).opacity(0.9)
                    : .white.opacity(0.9)),
                in: .rect(cornerRadius: 24)
            )
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

// MARK: - Attached Image View

struct AttachedImageView: View {
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

// MARK: - Message Cell

final class MessageTableCell: UITableViewCell {
    private let bubbleView = UIView()
    private let mosaicView = MosaicMediaView()
    private let messageLabel = UILabel()

    private var cachedMessage: Message?
    private var lastLayoutWidth: CGFloat = 0

    /// Callback when a photo is tapped: (index, sourceFrame in window, image, allPhotos)
    var onPhotoTapped: ((Int, CGRect, UIImage, [UIImage]) -> Void)?

    private var messageLabelTopToMosaic: NSLayoutConstraint!
    private var messageLabelTopToBubble: NSLayoutConstraint!
    private var messageLabelBottomToBubble: NSLayoutConstraint!
    private var mosaicHeightConstraint: NSLayoutConstraint!
    private var mosaicBottomToBubble: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupCell() {
        backgroundColor = .clear
        selectionStyle = .none

        bubbleView.layer.cornerRadius = 18
        bubbleView.clipsToBounds = true
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bubbleView)

        // Mosaic media view
        mosaicView.translatesAutoresizingMaskIntoConstraints = false
        mosaicView.onPhotoTapped = { [weak self] index, sourceFrame, image in
            guard let self = self, let message = self.cachedMessage else { return }
            self.onPhotoTapped?(index, sourceFrame, image, message.photos)
        }
        bubbleView.addSubview(mosaicView)

        // Message label
        messageLabel.textColor = .white
        messageLabel.font = .systemFont(ofSize: 16)
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.addSubview(messageLabel)

        mosaicHeightConstraint = mosaicView.heightAnchor.constraint(equalToConstant: 0)
        messageLabelTopToMosaic = messageLabel.topAnchor.constraint(equalTo: mosaicView.bottomAnchor, constant: 10)
        messageLabelTopToBubble = messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10)
        messageLabelBottomToBubble = messageLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -10)
        mosaicBottomToBubble = mosaicView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor)

        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),

            // Mosaic view
            mosaicView.topAnchor.constraint(equalTo: bubbleView.topAnchor),
            mosaicView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor),
            mosaicView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor),
            mosaicHeightConstraint,

            // Message label - horizontal constraints always active
            messageLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 14),
            messageLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -14),
        ])

        updateBubbleColor()
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: MessageTableCell, _) in
                self.updateBubbleColor()
            }
        }
    }

    private func updateBubbleColor() {
        if traitCollection.userInterfaceStyle == .dark {
            bubbleView.backgroundColor = UIColor(white: 0.12, alpha: 1)
            messageLabel.textColor = .white
        } else {
            bubbleView.backgroundColor = UIColor(white: 0.96, alpha: 1)
            messageLabel.textColor = .black
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let message = cachedMessage else { return }
        let width = contentView.bounds.width
        if width > 0, abs(width - lastLayoutWidth) > 0.5 {
            lastLayoutWidth = width
            applyLayout(for: message, width: width)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cachedMessage = nil
        lastLayoutWidth = 0
        // Reset constraints
        messageLabelTopToMosaic.isActive = false
        messageLabelTopToBubble.isActive = false
        messageLabelBottomToBubble.isActive = false
        mosaicBottomToBubble.isActive = false
    }

    func configure(with message: Message) {
        cachedMessage = message
        messageLabel.text = message.text
        updateBubbleColor()

        let width = contentView.bounds.width
        if width > 0 {
            lastLayoutWidth = width
            applyLayout(for: message, width: width)
        }
    }

    private func applyLayout(for message: Message, width: CGFloat) {
        let photos = message.photos
        let hasPhotos = !photos.isEmpty
        let hasText = !message.text.isEmpty

        // Reset constraints first
        messageLabelTopToMosaic.isActive = false
        messageLabelTopToBubble.isActive = false
        messageLabelBottomToBubble.isActive = false
        mosaicBottomToBubble.isActive = false

        // Calculate bubble width (cell width - 32 for margins)
        let bubbleWidth = max(width - 32, 0)

        // Configure photos with mosaic layout
        if hasPhotos {
            let mosaicHeight = MosaicMediaView.calculateHeight(for: photos, maxWidth: bubbleWidth)
            mosaicHeightConstraint.constant = mosaicHeight
            // isAtBottom: true only when there's no text below (photos-only message)
            mosaicView.configure(with: photos, maxWidth: bubbleWidth, isAtBottom: !hasText)
            mosaicView.isHidden = false
        } else {
            mosaicHeightConstraint.constant = 0
            mosaicView.isHidden = true
        }

        // Configure layout based on content
        if hasPhotos && hasText {
            // Both photos and text
            messageLabelTopToMosaic.isActive = true
            messageLabelBottomToBubble.isActive = true
            messageLabel.isHidden = false
        } else if hasPhotos && !hasText {
            // Photos only - mosaic fills to bottom
            mosaicBottomToBubble.isActive = true
            messageLabel.isHidden = true
        } else {
            // Text only (or empty)
            messageLabelTopToBubble.isActive = true
            messageLabelBottomToBubble.isActive = true
            messageLabel.isHidden = false
        }
    }
}

// MARK: - Empty Cell

final class EmptyTableCell: UITableViewCell {
    private let stackView = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupCell() {
        backgroundColor = .clear
        selectionStyle = .none

        let iconView = UIImageView(image: UIImage(systemName: "bubble.left.and.bubble.right"))
        iconView.tintColor = .tertiaryLabel
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.heightAnchor.constraint(equalToConstant: 48).isActive = true
        iconView.widthAnchor.constraint(equalToConstant: 48).isActive = true

        let titleLabel = UILabel()
        titleLabel.text = "No messages yet"
        titleLabel.textColor = .secondaryLabel
        titleLabel.font = .preferredFont(forTextStyle: .subheadline)

        let subtitleLabel = UILabel()
        subtitleLabel.text = "Type a note below to get started"
        subtitleLabel.textColor = .tertiaryLabel
        subtitleLabel.font = .preferredFont(forTextStyle: .caption1)

        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 8
        stackView.addArrangedSubview(iconView)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            contentView.heightAnchor.constraint(equalToConstant: 300)
        ])
    }
}
