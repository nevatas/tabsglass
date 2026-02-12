//
//  MessengerView.swift
//  tabsglass
//
//  Shared composer and message cell components used by UnifiedChatView
//

import SwiftUI
import UIKit

// MARK: - Identifiable Image Wrapper

struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

// MARK: - Attached Video Wrapper

struct AttachedVideo: Identifiable {
    let id = UUID()
    let url: URL
    let thumbnail: UIImage
    let duration: Double
}

// MARK: - Composer State (Observable)

@Observable
final class ComposerState {
    var text: String = ""
    var attributedText: NSAttributedString = NSAttributedString()
    var shouldFocus: Bool = false
    var attachedImages: [IdentifiableImage] = []
    var attachedVideos: [AttachedVideo] = []
    var textViewHeight: CGFloat = 24
    var onTextChange: ((String) -> Void)?
    var onSend: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    var onAttachmentChange: (() -> Void)?
    var onShowPhotoPicker: (() -> Void)?
    var onShowCamera: (() -> Void)?
    /// Reference to the formatting text view for extracting entities
    weak var formattingTextView: FormattingTextView?

    /// Height of media section (80 when visible, 0 when hidden)
    var mediaSectionHeight: CGFloat = 0

    /// Total count of attached media (photos + videos)
    var totalMediaCount: Int {
        attachedImages.count + attachedVideos.count
    }

    /// Whether more media can be added
    var canAddMedia: Bool {
        totalMediaCount < 10
    }

    /// Extract formatting entities from current text
    func extractEntities() -> [TextEntity] {
        return formattingTextView?.extractEntities() ?? []
    }

    func removeImage(at index: Int) {
        guard index < attachedImages.count else { return }
        let isLastMedia = totalMediaCount == 1

        if isLastMedia {
            // Last media: remove without animation
            mediaSectionHeight = 0
            attachedImages.removeAll()
        } else {
            _ = withAnimation(.easeOut(duration: 0.2)) {
                attachedImages.remove(at: index)
            }
        }
        onAttachmentChange?()
    }

    func removeImage(id: UUID) {
        guard let index = attachedImages.firstIndex(where: { $0.id == id }) else { return }
        removeImage(at: index)
    }

    func removeVideo(at index: Int) {
        guard index < attachedVideos.count else { return }
        let isLastMedia = totalMediaCount == 1

        if isLastMedia {
            // Last media: remove without animation
            mediaSectionHeight = 0
            attachedVideos.removeAll()
        } else {
            _ = withAnimation(.easeOut(duration: 0.2)) {
                attachedVideos.remove(at: index)
            }
        }
        onAttachmentChange?()
    }

    func removeVideo(id: UUID) {
        guard let index = attachedVideos.firstIndex(where: { $0.id == id }) else { return }
        removeVideo(at: index)
    }

    func addImages(_ images: [UIImage]) {
        let available = 10 - totalMediaCount
        let toAdd = images.prefix(available).map { IdentifiableImage(image: $0) }
        attachedImages.append(contentsOf: toAdd)
        // Set height when adding first media (80 + 12 spacing = 92)
        if mediaSectionHeight == 0 && totalMediaCount > 0 {
            withAnimation(.easeOut(duration: 0.25)) {
                mediaSectionHeight = 92
            }
        }
        onAttachmentChange?()
    }

    func addVideo(_ video: AttachedVideo) {
        guard canAddMedia else { return }
        attachedVideos.append(video)
        // Set height when adding first media
        if mediaSectionHeight == 0 && totalMediaCount > 0 {
            withAnimation(.easeOut(duration: 0.25)) {
                mediaSectionHeight = 92
            }
        }
        onAttachmentChange?()
    }

    func clearAttachments() {
        attachedImages.removeAll()
        attachedVideos.removeAll()
        mediaSectionHeight = 0
    }

    func clearAll() {
        text = ""
        attributedText = NSAttributedString()
        textViewHeight = 24
        formattingTextView?.clear()
        formattingTextView?.isScrollEnabled = false
        clearAttachments()
    }
}

// MARK: - SwiftUI Composer Wrapper

final class SwiftUIComposerContainer: UIView {
    var onTextChange: ((String) -> Void)?
    var onImagesChange: (([UIImage]) -> Void)?
    var onVideosChange: (([AttachedVideo]) -> Void)?
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
    /// Callback for height changes
    var onHeightChange: ((CGFloat) -> Void)?

