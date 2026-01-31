//
//  UserSettingsModels.swift
//  tabsglass
//
//  User settings API models
//

import Foundation

// MARK: - Response

struct UserSettingsResponse: Codable {
    let spaceName: String
    let theme: String
    let autoFocusInput: Bool

    enum CodingKeys: String, CodingKey {
        case spaceName = "space_name"
        case theme
        case autoFocusInput = "auto_focus_input"
    }
}

// MARK: - Request

struct UpdateUserSettingsRequest: Encodable {
    let spaceName: String?
    let theme: String?
    let autoFocusInput: Bool?

    enum CodingKeys: String, CodingKey {
        case spaceName = "space_name"
        case theme
        case autoFocusInput = "auto_focus_input"
    }
}
