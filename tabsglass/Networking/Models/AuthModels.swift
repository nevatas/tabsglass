//
//  AuthModels.swift
//  tabsglass
//
//  Authentication request/response models
//

import Foundation

// MARK: - Requests

struct RegisterRequest: Encodable {
    let email: String
    let password: String
}

struct LoginRequest: Encodable {
    let email: String
    let password: String
}

struct RefreshTokenRequest: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
    }
}

// MARK: - Responses

struct AuthResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int?
    let user: UserResponse

    enum CodingKeys: String, CodingKey {
        case accessToken
        case refreshToken
        case expiresIn = "expires_in"
        case user
    }
}

struct UserResponse: Decodable, Sendable {
    let id: String
    let email: String
    let hasCompletedInitialSync: Bool?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case hasCompletedInitialSync = "has_completed_initial_sync"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Stored user data (local representation)
struct User: Codable, Sendable {
    let id: String
    let email: String
    var hasCompletedInitialSync: Bool

    init(from response: UserResponse) {
        self.id = response.id
        self.email = response.email
        self.hasCompletedInitialSync = response.hasCompletedInitialSync ?? false
    }

    /// Create user from cached data (when offline)
    init(email: String, hasCompletedInitialSync: Bool = true) {
        self.id = ""
        self.email = email
        self.hasCompletedInitialSync = hasCompletedInitialSync
    }
}
