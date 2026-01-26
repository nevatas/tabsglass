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
    var attributedText: NSAttributedString = NSAttributedString()
    var shouldFocus: Bool = false
    var attachedImages: [UIImage] = []
    var onTextChange: ((String) -> Void)?
    var onSend: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    var onAttachmentChange: (() -> Void)?
    var onShowPhotoPicker: (() -> Void)?
    var onShowCamera: (() -> Void)?

    /// Reference to the formatting text view for extracting entities
    weak var formattingTextView: FormattingTextView?

    /// Height of images section (80 when visible, 0 when hidden)
    var imagesSectionHeight: CGFloat = 0

    /// Extract formatting entities from current text
    func extractEntities() -> [TextEntity] {
        return formattingTextView?.extractEntities() ?? []
    }

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

    func clearAll() {
        text = ""
        attributedText = NSAttributedString()
        formattingTextView?.clear()
        clearAttachments()
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
        composerState.clearAll()

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

    /// Extract formatting entities from current text
    func extractEntities() -> [TextEntity] {
        return composerState.extractEntities()
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

// MARK: - Formatting Text View Wrapper

struct FormattingTextViewWrapper: UIViewRepresentable {
    @Bindable var state: ComposerState
    var colorScheme: ColorScheme

    private let maxLines = 7
    private let lineHeight: CGFloat = 22  // Approximate line height for 16pt font

    private var maxHeight: CGFloat {
        CGFloat(maxLines) * lineHeight
    }

    func makeUIView(context: Context) -> FormattingTextView {
        let textView = FormattingTextView()
        textView.placeholder = "Note..."
        textView.textColor = colorScheme == .dark ? .white : .black

        textView.onTextChange = { [self] attrText in
            state.text = attrText.string
            state.attributedText = attrText
            state.onTextChange?(attrText.string)

            // Enable/disable scroll based on content height
            let contentHeight = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude)).height
            textView.isScrollEnabled = contentHeight > maxHeight
        }

        textView.onFocusChange = { isFocused in
            state.onFocusChange?(isFocused)
        }

        // Store reference for entity extraction
        state.formattingTextView = textView

        return textView
    }

    func updateUIView(_ uiView: FormattingTextView, context: Context) {
        // Update text color for theme
        uiView.textColor = colorScheme == .dark ? .white : .black

        // Handle focus request
        if state.shouldFocus {
            DispatchQueue.main.async {
                _ = uiView.becomeFirstResponder()
                state.shouldFocus = false
            }
        }

        // Update scroll enabled state
        let contentHeight = uiView.sizeThatFits(CGSize(width: uiView.bounds.width > 0 ? uiView.bounds.width : 300, height: .greatestFiniteMagnitude)).height
        uiView.isScrollEnabled = contentHeight > maxHeight
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: FormattingTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 300
        let naturalSize = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let height = min(naturalSize.height, maxHeight)  // Cap at maxLines
        return CGSize(width: width, height: max(24, height))  // min height 24
    }
}

// MARK: - Embedded Composer

