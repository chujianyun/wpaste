import Foundation
import SQLite3
import SwiftData

struct HistoryStorage {
    let applicationSupportDirectory: URL

    func configuration() throws -> ModelConfiguration {
        let directory = applicationSupportDirectory.appending(path: "WPaste", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appending(path: "History.store")
        let legacyURL = applicationSupportDirectory.appending(path: "default.store")
        if !FileManager.default.fileExists(atPath: storeURL.path), isLegacyHistory(at: legacyURL) {
            try copyLegacyStore(from: legacyURL, to: storeURL)
        }
        return ModelConfiguration(url: storeURL)
    }

    // Inspect the shared default file read-only. It may belong to another app.
    private func isLegacyHistory(at url: URL) -> Bool {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(database)
            return false
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT name FROM sqlite_master WHERE type = 'table'", -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        var tables = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 0) {
                tables.insert(String(cString: name))
            }
        }
        return Set(["ZHISTORYRECORD", "ZPINBOARDRECORD", "ZPINBOARDITEMRECORD"]).isSubset(of: tables)
    }

    // SQLite's backup API includes committed WAL data and leaves the source intact.
    private func copyLegacyStore(from sourceURL: URL, to destinationURL: URL) throws {
        let temporaryURL = destinationURL.deletingLastPathComponent()
            .appending(path: "Migration-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: temporaryURL.path + suffix)
            }
        }
        try backup(from: sourceURL, to: temporaryURL)
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
    }

    private func backup(from sourceURL: URL, to destinationURL: URL) throws {
        var source: OpaquePointer?
        var destination: OpaquePointer?
        defer {
            sqlite3_close(destination)
            sqlite3_close(source)
        }
        guard sqlite3_open_v2(sourceURL.path, &source, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              sqlite3_open_v2(destinationURL.path, &destination, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            throw migrationError()
        }
        sqlite3_busy_timeout(source, 1_000)
        sqlite3_busy_timeout(destination, 1_000)
        guard let backup = sqlite3_backup_init(destination, "main", source, "main") else {
            throw migrationError()
        }
        let result = sqlite3_backup_step(backup, -1)
        let finishResult = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE, finishResult == SQLITE_OK else { throw migrationError() }
    }

    private func migrationError() -> NSError {
        NSError(domain: "WPaste.HistoryStorage", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "无法迁移旧剪贴板历史；原数据库已保留"
        ])
    }
}
