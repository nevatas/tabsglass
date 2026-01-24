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
    var onTextChange: ((String) -> Void)?
    var onSend: (() -> Void)?
}

// MARK: - SwiftUI Composer Wrapper

final class SwiftUIComposerContainer: UIView {
    var onTextChange: ((String) -> Void)?
    var onSend: (() -> Void)? {
        didSet { composerState.onSend = onSend }
    }

    /// Callback для уведомления о изменении высоты
    var onHeightChange: ((CGFloat) -> Void)?

    private let composerState = ComposerState()
    private var hostingController: UIHostingController<EmbeddedComposerView>?
    private var currentHeight: CGFloat = 80

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        setupHostingController()
        setupTextChangeHandler()
        setupTapGesture()
    }

    private func setupTapGesture() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
    }

    @objc private func handleTap() {
        // Force focus on tap to work around UIHostingController + FocusState issues
        composerState.shouldFocus = true
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
    }

    private func setupHostingController() {
        let composerView = EmbeddedComposerView(state: composerState)
        let hc = UIHostingController(rootView: composerView)
        hc.view.backgroundColor = .clear
        hc.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hc.view)

        NSLayoutConstraint.activate([
            hc.view.topAnchor.constraint(equalTo: topAnchor),
            hc.view.bottomAnchor.constraint(equalTo: bottomAnchor),
            hc.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hc.view.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        hostingController = hc
    }

    /// Вычисляет текущую требуемую высоту
    func calculateHeight() -> CGFloat {
        guard let hc = hostingController else { return 80 }
        let targetWidth = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width
        let fittingSize = hc.sizeThatFits(in: CGSize(width: targetWidth, height: .greatestFiniteMagnitude))
        return max(80, fittingSize.height)
    }

    /// Обновляет высоту и уведомляет parent (синхронно, без async)
    private func updateHeight() {
        let newHeight = calculateHeight()
        if abs(newHeight - currentHeight) > 1 {
            currentHeight = newHeight
            onHeightChange?(newHeight)
        }
    }

    func clearText() {
        composerState.text = ""

        // Принудительно обновляем hosting controller
        hostingController?.view.setNeedsLayout()
        hostingController?.view.layoutIfNeeded()

        // Сразу устанавливаем минимальную высоту
        currentHeight = 80
        onHeightChange?(80)
    }

    // Отключаем intrinsicContentSize - используем явный height constraint
    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }
}

// MARK: - Embedded Composer (without FocusState)

struct EmbeddedComposerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var state: ComposerState
    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !state.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 12) {
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

                HStack {
                    Button {
                        // Attach action
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

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
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
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

// MARK: - Message Cell

final class MessageTableCell: UITableViewCell {
    private let bubbleView = UIView()
    private let messageLabel = UILabel()

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
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bubbleView)

        messageLabel.textColor = .white
        messageLabel.font = .systemFont(ofSize: 16)
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            bubbleView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 4),
            bubbleView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -4),
            bubbleView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            bubbleView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),

            messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 10),
            messageLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -10),
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

    func configure(with message: Message) {
        messageLabel.text = message.text
        updateBubbleColor()
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
