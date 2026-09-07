import Foundation
import SwiftUI
import Testing
@testable import WPaste

@MainActor
struct FeatureStoreTests {
    private let source = ClipboardSource(bundleIdentifier: "com.apple.Safari", name: "Safari")

    @Test func overlaySettingsButtonOpensSettingsAndReusesWindowAfterClosing() throws {
        let model = AppModel(settings: .default)
        defer { model.stop() }
        let existingWindows = Set(NSApp.windows.map(ObjectIdentifier.init))
        defer {
            for window in NSApp.windows where !existingWindows.contains(ObjectIdentifier(window)) {
                window.orderOut(nil)
                window.contentViewController = nil
                window.contentView = nil
            }
        }

        func settingsButton(in view: NSView) -> NSButton? {
            if let button = view as? NSButton, button.accessibilityIdentifier() == "overlay-settings" {
                return button
            }
            return view.subviews.lazy.compactMap { settingsButton(in: $0) }.first
        }

        var settingsWindow: NSWindow?
        for _ in 0..<2 {
            model.showHistory()
            let panel = try #require(NSApp.windows.first {
                !existingWindows.contains(ObjectIdentifier($0)) && $0 is NSPanel && $0.isVisible
            })
            let contentView = try #require(panel.contentView)
            contentView.layoutSubtreeIfNeeded()
            let button = try #require(settingsButton(in: contentView))
            let frame = panel.convertToScreen(button.convert(button.bounds, to: nil))
            #expect(frame.midX > panel.frame.maxX - 80)
            #expect(frame.midY > panel.frame.maxY - 60)
            button.performClick(nil)

