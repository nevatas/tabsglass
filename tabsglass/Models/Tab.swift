//
//  Tab.swift
//  tabsglass
//
//  Note: Inbox is virtual (messages with tabId = nil), not a real tab
//

import Foundation
import SwiftData

@Model
final class Tab {
    var id: UUID
    var serverId: Int?  // Backend ID for sync (nil = local only)
    var title: String
    var createdAt: Date
    var position: Int   // for sorting, 0 = first

    init(title: String, position: Int = 0) {
        self.id = UUID()
        self.serverId = nil
        self.title = title
        self.createdAt = Date()
        self.position = position
    }
}
