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
    private(set) var isEditMenuVisible: Bool = false
    private var editMenuLockUntil: CFTimeInterval = 0
    private var cachedEditMenuTargetRect: CGRect?
    private var pendingMenuDismissWorkItem: DispatchWorkItem?
    var placeholder: String = "Note..." {
        didSet {
            placeholderLabel.text = placeholder
            // Hide if empty or if there's text
            placeholderLabel.isHidden = placeholder.isEmpty || !text.isEmpty
        }
    }

    private let placeholderLabel = UILabel()
    @available(iOS 16.0, *)
    private lazy var editMenuInteraction = UIEditMenuInteraction(delegate: self)

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

        // Configure link text attributes to use theme color
        updateLinkTextAttributes()

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

        // Listen for theme changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: .themeDidChange,
            object: nil
        )

        setupEditMenuTracking()
    }

    private func updateLinkTextAttributes() {
        let linkColor = ThemeManager.shared.currentTheme.linkColor
        linkTextAttributes = [
            .foregroundColor: linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
    }

    @objc private func themeDidChange() {
        updateLinkTextAttributes()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        pendingMenuDismissWorkItem?.cancel()
    }

    /// Returns the default text color based on current trait collection
    private var defaultTextColor: UIColor {
        traitCollection.userInterfaceStyle == .dark ? .white : .black
    }

    private var defaultTypingAttributes: [NSAttributedString.Key: Any] {
        [
            .font: UIFont.systemFont(ofSize: 16),
            .foregroundColor: defaultTextColor
        ]
    }

    @objc private func textDidChange() {
        pendingMenuDismissWorkItem?.cancel()
        isEditMenuVisible = false
        placeholderLabel.isHidden = !text.isEmpty

        // Reset formatting when text becomes empty
        if text.isEmpty {
            resetToDefaultAttributes()
        } else {
            // Ensure typing attributes don't inherit link styling
            let hasLinkAttr = typingAttributes[.link] != nil
            let hasUnderline = typingAttributes[.underlineStyle] != nil
            let currentColor = typingAttributes[.foregroundColor] as? UIColor
            let normalColor = defaultTextColor
            let isNotNormalColor = currentColor != nil && currentColor != normalColor

            if hasLinkAttr || hasUnderline || isNotNormalColor {
                typingAttributes = defaultTypingAttributes
            }
        }

        // Notify SwiftUI about size change
        invalidateIntrinsicContentSize()

        onTextChange?(attributedText)
    }


    private func resetToDefaultAttributes() {
        let attrs = defaultTypingAttributes
        attributedText = NSAttributedString(string: "", attributes: attrs)
        typingAttributes = attrs
        // Also explicitly set text color
        textColor = defaultTextColor
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
            isEditMenuVisible = false
            onFocusChange?(false)
        }
        return result
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        beginEditMenuSession()
        cachedEditMenuTargetRect = currentSelectionRect()

        // Remove system menus we don't need
        builder.remove(menu: .autoFill)
        builder.remove(menu: .format)  // Remove system Format menu (we have our own)

        // Create formatting submenu
        let boldAction = UIAction(title: L10n.Format.bold, image: UIImage(systemName: "bold")) { [weak self] _ in
            self?.applyBold(nil)
        }

        let italicAction = UIAction(title: L10n.Format.italic, image: UIImage(systemName: "italic")) { [weak self] _ in
            self?.applyItalic(nil)
        }

        let underlineAction = UIAction(title: L10n.Format.underline, image: UIImage(systemName: "underline")) { [weak self] _ in
            self?.toggleUnderline(nil)
        }

        let strikethroughAction = UIAction(title: L10n.Format.strikethrough, image: UIImage(systemName: "strikethrough")) { [weak self] _ in
            self?.applyStrikethrough(nil)
        }

        let linkAction = UIAction(title: L10n.Format.link, image: UIImage(systemName: "link")) { [weak self] _ in
            self?.showLinkAlert()
        }

        let formattingMenu = UIMenu(
            title: "",
            options: .displayInline,
            children: [boldAction, italicAction, underlineAction, strikethroughAction, linkAction]
        )

        // Insert after standardEdit menu
        builder.insertSibling(formattingMenu, afterMenu: .standardEdit)
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

        let linkSheet = LinkInputSheet(
            onDone: { [weak self] urlString in
                self?.applyLink(urlString, to: savedRange)
            },
            validateURL: isValidURL
        )

        let hostingController = UIHostingController(rootView: linkSheet)
        hostingController.modalPresentationStyle = .overFullScreen
        hostingController.modalTransitionStyle = .crossDissolve
        hostingController.view.backgroundColor = .clear

        viewController.present(hostingController, animated: true)
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

        // Use theme's link color
        let linkColor = ThemeManager.shared.currentTheme.linkColor

        // Add link attribute and underline style
        mutableAttr.addAttribute(.link, value: normalizedURL, range: range)
        mutableAttr.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        mutableAttr.addAttribute(.foregroundColor, value: linkColor, range: range)

        // Insert a zero-width space with normal attributes after the link to break attribute inheritance
        let zeroWidthSpace = NSAttributedString(string: "\u{200B}", attributes: defaultTypingAttributes)
        mutableAttr.insert(zeroWidthSpace, at: range.location + range.length)

        attributedText = mutableAttr

        // Move cursor after the zero-width space
        selectedRange = NSRange(location: range.location + range.length + 1, length: 0)

        // Reset typing attributes
        typingAttributes = defaultTypingAttributes

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

        // Deselect and reset typing attributes so new text is unformatted
        selectedRange = NSRange(location: savedRange.location + savedRange.length, length: 0)
        typingAttributes = defaultTypingAttributes

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
        resetToDefaultAttributes()
        placeholderLabel.isHidden = false
    }

    private func setupEditMenuTracking() {
        if #available(iOS 16.0, *) {
            addInteraction(editMenuInteraction)
        }
    }

    var isEditMenuLayoutLocked: Bool {
        isEditMenuVisible || CACurrentMediaTime() < editMenuLockUntil
    }

    private func lockEditMenuLayout(duration: TimeInterval = 0.8) {
        isEditMenuVisible = true
        editMenuLockUntil = CACurrentMediaTime() + duration
    }

    private func currentSelectionRect() -> CGRect {
        guard let range = selectedTextRange else {
            return caretRect(for: endOfDocument)
        }

        let firstRect = self.firstRect(for: range)
        if !firstRect.isNull && !firstRect.isEmpty {
            return firstRect
        }

        return caretRect(for: range.start)
    }

    private func beginEditMenuSession() {
        pendingMenuDismissWorkItem?.cancel()
        pendingMenuDismissWorkItem = nil
        lockEditMenuLayout()
    }

    private func scheduleEndEditMenuSession(delay: TimeInterval = 0.35) {
        pendingMenuDismissWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.isEditMenuVisible = false
        }
        pendingMenuDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}

