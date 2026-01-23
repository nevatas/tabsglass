//
//  NewTabSheet.swift
//  tabsglass
//

import SwiftUI

struct NewTabSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tabTitle = ""
    @FocusState private var isTitleFocused: Bool
    let onCreate: (String) -> Void

    private var canCreate: Bool {
        !tabTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                TextField("Tab name", text: $tabTitle)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .focused($isTitleFocused)
                    .onSubmit {
                        if canCreate {
                            createAndDismiss()
                        }
                    }
                    .submitLabel(.done)

                Spacer()
            }
            .padding()
            .navigationTitle("New Tab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createAndDismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canCreate)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            isTitleFocused = true
        }
    }

    private func createAndDismiss() {
        let trimmedTitle = tabTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        onCreate(trimmedTitle)
        dismiss()
    }
}

struct RenameTabSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tabTitle: String
    @FocusState private var isTitleFocused: Bool
    let onRename: (String) -> Void

    init(currentTitle: String, onRename: @escaping (String) -> Void) {
        self._tabTitle = State(initialValue: currentTitle)
        self.onRename = onRename
    }

    private var canRename: Bool {
        !tabTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                TextField("Название таба", text: $tabTitle)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .focused($isTitleFocused)
                    .onSubmit {
                        if canRename {
                            renameAndDismiss()
                        }
                    }
                    .submitLabel(.done)

                Spacer()
            }
            .padding()
            .navigationTitle("Переименовать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        renameAndDismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canRename)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            isTitleFocused = true
        }
    }

    private func renameAndDismiss() {
        let trimmedTitle = tabTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        onRename(trimmedTitle)
        dismiss()
    }
}

#Preview("New Tab") {
    NewTabSheet { title in
        print("Created tab: \(title)")
    }
}

#Preview("Rename Tab") {
    RenameTabSheet(currentTitle: "My Tab") { title in
        print("Renamed to: \(title)")
    }
}
