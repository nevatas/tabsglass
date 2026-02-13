//
//  ComposerComponents.swift
//  tabsglass
//
//  Extracted from MessengerView.swift for maintainability
//

import SwiftUI
import UIKit

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
    var onLinkPreviewChange: (() -> Void)?
    var onShowPhotoPicker: (() -> Void)?
    var onShowCamera: (() -> Void)?
    /// Reference to the formatting text view for extracting entities
    weak var formattingTextView: FormattingTextView?

    /// Height of media section (80 when visible, 0 when hidden)
    var mediaSectionHeight: CGFloat = 0

    /// Link preview state
    var linkPreview: LinkPreview? = nil
    var linkPreviewDismissed: Bool = false
    var isLoadingLinkPreview: Bool = false
    private(set) var lastDetectedURL: String?

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

    /// Detect and fetch link preview for the first URL in text
    func detectLinkPreview(in text: String) {
        let service = LinkPreviewService.shared
        guard let url = service.firstURL(in: text) else {
            // No URL — hide preview
            if linkPreview != nil || isLoadingLinkPreview || lastDetectedURL != nil {
                linkPreview = nil
                lastDetectedURL = nil
                linkPreviewDismissed = false
                isLoadingLinkPreview = false
                service.cancel()
                onLinkPreviewChange?()
            }
            return
        }

        let urlString = url.absoluteString

        // URL changed — reset dismissed state
        if urlString != lastDetectedURL {
            linkPreviewDismissed = false
        }

        // User dismissed this URL
        if linkPreviewDismissed {
            return
        }

        // Same URL already showing or loading
        if urlString == lastDetectedURL && (linkPreview != nil || isLoadingLinkPreview) {
            return
        }

        lastDetectedURL = urlString

        // Show loading banner immediately with short URL
        let shortURL = url.host(percentEncoded: false) ?? urlString
        linkPreview = LinkPreview(url: urlString, siteName: shortURL)
        isLoadingLinkPreview = true
        onLinkPreviewChange?()

        service.fetchPreview(for: text) { [weak self] preview in
            guard let self = self else { return }
            guard self.lastDetectedURL == urlString else { return }
            self.isLoadingLinkPreview = false
            if let preview = preview {
                self.linkPreview = preview
            } else {
                // Fetch failed — hide banner
                self.linkPreview = nil
            }
            self.onLinkPreviewChange?()
        }
    }

    /// Dismiss the current link preview banner
    func dismissLinkPreview() {
        linkPreviewDismissed = true
        linkPreview = nil
        isLoadingLinkPreview = false
        LinkPreviewService.shared.cancel()
        onLinkPreviewChange?()
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
        linkPreview = nil
        linkPreviewDismissed = false
        isLoadingLinkPreview = false
        lastDetectedURL = nil
        LinkPreviewService.shared.cancel()
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
            self.composerState.detectLinkPreview(in: newText)
            self.updateHeight()
        }

        composerState.onLinkPreviewChange = { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.updateHeight()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.updateHeight()
            }
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

    /// Extract current link preview (called before send)
    /// Prefers enriched version from cache (may include image downloaded after banner appeared)
    /// Returns placeholder with isPlaceholder=true if still loading
    func extractLinkPreview() -> LinkPreview? {
        if let url = composerState.lastDetectedURL,
           let cached = LinkPreviewService.shared.cachedPreview(for: url) {
            return cached
        }
        // Still loading — return placeholder so message bubble shows loading state
        if composerState.isLoadingLinkPreview,
           let url = composerState.lastDetectedURL,
           let siteName = composerState.linkPreview?.siteName {
            return LinkPreview(url: url, siteName: siteName, isPlaceholder: true)
        }
        let preview = composerState.linkPreview
        guard preview?.title != nil || preview?.previewDescription != nil else {
            return nil
        }
        return preview
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

// MARK: - Link Preview Banner

struct LinkPreviewBanner: View {
    let preview: LinkPreview
    let isLoading: Bool
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var themeManager: ThemeManager { ThemeManager.shared }

    private var accentColor: Color {
        themeManager.currentTheme.accentColor ?? (colorScheme == .dark ? .white : .primary)
    }

    var body: some View {
        HStack(spacing: 8) {
            // Left accent bar
            RoundedRectangle(cornerRadius: 1.5)
                .fill(accentColor)
                .frame(width: 3, height: 36)

            // Text content
            VStack(alignment: .leading, spacing: 2) {
                if isLoading {
                    LoadingDotsText()
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(colorScheme == .dark ? .white : .primary)
                } else if let title = preview.title, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(colorScheme == .dark ? .white : .primary)
                }
                if isLoading {
                    if let siteName = preview.siteName, !siteName.isEmpty {
                        Text(siteName)
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                } else if let desc = preview.previewDescription, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                } else if let siteName = preview.siteName, !siteName.isEmpty {
                    Text(siteName)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Dismiss button
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

/// Animated "Loading..." text — dots appear one by one
private struct LoadingDotsText: View {
    @State private var dotCount = 1

    var body: some View {
        HStack(spacing: 0) {
            Text("Loading")
            Text("...")
                .opacity(0) // Reserve space for 3 dots
                .overlay(alignment: .leading) {
                    Text(String(repeating: ".", count: dotCount))
                }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
                dotCount = (dotCount % 3) + 1
            }
        }
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

    private var hasLinkPreview: Bool {
        state.linkPreview != nil
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

                    // Link preview banner — always in hierarchy, visibility via frame/opacity
                    VStack(spacing: 0) {
                        if let preview = state.linkPreview {
                            LinkPreviewBanner(preview: preview, isLoading: state.isLoadingLinkPreview, onDismiss: { state.dismissLinkPreview() })
                        }
                    }
                    .frame(height: state.linkPreview != nil ? 52 : 0)
                    .clipped()
                    .opacity(state.linkPreview != nil ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: state.linkPreview != nil)

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
                                if let tv = state.formattingTextView {
                                    if !tv.isFirstResponder {
                                        _ = tv.becomeFirstResponder()
                                    }
                                    tv.insertCheckbox()
                                }
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
            .padding(.top, (hasMedia || hasLinkPreview) ? 8 : 14)
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

