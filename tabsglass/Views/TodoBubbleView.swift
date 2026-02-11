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

final class TodoCheckboxRow: UIView {

    /// Callback when checkbox is toggled: (itemId, isCompleted)
    var onToggle: ((UUID, Bool) -> Void)?

    private var itemId: UUID?
    private var isCompleted: Bool = false
    private var isDarkMode: Bool = false

    private let checkboxButton = UIButton(type: .system)
    private let textLabel = UILabel()

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

        // Text label
        textLabel.font = .systemFont(ofSize: 16)
        textLabel.numberOfLines = 0
        textLabel.isUserInteractionEnabled = true
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textLabel)

        // Tap on text also toggles checkbox
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(checkboxTapped))
        textLabel.addGestureRecognizer(tapGesture)

        NSLayoutConstraint.activate([
            checkboxButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            checkboxButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            checkboxButton.widthAnchor.constraint(equalToConstant: 30),
            checkboxButton.heightAnchor.constraint(equalToConstant: 30),

            textLabel.leadingAnchor.constraint(equalTo: checkboxButton.trailingAnchor, constant: 10),
            textLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            textLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            textLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
    }

    func configure(with item: TodoItem, isDarkMode: Bool) {
        itemId = item.id
        isCompleted = item.isCompleted
        self.isDarkMode = isDarkMode

        let textColor: UIColor = isDarkMode ? .white : .black
        if item.isCompleted {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16),
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .foregroundColor: textColor.withAlphaComponent(0.5)
            ]
            textLabel.attributedText = NSAttributedString(string: item.text, attributes: attributes)
        } else {
            textLabel.attributedText = nil
            textLabel.text = item.text
            textLabel.textColor = textColor
        }

        updateCheckboxAppearance()
    }

    private func updateCheckboxAppearance() {
        let imageName = isCompleted ? "checkmark.circle.fill" : "circle"
        let config = UIImage.SymbolConfiguration(pointSize: 26, weight: .regular)
        let image = UIImage(systemName: imageName, withConfiguration: config)
        checkboxButton.setImage(image, for: .normal)
        checkboxButton.tintColor = isCompleted ? .systemGreen : .secondaryLabel
    }

    @objc private func checkboxTapped() {
        guard let itemId = itemId else { return }
        isCompleted.toggle()

        // Haptic feedback when completing a task
        if isCompleted {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        }

        updateCheckboxAppearance()

        // Get current text
        let currentText = textLabel.attributedText?.string ?? textLabel.text ?? ""

        // Animate text change
        UIView.transition(with: textLabel, duration: 0.2, options: .transitionCrossDissolve) {
            let textColor: UIColor = self.isDarkMode ? .white : .black
            if self.isCompleted {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 16),
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor: textColor.withAlphaComponent(0.5)
                ]
                self.textLabel.attributedText = NSAttributedString(string: currentText, attributes: attributes)
            } else {
                self.textLabel.attributedText = nil
                self.textLabel.text = currentText
                self.textLabel.textColor = textColor
            }
        }

        onToggle?(itemId, isCompleted)
    }

    /// Calculate height for a row with given text and max width
    static func calculateHeight(for text: String, maxWidth: CGFloat) -> CGFloat {
        let checkboxWidth: CGFloat = 30
        let spacing: CGFloat = 10
        let verticalPadding: CGFloat = 24  // 12 top + 12 bottom
        let textWidth = maxWidth - checkboxWidth - spacing

        let textHeight = text.boundingRect(
            with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: UIFont.systemFont(ofSize: 16)],
            context: nil
        ).height

        return max(44, ceil(textHeight) + verticalPadding)  // Minimum 44pt for touch target
    }
}
