//
//  MessageCells.swift
//  tabsglass
//
//  Extracted from MessengerView.swift for maintainability
//

import SwiftUI
import UIKit

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

    private let linkPreviewView = LinkPreviewBubbleView()
    private let showMoreButton = UIButton(type: .system)
    private let fadeGradientView = FadeGradientView()
    private var messageTextViewHeightConstraint: NSLayoutConstraint!
    private var showMoreTopToText: NSLayoutConstraint!
    private var showMoreBottomToBubble: NSLayoutConstraint!
    private var isExpanded: Bool = false
    var onShowMoreTapped: (() -> Void)?

    private var cachedMessage: Message?
    private var lastLayoutWidth: CGFloat = 0
    private var lastLayoutHash: Int = 0

    /// Callback when a photo is tapped: (index, sourceFrame in window, image, fileNames)
    var onPhotoTapped: ((Int, CGRect, UIImage, [String]) -> Void)?

    /// Callback when media is tapped (supports both photos and videos)
    var onMediaTapped: ((Int, CGRect, UIImage, [String], Bool) -> Void)?

    /// Callback when a todo item is toggled: (itemId, isCompleted)
    var onTodoToggle: ((UUID, Bool) -> Void)?

    /// Whether the keyboard/composer is currently active (propagated to todo checkbox rows)
    var isKeyboardActive: Bool = false {
        didSet {
            todoView.isKeyboardActive = isKeyboardActive
            mixedContentView.isKeyboardActive = isKeyboardActive
        }
    }

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
    private var linkPreviewHeightConstraint: NSLayoutConstraint!
    private var linkPreviewTopToText: NSLayoutConstraint!
    private var linkPreviewTopToMosaic: NSLayoutConstraint!
    private var linkPreviewTopToShowMore: NSLayoutConstraint!
    private var linkPreviewBottomToBubble: NSLayoutConstraint!
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

        // Link preview view
        linkPreviewView.translatesAutoresizingMaskIntoConstraints = false
        linkPreviewView.isHidden = true
        bubbleView.addSubview(linkPreviewView)

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

        // Link preview constraints
        linkPreviewHeightConstraint = linkPreviewView.heightAnchor.constraint(equalToConstant: 0)
        linkPreviewHeightConstraint.priority = UILayoutPriority(999)
        linkPreviewTopToText = linkPreviewView.topAnchor.constraint(equalTo: messageTextView.bottomAnchor, constant: 4)
        linkPreviewTopToMosaic = linkPreviewView.topAnchor.constraint(equalTo: mosaicView.bottomAnchor, constant: 4)
        linkPreviewTopToShowMore = linkPreviewView.topAnchor.constraint(equalTo: showMoreButton.bottomAnchor, constant: 4)
        linkPreviewBottomToBubble = linkPreviewView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -4)

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

            // Link preview view constraints (horizontal always active)
            linkPreviewView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor),
            linkPreviewView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor),
            linkPreviewHeightConstraint,
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

    /// Check if the given point (in contentView coordinates) is in the todo checkbox toggle zone.
    /// Returns true for the left 85% of the bubble when the message contains todos.
    func isTodoToggleZone(at point: CGPoint) -> Bool {
        guard let message = cachedMessage else { return false }

        let hasTodo: Bool
        if message.hasContentBlocks, let blocks = message.contentBlocks {
            hasTodo = blocks.contains { $0.type == "todo" }
        } else {
            hasTodo = message.isTodoList
        }
        guard hasTodo else { return false }

        // Convert point to bubble view coordinates
        let pointInBubble = contentView.convert(point, to: bubbleView)
        guard bubbleView.bounds.contains(pointInBubble) else { return false }

        // Left 85% is the toggle zone (right 15% is dismiss zone)
        let threshold = bubbleView.bounds.width * 0.85
        return pointInBubble.x <= threshold
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
        lastLayoutHash = 0
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
        // Reset link preview constraints
        linkPreviewTopToText.isActive = false
        linkPreviewTopToMosaic.isActive = false
        linkPreviewTopToShowMore.isActive = false
        linkPreviewBottomToBubble.isActive = false
        linkPreviewView.isHidden = true
        linkPreviewHeightConstraint.constant = 0
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

        // Configure link preview
        if message.linkPreview != nil && !message.isTodoList && !message.hasContentBlocks {
            let isDarkMode = traitCollection.userInterfaceStyle == .dark
            linkPreviewView.configure(with: message.linkPreview, isDarkMode: isDarkMode)
        }

        // Show/hide reminder badge (floating — no layout impact on cell height)
        reminderBadge.isHidden = !message.hasReminder

        updateBubbleColor()
        updateShowMoreButtonColor()

        let width = contentView.bounds.width
        if width > 0 {
            let layoutHash = makeLayoutHash(for: message, isExpanded: isExpanded)
            let widthUnchanged = abs(width - lastLayoutWidth) < 0.5
            if widthUnchanged && layoutHash == lastLayoutHash {
                // Layout-affecting data unchanged — skip expensive constraint rebuild
                return
            }
            lastLayoutWidth = width
            lastLayoutHash = layoutHash
            applyLayout(for: message, width: width)
        }
    }

    /// Hash of properties that affect cell layout (NOT todo isCompleted, NOT reminder state)
    private func makeLayoutHash(for message: Message, isExpanded: Bool) -> Int {
        var hasher = Hasher()
        hasher.combine(message.id)
        hasher.combine(message.content)
        hasher.combine(message.photoFileNames.count)
        hasher.combine(message.videoFileNames.count)
        hasher.combine(message.todoItems?.count ?? -1)
        hasher.combine(message.todoTitle)
        hasher.combine(message.contentBlocks?.count ?? -1)
        hasher.combine(message.linkPreview?.url)
        hasher.combine(message.linkPreview?.isPlaceholder)
        hasher.combine(message.linkPreview?.isLargeImage)
        hasher.combine(isExpanded)
        return hasher.finalize()
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
        linkPreviewTopToText.isActive = false
        linkPreviewTopToMosaic.isActive = false
        linkPreviewTopToShowMore.isActive = false
        linkPreviewBottomToBubble.isActive = false

        // Calculate bubble width (cell width - 32 for margins)
        let bubbleWidth = max(width - 32, 0)

        // Configure media with mosaic layout (async loading)
        if hasMedia {
            let mosaicHeight = MosaicMediaView.calculateHeight(for: aspectRatios, maxWidth: bubbleWidth)
            mosaicHeightConstraint.constant = mosaicHeight

            // Build MediaItems array in display order (respects mediaOrder)
            let mediaItems = message.orderedMediaItems

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

            // Check for link preview
            let hasLinkPreview = message.linkPreview != nil
            if hasLinkPreview {
                let previewHeight = LinkPreviewBubbleView.calculateHeight(for: message.linkPreview!, maxWidth: bubbleWidth)
                linkPreviewHeightConstraint.constant = previewHeight
                linkPreviewView.isHidden = false
            } else {
                linkPreviewHeightConstraint.constant = 0
                linkPreviewView.isHidden = true
            }

            // Configure layout based on content
            if hasMedia && hasText {
                // Both media and text
                messageTextViewTopToMosaic.isActive = true
                messageTextView.isHidden = false
                let hasShowMore = applyShowMoreIfNeeded(bubbleWidth: bubbleWidth)
                if hasLinkPreview {
                    if hasShowMore {
                        linkPreviewTopToShowMore.isActive = true
                    } else {
                        linkPreviewTopToText.isActive = true
                    }
                    linkPreviewBottomToBubble.isActive = true
                } else if hasShowMore {
                    showMoreBottomToBubble.isActive = true
                } else {
                    messageTextViewBottomToBubble.isActive = true
                }
            } else if hasMedia && !hasText {
                // Media only
                messageTextView.isHidden = true
                showMoreButton.isHidden = true
                if hasLinkPreview {
                    linkPreviewTopToMosaic.isActive = true
                    linkPreviewBottomToBubble.isActive = true
                } else {
                    mosaicBottomToBubble.isActive = true
                }
            } else {
                // Text only (or empty)
                messageTextViewTopToBubble.isActive = true
                messageTextView.isHidden = false
                let hasShowMore = applyShowMoreIfNeeded(bubbleWidth: bubbleWidth)
                if hasLinkPreview {
                    if hasShowMore {
                        linkPreviewTopToShowMore.isActive = true
                    } else {
                        linkPreviewTopToText.isActive = true
                    }
                    linkPreviewBottomToBubble.isActive = true
                } else if hasShowMore {
                    showMoreBottomToBubble.isActive = true
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
        // Don't set showMoreBottomToBubble here — caller handles bottom constraint
        // (link preview may go below the show more button)
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

// MARK: - Link Preview Bubble View

final class LinkPreviewBubbleView: UIView {
    // Shared
    private let accentBar = UIView()
    private let siteNameLabel = UILabel()
    private let titleLabel = UILabel()

    // Compact layout (description + small thumbnail)
    private let descriptionLabel = UILabel()
    private let thumbnailView = UIImageView()

    // Large layout (full-width image)
    private let largeImageView = UIImageView()

    // Loading state
    private let loadingTitleLabel = UILabel()
    private let shimmerView = UIView()
    private let shimmerGradientLayer = CAGradientLayer()
    private var dotsTimer: Timer?
    private var dotCount = 0
    private var isShowingLoading = false

    // Tap to open URL
    private var currentURL: String?

    // Layout state
    private var isLargeLayout = false
    private var activeConstraints: [NSLayoutConstraint] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        clipsToBounds = true
        isUserInteractionEnabled = true
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))

        // Accent bar (always present)
        accentBar.layer.cornerRadius = 1.5
        accentBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(accentBar)

        // Site name (always present)
        siteNameLabel.font = .systemFont(ofSize: 12, weight: .medium)
        siteNameLabel.textColor = .secondaryLabel
        siteNameLabel.numberOfLines = 1
        siteNameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(siteNameLabel)

        // Title (always present)
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        // Description (compact only)
        descriptionLabel.font = .systemFont(ofSize: 14)
        descriptionLabel.textColor = .secondaryLabel
        descriptionLabel.numberOfLines = 3
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(descriptionLabel)

        // Thumbnail (compact only)
        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.layer.cornerRadius = 8
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(thumbnailView)

        // Large image (large layout only)
        largeImageView.contentMode = .scaleAspectFill
        largeImageView.clipsToBounds = true
        largeImageView.layer.cornerRadius = 10
        largeImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(largeImageView)

        // Loading title ("Loading...")
        loadingTitleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        loadingTitleLabel.textColor = .secondaryLabel
        loadingTitleLabel.numberOfLines = 1
        loadingTitleLabel.isHidden = true
        loadingTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(loadingTitleLabel)

        // Shimmer placeholder rectangle
        shimmerView.backgroundColor = .quaternarySystemFill
        shimmerView.layer.cornerRadius = 8
        shimmerView.clipsToBounds = true
        shimmerView.isHidden = true
        shimmerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(shimmerView)

        // Shimmer gradient
        shimmerGradientLayer.colors = [
            UIColor.clear.cgColor,
            UIColor.white.withAlphaComponent(0.3).cgColor,
            UIColor.clear.cgColor
        ]
        shimmerGradientLayer.locations = [0, 0.5, 1]
        shimmerGradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        shimmerGradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        shimmerView.layer.addSublayer(shimmerGradientLayer)
    }

    func configure(with preview: LinkPreview?, isDarkMode: Bool) {
        guard let preview = preview else {
            isHidden = true
            currentURL = nil
            stopLoading()
            return
        }
        isHidden = false
        currentURL = preview.isPlaceholder == true ? nil : preview.url

        // Theme accent color
        let theme = ThemeManager.shared.currentTheme
        if let accent = theme.accentColor {
            accentBar.backgroundColor = UIColor(accent)
        } else {
            accentBar.backgroundColor = .systemBlue
        }

        // Reset all layout
        NSLayoutConstraint.deactivate(activeConstraints)
        activeConstraints.removeAll()
        thumbnailView.isHidden = true
        thumbnailView.image = nil
        largeImageView.isHidden = true
        largeImageView.image = nil
        descriptionLabel.isHidden = true
        titleLabel.isHidden = true
        siteNameLabel.isHidden = true

        // Loading placeholder state
        if preview.isPlaceholder == true {
            stopLoading()
            configureLoadingLayout(preview: preview)
            NSLayoutConstraint.activate(activeConstraints)
            startLoading()
            return
        }

        // Normal state — hide loading views
        stopLoading()
        isLargeLayout = preview.isLargeImage

        titleLabel.textColor = .label

        siteNameLabel.text = preview.siteName
        let hasSiteName = preview.siteName != nil && !preview.siteName!.isEmpty
        siteNameLabel.isHidden = !hasSiteName

        titleLabel.text = preview.title
        let hasTitle = preview.title != nil && !preview.title!.isEmpty
        titleLabel.isHidden = !hasTitle

        if isLargeLayout {
            configureLargeLayout(preview: preview, hasSiteName: hasSiteName, hasTitle: hasTitle)
        } else {
            configureCompactLayout(preview: preview, hasSiteName: hasSiteName, hasTitle: hasTitle)
        }

        NSLayoutConstraint.activate(activeConstraints)
    }

    @objc private func handleTap() {
        guard let urlString = currentURL,
              let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if isShowingLoading {
            shimmerGradientLayer.frame = shimmerView.bounds
        }
    }

    // MARK: - Loading Layout

    private func configureLoadingLayout(preview: LinkPreview) {
        isShowingLoading = true
        loadingTitleLabel.isHidden = false
        shimmerView.isHidden = false
        siteNameLabel.isHidden = false
        siteNameLabel.text = preview.siteName

        // Accent bar
        activeConstraints.append(contentsOf: [
            accentBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            accentBar.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            accentBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            accentBar.widthAnchor.constraint(equalToConstant: 3),
        ])

        let contentLeading = accentBar.trailingAnchor

        // Shimmer rectangle on right (same position as compact thumbnail)
        activeConstraints.append(contentsOf: [
            shimmerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            shimmerView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            shimmerView.widthAnchor.constraint(equalToConstant: 50),
            shimmerView.heightAnchor.constraint(equalToConstant: 50),
        ])

        // Site name
        activeConstraints.append(contentsOf: [
            siteNameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            siteNameLabel.leadingAnchor.constraint(equalTo: contentLeading, constant: 8),
            siteNameLabel.trailingAnchor.constraint(equalTo: shimmerView.leadingAnchor, constant: -8),
        ])

        // "Loading..." text
        activeConstraints.append(contentsOf: [
            loadingTitleLabel.topAnchor.constraint(equalTo: siteNameLabel.bottomAnchor, constant: 2),
            loadingTitleLabel.leadingAnchor.constraint(equalTo: contentLeading, constant: 8),
            loadingTitleLabel.trailingAnchor.constraint(equalTo: shimmerView.leadingAnchor, constant: -8),
        ])
    }

    private func startLoading() {
        // Animated dots
        dotCount = 3
        loadingTitleLabel.text = "Loading..."
        dotsTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            guard let self = self, self.isShowingLoading else { return }
            self.dotCount = (self.dotCount % 3) + 1
            let dots = String(repeating: ".", count: self.dotCount)
            self.loadingTitleLabel.text = "Loading" + dots
        }

        // Shimmer animation
        let animation = CABasicAnimation(keyPath: "locations")
        animation.fromValue = [-1.0, -0.5, 0.0]
        animation.toValue = [1.0, 1.5, 2.0]
        animation.duration = 1.5
        animation.repeatCount = .infinity
        shimmerGradientLayer.add(animation, forKey: "shimmer")
    }

    private func stopLoading() {
        isShowingLoading = false
        dotsTimer?.invalidate()
        dotsTimer = nil
        shimmerGradientLayer.removeAllAnimations()
        loadingTitleLabel.isHidden = true
        shimmerView.isHidden = true
    }

    // MARK: - Large Layout (full-width image below title)

    private func configureLargeLayout(preview: LinkPreview, hasSiteName: Bool, hasTitle: Bool) {
        titleLabel.numberOfLines = 2
        descriptionLabel.isHidden = true

        // Accent bar — spans from siteName to bottom of image
        activeConstraints.append(contentsOf: [
            accentBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            accentBar.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            accentBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            accentBar.widthAnchor.constraint(equalToConstant: 3),
        ])

        // Build text chain vertically
        let contentLeading = accentBar.trailingAnchor

        var topAnchorRef = topAnchor
        let topOffset: CGFloat = 6

        if hasSiteName {
            activeConstraints.append(contentsOf: [
                siteNameLabel.topAnchor.constraint(equalTo: topAnchorRef, constant: topOffset),
                siteNameLabel.leadingAnchor.constraint(equalTo: contentLeading, constant: 8),
                siteNameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            ])
            topAnchorRef = siteNameLabel.bottomAnchor
        }

        if hasTitle {
            activeConstraints.append(contentsOf: [
                titleLabel.topAnchor.constraint(equalTo: topAnchorRef, constant: hasSiteName ? 2 : topOffset),
                titleLabel.leadingAnchor.constraint(equalTo: contentLeading, constant: 8),
                titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            ])
            topAnchorRef = titleLabel.bottomAnchor
        }

        // Large image — full width (inside accent bar area)
        largeImageView.isHidden = false
        let aspectRatio = preview.imageAspectRatio ?? 1.5
        activeConstraints.append(contentsOf: [
            largeImageView.topAnchor.constraint(equalTo: topAnchorRef, constant: 6),
            largeImageView.leadingAnchor.constraint(equalTo: contentLeading, constant: 8),
            largeImageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            largeImageView.heightAnchor.constraint(equalTo: largeImageView.widthAnchor, multiplier: 1.0 / aspectRatio),
            largeImageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])

        // Load image
        if let imageFileName = preview.image, !imageFileName.isEmpty {
            let screenWidth = window?.windowScene?.screen.bounds.width ?? 393
            let targetWidth = screenWidth - 32 - 28 - 3 - 8
            let targetHeight = targetWidth / aspectRatio
            let thumbSize = CGSize(width: targetWidth * 2, height: targetHeight * 2)
            ImageCache.shared.loadThumbnail(for: imageFileName, targetSize: thumbSize) { [weak self] image in
                self?.largeImageView.image = image
            }
        }

    }

    // MARK: - Compact Layout (text + small thumbnail)

    private func configureCompactLayout(preview: LinkPreview, hasSiteName: Bool, hasTitle: Bool) {
        titleLabel.numberOfLines = 1

        let hasImage = preview.image != nil && !(preview.image?.isEmpty ?? true)
        let hasDesc = preview.previewDescription != nil && !(preview.previewDescription?.isEmpty ?? true)

        descriptionLabel.text = preview.previewDescription
        descriptionLabel.isHidden = !hasDesc

        // Accent bar
        activeConstraints.append(contentsOf: [
            accentBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            accentBar.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            accentBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            accentBar.widthAnchor.constraint(equalToConstant: 3),
        ])

        let contentLeading = accentBar.trailingAnchor
        let trailingRef: NSLayoutXAxisAnchor

        // Thumbnail on the right
        if hasImage {
            thumbnailView.isHidden = false
            activeConstraints.append(contentsOf: [
                thumbnailView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
                thumbnailView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
                thumbnailView.widthAnchor.constraint(equalToConstant: 50),
                thumbnailView.heightAnchor.constraint(equalToConstant: 50),
            ])
            trailingRef = thumbnailView.leadingAnchor
            let trailingOffset: CGFloat = -8

            // Load thumbnail
            if let imageFileName = preview.image {
                let thumbSize = CGSize(width: 100, height: 100)
                ImageCache.shared.loadThumbnail(for: imageFileName, targetSize: thumbSize) { [weak self] image in
                    self?.thumbnailView.image = image
                }
            }

            // Text trailing to thumbnail
            var topAnchorRef = topAnchor
            let topOffset: CGFloat = 4
            if hasSiteName {
                activeConstraints.append(contentsOf: [
                    siteNameLabel.topAnchor.constraint(equalTo: topAnchorRef, constant: topOffset),
                    siteNameLabel.leadingAnchor.constraint(equalTo: contentLeading, constant: 8),
                    siteNameLabel.trailingAnchor.constraint(equalTo: trailingRef, constant: trailingOffset),
                ])
                topAnchorRef = siteNameLabel.bottomAnchor
            }
            if hasTitle {
                activeConstraints.append(contentsOf: [
                    titleLabel.topAnchor.constraint(equalTo: topAnchorRef, constant: hasSiteName ? 2 : topOffset),
                    titleLabel.leadingAnchor.constraint(equalTo: contentLeading, constant: 8),
                    titleLabel.trailingAnchor.constraint(equalTo: trailingRef, constant: trailingOffset),
                ])
                topAnchorRef = titleLabel.bottomAnchor
            }
            if hasDesc {
                activeConstraints.append(contentsOf: [
                    descriptionLabel.topAnchor.constraint(equalTo: topAnchorRef, constant: 2),
                    descriptionLabel.leadingAnchor.constraint(equalTo: contentLeading, constant: 8),
                    descriptionLabel.trailingAnchor.constraint(equalTo: trailingRef, constant: trailingOffset),
                    descriptionLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -4),
                ])
            }
        } else {
            // No image — text fills full width
            var topAnchorRef = topAnchor
            let topOffset: CGFloat = 4
            if hasSiteName {
                activeConstraints.append(contentsOf: [
                    siteNameLabel.topAnchor.constraint(equalTo: topAnchorRef, constant: topOffset),
                    siteNameLabel.leadingAnchor.constraint(equalTo: contentLeading, constant: 8),
                    siteNameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
                ])
                topAnchorRef = siteNameLabel.bottomAnchor
            }
            if hasTitle {
                activeConstraints.append(contentsOf: [
                    titleLabel.topAnchor.constraint(equalTo: topAnchorRef, constant: hasSiteName ? 2 : topOffset),
                    titleLabel.leadingAnchor.constraint(equalTo: contentLeading, constant: 8),
                    titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
                ])
                topAnchorRef = titleLabel.bottomAnchor
            }
            if hasDesc {
                activeConstraints.append(contentsOf: [
                    descriptionLabel.topAnchor.constraint(equalTo: topAnchorRef, constant: 2),
                    descriptionLabel.leadingAnchor.constraint(equalTo: contentLeading, constant: 8),
                    descriptionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
                    descriptionLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -4),
                ])
            }
        }
    }

    // MARK: - Height Calculation

    static func calculateHeight(for preview: LinkPreview, maxWidth: CGFloat) -> CGFloat {
        if preview.isPlaceholder == true {
            return 58  // Fixed height matching compact with thumbnail
        }
        if preview.isLargeImage {
            return calculateLargeHeight(for: preview, maxWidth: maxWidth)
        } else {
            return calculateCompactHeight(for: preview, maxWidth: maxWidth)
        }
    }

    private static func calculateLargeHeight(for preview: LinkPreview, maxWidth: CGFloat) -> CGFloat {
        let textWidth = maxWidth - 14 - 3 - 8 - 14  // leading margin + bar + spacing + trailing margin
        var height: CGFloat = 6  // top padding

        if let siteName = preview.siteName, !siteName.isEmpty {
            height += 16  // ~12pt font + spacing
        }
        if let title = preview.title, !title.isEmpty {
            let titleHeight = title.boundingRect(
                with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: UIFont.systemFont(ofSize: 15, weight: .semibold)],
                context: nil
            ).height
            height += min(ceil(titleHeight), 40) + 2  // 2 lines max
        }

        // Image height based on aspect ratio
        let imageWidth = textWidth
        let aspectRatio = preview.imageAspectRatio ?? 1.5
        height += 6  // spacing above image
        height += imageWidth / aspectRatio
        height += 6  // bottom padding

        return height
    }

    private static func calculateCompactHeight(for preview: LinkPreview, maxWidth: CGFloat) -> CGFloat {
        let fullTextWidth = maxWidth - 14 - 3 - 8 - 14  // margins - bar - spacing
        let hasImage = preview.image != nil && !(preview.image?.isEmpty ?? true)
        let availableTextWidth = hasImage ? fullTextWidth - 50 - 8 : fullTextWidth

        var height: CGFloat = 0

        if let siteName = preview.siteName, !siteName.isEmpty {
            height += 16
        }
        if let title = preview.title, !title.isEmpty {
            let titleHeight = title.boundingRect(
                with: CGSize(width: availableTextWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: UIFont.systemFont(ofSize: 15, weight: .semibold)],
                context: nil
            ).height
            height += min(ceil(titleHeight), 20) + 2
        }
        if let desc = preview.previewDescription, !desc.isEmpty {
            let descHeight = desc.boundingRect(
                with: CGSize(width: availableTextWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: UIFont.systemFont(ofSize: 14)],
                context: nil
            ).height
            height += min(ceil(descHeight), 54)  // 3 lines max
        }

        height += 8  // top + bottom padding

        // Minimum height to accommodate thumbnail
        if hasImage {
            height = max(height, 58)
        }

        return max(height, 30)
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
    var isKeyboardActive: Bool = false {
        didSet {
            checkboxRows.forEach { $0.isKeyboardActive = isKeyboardActive }
            // Disable text block UITextViews to prevent them from stealing first responder
            for subview in stackView.arrangedSubviews {
                if let textView = subview as? UITextView {
                    textView.isUserInteractionEnabled = !isKeyboardActive
                }
            }
        }
    }
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
        let orderedItems = message.orderedMediaItems
        let totalMedia = orderedItems.count
        let visibleCount = min(totalMedia, Self.maxVisibleThumbnails)
        let hiddenCount = totalMedia - visibleCount

        for index in 0..<visibleCount {
            let item = orderedItems[index]
            let isLast = (index == visibleCount - 1) && hiddenCount > 0
            let thumbnailView = createThumbnailView(isLast: isLast, hiddenCount: hiddenCount, isVideo: item.isVideo)
            thumbnailStack.addArrangedSubview(thumbnailView)

            let thumbSize = CGSize(width: Self.thumbnailSize * 2, height: Self.thumbnailSize * 2)
            let fileNameToLoad = item.isVideo ? (item.thumbnailFileName ?? item.fileName) : item.fileName
            ImageCache.shared.loadThumbnail(for: fileNameToLoad, targetSize: thumbSize) { [weak thumbnailView] image in
                DispatchQueue.main.async {
                    guard let imageView = thumbnailView?.subviews.first as? UIImageView else { return }
                    imageView.image = image
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
