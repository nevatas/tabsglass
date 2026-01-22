//
//  Message.swift
//  tabsglass
//

import Foundation
import SwiftData

@Model
final class Message {
    var id: UUID
    var text: String
    var createdAt: Date
    var tab: Tab?

    init(text: String, tab: Tab) {
        self.id = UUID()
        self.text = text
        self.createdAt = Date()
        self.tab = tab
    }
}
