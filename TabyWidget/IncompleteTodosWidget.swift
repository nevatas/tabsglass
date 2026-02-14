//
//  IncompleteTodosWidget.swift
//  TabyWidget
//

import SwiftUI
import SwiftData
import WidgetKit

// MARK: - Widget Theme

enum WidgetTheme: String {
    case system, light, dark, pink, beige, green, blue

    static func current() -> WidgetTheme {
        guard let raw = UserDefaults(suiteName: SharedConstants.appGroupID)?.string(forKey: "appTheme"),
              let theme = WidgetTheme(rawValue: raw) else {
            return .system
        }
        return theme
    }

    var backgroundColor: Color {
        switch self {
        case .system, .light: return .white
        case .dark: return Color(red: 0x19/255, green: 0x1A/255, blue: 0x1A/255)
        case .pink: return Color(red: 0xFF/255, green: 0xC8/255, blue: 0xE0/255)
        case .beige: return Color(red: 0xF0/255, green: 0xDC/255, blue: 0xC0/255)
        case .green: return Color(red: 0xC8/255, green: 0xE8/255, blue: 0xC8/255)
        case .blue: return Color(red: 0xC8/255, green: 0xE0/255, blue: 0xF8/255)
        }
    }

    var backgroundColorDark: Color {
        switch self {
        case .system, .dark, .light: return Color(red: 0x19/255, green: 0x1A/255, blue: 0x1A/255)
        case .pink: return Color(red: 0x3C/255, green: 0x18/255, blue: 0x28/255)
        case .beige: return Color(red: 0x38/255, green: 0x2C/255, blue: 0x1C/255)
        case .green: return Color(red: 0x18/255, green: 0x30/255, blue: 0x18/255)
        case .blue: return Color(red: 0x18/255, green: 0x28/255, blue: 0x3C/255)
        }
    }

    var accentColor: Color? {
        switch self {
        case .system, .light, .dark: return nil
        case .pink: return Color(red: 0xD7/255, green: 0x33/255, blue: 0x82/255)
        case .beige: return Color(red: 0xA6/255, green: 0x7C/255, blue: 0x52/255)
        case .green: return Color(red: 0x2E/255, green: 0x7D/255, blue: 0x32/255)
        case .blue: return Color(red: 0x1E/255, green: 0x88/255, blue: 0xE5/255)
        }
    }

    var colorSchemeOverride: ColorScheme? {
        switch self {
        case .system: return nil
        case .light, .pink, .beige, .green, .blue: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Data Types

struct WidgetTodoItem: Identifiable {
    let id: UUID
    let text: String
    let tabName: String
}

struct TodoEntry: TimelineEntry {
    let date: Date
    let items: [WidgetTodoItem]
    let totalCount: Int
    let theme: WidgetTheme
}

// MARK: - Provider

struct IncompleteTodosProvider: TimelineProvider {
    private static let maxItems = 5

    func placeholder(in context: Context) -> TodoEntry {
        TodoEntry(
            date: .now,
            items: [
                WidgetTodoItem(id: UUID(), text: "Buy groceries", tabName: "Shopping"),
                WidgetTodoItem(id: UUID(), text: "Call dentist", tabName: "\u{1F4E5} Inbox")
            ],
            totalCount: 2,
            theme: .current()
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TodoEntry) -> Void) {
        completion(fetchTodoEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodoEntry>) -> Void) {
        let entry = fetchTodoEntry()
        completion(Timeline(entries: [entry], policy: .never))
    }

    private func fetchTodoEntry() -> TodoEntry {
        let theme = WidgetTheme.current()

        guard let container = try? SharedModelContainer.create() else {
            return TodoEntry(date: .now, items: [], totalCount: 0, theme: theme)
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

        // Fetch messages that have todos
        let descriptor = FetchDescriptor<Message>()
        guard let messages = try? context.fetch(descriptor) else {
            return TodoEntry(date: .now, items: [], totalCount: 0, theme: theme)
        }

        var allItems: [WidgetTodoItem] = []

        for message in messages {
            let tabName = message.tabId.flatMap { tabLookup[$0] } ?? "\u{1F4E5} Inbox"

            if let blocks = message.contentBlocks, !blocks.isEmpty {
                for block in blocks where block.type == "todo" && !block.isCompleted {
                    allItems.append(WidgetTodoItem(id: block.id, text: block.text, tabName: tabName))
                }
            } else if let todos = message.todoItems, !todos.isEmpty {
                for item in todos where !item.isCompleted {
                    allItems.append(WidgetTodoItem(id: item.id, text: item.text, tabName: tabName))
                }
            }
        }

        let totalCount = allItems.count
        let displayItems = Array(allItems.prefix(Self.maxItems))

        return TodoEntry(date: .now, items: displayItems, totalCount: totalCount, theme: theme)
    }
}

// MARK: - Widget View

struct IncompleteTodosWidgetEntryView: View {
    let entry: TodoEntry
    @Environment(\.colorScheme) private var systemColorScheme

    private var effectiveColorScheme: ColorScheme {
        entry.theme.colorSchemeOverride ?? systemColorScheme
    }

    private var checkColor: Color {
        entry.theme.accentColor ?? (effectiveColorScheme == .dark ? .white : .gray)
    }

    private var secondaryText: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.6) : .black.opacity(0.5)
    }

    private var tertiaryText: Color {
        effectiveColorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.35)
    }

    private var primaryText: Color {
        effectiveColorScheme == .dark ? .white : .black
    }

    var body: some View {
        if entry.totalCount == 0 {
            emptyState
        } else {
            contentView
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(entry.theme.accentColor ?? .green)
            Text("All done!")
                .font(.headline)
                .foregroundStyle(secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contentView: some View {
        // Try 5 items first, fall back to 4 on smaller screens
        ViewThatFits(in: .vertical) {
            todoList(maxVisible: 5)
            todoList(maxVisible: 4)
        }
    }

    private func todoList(maxVisible: Int) -> some View {
        let visible = Array(entry.items.prefix(maxVisible))
        let remaining = entry.totalCount - visible.count

        return VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack(spacing: 6) {
                Image("AppIconImage")
                    .resizable()
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                Text("Uncompleted Tasks")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(secondaryText)
                Spacer()
            }

            // Todo items
            ForEach(visible) { item in
                HStack(spacing: 8) {
                    Image(systemName: "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(checkColor)
                    Text(item.text)
                        .font(.callout)
                        .foregroundStyle(primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Text(item.tabName)
                        .font(.caption)
                        .foregroundStyle(tertiaryText)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }

            // "and N more" footer
            if remaining > 0 {
                Text("and \(remaining) more")
                    .font(.caption)
                    .foregroundStyle(tertiaryText)
            }
        }
        .padding(.top, -4)
        .padding(.bottom, -4)
    }
}

// MARK: - Widget Definition

struct IncompleteTodosWidget: Widget {
    let kind = "IncompleteTodosWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: IncompleteTodosProvider()) { entry in
            let theme = entry.theme
            let bg = Color(light: theme.backgroundColor, dark: theme.backgroundColorDark)
            IncompleteTodosWidgetEntryView(entry: entry)
                .containerBackground(bg, for: .widget)
        }
        .configurationDisplayName("Incomplete Tasks")
        .description("Shows your incomplete todo items.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Color Helper

extension Color {
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
    }
}
