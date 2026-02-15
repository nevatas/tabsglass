//
//  LatestMessageWidget.swift
//  TabyWidget
//

import SwiftUI
import SwiftData
import WidgetKit

// MARK: - Localization

private enum WidgetL10n {
    private static var lang: String {
        Locale.current.language.languageCode?.identifier ?? "en"
    }

    static var latest: String {
        switch lang {
        case "ru": "Недавнее"
        case "de": "Neueste"
        case "fr": "Récente"
        case "es": "Reciente"
        default: "Latest"
        }
    }

    static var andMore: (Int) -> String {
        { count in
            switch lang {
            case "ru": "и ещё \(count)"
            case "de": "und \(count) mehr"
            case "fr": "et \(count) de plus"
            case "es": "y \(count) más"
            default: "and \(count) more"
            }
        }
    }
}

// MARK: - Entry

struct TodoLine: Identifiable {
    let id = UUID()
    let text: String
    let isCompleted: Bool
}

struct LatestMessageEntry: TimelineEntry {
    let date: Date
    let content: String
    let mediaLabel: String?
    let todoLines: [TodoLine]
    let tabName: String
    let deepLinkURL: URL?
    let theme: WidgetTheme
}

// MARK: - Provider

struct LatestMessageProvider: TimelineProvider {
    func placeholder(in context: Context) -> LatestMessageEntry {
        LatestMessageEntry(
            date: .now,
            content: "Check out this new feature!",
            mediaLabel: nil,
            todoLines: [],
            tabName: "📥 Inbox",
            deepLinkURL: URL(string: "taby://message"),
            theme: .current()
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (LatestMessageEntry) -> Void) {
        completion(fetchEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LatestMessageEntry>) -> Void) {
        let entry = fetchEntry()
        completion(Timeline(entries: [entry], policy: .never))
    }

    private func fetchEntry() -> LatestMessageEntry {
        let theme = WidgetTheme.current()

        guard let container = try? SharedModelContainer.create() else {
            return LatestMessageEntry(date: .now, content: "", mediaLabel: nil, todoLines: [], tabName: "", deepLinkURL: nil, theme: theme)
        }

        let context = ModelContext(container)
        context.autosaveEnabled = false

        // Fetch all tabs for name lookup
        var tabLookup: [UUID: String] = [:]
        if let tabs = try? context.fetch(FetchDescriptor<Tab>()) {
            for tab in tabs {
                tabLookup[tab.id] = tab.title
            }
        }

        // Fetch the latest message
        var descriptor = FetchDescriptor<Message>(sortBy: [SortDescriptor(\Message.createdAt, order: .reverse)])
        descriptor.fetchLimit = 1

        guard let messages = try? context.fetch(descriptor),
              let message = messages.first else {
            return LatestMessageEntry(date: .now, content: "", mediaLabel: nil, todoLines: [], tabName: "", deepLinkURL: nil, theme: theme)
        }

        let tabName = message.tabId.flatMap { tabLookup[$0] } ?? "📥 Inbox"

        // Build content string and todo lines
        var content = ""
        var todoLines: [TodoLine] = []

        if let blocks = message.contentBlocks, !blocks.isEmpty {
            var textParts: [String] = []
            for block in blocks {
                if block.type == "todo" {
                    todoLines.append(TodoLine(text: block.text, isCompleted: block.isCompleted))
                } else {
                    textParts.append(block.text)
                }
            }
            content = textParts.joined(separator: "\n")
        } else if let todos = message.todoItems, !todos.isEmpty {
            for item in todos {
                todoLines.append(TodoLine(text: item.text, isCompleted: item.isCompleted))
            }
        }

        if todoLines.isEmpty && content.isEmpty {
            content = message.content
        }

        // Build media label
        var mediaLabel: String?
        if message.hasMedia {
            let photoCount = message.photoFileNames.count
            let videoCount = message.videoFileNames.count
            let totalMedia = photoCount + videoCount
            if photoCount > 0 && videoCount > 0 {
                mediaLabel = "🖼️ \(totalMedia) Media"
            } else if photoCount > 0 {
                mediaLabel = "📷 Photo"
            } else {
                mediaLabel = "🎬 Video"
            }
        }

        // Build deep link URL
        var components = URLComponents()
        components.scheme = "taby"
        components.host = "message"
        var queryItems = [URLQueryItem(name: "message", value: message.id.uuidString)]
        if let tabId = message.tabId {
            queryItems.insert(URLQueryItem(name: "tab", value: tabId.uuidString), at: 0)
        }
        components.queryItems = queryItems

        return LatestMessageEntry(
            date: .now,
            content: content,
            mediaLabel: mediaLabel,
            todoLines: todoLines,
            tabName: tabName,
            deepLinkURL: components.url,
            theme: theme
        )
    }
}

// MARK: - Widget View

struct LatestMessageWidgetEntryView: View {
    let entry: LatestMessageEntry
    @Environment(\.colorScheme) private var systemColorScheme

