//
//  AuthService.swift
//  tabsglass
//
//  Authentication service managing login, registration, and session state
//

import Foundation
import SwiftUI
import os.log

/// Authentication state observable by views
@Observable
@MainActor
final class AuthService {
    static let shared = AuthService()

    // MARK: - Published State

    /// Whether the user is currently authenticated
    private(set) var isAuthenticated = false

    /// Current user data (nil if not logged in)
    private(set) var currentUser: User?

    /// Whether auth state is being determined (initial session check)
    private(set) var isLoading = true

    /// Last auth error for display
    private(set) var lastError: String?

    // MARK: - Private

    private let apiClient = APIClient.shared
    private let keychain = KeychainService.shared
    private let logger = Logger(subsystem: "tabsglass", category: "AuthService")

    private init() {}

    // MARK: - Session Management

    /// Check and restore session on app launch
    func checkSession() async {
        isLoading = true
        defer { isLoading = false }

        guard keychain.hasTokens() else {
            logger.info("No stored tokens, user not logged in")
            isAuthenticated = false
            currentUser = nil
            return
        }

        do {
            // Verify token with server
            let response: UserResponse = try await apiClient.request(.me)
            currentUser = User(from: response)
            isAuthenticated = true
            logger.info("Session restored for user: \(response.email)")
        } catch {
            logger.warning("Session check failed: \(error.localizedDescription)")
            // Token might be invalid - clear it
            if let apiError = error as? APIError, apiError.shouldRefreshToken {
                // Token refresh will be attempted by APIClient
                // If it fails, tokens are cleared automatically
            }
            keychain.clearAll()
            isAuthenticated = false
            currentUser = nil
        }
    }

    // MARK: - Authentication

    /// Register a new user
    func register(email: String, password: String) async throws {
        clearError()

        do {
            let response: AuthResponse = try await apiClient.request(
                .register(email: email, password: password)
            )

            try saveAuthResponse(response)
            logger.info("User registered: \(email)")
        } catch {
            handleError(error)
            throw error
        }
    }

    /// Login with email and password
    func login(email: String, password: String) async throws {
        clearError()

        do {
            let response: AuthResponse = try await apiClient.request(
                .login(email: email, password: password)
            )

            try saveAuthResponse(response)
            logger.info("User logged in: \(email)")
        } catch {
            handleError(error)
            throw error
        }
    }

    /// Logout and clear session
    func logout() async {
        // Try to notify server
        try? await apiClient.requestVoid(.logout)

        // Clear local state
        keychain.clearAll()
        isAuthenticated = false
        currentUser = nil
        lastError = nil

        // Clear last sync date
        UserDefaults.standard.removeObject(forKey: "lastSyncDate")

        // Clear pending operations
        await SyncService.shared.clearSyncState()

        logger.info("User logged out")
    }

    /// Update user's initial sync completion status
    func markInitialSyncCompleted() {
        currentUser?.hasCompletedInitialSync = true
    }

    // MARK: - Private Helpers

    private func saveAuthResponse(_ response: AuthResponse) throws {
        try keychain.save(response.accessToken, for: .accessToken)
        try keychain.save(response.refreshToken, for: .refreshToken)
        try keychain.save(response.user.email, for: .userEmail)

        currentUser = User(from: response.user)
        isAuthenticated = true
    }

    private func handleError(_ error: Error) {
        if let apiError = error as? APIError {
            lastError = apiError.errorDescription
        } else {
            lastError = error.localizedDescription
        }
    }

    private func clearError() {
        lastError = nil
    }
}

// MARK: - Validation Helpers

extension AuthService {
    /// Validate email format
    static func isValidEmail(_ email: String) -> Bool {
        let emailRegex = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.range(of: emailRegex, options: .regularExpression) != nil
    }

    /// Validate password strength
    static func isValidPassword(_ password: String) -> Bool {
        password.count >= 8
    }
}
