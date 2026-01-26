//
//  FormattingTextView.swift
//  tabsglass
//
//  Custom UITextView with formatting menu (Bold, Italic, Underline, Strikethrough)
//

import SwiftUI
import UIKit

// MARK: - Formatting Text View

/// Custom UITextView that replaces AutoFill with Formatting submenu
final class FormattingTextView: UITextView {

    var onTextChange: ((NSAttributedString) -> Void)?
    var onFocusChange: ((Bool) -> Void)?
    var placeholder: String = "Note..." {
        didSet {
            placeholderLabel.text = placeholder
            // Hide if empty or if there's text
            placeholderLabel.isHidden = placeholder.isEmpty || !text.isEmpty
        }
    }

    private let placeholderLabel = UILabel()

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        font = .systemFont(ofSize: 16)
        backgroundColor = .clear
        isScrollEnabled = false
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0

        // Placeholder
        placeholderLabel.text = placeholder
        placeholderLabel.font = font
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderLabel)

        NSLayoutConstraint.activate([
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
        ])

        // Listen for text changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange),
            name: UITextView.textDidChangeNotification,
            object: self
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func textDidChange() {
        placeholderLabel.isHidden = !text.isEmpty

        // Reset formatting when text becomes empty
        if text.isEmpty {
            typingAttributes = [.font: UIFont.systemFont(ofSize: 16)]
        }

        onTextChange?(attributedText)
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            onFocusChange?(true)
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result {
            onFocusChange?(false)
        }
        return result
    }

    // MARK: - Edit Menu Customization

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        // Block AutoFill related actions
        let autoFillSelectors = [
            "fillWithOneTimeSMSCode:",
            "_autofill:",
            "_promptForReplace:",
            "_showTextStyleOptions:",
            "_accessibilitySpeak:",
            "_accessibilitySpeakLanguageSelection:",
            "_accessibilityPauseSpeaking:",
            "_share:",
            "_lookup:",
            "_translate:",
            "_searchWeb:",
            "_addShortcut:",
            "_define:",
        ]

        let actionString = NSStringFromSelector(action)
        if autoFillSelectors.contains(actionString) {
            return false
        }

        // Allow formatting actions when text is selected
        if action == #selector(applyBold(_:)) ||
           action == #selector(applyItalic(_:)) ||
           action == #selector(toggleUnderline(_:)) ||
           action == #selector(applyStrikethrough(_:)) {
            return selectedRange.length > 0
        }

        return super.canPerformAction(action, withSender: sender)
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)

        // Remove system menus we don't need
        builder.remove(menu: .autoFill)
        builder.remove(menu: .format)  // Remove system Format menu (we have our own)

        // Only add formatting when there's a selection
        if selectedRange.length > 0 {
            // Create formatting submenu
            let boldAction = UIAction(title: "Bold", image: UIImage(systemName: "bold")) { [weak self] _ in
                self?.applyBold(nil)
            }

            let italicAction = UIAction(title: "Italic", image: UIImage(systemName: "italic")) { [weak self] _ in
                self?.applyItalic(nil)
            }

            let underlineAction = UIAction(title: "Underline", image: UIImage(systemName: "underline")) { [weak self] _ in
                self?.toggleUnderline(nil)
            }

            let strikethroughAction = UIAction(title: "Strikethrough", image: UIImage(systemName: "strikethrough")) { [weak self] _ in
                self?.applyStrikethrough(nil)
            }

            let linkAction = UIAction(title: "Link", image: UIImage(systemName: "link")) { [weak self] _ in
                self?.showLinkAlert()
            }

            let formattingMenu = UIMenu(
                title: "Format",
                image: UIImage(systemName: "textformat"),
                children: [boldAction, italicAction, underlineAction, strikethroughAction, linkAction]
            )

            // Insert after standardEdit menu
            builder.insertSibling(formattingMenu, afterMenu: .standardEdit)
        }
    }

    // MARK: - Formatting Actions

    @objc func applyBold(_ sender: Any?) {
        applyFormatting(.bold)
    }

    @objc func applyItalic(_ sender: Any?) {
        applyFormatting(.italic)
    }

    @objc override func toggleUnderline(_ sender: Any?) {
        applyFormatting(.underline)
    }

    @objc func applyStrikethrough(_ sender: Any?) {
        applyFormatting(.strikethrough)
    }

    // MARK: - Link Actions

    private func showLinkAlert() {
        guard selectedRange.length > 0 else { return }
        guard let viewController = findViewController() else { return }

        // Store selection before showing alert (it might be lost)
        let savedRange = selectedRange

        let linkAlert = LinkInputAlertController(
            title: "Добавить ссылку",
            placeholder: "https://example.com",
            validateURL: isValidURL,
            onDone: { [weak self] urlString in
                self?.applyLink(urlString, to: savedRange)
            },
            onShake: { [weak self] textField in
                self?.shakeTextField(textField)
            }
        )

        viewController.present(linkAlert, animated: true)
    }

    private func isValidURL(_ string: String) -> Bool {
        // Add scheme if missing
        var urlString = string
        if !urlString.lowercased().hasPrefix("http://") && !urlString.lowercased().hasPrefix("https://") {
            urlString = "https://" + urlString
        }

        guard let url = URL(string: urlString),
              let host = url.host,
              host.contains(".") else {
            return false
        }
        return true
    }

    private func shakeTextField(_ textField: UITextField) {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.duration = 0.4
        animation.values = [-10, 10, -8, 8, -5, 5, -2, 2, 0]
        textField.layer.add(animation, forKey: "shake")
    }

    private func applyLink(_ urlString: String, to range: NSRange) {
        guard range.length > 0, range.location + range.length <= attributedText.length else { return }

        // Normalize URL
        var normalizedURL = urlString
        if !normalizedURL.lowercased().hasPrefix("http://") && !normalizedURL.lowercased().hasPrefix("https://") {
            normalizedURL = "https://" + normalizedURL
        }

        let mutableAttr = NSMutableAttributedString(attributedString: attributedText)

        // Add link attribute and underline style
        mutableAttr.addAttribute(.link, value: normalizedURL, range: range)
        mutableAttr.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        mutableAttr.addAttribute(.foregroundColor, value: UIColor.link, range: range)

        attributedText = mutableAttr

        // Reset typing attributes so new text after link isn't formatted as link
        typingAttributes = [.font: UIFont.systemFont(ofSize: 16)]

        onTextChange?(attributedText)
    }

    private func findViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let nextResponder = responder?.next {
            if let viewController = nextResponder as? UIViewController {
                return viewController
            }
            responder = nextResponder
        }
        return nil
    }

    enum FormattingStyle {
        case bold, italic, underline, strikethrough
    }

    private func applyFormatting(_ style: FormattingStyle) {
        guard selectedRange.length > 0 else { return }

        let mutableAttr = NSMutableAttributedString(attributedString: attributedText)
        let range = selectedRange

        switch style {
        case .bold:
            // Check if already bold
            var isBold = false
            mutableAttr.enumerateAttribute(.font, in: range, options: []) { value, _, _ in
                if let font = value as? UIFont {
                    isBold = font.fontDescriptor.symbolicTraits.contains(.traitBold)
                }
            }

            let newFont: UIFont
            if isBold {
                newFont = .systemFont(ofSize: 16)
            } else {
                newFont = .boldSystemFont(ofSize: 16)
            }
            mutableAttr.addAttribute(.font, value: newFont, range: range)

        case .italic:
            var isItalic = false
            mutableAttr.enumerateAttribute(.font, in: range, options: []) { value, _, _ in
                if let font = value as? UIFont {
                    isItalic = font.fontDescriptor.symbolicTraits.contains(.traitItalic)
                }
            }

            let newFont: UIFont
            if isItalic {
                newFont = .systemFont(ofSize: 16)
            } else {
                newFont = .italicSystemFont(ofSize: 16)
            }
            mutableAttr.addAttribute(.font, value: newFont, range: range)

        case .underline:
            var hasUnderline = false
            mutableAttr.enumerateAttribute(.underlineStyle, in: range, options: []) { value, _, _ in
                if let style = value as? Int, style != 0 {
                    hasUnderline = true
                }
            }

            if hasUnderline {
                mutableAttr.removeAttribute(.underlineStyle, range: range)
            } else {
                mutableAttr.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }

        case .strikethrough:
            var hasStrikethrough = false
            mutableAttr.enumerateAttribute(.strikethroughStyle, in: range, options: []) { value, _, _ in
                if let style = value as? Int, style != 0 {
                    hasStrikethrough = true
                }
            }

            if hasStrikethrough {
                mutableAttr.removeAttribute(.strikethroughStyle, range: range)
            } else {
                mutableAttr.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
        }

        // Preserve selection
        let savedRange = selectedRange
        attributedText = mutableAttr
        selectedRange = savedRange

        onTextChange?(attributedText)
    }

    // MARK: - Extract Entities

    /// Extract TextEntity array from current attributed text
    func extractEntities() -> [TextEntity] {
        var entities: [TextEntity] = []
        let fullRange = NSRange(location: 0, length: attributedText.length)

        attributedText.enumerateAttributes(in: fullRange, options: []) { attributes, range, _ in
            // Check for bold
            if let font = attributes[.font] as? UIFont,
               font.fontDescriptor.symbolicTraits.contains(.traitBold) {
                entities.append(TextEntity(type: "bold", offset: range.location, length: range.length))
            }

            // Check for italic
            if let font = attributes[.font] as? UIFont,
               font.fontDescriptor.symbolicTraits.contains(.traitItalic) {
                entities.append(TextEntity(type: "italic", offset: range.location, length: range.length))
            }

            // Check for underline (but not if it's part of a link - links have their own underline)
            if let underline = attributes[.underlineStyle] as? Int, underline != 0,
               attributes[.link] == nil {
                entities.append(TextEntity(type: "underline", offset: range.location, length: range.length))
            }

            // Check for strikethrough
            if let strikethrough = attributes[.strikethroughStyle] as? Int, strikethrough != 0 {
                entities.append(TextEntity(type: "strikethrough", offset: range.location, length: range.length))
            }

            // Check for links (text_link type - hyperlinked text)
            if let link = attributes[.link] {
                let urlString: String
                if let url = link as? URL {
                    urlString = url.absoluteString
                } else if let string = link as? String {
                    urlString = string
                } else {
                    return
                }
                entities.append(TextEntity(type: "text_link", offset: range.location, length: range.length, url: urlString))
            }
        }

        return entities
    }

    /// Clear text and formatting
    func clear() {
        attributedText = NSAttributedString()
        placeholderLabel.isHidden = false
    }
}