    private let composerState = ComposerState()
    private var hostingController: UIHostingController<EmbeddedComposerView>?
    private var currentHeight: CGFloat = 102
    private var didAddToParentVC = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        setupHostingController()
        setupTextChangeHandler()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Add hosting controller to parent view controller hierarchy
        if window != nil, !didAddToParentVC, let hc = hostingController {
            if let parentVC = findViewController() {
                parentVC.addChild(hc)
                hc.didMove(toParent: parentVC)
                didAddToParentVC = true
            }
        }
    }

    private func findViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let nextResponder = responder?.next {
            if let vc = nextResponder as? UIViewController {
                return vc
            }
            responder = nextResponder
        }
        return nil
    }

    private func setupTextChangeHandler() {
        composerState.onTextChange = { [weak self] newText in
            guard let self = self else { return }
            self.onTextChange?(newText)
            self.updateHeight()
        }

        composerState.onAttachmentChange = { [weak self] in
            guard let self = self else { return }
            // Notify about images and videos change
            self.onImagesChange?(self.composerState.attachedImages.map { $0.image })
            self.onVideosChange?(self.composerState.attachedVideos)
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
        composerState.attachedImages.map { $0.image }
    }

    /// Get currently attached videos
    var attachedVideos: [AttachedVideo] {
        composerState.attachedVideos
    }

    /// Total media count (images + videos)
    var totalMediaCount: Int {
        composerState.totalMediaCount
    }

    /// Add images from picker
    func addImages(_ images: [UIImage]) {
        composerState.addImages(images)
    }

    /// Add video from picker
    func addVideo(_ video: AttachedVideo) {
        composerState.addVideo(video)
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
        if composerState.formattingTextView?.isEditMenuLayoutLocked == true {
            return currentHeight
        }
        let screenWidth = window?.windowScene?.screen.bounds.width
        let targetWidth = bounds.width > 0 ? bounds.width : (screenWidth ?? bounds.width)
        let fittingSize = hc.sizeThatFits(in: CGSize(width: targetWidth, height: .greatestFiniteMagnitude))
        return max(102, fittingSize.height)
    }

    /// Обновляет высоту и уведомляет parent
    private func updateHeight() {
        if composerState.formattingTextView?.isEditMenuLayoutLocked == true {
            return
        }
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

        // Recalculate actual height after SwiftUI has fully updated
        // Use longer delay to ensure FormattingTextView size is recalculated
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            // Force FormattingTextView to recalculate its size
            if let textView = self.composerState.formattingTextView {
                let size = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude))
                self.composerState.textViewHeight = max(24, size.height)
            }
            self.hostingController?.view.setNeedsLayout()
            self.hostingController?.view.layoutIfNeeded()
            self.updateHeight()
        }
    }

    /// Extract formatting entities from current text
    func extractEntities() -> [TextEntity] {
        return composerState.extractEntities()
    }

    /// Extract structured composer content (text blocks + todo items)
    func extractComposerContent() -> FormattingTextView.ComposerContent? {
        return composerState.formattingTextView?.extractComposerContent()
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

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var cachedWidth: CGFloat = 0
        var cachedHeight: CGFloat = 24
    }

    func makeUIView(context: Context) -> FormattingTextView {
        let textView = FormattingTextView()
        textView.placeholder = L10n.Composer.placeholder
        textView.textColor = colorScheme == .dark ? .white : .black

        textView.onTextChange = { [weak textView, self] attrText in
            state.text = attrText.string
            state.attributedText = attrText
            state.onTextChange?(attrText.string)

            guard let textView = textView else { return }
            let targetWidth = textView.bounds.width > 0 ? textView.bounds.width : 300
            let contentHeight = textView.sizeThatFits(
                CGSize(width: targetWidth, height: .greatestFiniteMagnitude)
            ).height
            let clampedHeight = max(24, min(contentHeight, maxHeight))
            if abs(state.textViewHeight - clampedHeight) > 1 {
                state.textViewHeight = clampedHeight
            }
            let shouldScroll = contentHeight > maxHeight
            if textView.isScrollEnabled != shouldScroll {
                textView.isScrollEnabled = shouldScroll
            }
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
        let desiredColor: UIColor = colorScheme == .dark ? .white : .black
        if uiView.textColor != desiredColor {
            uiView.textColor = desiredColor
        }

        // Handle focus request
        if state.shouldFocus {
            DispatchQueue.main.async {
                _ = uiView.becomeFirstResponder()
                state.shouldFocus = false
            }
        }

        // Recalculate height when width changes (rotation/layout updates).
        let currentWidth = uiView.bounds.width
        if currentWidth > 0, abs(currentWidth - context.coordinator.cachedWidth) > 1 {
            let contentHeight = uiView.sizeThatFits(
                CGSize(width: currentWidth, height: .greatestFiniteMagnitude)
            ).height
            let clampedHeight = max(24, min(contentHeight, maxHeight))
            if abs(state.textViewHeight - clampedHeight) > 1 {
                state.textViewHeight = clampedHeight
            }
            let shouldScroll = contentHeight > maxHeight
            if uiView.isScrollEnabled != shouldScroll {
                uiView.isScrollEnabled = shouldScroll
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: FormattingTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 300
        let height = max(24, min(state.textViewHeight, maxHeight))
        context.coordinator.cachedWidth = width
        context.coordinator.cachedHeight = height
        return CGSize(width: width, height: height)
    }
}

// MARK: - Embedded Composer

struct EmbeddedComposerView: View {
    @Environment(\.colorScheme) private var colorScheme
    private var themeManager: ThemeManager { ThemeManager.shared }
    @Bindable var state: ComposerState

    private var canSend: Bool {
        !state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.totalMediaCount > 0
    }

    private var hasMedia: Bool {
        state.totalMediaCount > 0
    }

    private var composerTint: Color {
        let theme = themeManager.currentTheme
        return colorScheme == .dark ? theme.composerTintColorDark : theme.composerTintColor
    }

    /// Unique ID that changes with theme to force glassEffect refresh
    private var glassId: String {
        "\(themeManager.currentTheme.rawValue)-\(colorScheme == .dark ? "dark" : "light")"
    }

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                // Spacer pushes content to bottom during shrink animation
                Spacer(minLength: 0)

                VStack(spacing: 0) {
                    // Attached media row - height includes spacing (80 + 12 = 92, or 0)
                    if hasMedia {
                        VStack(spacing: 0) {
                            ScrollView(.horizontal) {
                                LazyHStack(spacing: 8) {
                                    // Images first
                                    ForEach(state.attachedImages) { item in
                                        AttachedImageView(image: item.image) {
                                            state.removeImage(id: item.id)
                                        }
                                        .transition(.scale.combined(with: .opacity))
                                    }
                                    // Videos after
                                    ForEach(state.attachedVideos) { video in
                                        AttachedVideoView(video: video) {
                                            state.removeVideo(id: video.id)
                                        }
                                        .transition(.scale.combined(with: .opacity))
                                    }
                                }
                                .padding(.horizontal, 8)
                            }
                            .scrollIndicators(.hidden)
                            .frame(height: 80)

                            Spacer().frame(height: 12) // spacing below media
                        }
                        .frame(height: state.mediaSectionHeight > 0 ? 92 : 0)
                        .clipped()
                        .opacity(state.mediaSectionHeight > 0 ? 1 : 0)
                    }

                    // Bottom section with text field and buttons
                    VStack(spacing: 0) {
                        FormattingTextViewWrapper(state: state, colorScheme: colorScheme)

                        Spacer().frame(height: 8) // Tighter spacing between textfield and buttons

                        HStack {
                            Menu {
                                Button {
                                    state.onShowPhotoPicker?()
                                } label: {
                                    Label(L10n.Composer.gallery, systemImage: "photo.on.rectangle")
                                }

                                Button {
                                    state.onShowCamera?()
                                } label: {
                                    Label(L10n.Composer.camera, systemImage: "camera")
                                }
                            } label: {
                                Image(systemName: "plus")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(themeManager.currentTheme.accentColor ?? (colorScheme == .dark ? .white : .black))
                                    .padding(.vertical, 8)
                                    .padding(.trailing, 12)
                                    .contentShape(Rectangle())
                            }

                            Button {
                                state.formattingTextView?.insertCheckbox()
                            } label: {
                                Image(systemName: "checkmark.circle")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(themeManager.currentTheme.accentColor ?? (colorScheme == .dark ? .white : .black))
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
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
                                    .background(canSend ? (themeManager.currentTheme.accentColor ?? Color.accentColor) : Color.gray.opacity(0.4))
                                    .clipShape(Circle())
                            }
                            .disabled(!canSend)
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.top, hasMedia ? 8 : 14)
            .padding(.bottom, 10)
            .contentShape(.rect(cornerRadius: 24))
            .onTapGesture {
                state.shouldFocus = true
            }
            .clipShape(.rect(cornerRadius: 24))
            .glassEffect(
                .regular.tint(composerTint).interactive(),
                in: .rect(cornerRadius: 24)
            )
            .id(glassId)  // Force recreation when theme changes
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
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .allowsHitTesting(false)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .zIndex(1)
            .padding(6)
        }
        .frame(width: 80, height: 80)
    }
}

// MARK: - Attached Video View

struct AttachedVideoView: View {
    let video: AttachedVideo
    let onRemove: () -> Void

    private var formattedDuration: String {
        let totalSeconds = Int(video.duration)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Thumbnail
            Image(uiImage: video.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .allowsHitTesting(false)

            // Play icon overlay (center)
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 28, height: 28)
                Image(systemName: "play.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .offset(x: 1) // Visual balance
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)

            // Duration badge (bottom right)
            Text(formattedDuration)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(6)
                .allowsHitTesting(false)

            // Remove button (top right)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .zIndex(1)
            .padding(6)
        }
        .frame(width: 80, height: 80)
    }
}

// MARK: - Fade Gradient View

private final class FadeGradientView: UIView {
    let gradientLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(gradientLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }
}

// MARK: - Message Cell

final class MessageTableCell: UITableViewCell {
    private let bubbleContainer = UIView()
    private let bubbleView = UIView()

    /// Public access to bubble container (includes reminder badge) for context menu
    var bubbleViewForContextMenu: UIView { bubbleContainer }

    // Selection mode
    private let checkboxView = UIImageView()
    private var bubbleContainerLeadingNormal: NSLayoutConstraint!
    private var bubbleContainerLeadingSelection: NSLayoutConstraint!
    var onSelectionToggle: ((Bool) -> Void)?
    private var isInSelectionMode = false
    private var isMessageSelected = false
    private var selectionTapGesture: UITapGestureRecognizer?
    private let mosaicView = MosaicMediaView()
    private let messageTextView = UITextView()
    private let todoView = TodoBubbleView()
    private let mixedContentView = MixedContentView()
    private let reminderBadge = UIView()
    private let reminderIcon = UIImageView()

    private let showMoreButton = UIButton(type: .system)
    private let fadeGradientView = FadeGradientView()
    private var messageTextViewHeightConstraint: NSLayoutConstraint!
    private var showMoreTopToText: NSLayoutConstraint!
    private var showMoreBottomToBubble: NSLayoutConstraint!
    private var isExpanded: Bool = false
    var onShowMoreTapped: (() -> Void)?

    private var cachedMessage: Message?
    private var lastLayoutWidth: CGFloat = 0

    /// Callback when a photo is tapped: (index, sourceFrame in window, image, fileNames)
    var onPhotoTapped: ((Int, CGRect, UIImage, [String]) -> Void)?

    /// Callback when media is tapped (supports both photos and videos)
    var onMediaTapped: ((Int, CGRect, UIImage, [String], Bool) -> Void)?

    /// Callback when a todo item is toggled: (itemId, isCompleted)
    var onTodoToggle: ((UUID, Bool) -> Void)?

    private var mixedContentTopToMosaic: NSLayoutConstraint!
    private var mixedContentTopToBubble: NSLayoutConstraint!
    private var mixedContentBottomToBubble: NSLayoutConstraint!
    private var mixedContentHeightConstraint: NSLayoutConstraint!
    private var messageTextViewTopToMosaic: NSLayoutConstraint!
    private var messageTextViewTopToBubble: NSLayoutConstraint!
    private var messageTextViewBottomToBubble: NSLayoutConstraint!
    private var mosaicHeightConstraint: NSLayoutConstraint!
    private var mosaicBottomToBubble: NSLayoutConstraint!
    private var todoViewHeightConstraint: NSLayoutConstraint!
    private var todoViewBottomToBubble: NSLayoutConstraint!
    private var bubbleContainerTopConstraint: NSLayoutConstraint!
    private var traitChangeRegistration: UITraitChangeRegistration?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
        registerTraitChanges()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func registerTraitChanges() {
        traitChangeRegistration = registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (cell: MessageTableCell, _) in
            self?.updateBubbleColor()
            guard let message = self?.cachedMessage else { return }
            let isDarkMode = cell.traitCollection.userInterfaceStyle == .dark
            if message.hasContentBlocks, let blocks = message.contentBlocks {
                let bubbleWidth = max(cell.contentView.bounds.width - 32, 0)
                self?.mixedContentView.configure(with: blocks, isDarkMode: isDarkMode, maxWidth: bubbleWidth)
            } else if message.isTodoList, let items = message.todoItems {
                self?.todoView.configure(with: message.todoTitle, items: items, isDarkMode: isDarkMode)
            }
        }
    }

    private func setupCell() {
        backgroundColor = .clear
        selectionStyle = .none
        clipsToBounds = false
        layer.masksToBounds = false
        contentView.clipsToBounds = false
        contentView.layer.masksToBounds = false

        // Checkbox for selection mode (hidden by default)
        checkboxView.translatesAutoresizingMaskIntoConstraints = false
        checkboxView.contentMode = .scaleAspectFit
        if let accentColor = ThemeManager.shared.currentTheme.accentColor {
            checkboxView.tintColor = UIColor(accentColor)
        } else {
            checkboxView.tintColor = .systemBlue
        }
        checkboxView.isHidden = true
        checkboxView.alpha = 0
        checkboxView.isUserInteractionEnabled = true
        checkboxView.image = UIImage(systemName: "circle")
        contentView.addSubview(checkboxView)

        let checkboxTap = UITapGestureRecognizer(target: self, action: #selector(checkboxTapped))
        checkboxView.addGestureRecognizer(checkboxTap)

        // Tap gesture for whole cell in selection mode
        selectionTapGesture = UITapGestureRecognizer(target: self, action: #selector(cellTappedInSelectionMode))
        selectionTapGesture?.isEnabled = false
        contentView.addGestureRecognizer(selectionTapGesture!)

        // Container for bubble + reminder badge (used for context menu preview)
        bubbleContainer.translatesAutoresizingMaskIntoConstraints = false
        bubbleContainer.clipsToBounds = false
        contentView.addSubview(bubbleContainer)

        bubbleView.layer.cornerRadius = 18
        bubbleView.clipsToBounds = true
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        bubbleContainer.addSubview(bubbleView)

        // Reminder badge (positioned on top-right corner of bubble, slightly outside)
        reminderBadge.backgroundColor = .systemRed
        reminderBadge.layer.cornerRadius = 12
        reminderBadge.layer.zPosition = 1000  // Render above adjacent cells
        reminderBadge.translatesAutoresizingMaskIntoConstraints = false
        reminderBadge.isHidden = true
        bubbleContainer.addSubview(reminderBadge)

        let bellConfig = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        reminderIcon.image = UIImage(systemName: "bell.fill", withConfiguration: bellConfig)
        reminderIcon.tintColor = .white
        reminderIcon.translatesAutoresizingMaskIntoConstraints = false
        reminderBadge.addSubview(reminderIcon)

        NSLayoutConstraint.activate([
            // Bubble fills container with symmetric padding (for context menu preview)
            bubbleView.topAnchor.constraint(equalTo: bubbleContainer.topAnchor, constant: 8),
            bubbleView.bottomAnchor.constraint(equalTo: bubbleContainer.bottomAnchor, constant: -8),
            bubbleView.leadingAnchor.constraint(equalTo: bubbleContainer.leadingAnchor, constant: 8),
            bubbleView.trailingAnchor.constraint(equalTo: bubbleContainer.trailingAnchor, constant: -8),

            reminderBadge.widthAnchor.constraint(equalToConstant: 24),
            reminderBadge.heightAnchor.constraint(equalToConstant: 24),
            reminderBadge.topAnchor.constraint(equalTo: bubbleContainer.topAnchor),
            reminderBadge.trailingAnchor.constraint(equalTo: bubbleContainer.trailingAnchor),
            reminderIcon.centerXAnchor.constraint(equalTo: reminderBadge.centerXAnchor),
            reminderIcon.centerYAnchor.constraint(equalTo: reminderBadge.centerYAnchor),
        ])

        // Mosaic media view
        mosaicView.translatesAutoresizingMaskIntoConstraints = false
        mosaicView.onMediaTapped = { [weak self] index, sourceFrame, image, fileNames, isVideo in
            self?.onMediaTapped?(index, sourceFrame, image, fileNames, isVideo)
            // Backward compatibility
            if !isVideo {
                self?.onPhotoTapped?(index, sourceFrame, image, fileNames)
            }
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
            .foregroundColor: ThemeManager.shared.currentTheme.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        messageTextView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.addSubview(messageTextView)

        // Todo view for task lists
        todoView.translatesAutoresizingMaskIntoConstraints = false
        todoView.onToggle = { [weak self] itemId, isCompleted in
            self?.onTodoToggle?(itemId, isCompleted)
        }
        bubbleView.addSubview(todoView)

        // Mixed content view for ordered text + todo blocks
        mixedContentView.translatesAutoresizingMaskIntoConstraints = false
        mixedContentView.isHidden = true
        bubbleView.addSubview(mixedContentView)

        // Fade gradient overlay for truncated messages (added before button so button is on top)
        fadeGradientView.translatesAutoresizingMaskIntoConstraints = false
        fadeGradientView.isHidden = true
        fadeGradientView.isUserInteractionEnabled = false
        fadeGradientView.gradientLayer.locations = [0.0, 1.0]
        bubbleView.addSubview(fadeGradientView)

        // Show more button for long messages
        showMoreButton.setTitle(L10n.Message.showMore, for: .normal)
        showMoreButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        showMoreButton.contentHorizontalAlignment = .leading
        showMoreButton.translatesAutoresizingMaskIntoConstraints = false
        showMoreButton.isHidden = true
        showMoreButton.addTarget(self, action: #selector(showMoreTapped), for: .touchUpInside)
        bubbleView.addSubview(showMoreButton)

        mosaicHeightConstraint = mosaicView.heightAnchor.constraint(equalToConstant: 0)
        mosaicHeightConstraint.priority = UILayoutPriority(999)  // Slightly lower to avoid conflict with encapsulated height
        todoViewHeightConstraint = todoView.heightAnchor.constraint(equalToConstant: 0)
        todoViewBottomToBubble = todoView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor)
        messageTextViewTopToMosaic = messageTextView.topAnchor.constraint(equalTo: mosaicView.bottomAnchor, constant: 10)
        messageTextViewTopToBubble = messageTextView.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10)
        messageTextViewBottomToBubble = messageTextView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -10)
        mosaicBottomToBubble = mosaicView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor)

        // Mixed content view constraints
        mixedContentTopToMosaic = mixedContentView.topAnchor.constraint(equalTo: mosaicView.bottomAnchor)
        mixedContentTopToBubble = mixedContentView.topAnchor.constraint(equalTo: bubbleView.topAnchor)
        mixedContentBottomToBubble = mixedContentView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor)
        mixedContentHeightConstraint = mixedContentView.heightAnchor.constraint(equalToConstant: 0)
        mixedContentHeightConstraint.priority = UILayoutPriority(999)

        // Show more button constraints
        showMoreTopToText = showMoreButton.topAnchor.constraint(equalTo: messageTextView.bottomAnchor, constant: 4)
        showMoreBottomToBubble = showMoreButton.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -8)

        // Height constraint for collapsing long messages (inactive by default)
        messageTextViewHeightConstraint = messageTextView.heightAnchor.constraint(equalToConstant: 0)
        messageTextViewHeightConstraint.priority = UILayoutPriority(999)
        messageTextViewHeightConstraint.isActive = false

        // Two variants of leading constraint for bubble container
        bubbleContainerLeadingNormal = bubbleContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8)
        bubbleContainerLeadingSelection = bubbleContainer.leadingAnchor.constraint(equalTo: checkboxView.trailingAnchor, constant: 4)
        // Top constraint adjustable for messages with reminders (need extra space at top)
        bubbleContainerTopConstraint = bubbleContainer.topAnchor.constraint(equalTo: contentView.topAnchor, constant: -4)

        NSLayoutConstraint.activate([
            // Checkbox constraints
            checkboxView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            checkboxView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            checkboxView.widthAnchor.constraint(equalToConstant: 28),
            checkboxView.heightAnchor.constraint(equalToConstant: 28),

            // Container positioned to keep bubble in same place as before (with symmetric 8pt padding)
            // bubble.top = container.top + 8, so container.top = contentView.top + 4 - 8 = -4
            // For messages with reminders, we use contentView.top + 4 instead (extra 8pt for badge)
            bubbleContainerTopConstraint,
            // bubble.bottom = container.bottom - 8, so container.bottom = contentView.bottom - 4 + 8 = +4
            bubbleContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: 4),
            // bubble.trailing = container.trailing - 8, so container.trailing = contentView.trailing - 16 + 8 = -8
            bubbleContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),

            // Mosaic view
            mosaicView.topAnchor.constraint(equalTo: bubbleView.topAnchor),
            mosaicView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor),
            mosaicView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor),
            mosaicHeightConstraint,

            // Message text view - horizontal constraints always active
            messageTextView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 14),
            messageTextView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -14),

            // Todo view constraints
            todoView.topAnchor.constraint(equalTo: bubbleView.topAnchor),
            todoView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor),
            todoView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor),
            todoViewHeightConstraint,

            // Mixed content view constraints (horizontal always active)
            mixedContentView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor),
            mixedContentView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor),
            mixedContentHeightConstraint,

            // Fade gradient constraints — covers bottom of text area + button
            fadeGradientView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor),
            fadeGradientView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor),
            fadeGradientView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor),
            fadeGradientView.heightAnchor.constraint(equalToConstant: 100),

            // Show more button constraints (horizontal only — vertical managed dynamically)
            showMoreButton.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 14),
            showMoreButton.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -14),
        ])

        // Activate normal leading constraint by default
        bubbleContainerLeadingNormal.isActive = true

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

    @objc private func checkboxTapped() {
        toggleSelection()
    }

    @objc private func cellTappedInSelectionMode() {
        toggleSelection()
    }

    private func toggleSelection() {
        isMessageSelected.toggle()
        setSelected(isMessageSelected)
        onSelectionToggle?(isMessageSelected)
    }

    // MARK: - Selection Mode

    func setSelectionMode(_ enabled: Bool, animated: Bool) {
        isInSelectionMode = enabled
        selectionTapGesture?.isEnabled = enabled

        // Disable interaction on inner views so taps pass through to cell
        bubbleContainer.isUserInteractionEnabled = !enabled
        messageTextView.isUserInteractionEnabled = !enabled
        mosaicView.isUserInteractionEnabled = !enabled
        todoView.isUserInteractionEnabled = !enabled
        mixedContentView.isUserInteractionEnabled = !enabled

        let changes = {
            self.checkboxView.isHidden = !enabled
            self.checkboxView.alpha = enabled ? 1 : 0
            self.bubbleContainerLeadingNormal.isActive = !enabled
            self.bubbleContainerLeadingSelection.isActive = enabled
            self.contentView.layoutIfNeeded()
        }

        if animated {
            UIView.animate(withDuration: 0.25, animations: changes)
        } else {
            changes()
        }
    }

    func setSelected(_ selected: Bool) {
        isMessageSelected = selected
        let imageName = selected ? "checkmark.circle.fill" : "circle"
        checkboxView.image = UIImage(systemName: imageName)
    }

    @objc private func handleThemeChange() {
        updateBubbleColor()
        updateCheckboxColor()
        updateShowMoreButtonColor()
    }

    private func updateCheckboxColor() {
        if let accentColor = ThemeManager.shared.currentTheme.accentColor {
            checkboxView.tintColor = UIColor(accentColor)
        } else {
            checkboxView.tintColor = .systemBlue
        }
    }

    private func updateBubbleColor() {
        let theme = ThemeManager.shared.currentTheme
        let bubbleColor: UIColor
        if traitCollection.userInterfaceStyle == .dark {
            bubbleColor = theme.bubbleColorDark
            messageTextView.textColor = .white
        } else {
            bubbleColor = theme.bubbleColor
            messageTextView.textColor = .black
        }
        bubbleView.backgroundColor = bubbleColor
        // Update fade gradient colors
        updateFadeGradientColors()
        // Update link color for current theme
        messageTextView.linkTextAttributes = [
            .foregroundColor: theme.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
    }

    private func updateFadeGradientColors() {
        let theme = ThemeManager.shared.currentTheme
        let bgColor: UIColor
        if traitCollection.userInterfaceStyle == .dark {
            bgColor = UIColor(theme.backgroundColorDark)
        } else {
            bgColor = UIColor(theme.backgroundColor)
        }
        fadeGradientView.gradientLayer.colors = [
            bgColor.withAlphaComponent(0).cgColor,
            bgColor.cgColor
        ]
    }

    private func updateShowMoreButtonColor() {
        let theme = ThemeManager.shared.currentTheme
        if let accent = theme.accentColor {
            showMoreButton.setTitleColor(UIColor(accent), for: .normal)
        } else {
            showMoreButton.setTitleColor(.systemBlue, for: .normal)
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

    @objc private func showMoreTapped() {
        onShowMoreTapped?()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        cachedMessage = nil
        lastLayoutWidth = 0
        reminderBadge.isHidden = true
        // Reset constraints
        messageTextViewTopToMosaic.isActive = false
        messageTextViewTopToBubble.isActive = false
        messageTextViewBottomToBubble.isActive = false
        mosaicBottomToBubble.isActive = false
        todoViewBottomToBubble.isActive = false
        showMoreTopToText.isActive = false
        showMoreBottomToBubble.isActive = false
        messageTextViewHeightConstraint.isActive = false
        // Reset mixed content constraints
        mixedContentTopToMosaic.isActive = false
        mixedContentTopToBubble.isActive = false
        mixedContentBottomToBubble.isActive = false
        mixedContentView.isHidden = true
        // Reset show more state
        isExpanded = false
        showMoreButton.isHidden = true
        fadeGradientView.isHidden = true
        messageTextView.textContainer.maximumNumberOfLines = 0
        onShowMoreTapped = nil
        // Reset selection state
        isMessageSelected = false
        checkboxView.image = UIImage(systemName: "circle")
        onSelectionToggle = nil
    }

    func configure(with message: Message, isExpanded: Bool = false) {
        cachedMessage = message
        self.isExpanded = isExpanded

        // Create attributed string with entities (links, formatting)
        let attributedText = createAttributedString(for: message)
        messageTextView.attributedText = attributedText

        // Configure mixed content view if message uses content blocks
        if message.hasContentBlocks, let blocks = message.contentBlocks {
            let isDarkMode = traitCollection.userInterfaceStyle == .dark
            let bubbleWidth = max(contentView.bounds.width - 32, 0)
            mixedContentView.configure(with: blocks, isDarkMode: isDarkMode, maxWidth: bubbleWidth)
            mixedContentView.onTodoToggle = { [weak self] itemId, isCompleted in
                self?.onTodoToggle?(itemId, isCompleted)
            }
        }

        // Configure todo view if this is a todo list (old format)
        if !message.hasContentBlocks && message.isTodoList, let items = message.todoItems {
            let isDarkMode = traitCollection.userInterfaceStyle == .dark
            todoView.configure(with: message.todoTitle, items: items, isDarkMode: isDarkMode)
        }

        // Show/hide reminder badge (floating — no layout impact on cell height)
        reminderBadge.isHidden = !message.hasReminder

        updateBubbleColor()
        updateShowMoreButtonColor()

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
        let aspectRatios = message.aspectRatios
        let hasMedia = message.hasMedia && !aspectRatios.isEmpty
        let hasText = !message.content.isEmpty
        let hasTodo = message.isTodoList

        // Reset constraints first
        messageTextViewTopToMosaic.isActive = false
        messageTextViewTopToBubble.isActive = false
        messageTextViewBottomToBubble.isActive = false
        mosaicBottomToBubble.isActive = false
        todoViewBottomToBubble.isActive = false
        showMoreTopToText.isActive = false
        showMoreBottomToBubble.isActive = false
        messageTextViewHeightConstraint.isActive = false
        mixedContentTopToMosaic.isActive = false
        mixedContentTopToBubble.isActive = false
        mixedContentBottomToBubble.isActive = false

        // Calculate bubble width (cell width - 32 for margins)
        let bubbleWidth = max(width - 32, 0)

        // Configure media with mosaic layout (async loading)
        if hasMedia {
            let mosaicHeight = MosaicMediaView.calculateHeight(for: aspectRatios, maxWidth: bubbleWidth)
            mosaicHeightConstraint.constant = mosaicHeight

            // Build MediaItems array (photos first, then videos)
            var mediaItems: [MediaItem] = []
            for fileName in message.photoFileNames {
                mediaItems.append(.photo(fileName))
            }
            for (index, fileName) in message.videoFileNames.enumerated() {
                let thumbnailFileName = index < message.videoThumbnailFileNames.count
                    ? message.videoThumbnailFileNames[index]
                    : ""
                let duration = index < message.videoDurations.count
                    ? message.videoDurations[index]
                    : 0
                mediaItems.append(.video(fileName, thumbnailFileName: thumbnailFileName, duration: duration))
            }

            // isAtBottom: true only when there's no text below (media-only message)
            mosaicView.configure(with: mediaItems, aspectRatios: aspectRatios, maxWidth: bubbleWidth, isAtBottom: !hasText && !hasTodo)
            mosaicView.isHidden = false
        } else {
            mosaicHeightConstraint.constant = 0
            mosaicView.isHidden = true
        }

        // Mixed content with ordered blocks (new format)
        if message.hasContentBlocks, let blocks = message.contentBlocks {
            let mixedHeight = MixedContentView.calculateHeight(for: blocks, maxWidth: bubbleWidth)
            mixedContentHeightConstraint.constant = mixedHeight
            mixedContentView.isHidden = false
            messageTextView.isHidden = true
            todoView.isHidden = true
            todoViewHeightConstraint.constant = 0
            showMoreButton.isHidden = true
            fadeGradientView.isHidden = true

            if hasMedia {
                mixedContentTopToMosaic.isActive = true
            } else {
                mixedContentTopToBubble.isActive = true
            }
            mixedContentBottomToBubble.isActive = true
            return
        }

        // Configure todo view (old format)
        if hasTodo, let items = message.todoItems {
            let todoHeight = TodoBubbleView.calculateHeight(for: message.todoTitle, items: items, maxWidth: bubbleWidth)
            todoViewHeightConstraint.constant = todoHeight
            todoView.isHidden = false
            todoViewBottomToBubble.isActive = true
            // Hide text and mosaic for todo lists
            messageTextView.isHidden = true
            mosaicView.isHidden = true
            mosaicHeightConstraint.constant = 0
        } else {
            todoViewHeightConstraint.constant = 0
            todoView.isHidden = true

            // Configure layout based on content
            if hasMedia && hasText {
                // Both media and text
                messageTextViewTopToMosaic.isActive = true
                messageTextView.isHidden = false
                if applyShowMoreIfNeeded(bubbleWidth: bubbleWidth) {
                    // Show more button handles bottom constraint
                } else {
                    messageTextViewBottomToBubble.isActive = true
                }
            } else if hasMedia && !hasText {
                // Media only - mosaic fills to bottom
                mosaicBottomToBubble.isActive = true
                messageTextView.isHidden = true
                showMoreButton.isHidden = true
            } else {
                // Text only (or empty)
                messageTextViewTopToBubble.isActive = true
                messageTextView.isHidden = false
                if applyShowMoreIfNeeded(bubbleWidth: bubbleWidth) {
                    // Show more button handles bottom constraint
                } else {
                    messageTextViewBottomToBubble.isActive = true
                }
            }
        }
    }

    /// Check if text needs truncation and configure show more button.
    /// Returns true if collapsed mode was activated.
    private func applyShowMoreIfNeeded(bubbleWidth: CGFloat) -> Bool {
        let textWidth = bubbleWidth - 28 // 14px padding on each side
        guard textWidth > 0 else { return false }

        let maxCollapsedHeight = Self.maxCollapsedTextHeight(for: textWidth)
        let fullTextHeight = messageTextView.attributedText?.boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).height ?? 0

        // Only applies to long messages
        guard ceil(fullTextHeight) > maxCollapsedHeight else {
            messageTextView.textContainer.maximumNumberOfLines = 0
            messageTextViewHeightConstraint.isActive = false
            showMoreButton.isHidden = true
            fadeGradientView.isHidden = true
            return false
        }

        if !isExpanded {
            // Collapsed mode
            messageTextView.textContainer.maximumNumberOfLines = Self.collapsedLineCount
            messageTextView.textContainer.lineBreakMode = .byTruncatingTail
            messageTextViewHeightConstraint.constant = maxCollapsedHeight
            messageTextViewHeightConstraint.isActive = true
            showMoreButton.setTitle(L10n.Message.showMore, for: .normal)
            fadeGradientView.isHidden = false
            updateFadeGradientColors()
        } else {
            // Expanded mode — full text with "Show less"
            messageTextView.textContainer.maximumNumberOfLines = 0
            messageTextViewHeightConstraint.isActive = false
            showMoreButton.setTitle(L10n.Message.showLess, for: .normal)
            fadeGradientView.isHidden = true
        }

        showMoreButton.isHidden = false
        showMoreTopToText.isActive = true
        showMoreBottomToBubble.isActive = true
        return true
    }

    // MARK: - Show More Helpers

    static let collapsedLineCount = 25
    /// Cached (textWidth → height) so we don't recompute boundingRect for every cell
    private static var _collapsedHeightCache: (width: CGFloat, height: CGFloat)?

    static func maxCollapsedTextHeight(for textWidth: CGFloat) -> CGFloat {
        if let cached = _collapsedHeightCache, abs(cached.width - textWidth) < 0.5 {
            return cached.height
        }
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        let referenceText = String(repeating: "A\n", count: collapsedLineCount - 1) + "A"
        let height = ceil(referenceText.boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: UIFont.systemFont(ofSize: 16), .paragraphStyle: paragraphStyle],
            context: nil
        ).height)
        _collapsedHeightCache = (textWidth, height)
        return height
    }
}

