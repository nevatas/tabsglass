//
//  TodoBubbleView.swift
//  tabsglass
//
//  UIKit view for rendering todo list checkboxes in message bubbles
//

import UIKit

final class TodoBubbleView: UIView {

    /// Callback when a checkbox is toggled: (itemId, isCompleted)
    var onToggle: ((UUID, Bool) -> Void)?

    private let titleLabel = UILabel()
    private let stackView = UIStackView()
    private let footerLabel = UILabel()
    private var checkboxRows: [TodoCheckboxRow] = []
    private var separators: [UIView] = []
    private var items: [TodoItem] = []
    private var isDarkMode: Bool = false
    private var titleLabelHeightConstraint: NSLayoutConstraint!
    private var titleTopConstraint: NSLayoutConstraint!
    private var stackTopConstraint: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        // Title label
        titleLabel.font = .boldSystemFont(ofSize: 16)
        titleLabel.numberOfLines = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        stackView.axis = .vertical
        stackView.spacing = 0
        stackView.alignment = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        // Footer label
        footerLabel.font = .systemFont(ofSize: 14)
        footerLabel.textAlignment = .center
        footerLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(footerLabel)

        titleLabelHeightConstraint = titleLabel.heightAnchor.constraint(equalToConstant: 0)
        titleLabelHeightConstraint.priority = .defaultHigh  // Lower priority to avoid conflict when hidden

        // Use lower priority for vertical chain so constraints don't conflict when height=0
        titleTopConstraint = titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12)
        titleTopConstraint.priority = .defaultHigh

        stackTopConstraint = stackView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4)
        stackTopConstraint.priority = .defaultHigh

        let footerTop = footerLabel.topAnchor.constraint(equalTo: stackView.bottomAnchor, constant: 4)
        footerTop.priority = .defaultHigh

        let footerBottom = footerLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        footerBottom.priority = .defaultHigh

        NSLayoutConstraint.activate([
            titleTopConstraint,
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            titleLabelHeightConstraint,

            stackTopConstraint,
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            footerTop,
            footerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            footerLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            footerBottom
        ])
    }

    func configure(with title: String?, items: [TodoItem], isDarkMode: Bool) {
        self.items = items
        self.isDarkMode = isDarkMode

        // Configure title
        let textColor: UIColor = isDarkMode ? .white : .black
        if let title = title, !title.isEmpty {
            titleLabel.text = title
            titleLabel.textColor = textColor
            titleLabel.isHidden = false
            titleTopConstraint.constant = 12
            stackTopConstraint.constant = 4
            // Calculate title height
            let titleWidth = bounds.width - 28  // 14 + 14 padding
            let titleHeight = title.boundingRect(
                with: CGSize(width: max(titleWidth, 200), height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: UIFont.boldSystemFont(ofSize: 16)],
                context: nil
            ).height
            titleLabelHeightConstraint.constant = ceil(titleHeight)
        } else {
            titleLabel.text = nil
            titleLabel.isHidden = true
            titleTopConstraint.constant = 0
            stackTopConstraint.constant = 4
            titleLabelHeightConstraint.constant = 0
        }

        // Clear existing views
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        checkboxRows.removeAll()
        separators.removeAll()

        // Create rows with separators
        for (index, item) in items.enumerated() {
            let row = TodoCheckboxRow()
            row.configure(with: item, isDarkMode: isDarkMode)
            row.onToggle = { [weak self] itemId, isCompleted in
                self?.handleToggle(itemId: itemId, isCompleted: isCompleted)
            }
            stackView.addArrangedSubview(row)
            checkboxRows.append(row)

            // Add separator after each row except the last
            if index < items.count - 1 {
                let separator = createSeparator(isDarkMode: isDarkMode)
                stackView.addArrangedSubview(separator)
                separators.append(separator)
            }
        }

        updateFooter()
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
            line.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 40), // Align with text (checkbox 30 + spacing 10)
            line.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            line.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            line.heightAnchor.constraint(equalToConstant: 0.5)
        ])

        return container
    }

    private func handleToggle(itemId: UUID, isCompleted: Bool) {
        // Update local state
        if let index = items.firstIndex(where: { $0.id == itemId }) {
            items[index].isCompleted = isCompleted
        }
        updateFooter()
        onToggle?(itemId, isCompleted)
    }

    private func updateFooter() {
        let completed = items.filter { $0.isCompleted }.count
        let total = items.count
        footerLabel.text = L10n.TaskList.completed(completed, total)
        footerLabel.textColor = isDarkMode ? UIColor.white.withAlphaComponent(0.5) : UIColor.black.withAlphaComponent(0.5)
    }

    /// Calculate height for given items and max width
    static func calculateHeight(for title: String?, items: [TodoItem], maxWidth: CGFloat) -> CGFloat {
        guard !items.isEmpty else { return 0 }

        let horizontalPadding: CGFloat = 24  // 12 + 12
        let titleHorizontalPadding: CGFloat = 28  // 14 + 14
        let bottomPadding: CGFloat = 10
        let footerHeight: CGFloat = 20  // font 14 + some padding
        let footerSpacing: CGFloat = 4
        let separatorHeight: CGFloat = 1
        let availableWidth = maxWidth - horizontalPadding

        var totalHeight: CGFloat = 0

        // Title height
        if let title = title, !title.isEmpty {
            let titleWidth = maxWidth - titleHorizontalPadding
            let titleHeight = title.boundingRect(
                with: CGSize(width: titleWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: UIFont.boldSystemFont(ofSize: 16)],
                context: nil
            ).height
            totalHeight += 12 + ceil(titleHeight) + 4  // top padding + title + spacing to stack
        } else {
            totalHeight += 4  // no title — small top padding before stack
        }

        for (index, item) in items.enumerated() {
            let rowHeight = TodoCheckboxRow.calculateHeight(for: item.text, maxWidth: availableWidth)
            totalHeight += rowHeight
            if index < items.count - 1 {
                totalHeight += separatorHeight
            }
        }

        totalHeight += footerSpacing + footerHeight + bottomPadding

        return totalHeight
    }
}

