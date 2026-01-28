//
//  TaskListSheet.swift
//  tabsglass
//
//  Sheet for creating and editing task lists
//

import SwiftUI

struct TaskListSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var items: [EditableTodoItem]
    @FocusState private var focusedItemId: UUID?

    let existingItems: [TodoItem]?
    let onSave: ([TodoItem]) -> Void
    let onCancel: () -> Void

    private let maxItems = 20

    /// Create mode
    init(onSave: @escaping ([TodoItem]) -> Void, onCancel: @escaping () -> Void) {
        self.existingItems = nil
        self.onSave = onSave
        self.onCancel = onCancel
        // Start with one empty item
        let initialItem = EditableTodoItem(text: "", isCompleted: false)
        _items = State(initialValue: [initialItem])
    }

    /// Edit mode
    init(existingItems: [TodoItem], onSave: @escaping ([TodoItem]) -> Void, onCancel: @escaping () -> Void) {
        self.existingItems = existingItems
        self.onSave = onSave
        self.onCancel = onCancel
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
                    ForEach($items) { $item in
                        TaskItemRow(
                            item: $item,
                            isFocused: focusedItemId == item.id,
                            canDelete: items.count > 1,
                            onDelete: { deleteItem(item) },
                            onSubmit: { addNewItemAfter(item, proxy: proxy) }
                        )
                        .focused($focusedItemId, equals: item.id)
                        .id(item.id)
                    }

                    if canAddMore {
                        Button {
                            addNewItem(proxy: proxy)
                        } label: {
                            Label(L10n.TaskList.addItem, systemImage: "plus")
                        }
                    }
                }
                .listStyle(.insetGrouped)
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
                // Focus first item on appear
                if let first = items.first {
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation {
                proxy.scrollTo(newItem.id, anchor: .bottom)
            }
        }
    }

    private func addNewItemAfter(_ item: EditableTodoItem, proxy: ScrollViewProxy) {
        guard canAddMore else { return }
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let newItem = EditableTodoItem(text: "", isCompleted: false)
        items.insert(newItem, at: index + 1)
        focusedItemId = newItem.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation {
                proxy.scrollTo(newItem.id, anchor: .bottom)
            }
        }
    }

    private func deleteItem(_ item: EditableTodoItem) {
        guard items.count > 1 else { return }
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items.remove(at: index)
            // Focus previous or next item
            if !items.isEmpty {
                let newIndex = min(index, items.count - 1)
                focusedItemId = items[newIndex].id
            }
        }
    }

    private func save() {
        let todoItems = items
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { TodoItem(id: $0.id, text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines), isCompleted: $0.isCompleted) }
        onSave(todoItems)
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
    let isFocused: Bool
    let canDelete: Bool
    let onDelete: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox (only in edit mode for existing items)
            Button {
                item.isCompleted.toggle()
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(item.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            // Text field
            TextField(L10n.TaskList.itemPlaceholder, text: $item.text)
                .strikethrough(item.isCompleted)
                .foregroundStyle(item.isCompleted ? .secondary : .primary)
                .submitLabel(.next)
                .onSubmit {
                    onSubmit()
                }

            // Delete button
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
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    TaskListSheet(
        onSave: { items in
            print("Saved: \(items)")
        },
        onCancel: {
            print("Cancelled")
        }
    )
}
