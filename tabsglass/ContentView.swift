//
//  ContentView.swift
//  tabsglass
//
//  Created by Sergey Tokarev on 22.01.2026.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        MainContainerView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Tab.self, Message.self], inMemory: true)
}