// MARK: - Empty Cell

final class EmptyTableCell: UITableViewCell {
    private let stackView = UIStackView()
    private let emojiLabel = UILabel()
    private static let fallbackEmojis = ["🤔", "👋", "🤙", "👀", "👻", "🥰", "🤭", "🤗", "🧠", "🩵", "❤️", "💛"]

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(tabTitle: String?) {
        if let firstEmoji = tabTitle?.first(where: { $0.isEmoji }) {
            emojiLabel.text = String(firstEmoji)
        }
        // Otherwise keep the random emoji assigned in setupCell (stable across reloadData)
    }

    private func setupCell() {
        backgroundColor = .clear
        selectionStyle = .none

        emojiLabel.text = Self.fallbackEmojis.randomElement()
        emojiLabel.font = .systemFont(ofSize: 48)
        emojiLabel.textAlignment = .center

        let titleLabel = UILabel()
        titleLabel.text = L10n.Empty.title
        titleLabel.textColor = .label
        let bodyDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
        titleLabel.font = UIFont.systemFont(ofSize: bodyDescriptor.pointSize, weight: .semibold)

        let subtitleLabel = UILabel()
        subtitleLabel.text = L10n.Empty.subtitle
        subtitleLabel.textColor = .label.withAlphaComponent(0.5)
        subtitleLabel.font = .preferredFont(forTextStyle: .body)

        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 8
        stackView.addArrangedSubview(emojiLabel)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }
}

