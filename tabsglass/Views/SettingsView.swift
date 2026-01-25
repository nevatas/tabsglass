//
//  SettingsView.swift
//  tabsglass
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Link(destination: URL(string: "https://example.com/privacy")!) {
                        Label("Политика Конфиденциальности", systemImage: "hand.raised")
                    }

                    Link(destination: URL(string: "https://example.com/terms")!) {
                        Label("Правила Пользования", systemImage: "doc.text")
                    }

                    Link(destination: URL(string: "mailto:support@example.com")!) {
                        Label("Связь с разработчиком", systemImage: "envelope")
                    }
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