    private var effectiveColorScheme: ColorScheme {
        entry.theme == .dark ? .dark : systemColorScheme
    }

    private var primaryText: Color {
        effectiveColorScheme == .dark ? .white : .black
    }

    private var secondaryText: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.5)
    }

    private var checkColor: Color {
        entry.theme.accentColor ?? (effectiveColorScheme == .dark ? .white : .gray)
    }

    var body: some View {
        if entry.deepLinkURL == nil {
            emptyState
        } else {
            messageContent
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "bubble.left")
                .font(.system(size: 28))
                .foregroundStyle(secondaryText)
            Text("No messages yet")
                .font(.callout)
                .foregroundStyle(secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tertiaryText: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.35)
    }

    private var messageContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: app icon + title
            HStack(spacing: 6) {
                Image("AppIconImage")
                    .resizable()
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                Text(WidgetL10n.latest)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(secondaryText)
                Spacer()
            }

            // Media label (bold)
            if let mediaLabel = entry.mediaLabel {
                Text(mediaLabel)
                    .font(.footnote.bold())
                    .foregroundStyle(primaryText)
            }

            // Message content
            if !entry.todoLines.isEmpty {
                let maxTodos = entry.content.isEmpty ? 4 : 3
                VStack(alignment: .leading, spacing: 3) {
                    if !entry.content.isEmpty {
                        Text(entry.content)
                            .font(.footnote)
                            .foregroundStyle(primaryText)
                            .lineLimit(2)
                    }
                    ForEach(Array(entry.todoLines.prefix(maxTodos))) { todo in
                        HStack(spacing: 5) {
                            Image(systemName: "circle")
                                .font(.system(size: 10))
                                .foregroundStyle(checkColor)
                            Text(todo.text)
                                .font(.footnote)
                                .foregroundStyle(primaryText)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Text(entry.content)
                    .font(.footnote)
                    .foregroundStyle(primaryText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(6)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            // Footer: "and N more" (left) + tab name (right)
            HStack {
                if !entry.todoLines.isEmpty {
                    let maxTodos = entry.content.isEmpty ? 4 : 3
                    if entry.todoLines.count > maxTodos {
                        Text(WidgetL10n.andMore(entry.todoLines.count - maxTodos))
                            .font(.caption2)
                            .foregroundStyle(tertiaryText)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text(entry.tabName)
                    .font(.caption2)
                    .foregroundStyle(tertiaryText)
                    .lineLimit(1)
            }
        }
        .padding(.top, -4)
        .padding(.bottom, -4)
    }
}

// MARK: - Widget Definition

struct LatestMessageWidget: Widget {
    let kind = "LatestMessageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LatestMessageProvider()) { entry in
            let theme = entry.theme
            let bg = Color(light: theme.backgroundColor, dark: theme.backgroundColorDark)
            LatestMessageWidgetEntryView(entry: entry)
                .widgetURL(entry.deepLinkURL)
                .containerBackground(bg, for: .widget)
        }
        .configurationDisplayName(WidgetL10n.latest)
        .description("Shows the most recent message.")
        .supportedFamilies([.systemSmall])
    }
}
