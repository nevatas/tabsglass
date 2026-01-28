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

    private let stackView = UIStackView()
    private let footerLabel = UILabel()
    private var checkboxRows: [TodoCheckboxRow] = []
    private var separators: [UIView] = []
    private var items: [TodoItem] = []
    private var isDarkMode: Bool = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
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

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            footerLabel.topAnchor.constraint(equalTo: stackView.bottomAnchor, constant: 8),
            footerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            footerLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            footerLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
    }

    func configure(with items: [TodoItem], isDarkMode: Bool) {
        self.items = items
        self.isDarkMode = isDarkMode

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
            line.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 36), // Align with text (checkbox 24 + spacing 12)
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
    static func calculateHeight(for items: [TodoItem], maxWidth: CGFloat) -> CGFloat {
        guard !items.isEmpty else { return 0 }

        let horizontalPadding: CGFloat = 24  // 12 + 12
        let topPadding: CGFloat = 4
        let bottomPadding: CGFloat = 10
        let footerHeight: CGFloat = 20  // font 14 + some padding
        let footerSpacing: CGFloat = 8
        let separatorHeight: CGFloat = 1
        let availableWidth = maxWidth - horizontalPadding

        var totalHeight = topPadding

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
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textLabel)

        NSLayoutConstraint.activate([
            checkboxButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            checkboxButton.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            checkboxButton.widthAnchor.constraint(equalToConstant: 24),
            checkboxButton.heightAnchor.constraint(equalToConstant: 24),

            textLabel.leadingAnchor.constraint(equalTo: checkboxButton.trailingAnchor, constant: 12),
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
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        let image = UIImage(systemName: imageName, withConfiguration: config)
        checkboxButton.setImage(image, for: .normal)
        checkboxButton.tintColor = isCompleted ? .systemGreen : .secondaryLabel
    }

    @objc private func checkboxTapped() {
        guard let itemId = itemId else { return }
        isCompleted.toggle()
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
        let checkboxWidth: CGFloat = 24
        let spacing: CGFloat = 12
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
