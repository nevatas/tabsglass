//
//  MessengerView.swift
//  tabsglass
//
//  UIKit-based messenger view with keyboard-synced scrolling
//

import SwiftUI
import UIKit

// MARK: - SwiftUI Bridge

struct MessengerView: UIViewControllerRepresentable {
    let tab: Tab
    @Binding var messageText: String
    let onSend: () -> Void
    let onTapOutside: () -> Void

    func makeUIViewController(context: Context) -> MessengerViewController {
        let vc = MessengerViewController()
        vc.currentTab = tab
        vc.onSend = onSend
        vc.onTapOutside = onTapOutside
        vc.textBinding = $messageText
        return vc
    }

    func updateUIViewController(_ uiViewController: MessengerViewController, context: Context) {
        uiViewController.currentTab = tab
        uiViewController.textBinding = $messageText
        uiViewController.reloadMessages()
    }
}

// MARK: - MessengerViewController

final class MessengerViewController: UIViewController {
    var currentTab: Tab!
    var textBinding: Binding<String>!
    var onSend: (() -> Void)?
    var onTapOutside: (() -> Void)?

    private let tableView = UITableView()
    private let inputContainer = SwiftUIComposerContainer()
    private var sortedMessages: [Message] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setupTableView()
        setupInputView()
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .none
        tableView.keyboardDismissMode = .interactive
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(MessageTableCell.self, forCellReuseIdentifier: "MessageCell")
        tableView.register(EmptyTableCell.self, forCellReuseIdentifier: "EmptyCell")
        tableView.transform = CGAffineTransform(scaleX: 1, y: -1) // Flip for bottom-up
        tableView.contentInset = UIEdgeInsets(top: 90, left: 0, bottom: 0, right: 0) // Space for input

        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.cancelsTouchesInView = false
        tableView.addGestureRecognizer(tap)
    }

    private func setupInputView() {
        inputContainer.translatesAutoresizingMaskIntoConstraints = false
        inputContainer.onTextChange = { [weak self] text in
            self?.textBinding.wrappedValue = text
        }
        inputContainer.onSend = { [weak self] in
            self?.onSend?()
            self?.inputContainer.clearText()
        }

        view.addSubview(inputContainer)

        // Use keyboardLayoutGuide - automatically handles keyboard
        NSLayoutConstraint.activate([
            inputContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            inputContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inputContainer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        ])
    }

    private func updateTableInsets() {
        let inputHeight = inputContainer.bounds.height
        tableView.contentInset.top = inputHeight
        tableView.verticalScrollIndicatorInsets.top = inputHeight
    }

    @objc private func handleTap() {
        view.endEditing(true)
        onTapOutside?()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadMessages()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateTableInsets()
    }

    func reloadMessages() {
        sortedMessages = currentTab.messages.sorted { $0.createdAt > $1.createdAt }
        tableView.reloadData()
    }
}

// MARK: - UITableViewDataSource & Delegate

extension MessengerViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sortedMessages.isEmpty ? 1 : sortedMessages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if sortedMessages.isEmpty {
            let cell = tableView.dequeueReusableCell(withIdentifier: "EmptyCell", for: indexPath) as! EmptyTableCell
            cell.transform = CGAffineTransform(scaleX: 1, y: -1)
            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: "MessageCell", for: indexPath) as! MessageTableCell
        cell.configure(with: sortedMessages[indexPath.row])
        cell.transform = CGAffineTransform(scaleX: 1, y: -1)
        return cell
    }
}

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
            // For last image: first animate height to 0, then remove
            withAnimation(.easeOut(duration: 0.25)) {
                imagesSectionHeight = 0
            }
            // Remove after animation completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.attachedImages.removeAll()
                self?.onAttachmentChange?()
            }
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
        let targetWidth = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width
        let fittingSize = hc.sizeThatFits(in: CGSize(width: targetWidth, height: .greatestFiniteMagnitude))
        return max(102, fittingSize.height)
    }

    /// Обновляет высоту и уведомляет parent
    private func updateHeight() {
        let newHeight = calculateHeight()
        if abs(newHeight - currentHeight) > 1 {
            currentHeight = newHeight
            onHeightChange?(newHeight)
        }
    }

    func clearText() {
        composerState.text = ""
        composerState.clearAttachments()

        // Принудительно обновляем hosting controller
        hostingController?.view.setNeedsLayout()
        hostingController?.view.layoutIfNeeded()

        // Recalculate actual height after clearing
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
        guard let hc = hostingController else {
            return CGSize(width: UIView.noIntrinsicMetric, height: 102)
        }
        return hc.view.intrinsicContentSize
    }
}

// MARK: - Embedded Composer (without FocusState)

