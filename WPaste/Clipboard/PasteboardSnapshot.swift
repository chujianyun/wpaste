import Foundation

struct PixelSize: Equatable, Sendable {
    let width: Int
    let height: Int
}

struct PasteboardSnapshot: Equatable, Sendable {
    static let restoredImageType = "com.chujianyun.wpaste.restored-image"

    var fileURLs: [URL]
    var imageData: Data?
    var imageSize: PixelSize?
    var urlString: String?
    var text: String?
    var declaredTypes: Set<String>
    var source: ClipboardSource

    init(
        fileURLs: [URL] = [],
        imageData: Data? = nil,
        imageSize: PixelSize? = nil,
        urlString: String? = nil,
        text: String? = nil,
        declaredTypes: Set<String> = [],
        source: ClipboardSource
    ) {
        self.fileURLs = fileURLs
        self.imageData = imageData
        self.imageSize = imageSize
        self.urlString = urlString
        self.text = text
        self.declaredTypes = declaredTypes
        self.source = source
    }
}

struct ParsedClipboard: Equatable, Sendable {
    let payload: ClipboardPayload
    let source: ClipboardSource
    let declaredTypes: Set<String>
    let imageData: Data?

    init(
        payload: ClipboardPayload,
        source: ClipboardSource,
        declaredTypes: Set<String> = [],
        imageData: Data? = nil
    ) {
        self.payload = payload
        self.source = source
        self.declaredTypes = declaredTypes
        self.imageData = imageData
    }
}

