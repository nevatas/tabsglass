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

#Preview {
    NewTabSheet { title in
        print("Created tab: \(title)")
    }
}