struct EmbeddedComposerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var state: ComposerState

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

                    FormattingTextViewWrapper(state: state, colorScheme: colorScheme)

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
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
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
    private let messageTextView = UITextView()

    private var cachedMessage: Message?
    private var lastLayoutWidth: CGFloat = 0

    /// Callback when a photo is tapped: (index, sourceFrame in window, image, fileNames)
    var onPhotoTapped: ((Int, CGRect, UIImage, [String]) -> Void)?

    private var messageTextViewTopToMosaic: NSLayoutConstraint!
    private var messageTextViewTopToBubble: NSLayoutConstraint!
    private var messageTextViewBottomToBubble: NSLayoutConstraint!
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
        mosaicView.onPhotoTapped = { [weak self] index, sourceFrame, image, fileNames in
            self?.onPhotoTapped?(index, sourceFrame, image, fileNames)
        }
        bubbleView.addSubview(mosaicView)

        // Message text view (configured to look like a label but with clickable links)
        messageTextView.backgroundColor = .clear
        messageTextView.textColor = .white
        messageTextView.font = .systemFont(ofSize: 16)
        messageTextView.isEditable = false
        messageTextView.isScrollEnabled = false
        messageTextView.isSelectable = true
        messageTextView.dataDetectorTypes = []  // We handle links via entities
        messageTextView.textContainerInset = .zero
        messageTextView.textContainer.lineFragmentPadding = 0
        messageTextView.linkTextAttributes = [
            .foregroundColor: UIColor.systemBlue,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        messageTextView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.addSubview(messageTextView)

        mosaicHeightConstraint = mosaicView.heightAnchor.constraint(equalToConstant: 0)
        messageTextViewTopToMosaic = messageTextView.topAnchor.constraint(equalTo: mosaicView.bottomAnchor, constant: 10)
        messageTextViewTopToBubble = messageTextView.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10)
        messageTextViewBottomToBubble = messageTextView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -10)
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

            // Message text view - horizontal constraints always active
            messageTextView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 14),
            messageTextView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -14),
        ])

        updateBubbleColor()
        if #available(iOS 17.0, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: MessageTableCell, _) in
                self.updateBubbleColor()
            }
        }

        // Listen for theme changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThemeChange),
            name: .themeDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleThemeChange() {
        updateBubbleColor()
    }

    private func updateBubbleColor() {
        let theme = ThemeManager.shared.currentTheme
        if traitCollection.userInterfaceStyle == .dark {
            bubbleView.backgroundColor = theme.bubbleColorDark
            messageTextView.textColor = .white
        } else {
            bubbleView.backgroundColor = theme.bubbleColor
            messageTextView.textColor = .black
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
        messageTextViewTopToMosaic.isActive = false
        messageTextViewTopToBubble.isActive = false
        messageTextViewBottomToBubble.isActive = false
        mosaicBottomToBubble.isActive = false
    }

    func configure(with message: Message) {
        cachedMessage = message

        // Create attributed string with entities (links, formatting)
        let attributedText = createAttributedString(for: message)
        messageTextView.attributedText = attributedText

        updateBubbleColor()

        let width = contentView.bounds.width
        if width > 0 {
            lastLayoutWidth = width
            applyLayout(for: message, width: width)
        }
    }

    private func createAttributedString(for message: Message) -> NSAttributedString {
        let text = message.content

        // Base attributes with line spacing
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16),
            .paragraphStyle: paragraphStyle
        ]

        let attributedString = NSMutableAttributedString(string: text, attributes: baseAttributes)

        // Apply entities (if any)
        guard let entities = message.entities else {
            return attributedString
        }

        let nsString = text as NSString

        for entity in entities {
            // Validate range
            guard entity.offset >= 0,
                  entity.length > 0,
                  entity.offset + entity.length <= nsString.length else {
                continue
            }

            let range = NSRange(location: entity.offset, length: entity.length)

            switch entity.type {
            case "url":
                // URL entity - make it a clickable link
                let urlString = entity.url ?? nsString.substring(with: range)
                if let url = URL(string: urlString) {
                    attributedString.addAttribute(.link, value: url, range: range)
                }

            case "text_link":
                // Text link - custom text with URL
                if let urlString = entity.url, let url = URL(string: urlString) {
                    attributedString.addAttribute(.link, value: url, range: range)
                }

            case "bold":
                attributedString.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: 16), range: range)

            case "italic":
                attributedString.addAttribute(.font, value: UIFont.italicSystemFont(ofSize: 16), range: range)

            case "underline":
                attributedString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)

            case "strikethrough":
                attributedString.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)

            case "code", "pre":
                attributedString.addAttribute(.font, value: UIFont.monospacedSystemFont(ofSize: 15, weight: .regular), range: range)
                attributedString.addAttribute(.backgroundColor, value: UIColor.systemGray5, range: range)

            default:
                break
            }
        }

        return attributedString
    }

    private func applyLayout(for message: Message, width: CGFloat) {
        let fileNames = message.photoFileNames
        let aspectRatios = message.aspectRatios
        let hasPhotos = !fileNames.isEmpty && !aspectRatios.isEmpty
        let hasText = !message.content.isEmpty

        // Reset constraints first
        messageTextViewTopToMosaic.isActive = false
        messageTextViewTopToBubble.isActive = false
        messageTextViewBottomToBubble.isActive = false
        mosaicBottomToBubble.isActive = false

        // Calculate bubble width (cell width - 32 for margins)
        let bubbleWidth = max(width - 32, 0)

        // Configure photos with mosaic layout (async loading)
        if hasPhotos {
            let mosaicHeight = MosaicMediaView.calculateHeight(for: aspectRatios, maxWidth: bubbleWidth)
            mosaicHeightConstraint.constant = mosaicHeight
            // isAtBottom: true only when there's no text below (photos-only message)
            mosaicView.configure(with: fileNames, aspectRatios: aspectRatios, maxWidth: bubbleWidth, isAtBottom: !hasText)
            mosaicView.isHidden = false
        } else {
            mosaicHeightConstraint.constant = 0
            mosaicView.isHidden = true
        }

        // Configure layout based on content
        if hasPhotos && hasText {
            // Both photos and text
            messageTextViewTopToMosaic.isActive = true
            messageTextViewBottomToBubble.isActive = true
            messageTextView.isHidden = false
        } else if hasPhotos && !hasText {
            // Photos only - mosaic fills to bottom
            mosaicBottomToBubble.isActive = true
            messageTextView.isHidden = true
        } else {
            // Text only (or empty)
            messageTextViewTopToBubble.isActive = true
            messageTextViewBottomToBubble.isActive = true
            messageTextView.isHidden = false
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