// MARK: - SwiftUI Wrapper

struct FormattingTextViewRepresentable: UIViewRepresentable {
    @Binding var text: String
    @Binding var attributedText: NSAttributedString
    var placeholder: String = "Note..."
    var onFocusChange: ((Bool) -> Void)?
    var shouldFocus: Binding<Bool>?

    func makeUIView(context: Context) -> FormattingTextView {
        let textView = FormattingTextView()
        textView.placeholder = placeholder
        textView.delegate = context.coordinator
        textView.onTextChange = { newAttr in
            DispatchQueue.main.async {
                self.attributedText = newAttr
                self.text = newAttr.string
            }
        }
        textView.onFocusChange = onFocusChange
        return textView
    }

    func updateUIView(_ uiView: FormattingTextView, context: Context) {
        // Update placeholder
        if uiView.placeholder != placeholder {
            uiView.placeholder = placeholder
        }

        // Handle focus request
        if let shouldFocus = shouldFocus, shouldFocus.wrappedValue {
            DispatchQueue.main.async {
                _ = uiView.becomeFirstResponder()
                shouldFocus.wrappedValue = false
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: FormattingTextViewRepresentable

        init(_ parent: FormattingTextViewRepresentable) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.attributedText = textView.attributedText
        }
    }
}

// MARK: - Custom Link Input Alert

/// Custom alert controller that doesn't dismiss on invalid URL
final class LinkInputAlertController: UIViewController {
    private let alertTitle: String
    private let placeholder: String
    private let validateURL: (String) -> Bool
    private let onDone: (String) -> Void
    private let onShake: (UITextField) -> Void