// MARK: - Mixed Content View (ordered text + todo blocks)

final class MixedContentView: UIView {
    var onTodoToggle: ((UUID, Bool) -> Void)?
    private let stackView = UIStackView()
    private var checkboxRows: [TodoCheckboxRow] = []
    private var currentBlocks: [ContentBlock]?
    private var topConstraint: NSLayoutConstraint?
    private var bottomConstraint: NSLayoutConstraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        stackView.axis = .vertical
        stackView.spacing = 0
        stackView.alignment = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        let top = stackView.topAnchor.constraint(equalTo: topAnchor, constant: 8)
        let bottom = stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        topConstraint = top
        bottomConstraint = bottom
        NSLayoutConstraint.activate([
            top,
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            bottom,
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with blocks: [ContentBlock], isDarkMode: Bool, maxWidth: CGFloat) {
        // Animation guard: if a checkbox is mid-animation and block count unchanged, skip rebuild
        if let current = currentBlocks, current.count == blocks.count && checkboxRows.contains(where: { $0.isAnimating }) {
            currentBlocks = blocks
            return
        }
        currentBlocks = blocks

        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        checkboxRows.removeAll()

        // Less padding when adjacent block is a todo (checkbox has its own vertical padding)
        topConstraint?.constant = (blocks.first?.type == "todo") ? 4 : 8
        bottomConstraint?.constant = (blocks.last?.type == "todo") ? -4 : -8

        let textColor: UIColor = isDarkMode ? .white : .black
        var previousBlockType: String?

        for block in blocks {
            switch block.type {
            case "text":
                let textView = UITextView()
                textView.backgroundColor = .clear
                textView.isEditable = false
                textView.isScrollEnabled = false
                textView.isSelectable = true
                textView.dataDetectorTypes = []
                textView.textContainerInset = UIEdgeInsets(top: 4, left: 2, bottom: 4, right: 2)
                textView.textContainer.lineFragmentPadding = 0
                textView.linkTextAttributes = [
                    .foregroundColor: ThemeManager.shared.currentTheme.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ]
                textView.textColor = textColor
                textView.font = .systemFont(ofSize: 16)

                // Build attributed string with entities
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.lineSpacing = 2
                let baseAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 16),
                    .foregroundColor: textColor,
                    .paragraphStyle: paragraphStyle
                ]
                let attrStr = NSMutableAttributedString(string: block.text, attributes: baseAttrs)

                if let entities = block.entities {
                    let nsString = block.text as NSString
                    for entity in entities {
                        guard entity.offset >= 0, entity.length > 0,
                              entity.offset + entity.length <= nsString.length else { continue }
                        let range = NSRange(location: entity.offset, length: entity.length)
                        switch entity.type {
                        case "url":
                            let urlString = entity.url ?? nsString.substring(with: range)
                            if let url = URL(string: urlString) {
                                attrStr.addAttribute(.link, value: url, range: range)
                            }
                        case "text_link":
                            if let urlString = entity.url, let url = URL(string: urlString) {
                                attrStr.addAttribute(.link, value: url, range: range)
                            }
                        case "bold":
                            attrStr.addAttribute(.font, value: UIFont.boldSystemFont(ofSize: 16), range: range)
                        case "italic":
                            attrStr.addAttribute(.font, value: UIFont.italicSystemFont(ofSize: 16), range: range)
                        case "underline":
                            attrStr.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                        case "strikethrough":
                            attrStr.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                        default: break
                        }
                    }
                }

                textView.attributedText = attrStr
                textView.translatesAutoresizingMaskIntoConstraints = false

                // Calculate height
                let textWidth = maxWidth - 28
                let textHeight = attrStr.boundingRect(
                    with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                ).height

                let heightConstraint = textView.heightAnchor.constraint(equalToConstant: ceil(textHeight) + 8)
                heightConstraint.priority = UILayoutPriority(999)
                heightConstraint.isActive = true

                stackView.addArrangedSubview(textView)
                previousBlockType = "text"

            case "todo":
                // Add separator between consecutive todo items
                if previousBlockType == "todo" {
                    stackView.addArrangedSubview(createSeparator(isDarkMode: isDarkMode))
                }

                let row = TodoCheckboxRow()
                let item = TodoItem(id: block.id, text: block.text, isCompleted: block.isCompleted)
                row.configure(with: item, isDarkMode: isDarkMode, entities: block.entities)
                row.onToggle = { [weak self] itemId, isCompleted in
                    self?.onTodoToggle?(itemId, isCompleted)
                }
                row.translatesAutoresizingMaskIntoConstraints = false

                // Set explicit height to match calculateHeight and prevent stack stretching
                let availableWidth = maxWidth - 24
                let todoHeight = TodoCheckboxRow.calculateHeight(for: block.text, maxWidth: availableWidth, entities: block.entities)
                let todoHeightConstraint = row.heightAnchor.constraint(equalToConstant: todoHeight)
                todoHeightConstraint.priority = UILayoutPriority(999)
                todoHeightConstraint.isActive = true

                stackView.addArrangedSubview(row)
                checkboxRows.append(row)
                previousBlockType = "todo"

            default:
                break
            }
        }
    }

    private func createSeparator(isDarkMode: Bool) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let line = UIView()
        line.backgroundColor = isDarkMode ? UIColor.white.withAlphaComponent(0.15) : UIColor.black.withAlphaComponent(0.1)
        line.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(line)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 1),
            line.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 40),
            line.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            line.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            line.heightAnchor.constraint(equalToConstant: 0.5)
        ])
        return container
    }

    static func calculateHeight(for blocks: [ContentBlock], maxWidth: CGFloat) -> CGFloat {
        var height: CGFloat = 0
        let horizontalPadding: CGFloat = 24  // 12 + 12 for todo rows
        let availableWidth = maxWidth - horizontalPadding
        var previousBlockType: String?

        for block in blocks {
            switch block.type {
            case "text":
                let textWidth = maxWidth - 28
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.lineSpacing = 2
                let textHeight = block.text.boundingRect(
                    with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: UIFont.systemFont(ofSize: 16), .paragraphStyle: paragraphStyle],
                    context: nil
                ).height
                height += ceil(textHeight) + 8  // 4 top + 4 bottom inset
                previousBlockType = "text"
            case "todo":
                if previousBlockType == "todo" {
                    height += 1  // separator
                }
                height += TodoCheckboxRow.calculateHeight(for: block.text, maxWidth: availableWidth, entities: block.entities)
                previousBlockType = "todo"
            default:
                break
            }
        }

        let topPadding: CGFloat = (blocks.first?.type == "todo") ? 4 : 8
        let bottomPadding: CGFloat = (blocks.last?.type == "todo") ? 4 : 8
        height += topPadding + bottomPadding
        return height
    }
}

