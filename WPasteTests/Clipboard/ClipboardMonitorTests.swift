import AppKit
import Testing
@testable import WPaste

@MainActor
struct ClipboardMonitorTests {
    private let source = ClipboardSource(bundleIdentifier: "com.apple.TextEdit", name: "文本编辑")

    @Test func capturesExactlyOnceForEachChangeCount() throws {
        let pasteboard = FakePasteboardClient(snapshot: .init(text: "hello", source: source))
        let repository = try HistoryRepository.inMemory()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, repository: repository) { .default }

        try monitor.pollOnce(now: Date(timeIntervalSince1970: 100))
        #expect(try repository.items().isEmpty)

        pasteboard.changeCount = 1
        try monitor.pollOnce(now: Date(timeIntervalSince1970: 101))
        try monitor.pollOnce(now: Date(timeIntervalSince1970: 102))
        #expect(try repository.items().count == 1)
    }

    @Test func privacyFilteringHappensBeforePersistence() throws {
        let pasteboard = FakePasteboardClient(snapshot: .init(
            text: "secret",
            declaredTypes: ["org.nspasteboard.ConcealedType"],
            source: source
        ))
        let repository = try HistoryRepository.inMemory()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, repository: repository) { .default }
        pasteboard.changeCount = 1

        try monitor.pollOnce()

        #expect(try repository.items().isEmpty)
    }

    @Test func appWriteSuppressionSkipsMatchingNextCapture() throws {
        let pasteboard = FakePasteboardClient(snapshot: .init(text: "self write", source: source))
        let repository = try HistoryRepository.inMemory()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, repository: repository) { .default }
        let payload = ClipboardPayload.text("self write")
        let now = Date(timeIntervalSince1970: 200)
        monitor.suppressNextWrite(fingerprint: ContentFingerprint.make(for: payload), until: now.addingTimeInterval(2))
        pasteboard.changeCount = 1

        try monitor.pollOnce(now: now)

        #expect(try repository.items().isEmpty)
    }

    @Test func restoringNamedImageDoesNotCreateFileHistoryEntry() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ImageFileStore(rootDirectory: root)
        let repository = try HistoryRepository.inMemory(imageFileStore: store)
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let bitmap = NSBitmapImageRep(cgImage: try #require(context.makeImage()))
        let data = try #require(bitmap.representation(using: .tiff, properties: [:]))
        let item = try repository.upsert(candidate: .init(
            payload: .image(.init(width: 1, height: 1, relativePath: "")),
            source: source, imageData: data
        ), fingerprint: ContentFingerprint.make(forImageData: data))
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        var settings = AppSettings.default
        settings.ignoreSensitiveContent = false
        settings.ignoreTransientContent = false
        let monitor = ClipboardMonitor(
            pasteboard: SystemPasteboardClient(pasteboard: pasteboard), repository: repository
        ) { settings }
        let writer = SystemPasteboardWriter(
            pasteboard: pasteboard, applicationSupportDirectory: root,
            imageExportDirectory: root.appending(path: "Exports")
        )

        #expect(writer.write(item.payload, asPlainText: false))
        try monitor.pollOnce()

        #expect(try repository.items() == [item])
    }
}

@MainActor
private final class FakePasteboardClient: PasteboardReading {
    var changeCount = 0
    var snapshotValue: PasteboardSnapshot

    init(snapshot: PasteboardSnapshot) {
        snapshotValue = snapshot
    }

    func snapshot() -> PasteboardSnapshot? {
        snapshotValue
    }
}

