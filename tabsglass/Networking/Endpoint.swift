//
//  Endpoint.swift
//  tabsglass
//
//  Type-safe API route definitions
//

import Foundation

/// HTTP methods
enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// API endpoint definitions
enum Endpoint {
    // MARK: - Auth
    case register(email: String, password: String)
    case login(email: String, password: String)
    case refreshToken(refreshToken: String)
    case logout
    case me

    // MARK: - Tabs
    case getTabs
    case createTab(title: String, position: Int, localId: UUID)
    case updateTab(serverId: Int, title: String?, position: Int?)
    case deleteTab(serverId: Int)

    // MARK: - Messages
    case getMessages(tabServerId: Int?, since: Date?)
    case createMessage(CreateMessageRequest)
    case updateMessage(serverId: Int, UpdateMessageRequest)
    case moveMessage(serverId: Int, targetTabServerId: Int?)
    case deleteMessage(serverId: Int)

    // MARK: - Media
    case getUploadURL(contentType: String, contentLength: Int64)
    case confirmUpload(fileKey: String)

    // MARK: - Sync
    case initialSync(InitialSyncRequest)
    case incrementalSync(since: Date)

    // MARK: - User Settings
    case getUserSettings
    case updateUserSettings(UpdateUserSettingsRequest)

    // MARK: - Health
    case health

    /// The path component of the URL
    var path: String {
        switch self {
        // Auth
        case .register:
            return "/api/auth/register"
        case .login:
            return "/api/auth/login"
        case .refreshToken:
            return "/api/auth/refresh"
        case .logout:
            return "/api/auth/logout"
        case .me:
            return "/api/auth/me"

        // Tabs
        case .getTabs:
            return "/api/tabs"
        case .createTab:
            return "/api/tabs"
        case .updateTab(let serverId, _, _):
            return "/api/tabs/\(serverId)"
        case .deleteTab(let serverId):
            return "/api/tabs/\(serverId)"

        // Messages
        case .getMessages:
            return "/api/messages"
        case .createMessage:
            return "/api/messages"
        case .updateMessage(let serverId, _):
            return "/api/messages/\(serverId)"
        case .moveMessage(let serverId, _):
            return "/api/messages/\(serverId)/move"
        case .deleteMessage(let serverId):
            return "/api/messages/\(serverId)"

        // Media
        case .getUploadURL:
            return "/api/media/upload-url"
        case .confirmUpload:
            return "/api/media/confirm"

        // Sync
        case .initialSync:
            return "/api/sync/initial"
        case .incrementalSync:
            return "/api/sync"

        // User Settings
        case .getUserSettings:
            return "/api/user/settings"
        case .updateUserSettings:
            return "/api/user/settings"

        // Health
        case .health:
            return "/health"
        }
    }

    /// HTTP method for this endpoint
    var method: HTTPMethod {
        switch self {
        case .register, .login, .refreshToken, .logout,
             .createTab, .createMessage,
             .getUploadURL, .confirmUpload,
             .initialSync:
            return .post
        case .updateUserSettings:
            return .put
        case .updateTab, .updateMessage:
            return .put
        case .moveMessage:
            return .patch
        case .deleteTab, .deleteMessage:
            return .delete
        case .getTabs, .getMessages, .me, .incrementalSync, .health, .getUserSettings:
            return .get
        }
    }

    /// Whether this endpoint requires authentication
    var requiresAuth: Bool {
        switch self {
        case .register, .login, .refreshToken, .health:
            return false
        default:
            return true
        }
    }

    /// Request body as encodable data
    var body: Encodable? {
        switch self {
        case .register(let email, let password):
            return RegisterRequest(email: email, password: password)
        case .login(let email, let password):
            return LoginRequest(email: email, password: password)
        case .refreshToken(let refreshToken):
            return RefreshTokenRequest(refreshToken: refreshToken)
        case .createTab(let title, let position, let localId):
            return CreateTabRequest(title: title, position: position, localId: localId)
        case .updateTab(_, let title, let position):
            return UpdateTabRequest(title: title, position: position)
        case .createMessage(let request):
            return request
        case .updateMessage(_, let request):
            return request
        case .moveMessage(_, let targetTabServerId):
            return MoveMessageRequest(targetTabServerId: targetTabServerId)
        case .getUploadURL(let contentType, let contentLength):
            return GetUploadURLRequest(contentType: contentType, contentLength: contentLength)
        case .confirmUpload(let fileKey):
            return ConfirmUploadRequest(fileKey: fileKey)
        case .initialSync(let request):
            return request
        case .updateUserSettings(let request):
            return request
        default:
            return nil
        }
    }

    /// Query parameters for GET requests
    var queryItems: [URLQueryItem]? {
        switch self {
        case .getMessages(let tabServerId, let since):
            var items: [URLQueryItem] = []
            if let tabId = tabServerId {
                items.append(URLQueryItem(name: "tab_id", value: String(tabId)))
            }
            if let since = since {
                items.append(URLQueryItem(name: "since", value: ISO8601DateFormatter().string(from: since)))
            }
            return items.isEmpty ? nil : items
        case .incrementalSync(let since):
            let dateString = ISO8601DateFormatter().string(from: since)
            return [URLQueryItem(name: "since", value: dateString)]
        default:
            return nil
        }
    }
}
