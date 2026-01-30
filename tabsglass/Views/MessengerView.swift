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
    var onShowTaskList: (() -> Void)?

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
    var onShowTaskList: (() -> Void)? {
        didSet { composerState.onShowTaskList = onShowTaskList }
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
                                    state.onShowTaskList?()
                                } label: {
                                    Label(L10n.Composer.list, systemImage: "checklist")
                                }

                                Button {
                                    state.onShowPhotoPicker?()
                                } label: {
                                    Label(L10n.Composer.photo, systemImage: "photo.on.rectangle")
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
            .padding(.bottom, 14)
            .clipShape(.rect(cornerRadius: 24))
            .glassEffect(
                .regular.tint(composerTint),
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

// MARK: - Message Cell

final class MessageTableCell: UITableViewCell {
    private let bubbleContainer = UIView()
    private let bubbleView = UIView()

    /// Public access to bubble container (includes reminder badge) for context menu
    var bubbleViewForContextMenu: UIView { bubbleContainer }
    private let mosaicView = MosaicMediaView()
    private let messageTextView = UITextView()
    private let todoView = TodoBubbleView()
    private let reminderBadge = UIView()
    private let reminderIcon = UIImageView()

    private var cachedMessage: Message?
    private var lastLayoutWidth: CGFloat = 0

    /// Callback when a photo is tapped: (index, sourceFrame in window, image, fileNames)
    var onPhotoTapped: ((Int, CGRect, UIImage, [String]) -> Void)?

    /// Callback when media is tapped (supports both photos and videos)
    var onMediaTapped: ((Int, CGRect, UIImage, [String], Bool) -> Void)?

    /// Callback when a todo item is toggled: (itemId, isCompleted)
    var onTodoToggle: ((UUID, Bool) -> Void)?

    private var messageTextViewTopToMosaic: NSLayoutConstraint!
    private var messageTextViewTopToBubble: NSLayoutConstraint!
    private var messageTextViewBottomToBubble: NSLayoutConstraint!
    private var mosaicHeightConstraint: NSLayoutConstraint!
    private var mosaicBottomToBubble: NSLayoutConstraint!
    private var todoViewHeightConstraint: NSLayoutConstraint!
    private var todoViewBottomToBubble: NSLayoutConstraint!
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
            if let message = self?.cachedMessage, message.isTodoList, let items = message.todoItems {
                let isDarkMode = cell.traitCollection.userInterfaceStyle == .dark
                self?.todoView.configure(with: message.todoTitle, items: items, isDarkMode: isDarkMode)
            }
        }
    }

    private func setupCell() {
        backgroundColor = .clear
        selectionStyle = .none
        clipsToBounds = false
        contentView.clipsToBounds = false

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

        mosaicHeightConstraint = mosaicView.heightAnchor.constraint(equalToConstant: 0)
        todoViewHeightConstraint = todoView.heightAnchor.constraint(equalToConstant: 0)
        todoViewBottomToBubble = todoView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor)
        messageTextViewTopToMosaic = messageTextView.topAnchor.constraint(equalTo: mosaicView.bottomAnchor, constant: 10)
        messageTextViewTopToBubble = messageTextView.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10)
        messageTextViewBottomToBubble = messageTextView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -10)
        mosaicBottomToBubble = mosaicView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor)

        NSLayoutConstraint.activate([
            // Container positioned to keep bubble in same place as before (with symmetric 8pt padding)
            // bubble.top = container.top + 8, so container.top = contentView.top + 4 - 8 = -4
            bubbleContainer.topAnchor.constraint(equalTo: contentView.topAnchor, constant: -4),
            // bubble.bottom = container.bottom - 8, so container.bottom = contentView.bottom - 4 + 8 = +4
            bubbleContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: 4),
            // bubble.trailing = container.trailing - 8, so container.trailing = contentView.trailing - 16 + 8 = -8
            bubbleContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            // bubble.leading = container.leading + 8, so container.leading = contentView.leading + 16 - 8 = +8
            bubbleContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),

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
        // Update link color for current theme
        messageTextView.linkTextAttributes = [
            .foregroundColor: theme.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
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
        reminderBadge.isHidden = true
        // Reset constraints
        messageTextViewTopToMosaic.isActive = false
        messageTextViewTopToBubble.isActive = false
        messageTextViewBottomToBubble.isActive = false
        mosaicBottomToBubble.isActive = false
        todoViewBottomToBubble.isActive = false
    }

    func configure(with message: Message) {
        cachedMessage = message

        // Create attributed string with entities (links, formatting)
        let attributedText = createAttributedString(for: message)
        messageTextView.attributedText = attributedText

        // Configure todo view if this is a todo list
        if message.isTodoList, let items = message.todoItems {
            let isDarkMode = traitCollection.userInterfaceStyle == .dark
            todoView.configure(with: message.todoTitle, items: items, isDarkMode: isDarkMode)
        }

        // Show/hide reminder badge
        reminderBadge.isHidden = !message.hasReminder

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

        // Configure todo view
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
                messageTextViewBottomToBubble.isActive = true
                messageTextView.isHidden = false
            } else if hasMedia && !hasText {
                // Media only - mosaic fills to bottom
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

        let emojis = ["🤔", "👋", "🤙", "👀", "👻", "🥰", "🤭", "🤗", "🧠", "🩵", "❤️", "💛"]
        let emojiLabel = UILabel()
        emojiLabel.text = emojis.randomElement()
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
