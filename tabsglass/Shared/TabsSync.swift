//
//  TabsSync.swift
//  tabsglass
//
//  Syncs tabs list to App Group for Share Extension access
//

import Foundation

/// Lightweight tab representation for sharing with extension
struct SharedTab: Codable, Identifiable {
    let id: UUID
    let title: String
    let position: Int
}

/// Manages tabs synchronization between main app and extension
enum TabsSync {
    private static var fileURL: URL? {
        SharedConstants.containerURL?.appendingPathComponent("tabs_list.json")
    }

    /// Save tabs list (called from main app when tabs change)
    static func saveTabs(_ tabs: [Tab]) {
        let sharedTabs = tabs.map { SharedTab(id: $0.id, title: $0.title, position: $0.position) }
        guard let url = fileURL,
              let data = try? JSONEncoder().encode(sharedTabs) else { return }
        try? data.write(to: url)
    }

    /// Load tabs list (called from extension)
    static func loadTabs() -> [SharedTab] {
        guard let url = fileURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let tabs = try? JSONDecoder().decode([SharedTab].self, from: data) else {
            return []
        }
        return tabs.sorted { $0.position < $1.position }
    }
}
