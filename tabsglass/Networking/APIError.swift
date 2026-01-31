//
//  APIError.swift
//  tabsglass
//
//  Network and API error types
//

import Foundation

/// Errors that can occur during API operations
enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case decodingError(Error)
    case encodingError(Error)
    case networkError(Error)
    case unauthorized
    case tokenRefreshFailed
    case serverError(String)
    case noData
    case rateLimited(retryAfter: TimeInterval?)
    case offline

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let statusCode, let message):
            return message ?? "HTTP error \(statusCode)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .encodingError(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .unauthorized:
            return "Authentication required"
        case .tokenRefreshFailed:
            return "Session expired. Please log in again."
        case .serverError(let message):
            return message
        case .noData:
            return "No data received"
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limited. Try again in \(Int(seconds)) seconds."
            }
            return "Rate limited. Please try again later."
        case .offline:
            return "No internet connection"
        }
    }

    /// Whether this error should trigger a token refresh attempt
    var shouldRefreshToken: Bool {
        if case .unauthorized = self {
            return true
        }
        return false
    }

    /// Whether this error is recoverable by retrying
    var isRetryable: Bool {
        switch self {
        case .networkError, .rateLimited, .offline:
            return true
        case .httpError(let statusCode, _):
            return statusCode >= 500
        default:
            return false
        }
    }
}

/// Error response from the server
/// Supports both flat format: {"error": "...", "message": "..."}
/// And nested format: {"error": {"code": "...", "message": "..."}}
struct ServerErrorResponse: Decodable {
    let error: String
    let message: String?
    let code: String?

    private enum CodingKeys: String, CodingKey {
        case error
        case message
        case code
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Try nested format first: {"error": {"code": "...", "message": "..."}}
        if let nestedError = try? container.decode(NestedError.self, forKey: .error) {
            self.error = nestedError.code ?? nestedError.message ?? "Unknown error"
            self.message = nestedError.message
            self.code = nestedError.code
        } else {
            // Flat format: {"error": "...", "message": "..."}
            self.error = try container.decode(String.self, forKey: .error)
            self.message = try container.decodeIfPresent(String.self, forKey: .message)
            self.code = try container.decodeIfPresent(String.self, forKey: .code)
        }
    }

    private struct NestedError: Decodable {
        let code: String?
        let message: String?
    }
}