@available(iOS 16.0, *)
extension FormattingTextView: UIEditMenuInteractionDelegate {
    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        willPresentMenuFor configuration: UIEditMenuConfiguration,
        animator: UIEditMenuInteractionAnimating
    ) {
        beginEditMenuSession()
        cachedEditMenuTargetRect = currentSelectionRect()
    }

    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        didDismissMenuFor configuration: UIEditMenuConfiguration
    ) {
        scheduleEndEditMenuSession(delay: 0.35)
        editMenuLockUntil = CACurrentMediaTime() + 0.8
        cachedEditMenuTargetRect = nil
    }

    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        targetRectFor configuration: UIEditMenuConfiguration
    ) -> CGRect {
        if let cached = cachedEditMenuTargetRect {
            return cached
        }
        let rect = currentSelectionRect()
        cachedEditMenuTargetRect = rect
        return rect
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

        // Sync text from SwiftUI binding - especially important when cleared after send
        if text.isEmpty && !uiView.text.isEmpty {
            uiView.clear()
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

// MARK: - Shake Modifier

struct ShakeModifier: ViewModifier {
    @Binding var trigger: Bool
    @State private var shakeOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: shakeOffset)
            .onChange(of: trigger) { _, newValue in
                if newValue {
                    performShake()
                    // Reset trigger after animation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        trigger = false
                    }
                }
            }
    }

    private func performShake() {
        let amplitude: CGFloat = 8.0
        let duration: Double = 0.08

        withAnimation(.linear(duration: duration)) { shakeOffset = amplitude }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            withAnimation(.linear(duration: duration)) { shakeOffset = -amplitude }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 2) {
            withAnimation(.linear(duration: duration)) { shakeOffset = amplitude * 0.6 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 3) {
            withAnimation(.linear(duration: duration)) { shakeOffset = -amplitude * 0.6 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 4) {
            withAnimation(.spring(duration: 0.15)) { shakeOffset = 0 }
        }
    }
}

extension View {
    func shake(trigger: Binding<Bool>) -> some View {
        self.modifier(ShakeModifier(trigger: trigger))
    }
}

// MARK: - Link Input Sheet (SwiftUI - iOS 26 Liquid Glass)

struct LinkInputSheet: View {
    let onDone: (String) -> Void
    let validateURL: (String) -> Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var urlText = ""
    @State private var shouldShake = false
    @FocusState private var isFocused: Bool

    @ViewBuilder
    private func controlBackground() -> some View {
        if colorScheme == .light {
            Capsule().fill(Color.black.opacity(0.12))
        } else {
            Capsule().fill(.ultraThinMaterial)
        }
    }

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            // Alert container
            VStack(spacing: 16) {
                // Title
                Text(L10n.Format.addLink)
                    .font(.body.weight(.semibold))
                    .padding(.top, 4)
                    .padding(.bottom, 12)

                // Text field - capsule style
                TextField("", text: $urlText, prompt: Text("URL").foregroundStyle(colorScheme == .light ? Color.black.opacity(0.4) : .secondary))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background { controlBackground() }
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .shake(trigger: $shouldShake)
                    .onSubmit {
                        validateAndSubmit()
                    }

                // Buttons - capsule, same background as input
                HStack(spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        Text(L10n.Tab.cancel)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(colorScheme == .light ? Color.primary : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .background { controlBackground() }

                    Button {
                        validateAndSubmit()
                    } label: {
                        Text(L10n.Settings.done)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(colorScheme == .light ? Color.primary : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .background { controlBackground() }
                }
            }
            .padding(24)
            .background {
                RoundedRectangle(cornerRadius: 36)
                    .fill(.clear)
                    .glassEffect(.regular, in: .rect(cornerRadius: 36))
            }
            .padding(.horizontal, 40)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }
        }
    }

    private func validateAndSubmit() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            triggerShake()
            return
        }

        if validateURL(trimmed) {
            dismiss()
            onDone(trimmed)
        } else {
            triggerShake()
        }
    }

    private func triggerShake() {
        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)

        // Trigger shake animation
        shouldShake = true
    }
}
