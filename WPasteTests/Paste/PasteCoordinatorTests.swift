import AppKit
import Testing
@testable import WPaste

@MainActor
struct PasteCoordinatorTests {
    private let source = ClipboardSource(bundleIdentifier: "com.apple.TextEdit", name: "文本编辑")

    @Test func capturedApplicationRemainsAvailableAfterCaptureScopeEnds() {
        let target = autoreleasepool {
            RunningApplicationTarget(application: NSRunningApplication(processIdentifier: ProcessInfo.processInfo.processIdentifier)!)
        }
        #expect(target.isRunning)
    }

    @Test func differentImagesExposeDistinctFilenamesAndReadableImageData() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ImageFileStore(rootDirectory: root)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let writer = SystemPasteboardWriter(
            pasteboard: pasteboard, applicationSupportDirectory: root,
            imageExportDirectory: root.appending(path: "Exports")
        )
        var filenames: Set<String> = []

        // Existing history can contain either PNG or TIFF bytes with a .png extension.
        for (format, blue) in [(NSBitmapImageRep.FileType.png, 0.0), (.tiff, 1.0)] {
            let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
            let context = try #require(CGContext(
                data: nil, width: 2, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.setFillColor(red: 1 - blue, green: 0, blue: blue, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 1))
            let bitmap = NSBitmapImageRep(cgImage: try #require(context.makeImage()))
            let data = try #require(bitmap.representation(using: format, properties: [:]))
            let path = try store.save(data, fileExtension: "png")
            let payload = ClipboardPayload.image(.init(width: 2, height: 1, relativePath: path))

            #expect(writer.write(payload, asPlainText: false))
            #expect(pasteboard.pasteboardItems?.count == 1)
            let urls = try #require(pasteboard.readObjects(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
            ) as? [URL])
            let url = try #require(urls.first)
            #expect(urls.count == 1)
            #expect(url.pathExtension == "png")
            #expect(filenames.insert(url.lastPathComponent).inserted)
            let exported = try Data(contentsOf: url)
            #expect(exported.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]))
            #expect(pasteboard.data(forType: .png) == exported)
            let restored = try #require(NSBitmapImageRep(data: exported))
            #expect(restored.pixelsWide == 2)
            #expect(restored.pixelsHigh == 1)
            let pixel = try #require(restored.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB))
            // Allow AppKit's display color management while checking distinct pixel content.
            #expect(abs(pixel.blueComponent - blue) < 0.05)
            #expect(abs(pixel.redComponent - (1 - blue)) < 0.05)
            #expect(pixel.alphaComponent > 0.99)
            #expect(NSImage(pasteboard: pasteboard)?.isValid == true)

            #expect(writer.write(payload, asPlainText: false))
            #expect(pasteboard.string(forType: .fileURL) == url.absoluteString)
            // The exported file remains usable after its history entry is removed.
            try store.delete(relativePath: path)
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
        #expect(filenames.count == 2)
    }

    @Test func automaticPasteWritesClosesActivatesAndSendsInOrder() {
        var events: [String] = []
        let writer = RecordingPasteboardWriter { events.append($0) }
        let accessibility = RecordingAccessibilityClient(trusted: true) { events.append($0) }
        let target = RecordingApplicationTarget(isRunning: true) { events.append($0) }
        let coordinator = PasteCoordinator(
            pasteboard: writer,
            accessibility: accessibility,
            closeOverlay: { events.append("close") }
        )
        let item = ClipboardItem(payload: .text("hello"), fingerprint: "hello", source: source)

        let result = coordinator.paste(item: item, mode: .automatic(plainText: false), target: target)

        #expect(result == .pasted)
        #expect(events == ["write", "close", "activate", "paste"])
    }

    @Test func deniedAccessibilityFallsBackToCopyOnly() {
        var events: [String] = []
        let coordinator = PasteCoordinator(
            pasteboard: RecordingPasteboardWriter { events.append($0) },
            accessibility: RecordingAccessibilityClient(trusted: false) { events.append($0) },
            closeOverlay: { events.append("close") }
        )
        let item = ClipboardItem(payload: .text("hello"), fingerprint: "hello", source: source)

        let result = coordinator.paste(item: item, mode: .automatic(plainText: false), target: RecordingApplicationTarget(isRunning: true) { events.append($0) })

        #expect(result == .copiedOnly(.accessibilityPermissionMissing))
        #expect(events == ["write", "close", "permission"])
    }

    @Test func plainTextModeWritesStringRepresentation() {
        let writer = RecordingPasteboardWriter { _ in }
        let coordinator = PasteCoordinator(
            pasteboard: writer,
            accessibility: RecordingAccessibilityClient(trusted: true) { _ in },
            closeOverlay: {}
        )
        let item = ClipboardItem(payload: .url(URL(string: "https://example.com")!), fingerprint: "url", source: source)

        _ = coordinator.paste(item: item, mode: .copyOnly(plainText: true), target: nil)

        #expect(writer.lastPlainText == true)
        #expect(writer.lastPayload == item.payload)
    }

    @Test(arguments: [
        ClipboardPayload.text("hello"),
        ClipboardPayload.image(ImageMetadata(width: 10, height: 10, relativePath: "Images/test.png"))
    ])
    func repeatedDeniedPastesPromptOnlyOnceAndStillCopy(payload: ClipboardPayload) {
        var events: [String] = []
        let coordinator = PasteCoordinator(
            pasteboard: RecordingPasteboardWriter { events.append($0) },
            accessibility: RecordingAccessibilityClient(trusted: false) { events.append($0) },
            closeOverlay: { events.append("close") }
        )
        let item = ClipboardItem(payload: payload, fingerprint: "repeated", source: source)

        for _ in 0..<3 {
            #expect(coordinator.paste(item: item, mode: .automatic(plainText: false), target: nil)
                == .copiedOnly(.accessibilityPermissionMissing))
        }

        #expect(events.filter { $0 == "permission" }.count == 1)
        #expect(events.filter { $0 == "write" }.count == 3)
        #expect(!events.contains("paste"))
    }

    @Test func grantingPermissionAfterPromptRestoresAutomaticPaste() {
        var events: [String] = []
        let accessibility = RecordingAccessibilityClient(trusted: false) { events.append($0) }
        let coordinator = PasteCoordinator(
            pasteboard: RecordingPasteboardWriter { events.append($0) },
            accessibility: accessibility,
            closeOverlay: { events.append("close") }
        )
        let item = ClipboardItem(payload: .text("hello"), fingerprint: "hello", source: source)
        let target = RecordingApplicationTarget(isRunning: true) { events.append($0) }

        #expect(coordinator.paste(item: item, mode: .automatic(plainText: false), target: target)
            == .copiedOnly(.accessibilityPermissionMissing))
        accessibility.isTrusted = true
        #expect(coordinator.paste(item: item, mode: .automatic(plainText: false), target: target) == .pasted)
        #expect(events.filter { $0 == "permission" }.count == 1)
        #expect(events.suffix(2) == ["activate", "paste"])
    }

    @Test func exitedTargetLeavesContentCopied() {
        let coordinator = PasteCoordinator(
            pasteboard: RecordingPasteboardWriter { _ in },
            accessibility: RecordingAccessibilityClient(trusted: true) { _ in },
            closeOverlay: {}
        )
        let item = ClipboardItem(payload: .text("hello"), fingerprint: "hello", source: source)
        let target = RecordingApplicationTarget(isRunning: false) { _ in }
        #expect(coordinator.paste(item: item, mode: .automatic(plainText: false), target: target) == .copiedOnly(.targetUnavailable))
    }
}

@MainActor
private final class RecordingPasteboardWriter: PasteboardWriting {
    var lastPayload: ClipboardPayload?
    var lastPlainText: Bool?
    private let record: (String) -> Void

    init(record: @escaping (String) -> Void) { self.record = record }

    func write(_ payload: ClipboardPayload, asPlainText: Bool) -> Bool {
        lastPayload = payload
        lastPlainText = asPlainText
        record("write")
        return true
    }
}

@MainActor
private final class RecordingAccessibilityClient: AccessibilityControlling {
    var isTrusted: Bool
    let record: (String) -> Void

    init(trusted: Bool, record: @escaping (String) -> Void) {
        isTrusted = trusted
        self.record = record
    }

    func sendPasteCommand() -> Bool {
        record("paste")
        return true
    }

    func requestPermission() {
        record("permission")
    }
}

@MainActor
private final class RecordingApplicationTarget: ApplicationTargeting {
    let isRunning: Bool
    private let record: (String) -> Void

    init(isRunning: Bool, record: @escaping (String) -> Void) {
        self.isRunning = isRunning
        self.record = record
    }

    func activate() -> Bool {
        record("activate")
        return true
    }
}