    private let containerView = UIView()
    private let titleLabel = UILabel()
    private let textField = UITextField()
    private let buttonStack = UIStackView()
    private let cancelButton = UIButton(type: .system)
    private let doneButton = UIButton(type: .system)

    init(title: String, placeholder: String, validateURL: @escaping (String) -> Bool, onDone: @escaping (String) -> Void, onShake: @escaping (UITextField) -> Void) {
        self.alertTitle = title
        self.placeholder = placeholder
        self.validateURL = validateURL
        self.onDone = onDone
        self.onShake = onShake
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textField.becomeFirstResponder()
    }

    private func setupUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)

        // Container
        containerView.backgroundColor = .secondarySystemBackground
        containerView.layer.cornerRadius = 14
        containerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(containerView)

        // Title
        titleLabel.text = alertTitle
        titleLabel.font = .boldSystemFont(ofSize: 17)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(titleLabel)

        // Text field
        textField.placeholder = placeholder
        textField.borderStyle = .roundedRect
        textField.keyboardType = .URL
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.returnKeyType = .done
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.addTarget(self, action: #selector(textFieldReturnPressed), for: .editingDidEndOnExit)
        containerView.addSubview(textField)

        // Separator
        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(separator)

        // Buttons
        buttonStack.axis = .horizontal
        buttonStack.distribution = .fillEqually
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(buttonStack)

        cancelButton.setTitle("Отмена", for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 17)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        doneButton.setTitle("Готово", for: .normal)
        doneButton.titleLabel?.font = .boldSystemFont(ofSize: 17)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

        let verticalSeparator = UIView()
        verticalSeparator.backgroundColor = .separator
        verticalSeparator.translatesAutoresizingMaskIntoConstraints = false

        buttonStack.addArrangedSubview(cancelButton)
        buttonStack.addArrangedSubview(doneButton)
        containerView.addSubview(verticalSeparator)

        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -50),
            containerView.widthAnchor.constraint(equalToConstant: 270),

            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),

            textField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            textField.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            textField.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            textField.heightAnchor.constraint(equalToConstant: 36),

            separator.topAnchor.constraint(equalTo: textField.bottomAnchor, constant: 16),
            separator.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            buttonStack.topAnchor.constraint(equalTo: separator.bottomAnchor),
            buttonStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            buttonStack.heightAnchor.constraint(equalToConstant: 44),

            verticalSeparator.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            verticalSeparator.topAnchor.constraint(equalTo: separator.bottomAnchor),
            verticalSeparator.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            verticalSeparator.widthAnchor.constraint(equalToConstant: 0.5),
        ])

        // Tap outside to dismiss
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped))
        tapGesture.delegate = self
        view.addGestureRecognizer(tapGesture)
    }

    @objc private func cancelTapped() {
        textField.resignFirstResponder()
        dismiss(animated: true)
    }

    @objc private func doneTapped() {
        validateAndSubmit()
    }

    @objc private func textFieldReturnPressed() {
        validateAndSubmit()
    }

    @objc private func backgroundTapped() {
        textField.resignFirstResponder()
        dismiss(animated: true)
    }

    private func validateAndSubmit() {
        guard let urlString = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !urlString.isEmpty else {
            onShake(textField)
            return
        }

        if validateURL(urlString) {
            textField.resignFirstResponder()
            dismiss(animated: true) { [weak self] in
                self?.onDone(urlString)
            }
        } else {
            onShake(textField)
        }
    }
}

extension LinkInputAlertController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Only handle taps outside the container
        return !containerView.frame.contains(touch.location(in: view))
    }
}
