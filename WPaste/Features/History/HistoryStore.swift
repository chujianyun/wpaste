import Foundation
import Observation

enum HistoryContentType: String, CaseIterable {
    case all = "全部"
    case text = "文本"
    case url = "链接"
    case image = "图片"
    case files = "文件"

    func matches(_ payload: ClipboardPayload) -> Bool {
        switch (self, payload) {
        case (.all, _), (.text, .text), (.url, .url), (.image, .image), (.files, .files): true
        default: false
        }
    }
}

@MainActor
@Observable
final class HistoryStore {
    var query = ""
    var selectedType: HistoryContentType = .all
    private(set) var items: [ClipboardItem] = []
    private let repository: HistoryRepository

    init(repository: HistoryRepository) {
        self.repository = repository
    }

    var filteredItems: [ClipboardItem] {
        let needle = query.searchNormalized
        return items.filter { item in
            selectedType.matches(item.payload)
                && (needle.isEmpty || item.searchableText.searchNormalized.contains(needle))
        }
    }

    func reload() throws {
        items = try repository.items()
    }

    func delete(id: UUID) throws {
        try repository.delete(id: id)
        try reload()
    }
}

private extension String {
    var searchNormalized: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

private extension ClipboardItem {
    var searchableText: String {
        let payloadText: String
        switch payload {
        case let .text(value): payloadText = value
        case let .url(value): payloadText = value.absoluteString
        case let .image(value): payloadText = "\(value.width) \(value.height)"
        case let .files(value): payloadText = value.map(\.displayName).joined(separator: " ")
        }
        return "\(payloadText) \(source.name) \(source.bundleIdentifier ?? "")"
    }
}