// MARK: - Todo Checkbox Row

final class TodoCheckboxRow: UIView, UITextViewDelegate {

    /// Callback when checkbox is toggled: (itemId, isCompleted)
    var onToggle: ((UUID, Bool) -> Void)?

    private var itemId: UUID?
    private var isCompleted: Bool = false
    private var isDarkMode: Bool = false
    private var entities: [TextEntity]?
    private var baseAttributedText: NSAttributedString?

    private let checkboxButton = UIButton(type: .system)
    private let textView = UITextView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        // Checkbox button
        checkboxButton.translatesAutoresizingMaskIntoConstraints = false
        checkboxButton.addTarget(self, action: #selector(checkboxTapped), for: .touchUpInside)
        addSubview(checkboxButton)

        // Text view (replaces UILabel for link & formatting support)
        textView.font = .systemFont(ofSize: 16)
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.isSelectable = true
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.dataDetectorTypes = []
        textView.delegate = self
        textView.linkTextAttributes = [
            .foregroundColor: ThemeManager.shared.currentTheme.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        textView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textView)

        // Tap on non-link areas toggles checkbox
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(rowTapped(_:)))
        tapGesture.delegate = self
        addGestureRecognizer(tapGesture)

        NSLayoutConstraint.activate([
            checkboxButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            checkboxButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            checkboxButton.widthAnchor.constraint(equalToConstant: 30),
            checkboxButton.heightAnchor.constraint(equalToConstant: 30),

            textView.leadingAnchor.constraint(equalTo: checkboxButton.trailingAnchor, constant: 10),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.centerYAnchor.constraint(equalTo: centerYAnchor),
            textView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 10),
            textView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -10),

            heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])

        // Resist stretching in stack views so extra space goes to text blocks
        setContentHuggingPriority(.defaultHigh, for: .vertical)
    }

    func configure(with item: TodoItem, isDarkMode: Bool, entities: [TextEntity]? = nil) {
        itemId = item.id
        isCompleted = item.isCompleted
        self.isDarkMode = isDarkMode
        self.entities = entities

        let textColor: UIColor = isDarkMode ? .white : .black

        // Build base attributed string with formatting
        let baseAttrStr = Self.buildAttributedString(text: item.text, entities: entities, textColor: textColor)
        self.baseAttributedText = baseAttrStr

        if item.isCompleted {
            textView.attributedText = Self.applyCompletion(to: baseAttrStr, textColor: textColor)
        } else {
            textView.attributedText = baseAttrStr
        }

        updateCheckboxAppearance()
    }

    /// Build NSAttributedString with formatting entities applied
    private static func buildAttributedString(text: String, entities: [TextEntity]?, textColor: UIColor) -> NSAttributedString {
        let attrStr = NSMutableAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: 16),
            .foregroundColor: textColor
        ])

        guard let entities = entities else { return attrStr }
        let nsString = text as NSString

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

        return attrStr
    }

    /// Apply completion overlay: strikethrough + dimmed color, preserving existing formatting
    private static func applyCompletion(to base: NSAttributedString, textColor: UIColor) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: base)
        let fullRange = NSRange(location: 0, length: result.length)
        result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: fullRange)
        result.addAttribute(.foregroundColor, value: textColor.withAlphaComponent(0.5), range: fullRange)
        // Remove links when completed so taps toggle instead
        result.removeAttribute(.link, range: fullRange)
        return result
    }

    private func updateCheckboxAppearance() {
        let imageName = isCompleted ? "checkmark.circle.fill" : "circle"
        let config = UIImage.SymbolConfiguration(pointSize: 26, weight: .regular)
        let image = UIImage(systemName: imageName, withConfiguration: config)
        checkboxButton.setImage(image, for: .normal)
        checkboxButton.tintColor = isCompleted ? .systemGreen : .secondaryLabel
    }

    @objc private func checkboxTapped() {
        toggleCheckbox()
    }

    @objc private func rowTapped(_ gesture: UITapGestureRecognizer) {
        // Check if tap landed on a link in the text view
        let location = gesture.location(in: textView)
        if isPointOnLink(location) { return } // Let textView handle the link tap
        toggleCheckbox()
    }

    private func isPointOnLink(_ point: CGPoint) -> Bool {
        guard point.x >= 0, point.y >= 0 else { return false }
        let layoutManager = textView.layoutManager
        let textContainer = textView.textContainer
        var fraction: CGFloat = 0
        let charIndex = layoutManager.characterIndex(for: point, in: textContainer, fractionOfDistanceBetweenInsertionPoints: &fraction)
        guard charIndex < textView.attributedText.length else { return false }
        return textView.attributedText.attribute(.link, at: charIndex, effectiveRange: nil) != nil
    }

    private func toggleCheckbox() {
        guard let itemId = itemId else { return }
        isCompleted.toggle()

        if isCompleted {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }

        updateCheckboxAppearance()

        // Animate text change — preserve formatting
        UIView.transition(with: textView, duration: 0.2, options: .transitionCrossDissolve) {
            let textColor: UIColor = self.isDarkMode ? .white : .black
            if self.isCompleted {
                if let base = self.baseAttributedText {
                    self.textView.attributedText = Self.applyCompletion(to: base, textColor: textColor)
                }
            } else {
                self.textView.attributedText = self.baseAttributedText
            }
        }

        onToggle?(itemId, isCompleted)
    }

    // MARK: - UITextViewDelegate

    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        // Open the link in Safari — don't toggle the checkbox
        UIApplication.shared.open(URL)
        return false
    }

    /// Calculate height for a row with given text, entities, and max width
    static func calculateHeight(for text: String, maxWidth: CGFloat, entities: [TextEntity]? = nil) -> CGFloat {
        let checkboxWidth: CGFloat = 30
        let spacing: CGFloat = 10
        let verticalPadding: CGFloat = 20  // 10 top + 10 bottom
        let textWidth = maxWidth - checkboxWidth - spacing

        let attrStr: NSAttributedString
        if let entities = entities, !entities.isEmpty {
            attrStr = buildAttributedString(text: text, entities: entities, textColor: .black)
        } else {
            attrStr = NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 16)])
        }

        let textHeight = attrStr.boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).height

        return max(44, ceil(textHeight) + verticalPadding)  // Minimum 44pt for touch target
    }
}

extension TodoCheckboxRow: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Don't let row tap gesture fire if the touch is on a link
        let location = touch.location(in: textView)
        if location.x >= 0 && location.y >= 0 && isPointOnLink(location) {
            return false
        }
        return true
    }
}