struct EmbeddedComposerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var state: ComposerState
    @FocusState private var isFocused: Bool

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
                    .lineLimit(1...10)
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
            .animation(.easeOut(duration: 0.25), value: state.attachedImages.count)
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
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            .offset(x: 4, y: -4)
        }
    }
}

// MARK: - Message Cell

final class MessageTableCell: UITableViewCell {
    private let bubbleView = UIView()
    private let photosScrollView = UIScrollView()
    private let photosStackView = UIStackView()
    private let messageLabel = UILabel()
    private var photoImageViews: [UIImageView] = []

    private var messageLabelTopToPhotos: NSLayoutConstraint!
    private var messageLabelTopToBubble: NSLayoutConstraint!
    private var messageLabelBottomToBubble: NSLayoutConstraint!
    private var photosHeightConstraint: NSLayoutConstraint!
    private var photosBottomToBubble: NSLayoutConstraint!

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

        // Photos scroll view (horizontal)
        photosScrollView.showsHorizontalScrollIndicator = false
        photosScrollView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.addSubview(photosScrollView)

        // Photos stack view (inside scroll view)
        photosStackView.axis = .horizontal
        photosStackView.spacing = 4
        photosStackView.translatesAutoresizingMaskIntoConstraints = false
        photosScrollView.addSubview(photosStackView)

        // Message label
        messageLabel.textColor = .white
        messageLabel.font = .systemFont(ofSize: 16)
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.addSubview(messageLabel)

        photosHeightConstraint = photosScrollView.heightAnchor.constraint(equalToConstant: 0)
        messageLabelTopToPhotos = messageLabel.topAnchor.constraint(equalTo: photosScrollView.bottomAnchor, constant: 8)
        messageLabelTopToBubble = messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10)
        messageLabelBottomToBubble = messageLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -10)
        photosBottomToBubble = photosScrollView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor)

        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),

            // Photos scroll view
            photosScrollView.topAnchor.constraint(equalTo: bubbleView.topAnchor),
            photosScrollView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor),
            photosScrollView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor),
            photosHeightConstraint,

            // Photos stack view (inside scroll view)
            photosStackView.topAnchor.constraint(equalTo: photosScrollView.topAnchor),
            photosStackView.bottomAnchor.constraint(equalTo: photosScrollView.bottomAnchor),
            photosStackView.leadingAnchor.constraint(equalTo: photosScrollView.leadingAnchor),
            photosStackView.trailingAnchor.constraint(equalTo: photosScrollView.trailingAnchor),
            photosStackView.heightAnchor.constraint(equalTo: photosScrollView.heightAnchor),

            // Message label - horizontal constraints always active
            messageLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 14),
            messageLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -14),
        ])

        updateBubbleColor()
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

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateBubbleColor()
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // Clear old photos
        for imageView in photoImageViews {
            imageView.removeFromSuperview()
        }
        photoImageViews.removeAll()

        // Reset constraints
        messageLabelTopToPhotos.isActive = false
        messageLabelTopToBubble.isActive = false
        messageLabelBottomToBubble.isActive = false
        photosBottomToBubble.isActive = false
    }

    func configure(with message: Message) {
        messageLabel.text = message.text
        updateBubbleColor()

        // Clear old photos
        for imageView in photoImageViews {
            imageView.removeFromSuperview()
        }
        photoImageViews.removeAll()

        let photos = message.photos
        let hasPhotos = !photos.isEmpty
        let hasText = !message.text.isEmpty

        // Reset constraints first
        messageLabelTopToPhotos.isActive = false
        messageLabelTopToBubble.isActive = false
        messageLabelBottomToBubble.isActive = false
        photosBottomToBubble.isActive = false

        // Configure photos
        if hasPhotos {
            let photoSize: CGFloat = 150
            photosHeightConstraint.constant = photoSize

            for photo in photos {
                let imageView = UIImageView(image: photo)
                imageView.contentMode = .scaleAspectFill
                imageView.clipsToBounds = true
                imageView.translatesAutoresizingMaskIntoConstraints = false
                imageView.widthAnchor.constraint(equalToConstant: photoSize).isActive = true
                photosStackView.addArrangedSubview(imageView)
                photoImageViews.append(imageView)
            }

            photosScrollView.isHidden = false
        } else {
            photosHeightConstraint.constant = 0
            photosScrollView.isHidden = true
        }

        // Configure layout based on content
        if hasPhotos && hasText {
            // Both photos and text
            messageLabelTopToPhotos.isActive = true
            messageLabelBottomToBubble.isActive = true
            messageLabel.isHidden = false
        } else if hasPhotos && !hasText {
            // Photos only - photos fill to bottom
            photosBottomToBubble.isActive = true
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
