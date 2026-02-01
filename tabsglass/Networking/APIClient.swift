//
//  APIClient.swift
//  tabsglass
//
//  Actor-based HTTP client with automatic token refresh
//

import Foundation
import os.log

/// Thread-safe API client with automatic token refresh
actor APIClient {
    static let shared = APIClient()

    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let logger = Logger(subsystem: "tabsglass", category: "APIClient")

    /// Lock to prevent multiple simultaneous token refreshes
    private var isRefreshingToken = false
    private var refreshContinuations: [CheckedContinuation<Void, Error>] = []

    init(baseURL: URL = SharedConstants.apiBaseURL) {
        self.baseURL = baseURL

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try ISO8601 with fractional seconds first
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                return date
            }

            // Fallback to standard ISO8601
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(dateString)")
        }

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Public API

    /// Perform a request and decode the response
    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T {
        let data = try await performRequest(endpoint)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            // Log raw response for debugging
            let rawResponse = String(data: data, encoding: .utf8) ?? "<binary data>"
            logger.error("Decoding error: \(error.localizedDescription)")
            logger.error("Raw response: \(rawResponse)")
            throw APIError.decodingError(error)
        }
    }

    /// Perform a request without expecting a response body
    func requestVoid(_ endpoint: Endpoint) async throws {
        _ = try await performRequest(endpoint)
    }

    /// Upload data to a presigned URL (R2)
    func upload(data: Data, to url: URL, contentType: String) async throws {
        try await upload(data: data, to: url, contentType: contentType, onProgress: nil)
    }

    /// Upload data to a presigned URL (R2) with progress callback
    nonisolated func upload(data: Data, to url: URL, contentType: String, onProgress: ((Double) -> Void)?) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(String(data.count), forHTTPHeaderField: "Content-Length")

        // Use upload task with delegate for progress tracking
        let (_, response) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
            let delegate = UploadProgressDelegate(onProgress: onProgress) { result in
                continuation.resume(with: result)
            }

            // Create session with delegate for this upload (extended timeout for large files)
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 300  // 5 minutes for slow uploads
            config.timeoutIntervalForResource = 600 // 10 minutes total
            let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
            let task = session.uploadTask(with: request, from: data)
            delegate.associateWith(task: task)
            task.resume()
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: "Upload failed")
        }
    }

    /// Upload file from URL to a presigned URL (R2)
    func uploadFile(from fileURL: URL, to uploadURL: URL, contentType: String) async throws {
        guard let data = try? Data(contentsOf: fileURL) else {
            throw APIError.noData
        }
        try await upload(data: data, to: uploadURL, contentType: contentType)
    }

    // MARK: - Private Implementation

    private func performRequest(_ endpoint: Endpoint, isRetry: Bool = false) async throws -> Data {
        let request = try buildRequest(for: endpoint)

        logger.debug("[\(endpoint.method.rawValue)] \(endpoint.path)")

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            // Log response for debugging
            if httpResponse.statusCode >= 400 {
                if let responseText = String(data: data, encoding: .utf8) {
                    logger.error("Server error response (\(httpResponse.statusCode)): \(responseText)")
                }
            }

            // Handle auth errors
            if httpResponse.statusCode == 401 && endpoint.requiresAuth && !isRetry {
                // Try token refresh
                try await refreshTokenIfNeeded()
                // Retry original request
                return try await performRequest(endpoint, isRetry: true)
            }

            // Handle other errors
            try handleErrorResponse(statusCode: httpResponse.statusCode, data: data)

            return data
        } catch let error as APIError {
            throw error
        } catch let error as URLError {
            if error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
                throw APIError.offline
            }
            throw APIError.networkError(error)
        } catch {
            throw APIError.networkError(error)
        }
    }

    private func buildRequest(for endpoint: Endpoint) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(endpoint.path), resolvingAgainstBaseURL: true)
        components?.queryItems = endpoint.queryItems

        guard let url = components?.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Add auth header if required
        if endpoint.requiresAuth {
            if let token = try? KeychainService.shared.load(.accessToken) {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        }

        // Add WebSocket connection ID to exclude self from broadcasts
        if let connectionId = WebSocketConnectionStore.shared.connectionId {
            request.setValue(connectionId, forHTTPHeaderField: "X-Connection-ID")
            logger.debug("🔗 X-Connection-ID: \(connectionId)")
        } else {
            logger.warning("⚠️ No WebSocket connection ID available for request")
        }

        // Add body if present
        if let body = endpoint.body {
            do {
                request.httpBody = try encoder.encode(AnyEncodable(body))
            } catch {
                throw APIError.encodingError(error)
            }
        }

        return request
    }

    private func handleErrorResponse(statusCode: Int, data: Data) throws {
        switch statusCode {
        case 200...299:
            return // Success
        case 401:
            // Try to get error message from server
            if let errorResponse = try? decoder.decode(ServerErrorResponse.self, from: data) {
                throw APIError.httpError(statusCode: 401, message: errorResponse.message ?? errorResponse.error)
            }
            throw APIError.unauthorized
        case 429:
            // Parse retry-after if available
            if let errorResponse = try? decoder.decode(ServerErrorResponse.self, from: data) {
                throw APIError.rateLimited(retryAfter: nil)
            }
            throw APIError.rateLimited(retryAfter: nil)
        case 400...499:
            if let errorResponse = try? decoder.decode(ServerErrorResponse.self, from: data) {
                throw APIError.httpError(statusCode: statusCode, message: errorResponse.message ?? errorResponse.error)
            }
            throw APIError.httpError(statusCode: statusCode, message: nil)
        case 500...599:
            if let errorResponse = try? decoder.decode(ServerErrorResponse.self, from: data) {
                throw APIError.serverError(errorResponse.message ?? errorResponse.error)
            }
            throw APIError.serverError("Server error")
        default:
            throw APIError.httpError(statusCode: statusCode, message: nil)
        }
    }

    // MARK: - Token Refresh

    private func refreshTokenIfNeeded() async throws {
        // If already refreshing, wait for it
        if isRefreshingToken {
            try await withCheckedThrowingContinuation { continuation in
                refreshContinuations.append(continuation)
            }
            return
        }

        isRefreshingToken = true
        defer {
            isRefreshingToken = false
            // Resume all waiting continuations
            let continuations = refreshContinuations
            refreshContinuations.removeAll()
            for continuation in continuations {
                continuation.resume()
            }
        }

        guard let refreshToken = try? KeychainService.shared.load(.refreshToken) else {
            throw APIError.tokenRefreshFailed
        }

        do {
            let response: AuthResponse = try await request(.refreshToken(refreshToken: refreshToken))
            try KeychainService.shared.save(response.accessToken, for: .accessToken)
            try KeychainService.shared.save(response.refreshToken, for: .refreshToken)
            logger.info("Token refreshed successfully")
        } catch {
            logger.error("Token refresh failed: \(error.localizedDescription)")
            // Clear tokens on refresh failure
            try? KeychainService.shared.delete(.accessToken)
            try? KeychainService.shared.delete(.refreshToken)
            throw APIError.tokenRefreshFailed
        }
    }
}

