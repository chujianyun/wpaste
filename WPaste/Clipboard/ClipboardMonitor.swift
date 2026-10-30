import Foundation

@MainActor
final class ClipboardMonitor {
    private let pasteboard: PasteboardReading
    private let repository: HistoryRepository
    private let settings: () -> AppSettings
    private let parser: ClipboardParser
    private let privacyFilter: PrivacyFilter
    private var lastChangeCount: Int
    private var pollingTask: Task<Void, Never>?
    private var suppression: (fingerprint: String, until: Date)?

    init(
        pasteboard: PasteboardReading,
        repository: HistoryRepository,
        settings: @escaping () -> AppSettings,
        parser: ClipboardParser = .init(),
        privacyFilter: PrivacyFilter = .init()
    ) {
        self.pasteboard = pasteboard
        self.repository = repository
        self.settings = settings
        self.parser = parser
        self.privacyFilter = privacyFilter
        lastChangeCount = pasteboard.changeCount
    }

    func start(interval: Duration = .milliseconds(500)) {
        guard pollingTask == nil else { return }
        pollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? self?.pollOnce()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func suppressNextWrite(fingerprint: String, until: Date) {
        suppression = (fingerprint, until)
    }

    func pollOnce(now: Date = .now) throws {
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount
        guard let snapshot = pasteboard.snapshot(),
              // Restored images also expose a file URL and may have been transcoded to PNG;
              // their parsed fingerprint no longer necessarily matches the original image.
              !snapshot.declaredTypes.contains(PasteboardSnapshot.restoredImageType),
              let parsed = parser.parse(snapshot) else { return }
        guard privacyFilter.decision(for: parsed, settings: settings()) == .allow else { return }

        let fingerprint = parsed.imageData.map(ContentFingerprint.make(forImageData:))
            ?? ContentFingerprint.make(for: parsed.payload)
        if let suppression, suppression.until >= now, suppression.fingerprint == fingerprint {
            self.suppression = nil
            return
        }
        if suppression?.until ?? .distantFuture < now {
            suppression = nil
        }
        try repository.upsert(candidate: parsed, fingerprint: fingerprint, at: now)
    }
}
