import Foundation
import SwiftData

@MainActor
final class HistoryRepository {
    private let container: ModelContainer
    private let context: ModelContext
    private let imageFileStore: ImageFileStore?

    init(inMemory: Bool = false, imageFileStore: ImageFileStore? = nil) throws {
        if let imageFileStore {
            self.imageFileStore = imageFileStore
        } else if inMemory {
            self.imageFileStore = nil
        } else {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appending(path: "WPaste", directoryHint: .isDirectory)
            self.imageFileStore = ImageFileStore(rootDirectory: root)
        }
        let configuration = try inMemory
            ? ModelConfiguration(isStoredInMemoryOnly: true)
            : HistoryStorage(applicationSupportDirectory: FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            )[0]).configuration()
        container = try ModelContainer(
            for: HistoryRecord.self,
            PinboardRecord.self,
            PinboardItemRecord.self,
            configurations: configuration
        )
        context = container.mainContext
        context.autosaveEnabled = false
    }

    static func inMemory(imageFileStore: ImageFileStore? = nil) throws -> HistoryRepository {
        try HistoryRepository(inMemory: true, imageFileStore: imageFileStore)
    }

    @discardableResult
    func upsert(
        payload: ClipboardPayload,
        fingerprint: String,
        source: ClipboardSource,
        at date: Date = .now
    ) throws -> ClipboardItem {
        let descriptor = FetchDescriptor<HistoryRecord>(predicate: #Predicate { $0.fingerprint == fingerprint })
        if let existing = try context.fetch(descriptor).first {
            let item = ClipboardItem(
                id: existing.id,
                payload: payload,
                fingerprint: fingerprint,
                source: source,
                createdAt: existing.createdAt,
                lastUsedAt: date
            )
            try existing.update(from: item)
            try context.save()
            return item
        }

        let item = ClipboardItem(
            payload: payload,
            fingerprint: fingerprint,
            source: source,
            createdAt: date,
            lastUsedAt: date
        )
        context.insert(try HistoryRecord(item: item))
        try context.save()
        return item
    }

    func items() throws -> [ClipboardItem] {
        var descriptor = FetchDescriptor<HistoryRecord>(sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)])
        descriptor.includePendingChanges = true
        return try context.fetch(descriptor).compactMap { try? $0.domainItem() }
    }

    @discardableResult
    func upsert(candidate: ParsedClipboard, fingerprint: String, at date: Date = .now) throws -> ClipboardItem {
        var payload = candidate.payload
        var newlySavedPath: String?
        let existingDescriptor = FetchDescriptor<HistoryRecord>(predicate: #Predicate { $0.fingerprint == fingerprint })
        let previousImagePath = try context.fetch(existingDescriptor).first?.imageRelativePath
        if case let .image(metadata) = candidate.payload,
           let data = candidate.imageData,
           let imageFileStore {
            let relativePath = try imageFileStore.save(data, fileExtension: "png")
            newlySavedPath = relativePath
            payload = .image(.init(width: metadata.width, height: metadata.height, relativePath: relativePath))
        }
        do {
            let item = try upsert(payload: payload, fingerprint: fingerprint, source: candidate.source, at: date)
            if let previousImagePath, previousImagePath != newlySavedPath {
                try imageFileStore?.delete(relativePath: previousImagePath)
            }
            return item
        } catch {
            if let newlySavedPath { try? imageFileStore?.delete(relativePath: newlySavedPath) }
            throw error
        }
    }

    func delete(id: UUID) throws {
        let descriptor = FetchDescriptor<HistoryRecord>(predicate: #Predicate { $0.id == id })
        let records = try context.fetch(descriptor)
        let imagePaths = records.compactMap(\.imageRelativePath)
        records.forEach(context.delete)
        let memberships = FetchDescriptor<PinboardItemRecord>(predicate: #Predicate { $0.itemID == id })
        try context.fetch(memberships).forEach(context.delete)
        try context.save()
        for path in imagePaths { try imageFileStore?.delete(relativePath: path) }
    }

    func clear() throws {
        let imagePaths = try context.fetch(FetchDescriptor<HistoryRecord>()).compactMap(\.imageRelativePath)
        try context.delete(model: HistoryRecord.self)
        try context.delete(model: PinboardItemRecord.self)
        try context.save()
        for path in imagePaths { try imageFileStore?.delete(relativePath: path) }
    }

    @discardableResult
    func cleanExpired(retention: HistoryRetention, now: Date = .now) throws -> Int {
        guard let interval = retention.duration else { return 0 }
        let cutoff = now.addingTimeInterval(-interval)
        let descriptor = FetchDescriptor<HistoryRecord>(predicate: #Predicate { $0.lastUsedAt < cutoff })
        let expired = try context.fetch(descriptor)
        let expiredIDs = Set(expired.map(\.id))
        let imagePaths = expired.compactMap(\.imageRelativePath)
        expired.forEach(context.delete)
        for membership in try context.fetch(FetchDescriptor<PinboardItemRecord>()) where expiredIDs.contains(membership.itemID) {
            context.delete(membership)
        }
        try context.save()
        for path in imagePaths { try imageFileStore?.delete(relativePath: path) }
        return expired.count
    }

    func pinboards() throws -> [Pinboard] {
        let descriptor = FetchDescriptor<PinboardRecord>(sortBy: [SortDescriptor(\.order)])
        return try context.fetch(descriptor).map { Pinboard(id: $0.id, name: $0.name, order: $0.order) }
    }

    func createPinboard(name: String) throws -> Pinboard {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = PinboardRecord(name: cleanName, order: try pinboards().count)
        context.insert(record)
        try context.save()
        return Pinboard(id: record.id, name: record.name, order: record.order)
    }

    func renamePinboard(id: UUID, name: String) throws {
        let descriptor = FetchDescriptor<PinboardRecord>(predicate: #Predicate { $0.id == id })
        guard let record = try context.fetch(descriptor).first else { return }
        record.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try context.save()
    }

    func deletePinboard(id: UUID) throws {
        let descriptor = FetchDescriptor<PinboardRecord>(predicate: #Predicate { $0.id == id })
        try context.fetch(descriptor).forEach(context.delete)
        let memberships = FetchDescriptor<PinboardItemRecord>(predicate: #Predicate { $0.pinboardID == id })
        try context.fetch(memberships).forEach(context.delete)
        try context.save()
    }

    func movePinboard(id: UUID, to destination: Int) throws {
        let descriptor = FetchDescriptor<PinboardRecord>(sortBy: [SortDescriptor(\.order)])
        var records = try context.fetch(descriptor)
        guard let source = records.firstIndex(where: { $0.id == id }),
              destination >= 0, destination < records.count else { return }
        let moved = records.remove(at: source)
        records.insert(moved, at: destination)
        for (index, record) in records.enumerated() { record.order = index }
        try context.save()
    }

    func add(itemID: UUID, toPinboard pinboardID: UUID) throws {
        let descriptor = FetchDescriptor<PinboardItemRecord>(predicate: #Predicate {
            $0.itemID == itemID && $0.pinboardID == pinboardID
        })
        guard try context.fetch(descriptor).isEmpty else { return }
        context.insert(PinboardItemRecord(pinboardID: pinboardID, itemID: itemID))
        try context.save()
    }

    func itemIDs(inPinboard pinboardID: UUID) throws -> [UUID] {
        let descriptor = FetchDescriptor<PinboardItemRecord>(predicate: #Predicate { $0.pinboardID == pinboardID })
        return try context.fetch(descriptor).map(\.itemID)
    }

}

private extension HistoryRetention {
    var duration: TimeInterval? {
        switch self {
        case .oneDay: 86_400
        case .sevenDays: 604_800
        case .oneMonth: 2_592_000
        case .oneYear: 31_536_000
        case .forever: nil
        }
    }
}