// MARK: - Search Result Cell

final class SearchResultCell: UITableViewCell {
    private let tabNameLabel = UILabel()
    private let messageLabel = UILabel()
    private let thumbnailStack = UIStackView()

    private let glassBackgroundView: UIVisualEffectView = {
        let effect = UIGlassEffect()
        let view = UIVisualEffectView(effect: effect)
        view.layer.cornerRadius = 16
        view.clipsToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private static let thumbnailSize: CGFloat = 36
    private static let maxVisibleThumbnails = 5
    private static let cardHorizontalInset: CGFloat = 12
    private static let cardVerticalInset: CGFloat = 4
    private static let contentPadding: CGFloat = 14

    var onTap: (() -> Void)?

    // Store for theme updates
    private var currentMessage: Message?
    private var currentTabName: String?

    // Dynamic constraints
    private var labelBottomWithoutMedia: NSLayoutConstraint!
    private var labelBottomWithMedia: NSLayoutConstraint!
    private var thumbnailStackHeight: NSLayoutConstraint!
    private var labelTopNormal: NSLayoutConstraint!

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupCell()

        // Listen for theme changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: .themeDidChange,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func themeDidChange() {
        tabNameLabel.textColor = ThemeManager.shared.currentTheme.placeholderColor
        // Reconfigure to update attributed string colors (e.g., "+N more" in task lists)
        if let message = currentMessage, let tabName = currentTabName {
            configure(with: message, tabName: tabName)
        }
    }

