//
//  AuthService.swift
//  tabsglass
//
//  Authentication service managing login, registration, and session state
//

import Foundation
import SwiftUI
import os.log

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when user successfully logs in or registers
    static let userDidAuthenticate = Notification.Name("userDidAuthenticate")
}

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
        } catch let error as APIError {
            logger.warning("Session check failed: \(error.localizedDescription)")

            // Only clear tokens on actual auth errors (401/403)
            // Network errors should preserve the session for offline use
            switch error {
            case .httpError(let statusCode, _) where statusCode == 401 || statusCode == 403:
                logger.info("Auth token invalid, clearing session")
                keychain.clearAll()
                isAuthenticated = false
                currentUser = nil
            case .unauthorized:
                logger.info("Unauthorized, clearing session")
                keychain.clearAll()
                isAuthenticated = false
                currentUser = nil
            default:
                // Network error or other issue - keep tokens, assume still logged in
                logger.info("Network error during session check, preserving session")
                if let email = try? keychain.load(.userEmail) {
                    currentUser = User(email: email)
                }
                isAuthenticated = true
            }
        } catch {
            // Non-API error (e.g., network) - preserve session
            logger.warning("Session check error: \(error.localizedDescription), preserving session")
            if let email = try? keychain.load(.userEmail) {
                currentUser = User(email: email)
            }
            isAuthenticated = true
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

            // Notify app to connect WebSocket
            NotificationCenter.default.post(name: .userDidAuthenticate, object: nil)
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

            // Notify app to connect WebSocket
            NotificationCenter.default.post(name: .userDidAuthenticate, object: nil)
        } catch {
            handleError(error)
            throw error
        }
    }

    /// Logout and clear session
    func logout() async {
        // Disconnect WebSocket first
        await WebSocketService.shared.disconnect()

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