            #expect(!panel.isVisible)
            let windows = NSApp.windows.filter {
                !existingWindows.contains(ObjectIdentifier($0)) && !($0 is NSPanel) && $0.isVisible
            }
            #expect(windows.count == 1)
            let window = try #require(windows.first)
            #expect(window.canBecomeKey)
            #expect(window.contentViewController is NSHostingController<SettingsView>)
            if let settingsWindow { #expect(window === settingsWindow) }
            settingsWindow = window
            window.performClose(nil)
        }
    }

    @Test func historySearchMatchesTextURLFilenameAndSource() throws {
        let repository = try HistoryRepository.inMemory()
        _ = try repository.upsert(payload: .text("季度计划"), fingerprint: "text", source: source)
        _ = try repository.upsert(payload: .url(URL(string: "https://example.com/docs")!), fingerprint: "url", source: source)
        _ = try repository.upsert(payload: .files([.init(path: "/tmp/report.pdf", displayName: "report.pdf")]), fingerprint: "file", source: source)
        let store = HistoryStore(repository: repository)

        try store.reload()
        store.query = "REPORT"
        #expect(store.filteredItems.map(\.fingerprint) == ["file"])
        store.query = "safari"
        #expect(store.filteredItems.count == 3)
    }

    @Test func searchClearButtonClearsQueryAndRestoresHistory() throws {
        let repository = try HistoryRepository.inMemory()
        _ = try repository.upsert(payload: .text("季度计划"), fingerprint: "plan", source: source)
        _ = try repository.upsert(payload: .text("会议记录"), fingerprint: "notes", source: source)
        let history = HistoryStore(repository: repository)
        try history.reload()
        let view = NSHostingView(rootView: HistoryOverlayView(
            history: history,
            pinboards: PinboardStore(repository: repository),
            onPaste: { _, _ in },
            onClose: {},
            onOpenSettings: {}
        ))
        view.frame = NSRect(x: 0, y: 0, width: 900, height: 320)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }

        func searchField(in view: NSView) -> NSSearchField? {
            if let field = view as? NSSearchField { return field }
            return view.subviews.lazy.compactMap { searchField(in: $0) }.first
        }
        view.layoutSubtreeIfNeeded()
        let field = try #require(searchField(in: view))
        let cell = try #require(field.cell as? NSSearchFieldCell)
        #expect(field.stringValue.isEmpty)

        field.stringValue = "季度"
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        #expect(history.query == "季度")
        #expect(history.filteredItems.map(\.fingerprint) == ["plan"])

        for query in ["季度", "   "] {
            history.query = query
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            #expect(field.stringValue == query)
            #expect(history.filteredItems.count < 2)
            let cancelRect = cell.cancelButtonRect(forBounds: field.bounds)
            #expect(!cancelRect.isEmpty)
            let button = try #require(cell.cancelButtonCell)
            button.performClick(field)
            #expect(history.query.isEmpty)
            #expect(history.filteredItems.count == 2)
            #expect(field.stringValue.isEmpty)
        }
    }

    @Test func typeSelectorInsideSearchCombinesTypeAndQuery() throws {
        let repository = try HistoryRepository.inMemory()
        let fixtures: [(String, ClipboardPayload)] = [
            ("text", .text("Report memo")),
            ("url", .url(URL(string: "https://example.com/report")!)),
            ("image", .image(.init(width: 640, height: 480, relativePath: "report.png"))),
            ("files", .files([.init(path: "/tmp/report.pdf", displayName: "report.pdf")])),
            ("other", .text("Unrelated memo"))
        ]
        for (fingerprint, payload) in fixtures {
            _ = try repository.upsert(payload: payload, fingerprint: fingerprint, source: source)
        }
        let history = HistoryStore(repository: repository)
        try history.reload()
        let view = NSHostingView(rootView: HistoryOverlayView(
            history: history, pinboards: PinboardStore(repository: repository),
            onPaste: { _, _ in }, onClose: {}, onOpenSettings: {}
        ))
        view.frame = NSRect(x: 0, y: 0, width: 900, height: 320)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        func descendant<T: NSView>(in view: NSView, type: T.Type) -> T? {
            if let match = view as? T { return match }
            return view.subviews.lazy.compactMap { descendant(in: $0, type: type) }.first
        }
        view.layoutSubtreeIfNeeded()
        let field = try #require(descendant(in: view, type: NSSearchField.self))
        let selector = try #require(descendant(in: field, type: NSPopUpButton.self))
        #expect(field.accessibilityChildren()?.contains { ($0 as? NSPopUpButton) === selector } == true)
        #expect(field.bounds.contains(selector.frame))
        #expect(selector.frame.midX < field.bounds.midX)
        func select(_ title: String) throws {
            selector.selectItem(withTitle: title)
            let action = try #require(selector.action)
            #expect(selector.sendAction(action, to: selector.target))
        }
        for (title, fingerprint) in [("文本", "text"), ("链接", "url"), ("图片", "image"), ("文件", "files")] {
            history.query = "SAFARI"
            try select(title)
            let expected: Set<String> = title == "文本" ? ["text", "other"] : [fingerprint]
            #expect(Set(history.filteredItems.map(\.fingerprint)) == expected)
            history.query = "REPORT"
            #expect(history.filteredItems.map(\.fingerprint) == (title == "图片" ? [] : [fingerprint]))
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        let cell = try #require(field.cell as? NSSearchFieldCell)
        try #require(cell.cancelButtonCell).performClick(field)
        #expect(history.query.isEmpty)
        #expect(history.filteredItems.map(\.fingerprint) == ["files"])
        history.query = "REPORT"
        try select("全部")
        #expect(history.query == "REPORT")
        #expect(Set(history.filteredItems.map(\.fingerprint)) == ["text", "url", "files"])
        history.query = ""
        #expect(history.filteredItems.count == 5)
    }

    @Test func itemCanBelongToMultiplePinboardsAndDeletingBoardKeepsHistory() throws {
        let repository = try HistoryRepository.inMemory()
        let item = try repository.upsert(payload: .text("keep"), fingerprint: "keep", source: source)
        let store = PinboardStore(repository: repository)
        let work = try store.create(name: "工作")
        let later = try store.create(name: "稍后")
        try store.add(itemID: item.id, to: work.id)
        try store.add(itemID: item.id, to: later.id)

        #expect(try store.itemIDs(in: work.id) == [item.id])
        #expect(try store.itemIDs(in: later.id) == [item.id])
        try store.delete(id: work.id)
        #expect(try repository.items().map(\.id) == [item.id])
        #expect(try store.itemIDs(in: later.id) == [item.id])
    }

    @Test func pinboardsCanBeRenamedAndReordered() throws {
        let repository = try HistoryRepository.inMemory()
        let store = PinboardStore(repository: repository)
        let first = try store.create(name: "第一")
        _ = try store.create(name: "第二")
        let third = try store.create(name: "第三")

        try store.rename(id: first.id, name: "已重命名")
        try store.move(id: third.id, to: 0)

        #expect(store.pinboards.map(\.name) == ["第三", "已重命名", "第二"])
    }
}
