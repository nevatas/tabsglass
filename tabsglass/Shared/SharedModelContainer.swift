//
//  SharedModelContainer.swift
//  tabsglass
//
//  Factory for creating SwiftData ModelContainer with shared store
//

import Foundation
import SwiftData
import os.log

enum SharedModelContainer {
    private static let logger = Logger(subsystem: "com.thecool.taby", category: "Migration")

    /// Shared container instance (set during app initialization)
    private(set) static var shared: ModelContainer?

    /// Set the shared container (call from app initialization)
    static func setShared(_ container: ModelContainer) {
        shared = container
    }

    /// Get a new ModelContext from the shared container
    @MainActor
    static var mainContext: ModelContext? {
        shared?.mainContext
    }

    /// Legacy SwiftData store URL (in Application Support)
    private static var legacyStoreURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("default.store")
    }

    /// Creates a ModelContainer using the shared App Group store
    /// Automatically migrates data from legacy location on first run
    static func create() throws -> ModelContainer {
        let schema = Schema([Tab.self, Message.self])
        let fileManager = FileManager.default

        // Check if shared container is available
        guard let sharedURL = SharedConstants.sharedStoreURL,
              let containerURL = SharedConstants.containerURL else {
            // Shared container not available, use default store
            logger.warning("Shared container not available, using default store")
            return try ModelContainer(for: Tab.self, Message.self)
        }

        // Ensure container directory exists
        if !fileManager.fileExists(atPath: containerURL.path) {
            try? fileManager.createDirectory(at: containerURL, withIntermediateDirectories: true)
        }

        let legacyURL = legacyStoreURL
        let legacyExists = fileManager.fileExists(atPath: legacyURL.path)
        let sharedExists = fileManager.fileExists(atPath: sharedURL.path)

        // Migration logic: copy legacy to shared if needed
        if legacyExists && !sharedExists {
            logger.info("Migrating database from legacy location to shared container")
            migrateStore(from: legacyURL, to: sharedURL)
        }

        // Use shared container
        let config = ModelConfiguration(
            schema: schema,
            url: sharedURL,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: config)
    }

    /// Copy store files from source to destination
    private static func migrateStore(from source: URL, to destination: URL) {
        let fileManager = FileManager.default
        let extensions = ["", "-shm", "-wal"]

        for ext in extensions {
            let sourcePath = source.path + ext
            let destPath = destination.path + ext

            if fileManager.fileExists(atPath: sourcePath) {
                do {
                    try fileManager.copyItem(atPath: sourcePath, toPath: destPath)
                    logger.info("Copied \(sourcePath) to \(destPath)")
                } catch {
                    logger.error("Failed to copy \(sourcePath): \(error.localizedDescription)")
                }
            }
        }
    }

    /// Migrate photos from Documents to shared container
    static func migratePhotosIfNeeded() {
        let migrationKey = "hasCompletedPhotoMigration_v3"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        guard let sharedPhotosDir = SharedConstants.photosDirectory else {
            return
        }

        let legacyDir = SharedConstants.legacyPhotosDirectory
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: legacyDir.path) else {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        do {
            let files = try fileManager.contentsOfDirectory(atPath: legacyDir.path)
            logger.info("Migrating \(files.count) photos to shared container")

            for fileName in files {
                let sourceURL = legacyDir.appendingPathComponent(fileName)
                let destURL = sharedPhotosDir.appendingPathComponent(fileName)

                if !fileManager.fileExists(atPath: destURL.path) {
                    try fileManager.copyItem(at: sourceURL, to: destURL)
                }
            }

            UserDefaults.standard.set(true, forKey: migrationKey)
            logger.info("Photo migration completed")

        } catch {
            logger.error("Photo migration failed: \(error.localizedDescription)")
        }
    }
}