    private func setupCell() {
        backgroundColor = .clear
        selectionStyle = .none

        // Glass card background
        contentView.addSubview(glassBackgroundView)
        let glassContent = glassBackgroundView.contentView

        // Tab name label
        tabNameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        tabNameLabel.textColor = ThemeManager.shared.currentTheme.placeholderColor
        tabNameLabel.translatesAutoresizingMaskIntoConstraints = false
        glassContent.addSubview(tabNameLabel)

        // Message text label
        messageLabel.font = .systemFont(ofSize: 16)
        messageLabel.textColor = .label
        messageLabel.numberOfLines = 3
        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        glassContent.addSubview(messageLabel)

        // Thumbnail horizontal stack
        thumbnailStack.axis = .horizontal
        thumbnailStack.spacing = 6
        thumbnailStack.alignment = .center
        thumbnailStack.translatesAutoresizingMaskIntoConstraints = false
        glassContent.addSubview(thumbnailStack)

        // Create dynamic constraints
        labelBottomWithoutMedia = messageLabel.bottomAnchor.constraint(equalTo: glassContent.bottomAnchor, constant: -12)
        labelBottomWithMedia = thumbnailStack.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 8)
        thumbnailStackHeight = thumbnailStack.heightAnchor.constraint(equalToConstant: Self.thumbnailSize)
        labelTopNormal = messageLabel.topAnchor.constraint(equalTo: tabNameLabel.bottomAnchor, constant: 4)

