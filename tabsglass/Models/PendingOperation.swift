//
//  PendingOperation.swift
//  tabsglass
//
//  Model for offline sync queue operations
//

import Foundation

/// Type of sync operation
enum OperationType: String, Codable, Sendable {
    case create
    case update
    case delete
}

/// Type of entity being synced
enum EntityType: String, Codable, Sendable {
    case tab
    case message
}

/// A pending sync operation stored for offline processing
struct PendingOperation: Codable, Identifiable, Sendable {
    let id: UUID
    let type: OperationType
    let entityType: EntityType
    let entityId: UUID
    let payload: Data  // JSON-encoded request body
    let createdAt: Date
    var retryCount: Int
    var lastError: String?

    init(
        type: OperationType,
        entityType: EntityType,
        entityId: UUID,
        payload: Data
    ) {
        self.id = UUID()
        self.type = type
        self.entityType = entityType
        self.entityId = entityId
        self.payload = payload
        self.createdAt = Date()
        self.retryCount = 0
        self.lastError = nil
    }

    /// Maximum retry attempts before giving up
    static let maxRetries = 5

    /// Whether this operation should be retried
    var shouldRetry: Bool {
        retryCount < Self.maxRetries
    }

    /// Delay before next retry (exponential backoff)
    var retryDelay: TimeInterval {
        Double(min(30, pow(2.0, Double(retryCount))))  // 1, 2, 4, 8, 16, 30 seconds
    }
}

// MARK: - Pending Operations Storage

/// Persistent storage for offline sync queue using UserDefaults
/// Thread-safe through serial dispatch queue
final class PendingOperationsStore: Sendable {
    static let shared = PendingOperationsStore()

    private let queue = DispatchQueue(label: "com.tabsglass.pendingOperations")
    private let key = "pendingOperations"

    private init() {}

    /// Get all pending operations
    nonisolated func getAll() -> [PendingOperation] {
        queue.sync {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let operations = try? JSONDecoder().decode([PendingOperation].self, from: data) else {
                return []
            }
            return operations.sorted { $0.createdAt < $1.createdAt }
        }
    }

    /// Add a new pending operation
    nonisolated func add(_ operation: PendingOperation) {
        queue.sync {
            var operations = self.loadOperations()
            operations.append(operation)
            self.saveOperations(operations)
        }
    }

    /// Update an existing operation (e.g., increment retry count)
    nonisolated func update(_ operation: PendingOperation) {
        queue.sync {
            var operations = self.loadOperations()
            if let index = operations.firstIndex(where: { $0.id == operation.id }) {
                operations[index] = operation
                self.saveOperations(operations)
            }
        }
    }

    /// Remove a completed operation
    nonisolated func remove(id: UUID) {
        queue.sync {
            var operations = self.loadOperations()
            operations.removeAll { $0.id == id }
            self.saveOperations(operations)
        }
    }

    /// Remove all operations for a specific entity
    nonisolated func removeAll(for entityId: UUID) {
        queue.sync {
            var operations = self.loadOperations()
            operations.removeAll { $0.entityId == entityId }
            self.saveOperations(operations)
        }
    }

    /// Clear all pending operations
    nonisolated func clearAll() {
        queue.sync {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// Get count of pending operations
    nonisolated var count: Int {
        getAll().count
    }

    // MARK: - Private helpers (called within queue.sync, no recursion)

    private func loadOperations() -> [PendingOperation] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let operations = try? JSONDecoder().decode([PendingOperation].self, from: data) else {
            return []
        }
        return operations
    }

    private func saveOperations(_ operations: [PendingOperation]) {
        if let data = try? JSONEncoder().encode(operations) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
