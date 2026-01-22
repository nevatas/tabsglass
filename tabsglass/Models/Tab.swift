//
//  Tab.swift
//  tabsglass
//

import Foundation
import SwiftData

@Model
final class Tab {
    var id: UUID
    var title: String
    var createdAt: Date
    var sortOrder: Int

    @Relationship(deleteRule: .cascade, inverse: \Message.tab)
    var messages: [Message]

    init(title: String, sortOrder: Int = 0) {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.sortOrder = sortOrder
        self.messages = []
    }
}