// MARK: - Type Erasure Helper

/// Type-erasing wrapper for Encodable
private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init(_ value: any Encodable) {
        self._encode = { encoder in
            try value.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}

// MARK: - Upload Progress Delegate

/// URLSession delegate for tracking upload progress
private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {
    private let onProgress: ((Double) -> Void)?
    private let completion: (Result<(Data, URLResponse), Error>) -> Void
    private var receivedData = Data()
    private var response: URLResponse?

    init(onProgress: ((Double) -> Void)?, completion: @escaping (Result<(Data, URLResponse), Error>) -> Void) {
        self.onProgress = onProgress
        self.completion = completion
        super.init()
    }

    /// Keep a strong reference to self while task is running
    private static var activeDelegates: [Int: UploadProgressDelegate] = [:]
    private static let lock = NSLock()

    func associateWith(task: URLSessionTask) {
        Self.lock.lock()
        Self.activeDelegates[task.taskIdentifier] = self
        Self.lock.unlock()
    }

    private func cleanup(taskIdentifier: Int) {
        Self.lock.lock()
        Self.activeDelegates.removeValue(forKey: taskIdentifier)
        Self.lock.unlock()
    }

    // MARK: - URLSessionTaskDelegate

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        DispatchQueue.main.async { [weak self] in
            self?.onProgress?(progress)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer { cleanup(taskIdentifier: task.taskIdentifier) }

        if let error = error {
            completion(.failure(error))
        } else if let response = response {
            completion(.success((receivedData, response)))
        } else {
            completion(.failure(URLError(.badServerResponse)))
        }
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        self.response = response
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        receivedData.append(data)
    }
}
