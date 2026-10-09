import Foundation
import SQLite3
import SwiftData
import Testing
@testable import WPaste

@MainActor
struct HistoryStorageTests {
    @Test func persistentStoreIsInsideWPasteDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = try HistoryStorage(applicationSupportDirectory: root).configuration()

        #expect(configuration.url == root.appending(path: "WPaste/History.store"))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "WPaste").path))
    }

    @Test func migratesLegacyHistoryWithoutChangingLegacyStore() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let legacyURL = root.appending(path: "default.store")
        let legacy = try ModelContainer(
            for: HistoryRecord.self, PinboardRecord.self, PinboardItemRecord.self,
            configurations: ModelConfiguration(url: legacyURL)
        )
        let item = ClipboardItem(
            payload: .text("legacy history"), fingerprint: "legacy",
            source: .init(bundleIdentifier: "com.apple.TextEdit", name: "TextEdit")
        )
        legacy.mainContext.insert(try HistoryRecord(item: item))
        let board = PinboardRecord(name: "Saved", order: 0)
        legacy.mainContext.insert(board)
        legacy.mainContext.insert(PinboardItemRecord(pinboardID: board.id, itemID: item.id))
        try legacy.mainContext.save()

        let configuration = try HistoryStorage(applicationSupportDirectory: root).configuration()
        let migratedURL = root.appending(path: "WPaste/History.store")
        #expect(configuration.url == migratedURL)
        guard FileManager.default.fileExists(atPath: migratedURL.path) else {
            Issue.record("Legacy history was not migrated")
            return
        }
        let migrated = try ModelContainer(
            for: HistoryRecord.self, PinboardRecord.self, PinboardItemRecord.self,
            configurations: configuration
        )
        #expect(try migrated.mainContext.fetch(FetchDescriptor<HistoryRecord>()).map(\.id) == [item.id])
        #expect(try migrated.mainContext.fetch(FetchDescriptor<PinboardRecord>()).map(\.id) == [board.id])
        #expect(try migrated.mainContext.fetch(FetchDescriptor<PinboardItemRecord>()).map(\.itemID) == [item.id])
        #expect(try legacy.mainContext.fetch(FetchDescriptor<HistoryRecord>()).map(\.id) == [item.id])
    }

    @Test func unrelatedDefaultStoreIsNotTouchedAndNewHistorySurvivesReopening() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let legacyURL = root.appending(path: "default.store")
        var database: OpaquePointer?
        #expect(sqlite3_open(legacyURL.path, &database) == SQLITE_OK)
        #expect(sqlite3_exec(database, "CREATE TABLE OtherApp (value TEXT); INSERT INTO OtherApp VALUES ('keep');", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(database)
        let original = try Data(contentsOf: legacyURL)

        let storage = HistoryStorage(applicationSupportDirectory: root)
        let configuration = try storage.configuration()
        var itemID: UUID?
        do {
            let container = try ModelContainer(
                for: HistoryRecord.self, PinboardRecord.self, PinboardItemRecord.self,
                configurations: configuration
            )
            let item = ClipboardItem(
                payload: .text("new history"), fingerprint: "new",
                source: .init(bundleIdentifier: nil, name: "Test")
            )
            itemID = item.id
            container.mainContext.insert(try HistoryRecord(item: item))
            try container.mainContext.save()
        }
        let reopened = try ModelContainer(
            for: HistoryRecord.self, PinboardRecord.self, PinboardItemRecord.self,
            configurations: storage.configuration()
        )
        #expect(try reopened.mainContext.fetch(FetchDescriptor<HistoryRecord>()).map(\.id) == [itemID])
        #expect(try Data(contentsOf: legacyURL) == original)
    }

    @Test func existingDedicatedHistoryIsNotReplacedByLegacyHistory() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = try ModelContainer(
            for: HistoryRecord.self, PinboardRecord.self, PinboardItemRecord.self,
            configurations: ModelConfiguration(url: root.appending(path: "default.store"))
        )
        let storage = HistoryStorage(applicationSupportDirectory: root)
        let configuration = try storage.configuration()
        let current = try ModelContainer(
            for: HistoryRecord.self, PinboardRecord.self, PinboardItemRecord.self,
            configurations: configuration
        )
        let item = ClipboardItem(
            payload: .text("current"), fingerprint: "current",
            source: .init(bundleIdentifier: nil, name: "Test")
        )
        current.mainContext.insert(try HistoryRecord(item: item))
        try current.mainContext.save()
        legacy.mainContext.insert(try HistoryRecord(item: ClipboardItem(
            payload: .text("legacy"), fingerprint: "legacy", source: item.source
        )))
        try legacy.mainContext.save()

        _ = try storage.configuration()

        #expect(try current.mainContext.fetch(FetchDescriptor<HistoryRecord>()).map(\.id) == [item.id])
    }
}
