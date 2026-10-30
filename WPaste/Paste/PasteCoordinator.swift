import AppKit
import Foundation

@MainActor
protocol PasteboardWriting: AnyObject {
    func write(_ payload: ClipboardPayload, asPlainText: Bool) -> Bool
}

@MainActor
final class SystemPasteboardWriter: PasteboardWriting {
    private let pasteboard: NSPasteboard
    private let applicationSupportDirectory: URL
    private let imageExportDirectory: URL

    init(
        pasteboard: NSPasteboard = .general,
        applicationSupportDirectory: URL? = nil,
        imageExportDirectory: URL? = nil
    ) {
        self.pasteboard = pasteboard
        self.applicationSupportDirectory = applicationSupportDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appending(path: "WPaste", directoryHint: .isDirectory)
        self.imageExportDirectory = imageExportDirectory
            ?? FileManager.default.temporaryDirectory.appending(path: "WPaste/PastedImages", directoryHint: .isDirectory)
    }

    func write(_ payload: ClipboardPayload, asPlainText: Bool) -> Bool {
        pasteboard.clearContents()
        if asPlainText {
            return pasteboard.setString(payload.plainTextRepresentation, forType: .string)
        }
        switch payload {
        case let .text(value):
            return pasteboard.setString(value, forType: .string)
        case let .url(value):
            return pasteboard.writeObjects([value as NSURL])
        case let .image(metadata):
            let url = applicationSupportDirectory.appending(path: metadata.relativePath)
            guard let data = try? Data(contentsOf: url),
                  let bitmap = NSBitmapImageRep(data: data),
                  let png = bitmap.representation(using: .png, properties: [:]) else { return false }
            // A bitmap alone lets receiving apps invent the same name for every image.
            // Keep a named PNG outside history so deleting an entry cannot invalidate a pending paste.
            let filename = "WPaste-\(ContentFingerprint.make(forImageData: data)).png"
            let exportedURL = imageExportDirectory.appending(path: filename)
            do {
                try FileManager.default.createDirectory(at: imageExportDirectory, withIntermediateDirectories: true)
                try png.write(to: exportedURL, options: .atomic)
            } catch {
                return false
            }
            let item = NSPasteboardItem()
            item.setString(exportedURL.absoluteString, forType: .fileURL)
            item.setData(png, forType: .png)
            if let tiff = bitmap.tiffRepresentation { item.setData(tiff, forType: .tiff) }
            item.setString("", forType: .init(PasteboardSnapshot.restoredImageType))
            return pasteboard.writeObjects([item])
        case let .files(files):
            let urls = files.map { URL(fileURLWithPath: $0.path) as NSURL }
            guard urls.allSatisfy({ FileManager.default.fileExists(atPath: $0.path ?? "") }) else { return false }
            return pasteboard.writeObjects(urls)
        }
    }
}

enum PasteMode: Equatable, Sendable {
    case automatic(plainText: Bool)
    case copyOnly(plainText: Bool)

    var plainText: Bool {
        switch self {
        case let .automatic(value), let .copyOnly(value): value
        }
    }
}

enum PasteFallbackReason: Equatable, Sendable {
    case accessibilityPermissionMissing
    case targetUnavailable
    case activationFailed
    case keyEventFailed
}

enum PasteResult: Equatable, Sendable {
    case pasted
    case copiedOnly(PasteFallbackReason)
    case copied
    case unavailable
}

@MainActor
final class PasteCoordinator {
    private let pasteboard: PasteboardWriting
    private let accessibility: AccessibilityControlling
    private let closeOverlay: () -> Void
    private let suppressWrite: (String, Date) -> Void
    private var hasRequestedAccessibilityPermission = false

    init(
        pasteboard: PasteboardWriting,
        accessibility: AccessibilityControlling,
        closeOverlay: @escaping () -> Void,
        suppressWrite: @escaping (String, Date) -> Void = { _, _ in }
    ) {
        self.pasteboard = pasteboard
        self.accessibility = accessibility
        self.closeOverlay = closeOverlay
        self.suppressWrite = suppressWrite
    }

    func paste(item: ClipboardItem, mode: PasteMode, target: ApplicationTargeting?) -> PasteResult {
        suppressWrite(item.fingerprint, .now.addingTimeInterval(2))
        guard pasteboard.write(item.payload, asPlainText: mode.plainText) else { return .unavailable }
        closeOverlay()
        guard case .automatic = mode else { return .copied }
        guard accessibility.isTrusted else {
            if !hasRequestedAccessibilityPermission {
                hasRequestedAccessibilityPermission = true
                accessibility.requestPermission()
            }
            return .copiedOnly(.accessibilityPermissionMissing)
        }
        guard let target, target.isRunning else { return .copiedOnly(.targetUnavailable) }
        guard target.activate() else { return .copiedOnly(.activationFailed) }
        guard accessibility.sendPasteCommand() else { return .copiedOnly(.keyEventFailed) }
        return .pasted
    }
}

private extension ClipboardPayload {
    var plainTextRepresentation: String {
        switch self {
        case let .text(value): value
        case let .url(value): value.absoluteString
        case let .image(metadata): "图片 \(metadata.width) × \(metadata.height)"
        case let .files(files): files.map(\.path).joined(separator: "\n")
        }
    }
}
