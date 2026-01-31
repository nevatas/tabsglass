//
//  MediaModels.swift
//  tabsglass
//
//  Media upload/download API models
//

import Foundation

// MARK: - Requests

struct GetUploadURLRequest: Encodable {
    let contentType: String
    let contentLength: Int64

    enum CodingKeys: String, CodingKey {
        case contentType = "content_type"
        case contentLength = "content_length"
    }
}

struct ConfirmUploadRequest: Encodable {
    let fileKey: String

    enum CodingKeys: String, CodingKey {
        case fileKey = "file_key"
    }
}

// MARK: - Responses

struct UploadURLResponse: Decodable {
    let uploadUrl: String
    let fileKey: String
    let expiresAt: Date?  // Optional - server may not return this

    enum CodingKeys: String, CodingKey {
        case uploadUrl = "upload_url"
        case fileKey = "file_key"
        case expiresAt = "expires_at"
    }
}

struct ConfirmUploadResponse: Decodable {
    let confirmed: Bool  // Server returns "confirmed", not "success"
    let downloadUrl: String?

    enum CodingKeys: String, CodingKey {
        case confirmed
        case downloadUrl = "download_url"
    }
}
