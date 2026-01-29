//
//  TaskListSheet.swift
//  tabsglass
//
//  Sheet for creating and editing task lists
//

import SwiftUI

struct TaskListSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var listTitle: String
    @State private var items: [EditableTodoItem]
    @FocusState private var focusedItemId: UUID?
    @FocusState private var isTitleFocused: Bool

    let existingTitle: String?
    let existingItems: [TodoItem]?
    let onSave: (String?, [TodoItem]) -> Void
    let onCancel: () -> Void

    private let maxItems = 20

    /// Create mode
    init(onSave: @escaping (String?, [TodoItem]) -> Void, onCancel: @escaping () -> Void) {
        self.existingTitle = nil
        self.existingItems = nil
        self.onSave = onSave
        self.onCancel = onCancel
        _listTitle = State(initialValue: "")
        // Start with one empty item
        let initialItem = EditableTodoItem(text: "", isCompleted: false)
        _items = State(initialValue: [initialItem])
    }

    /// Edit mode
    init(existingTitle: String?, existingItems: [TodoItem], onSave: @escaping (String?, [TodoItem]) -> Void, onCancel: @escaping () -> Void) {
        self.existingTitle = existingTitle
        self.existingItems = existingItems
        self.onSave = onSave
        self.onCancel = onCancel
        _listTitle = State(initialValue: existingTitle ?? "")
        _items = State(initialValue: existingItems.map { EditableTodoItem(from: $0) })
    }

    private var isEditMode: Bool {
        existingItems != nil
    }

    private var canSave: Bool {
        items.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var canAddMore: Bool {
        items.count < maxItems
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    // Title section
                    Section {
                        TextField(L10n.TaskList.titlePlaceholder, text: $listTitle)
                            .font(.headline)
                            .focused($isTitleFocused)
                            .submitLabel(.next)
                            .onSubmit {
                                if let first = items.first {
                                    focusedItemId = first.id
                                }
                            }
                    }

                    // Tasks section
                    Section {
                        ForEach($items) { $item in
                            TaskItemRow(
                                item: $item,
                                canDelete: items.count > 1,
                                onDelete: { deleteItem(item) },
                                onSubmit: { addNewItemAfter(item, proxy: proxy) }
                            )
                            .focused($focusedItemId, equals: item.id)
                            .id(item.id)
                        }
                        .onMove(perform: moveItem)
                        .deleteDisabled(true)

                        if canAddMore {
                            Button {
                                addNewItem(proxy: proxy)
                            } label: {
                                Label(L10n.TaskList.addItem, systemImage: "plus")
                            }
                            .id("addButton")
                        }
                    }

                }
                .listStyle(.insetGrouped)
                .environment(\.editMode, .constant(.active))
            }
            .navigationTitle(isEditMode ? L10n.Menu.edit : L10n.TaskList.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .fontWeight(.medium)
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.medium)
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                // Focus first task item only in create mode
                if !isEditMode, let first = items.first {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        focusedItemId = first.id
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    private func addNewItem(proxy: ScrollViewProxy) {
        guard canAddMore else { return }
        let newItem = EditableTodoItem(text: "", isCompleted: false)
        items.append(newItem)
        focusedItemId = newItem.id
        scrollToBottom(proxy: proxy)
    }

    private func addNewItemAfter(_ item: EditableTodoItem, proxy: ScrollViewProxy) {
        guard canAddMore else { return }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let newItem = EditableTodoItem(text: "", isCompleted: false)
        items.insert(newItem, at: index + 1)
        focusedItemId = newItem.id
        scrollToBottom(proxy: proxy)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        // Delay to ensure layout is complete after keyboard appears
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo("addButton", anchor: .bottom)
            }
        }
    }

    private func moveItem(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }

    private func deleteItem(_ item: EditableTodoItem) {
        guard items.count > 1 else { return }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }

        // Check if the deleted item was focused (keyboard was active)
        let wasItemFocused = focusedItemId == item.id

        if wasItemFocused {
            // Move focus first to keep keyboard open, then delete
            let targetIndex = index > 0 ? index - 1 : 1
            focusedItemId = items[targetIndex].id

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [self] in
                _ = withAnimation {
                    items.remove(at: index)
                }
            }
        } else {
            // No keyboard active, just delete
            _ = withAnimation {
                items.remove(at: index)
            }
        }
    }

    private func save() {
        let trimmedTitle = listTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String? = trimmedTitle.isEmpty ? nil : trimmedTitle

        let todoItems = items
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { TodoItem(id: $0.id, text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines), isCompleted: $0.isCompleted) }
        onSave(title, todoItems)
    }
}

// MARK: - Editable Todo Item

private struct EditableTodoItem: Identifiable {
    let id: UUID
    var text: String
    var isCompleted: Bool

    init(text: String, isCompleted: Bool) {
        self.id = UUID()
        self.text = text
        self.isCompleted = isCompleted
    }

    init(from todoItem: TodoItem) {
        self.id = todoItem.id
        self.text = todoItem.text
        self.isCompleted = todoItem.isCompleted
    }
}

// MARK: - Task Item Row

private struct TaskItemRow: View {
    @Binding var item: EditableTodoItem
    let canDelete: Bool
    let onDelete: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if canDelete {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            TextField(L10n.TaskList.itemPlaceholder, text: $item.text, axis: .vertical)
                .lineLimit(1...10)
                .submitLabel(.next)
                .onSubmit {
                    onSubmit()
                }
        }
    }
}

#Preview {
    TaskListSheet(
        onSave: { title, items in
            print("Saved: \(title ?? "no title"), \(items)")
        },
        onCancel: {
            print("Cancelled")
        }
    )
}