        NSLayoutConstraint.activate([
            // Glass card margins
            glassBackgroundView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Self.cardVerticalInset),
            glassBackgroundView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Self.cardHorizontalInset),
            glassBackgroundView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Self.cardHorizontalInset),
            glassBackgroundView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Self.cardVerticalInset),

            // Content inside glass
            tabNameLabel.topAnchor.constraint(equalTo: glassContent.topAnchor, constant: 10),
            tabNameLabel.leadingAnchor.constraint(equalTo: glassContent.leadingAnchor, constant: Self.contentPadding),
            tabNameLabel.trailingAnchor.constraint(equalTo: glassContent.trailingAnchor, constant: -Self.contentPadding),

            labelTopNormal,
            messageLabel.leadingAnchor.constraint(equalTo: glassContent.leadingAnchor, constant: Self.contentPadding),
            messageLabel.trailingAnchor.constraint(equalTo: glassContent.trailingAnchor, constant: -Self.contentPadding),

            thumbnailStack.leadingAnchor.constraint(equalTo: glassContent.leadingAnchor, constant: Self.contentPadding),
            thumbnailStack.bottomAnchor.constraint(equalTo: glassContent.bottomAnchor, constant: -12),
        ])

        // Tap gesture
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        contentView.addGestureRecognizer(tap)
    }

    @objc private func handleTap() {
        onTap?()
    }

    func configure(with message: Message, tabName: String) {
        // Store for theme updates
        currentMessage = message
        currentTabName = tabName

        // Set tab name
        tabNameLabel.text = tabName
        tabNameLabel.textColor = ThemeManager.shared.currentTheme.placeholderColor

        // Clear old thumbnails
        thumbnailStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Handle mixed content (new format)
        if message.hasContentBlocks, let blocks = message.contentBlocks {
            messageLabel.numberOfLines = 5
            messageLabel.attributedText = formatMixedContent(blocks: blocks)

            labelBottomWithMedia.isActive = false
            thumbnailStackHeight.isActive = false
            labelBottomWithoutMedia.isActive = true
            thumbnailStack.isHidden = true

            // Show thumbnails if has media
            let totalMedia = message.photoFileNames.count + message.videoFileNames.count
            if totalMedia > 0 {
                labelBottomWithoutMedia.isActive = false
                labelBottomWithMedia.isActive = true
                thumbnailStackHeight.isActive = true
                thumbnailStack.isHidden = false
                configureThumbnails(for: message)
            }
            return
        }

        // Handle task lists (old format)
        if message.isTodoList, let todoItems = message.todoItems {
            // Allow more lines for todo lists (title + 3 items + "+N more")
            messageLabel.numberOfLines = 5
            messageLabel.attributedText = formatTodoList(title: message.todoTitle, items: todoItems)

            // No thumbnails for task lists
            labelBottomWithMedia.isActive = false
            thumbnailStackHeight.isActive = false
            labelBottomWithoutMedia.isActive = true
            thumbnailStack.isHidden = true
            return
        }

        // Normal line limit for regular messages
        messageLabel.numberOfLines = 3

        // Set text for regular messages
        if message.content.isEmpty {
            messageLabel.attributedText = nil
            messageLabel.text = message.hasMedia ? "📷 \(L10n.Composer.gallery)" : ""
        } else {
            messageLabel.attributedText = nil
            messageLabel.text = message.content
        }

        // Check if message has media
        let totalMedia = message.photoFileNames.count + message.videoFileNames.count
        let hasMedia = totalMedia > 0

        // Update constraints based on media presence
        if hasMedia {
            labelBottomWithoutMedia.isActive = false
            labelBottomWithMedia.isActive = true
            thumbnailStackHeight.isActive = true
            thumbnailStack.isHidden = false
            configureThumbnails(for: message)
        } else {
            labelBottomWithMedia.isActive = false
            thumbnailStackHeight.isActive = false
            labelBottomWithoutMedia.isActive = true
            thumbnailStack.isHidden = true
        }
    }

    private func createThumbnailView(isLast: Bool, hiddenCount: Int, isVideo: Bool = false) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer.cornerRadius = 8
        container.clipsToBounds = true
        container.backgroundColor = .systemGray5

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(imageView)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: Self.thumbnailSize),
            container.heightAnchor.constraint(equalToConstant: Self.thumbnailSize),
            imageView.topAnchor.constraint(equalTo: container.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        // Add video indicator
        if isVideo {
            let playIcon = UIImageView(image: UIImage(systemName: "play.fill"))
            playIcon.tintColor = .white
            playIcon.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(playIcon)

            NSLayoutConstraint.activate([
                playIcon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                playIcon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                playIcon.widthAnchor.constraint(equalToConstant: 14),
                playIcon.heightAnchor.constraint(equalToConstant: 14),
            ])
        }

        // Add "+N" overlay for last thumbnail if there are hidden items
        if isLast && hiddenCount > 0 {
            let overlay = UIView()
            overlay.backgroundColor = .black.withAlphaComponent(0.6)
            overlay.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(overlay)

            let countLabel = UILabel()
            countLabel.text = "+\(hiddenCount)"
            countLabel.font = .systemFont(ofSize: 13, weight: .semibold)
            countLabel.textColor = .white
            countLabel.textAlignment = .center
            countLabel.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(countLabel)

            NSLayoutConstraint.activate([
                overlay.topAnchor.constraint(equalTo: container.topAnchor),
                overlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                overlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                overlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                countLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                countLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
        }

        return container
    }

    /// Format todo list as attributed string for search results
    private func formatTodoList(title: String?, items: [TodoItem]) -> NSAttributedString {
        let result = NSMutableAttributedString()

        // Tight paragraph style
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 0
        paragraphStyle.paragraphSpacing = 0
        paragraphStyle.lineHeightMultiple = 1.0

        // Add title if present
        if let title = title, !title.isEmpty {
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16, weight: .medium),
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraphStyle
            ]
            result.append(NSAttributedString(string: title + "\n", attributes: titleAttrs))
        }

        // Show up to 2 items
        let maxItems = 2
        let itemsToShow = Array(items.prefix(maxItems))
        let itemAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15),
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraphStyle
        ]
        let completedAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15),
            .foregroundColor: UIColor.secondaryLabel,
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .paragraphStyle: paragraphStyle
        ]

        for (index, item) in itemsToShow.enumerated() {
            let checkbox = item.isCompleted ? "● " : "○ "
            let attrs = item.isCompleted ? completedAttrs : itemAttrs

            // Add checkbox
            let checkboxAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: item.isCompleted ? UIColor.secondaryLabel : UIColor.tertiaryLabel,
                .paragraphStyle: paragraphStyle
            ]
            result.append(NSAttributedString(string: checkbox, attributes: checkboxAttrs))
            result.append(NSAttributedString(string: item.text, attributes: attrs))

            if index < itemsToShow.count - 1 || items.count > maxItems {
                result.append(NSAttributedString(string: "\n", attributes: itemAttrs))
            }
        }

        // Show remaining count if needed
        if items.count > maxItems {
            let remaining = items.count - maxItems
            let moreText = String(format: NSLocalizedString("search.tasks_more", comment: ""), remaining)
            let moreAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: ThemeManager.shared.currentTheme.placeholderColor,
                .paragraphStyle: paragraphStyle
            ]
            result.append(NSAttributedString(string: moreText, attributes: moreAttrs))
        }

        return result
    }

    /// Format mixed content blocks for search results
    private func formatMixedContent(blocks: [ContentBlock]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 0
        paragraphStyle.paragraphSpacing = 0
        paragraphStyle.lineHeightMultiple = 1.0

        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16),
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraphStyle
        ]
        let completedAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15),
            .foregroundColor: UIColor.secondaryLabel,
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .paragraphStyle: paragraphStyle
        ]
        let itemAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 15),
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraphStyle
        ]
        let checkboxAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 14),
            .foregroundColor: UIColor.tertiaryLabel,
            .paragraphStyle: paragraphStyle
        ]

        for (index, block) in blocks.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n", attributes: textAttrs)) }
            switch block.type {
            case "text":
                // Truncate to first 2 lines
                let truncated = block.text.components(separatedBy: "\n").prefix(2).joined(separator: "\n")
                result.append(NSAttributedString(string: truncated, attributes: textAttrs))
            case "todo":
                let checkbox = block.isCompleted ? "● " : "○ "
                result.append(NSAttributedString(string: checkbox, attributes: checkboxAttrs))
                result.append(NSAttributedString(string: block.text, attributes: block.isCompleted ? completedAttrs : itemAttrs))
            default: break
            }
        }

        return result
    }

    /// Configure thumbnail images for search result
    private func configureThumbnails(for message: Message) {
        let totalMedia = message.photoFileNames.count + message.videoFileNames.count
        let visibleCount = min(totalMedia, Self.maxVisibleThumbnails)
        let hiddenCount = totalMedia - visibleCount

        for (index, fileName) in message.photoFileNames.prefix(visibleCount).enumerated() {
            let isLast = (index == visibleCount - 1) && hiddenCount > 0
            let thumbnailView = createThumbnailView(isLast: isLast, hiddenCount: hiddenCount)
            thumbnailStack.addArrangedSubview(thumbnailView)

            let thumbSize = CGSize(width: Self.thumbnailSize * 2, height: Self.thumbnailSize * 2)
            ImageCache.shared.loadThumbnail(for: fileName, targetSize: thumbSize) { [weak thumbnailView] image in
                DispatchQueue.main.async {
                    guard let imageView = thumbnailView?.subviews.first as? UIImageView else { return }
                    imageView.image = image
                }
            }
        }

        let remainingSlots = visibleCount - message.photoFileNames.count
        if remainingSlots > 0 {
            for (index, thumbFileName) in message.videoThumbnailFileNames.prefix(remainingSlots).enumerated() {
                let actualIndex = message.photoFileNames.count + index
                let isLast = (actualIndex == visibleCount - 1) && hiddenCount > 0
                let thumbnailView = createThumbnailView(isLast: isLast, hiddenCount: hiddenCount, isVideo: true)
                thumbnailStack.addArrangedSubview(thumbnailView)

                let thumbSize = CGSize(width: Self.thumbnailSize * 2, height: Self.thumbnailSize * 2)
                ImageCache.shared.loadThumbnail(for: thumbFileName, targetSize: thumbSize) { [weak thumbnailView] image in
                    DispatchQueue.main.async {
                        guard let imageView = thumbnailView?.subviews.first as? UIImageView else { return }
                        imageView.image = image
                    }
                }
            }
        }
    }

    /// Calculate cell height for a message
    static func calculateHeight(for message: Message, maxWidth: CGFloat) -> CGFloat {
        let textWidth = maxWidth - (cardHorizontalInset * 2) - (contentPadding * 2)
        var height: CGFloat = cardVerticalInset // top card margin
        height += 10 // top padding inside card

        // Tab name label height
        height += 16 // ~13pt font + some padding
        height += 4 // spacing between tab name and message

        // Handle mixed content (new format)
        if message.hasContentBlocks, let blocks = message.contentBlocks {
            var lines = 0
            for block in blocks {
                switch block.type {
                case "text": lines += min(block.text.components(separatedBy: "\n").count, 2)
                case "todo": lines += 1
                default: break
                }
            }
            height += CGFloat(min(lines, 5)) * 20

            let totalMedia = message.photoFileNames.count + message.videoFileNames.count
            if totalMedia > 0 {
                height += 8 + thumbnailSize
            }
        }
        // Handle task lists (old format)
        else if message.isTodoList, let todoItems = message.todoItems {
            var lines = 0

            // Title line
            if let title = message.todoTitle, !title.isEmpty {
                lines += 1
            }

            // Task items (max 2)
            lines += min(todoItems.count, 2)

            // "+N more" line
            if todoItems.count > 2 {
                lines += 1
            }

            height += CGFloat(lines) * 20 // ~20pt per line
        } else {
            // Text height (max 3 lines)
            let text = message.content.isEmpty && message.hasMedia ? "📷 \(L10n.Composer.gallery)" : message.content
            let textHeight = text.boundingRect(
                with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: UIFont.systemFont(ofSize: 16)],
                context: nil
            ).height
            height += min(ceil(textHeight), 60) // max 3 lines ~60pt

            // Thumbnails height if has media
            let totalMedia = message.photoFileNames.count + message.videoFileNames.count
            if totalMedia > 0 {
                height += 8 + thumbnailSize // spacing + thumbnail height
            }
        }

        height += 12 // bottom padding inside card
        height += cardVerticalInset // bottom card margin

        return height
    }
}
