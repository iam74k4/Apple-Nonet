// 担当: core-model。最近のスクリーンショットを探す（ScreenshotFolder）と、アクションの書式
import Darwin
import Foundation
import Testing
@testable import NonetCore

@Suite struct ModelScreenshotsTests {
    private func defaults(_ values: [String: String]) throws -> UserDefaults {
        let name = "ModelScreenshotsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        for (key, value) in values { defaults.set(value, forKey: key) }
        return defaults
    }

    private let home = URL(filePath: "/Users/someone", directoryHint: .isDirectory)

    @Test func theLocationFollowsTheScreenshotSettings() throws {
        let desktop = home.appending(path: "Desktop", directoryHint: .isDirectory)
        #expect(ScreenshotFolder.location(defaults: try defaults([:]), home: home) == desktop)
        #expect(ScreenshotFolder.location(defaults: nil, home: home) == desktop)
        #expect(ScreenshotFolder.location(defaults: try defaults(["location": "  "]), home: home) == desktop)
        #expect(ScreenshotFolder.location(defaults: try defaults(["location": "~/Pictures/Shots"]), home: home).path(percentEncoded: false)
            == "/Users/someone/Pictures/Shots/")
        #expect(ScreenshotFolder.location(defaults: try defaults(["location": "/Volumes/Work/Shots"]), home: home).path(percentEncoded: false)
            == "/Volumes/Work/Shots/")
        // 場所でない値（クリップボードなど）はデスクトップ
        #expect(ScreenshotFolder.location(defaults: try defaults(["location": "clipboard"]), home: home) == desktop)
    }

    @Test func aCustomNameIsRecognizedToo() throws {
        let prefixes = ScreenshotFolder.namePrefixes(defaults: try defaults(["name": "Shot"]))
        #expect(prefixes.first == "Shot")
        #expect(prefixes.contains("スクリーンショット"))
        #expect(ScreenshotFolder.namePrefixes(defaults: try defaults([:])) == ScreenshotFolder.defaultNamePrefixes)
    }

    // MARK: 探す

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "ModelScreenshotsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func file(_ name: String, in folder: URL, created: TimeInterval, marked: Bool = false) throws -> URL {
        let url = folder.appending(path: name)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: url)
        let date = Date(timeIntervalSince1970: created)
        try FileManager.default.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: url.path(percentEncoded: false))
        if marked {
            var value: UInt8 = 1
            let result = url.withUnsafeFileSystemRepresentation { path in
                setxattr(path!, ScreenshotFolder.screenCaptureAttribute, &value, 1, 0, 0)
            }
            #expect(result == 0)
        }
        return url
    }

    @Test func findsTheNewestScreenshotsFirst() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        try file("スクリーンショット 2026-11-23 10.00.00.png", in: dir, created: 100)
        try file("Screenshot 2026-11-23 at 11.00.00.png", in: dir, created: 300)
        try file("design.png", in: dir, created: 400, marked: true)
        // スクリーンショットでない画像・動画・ほかのファイルは並べない
        try file("photo.png", in: dir, created: 500)
        try file("holiday.mov", in: dir, created: 550)
        try file("Screenshot notes.txt", in: dir, created: 700)
        let listing = ScreenshotFolder.recent(in: dir, includesVideos: false)
        guard case .found(let items, let found) = listing else {
            Issue.record("見つからなかった: \(listing)")
            return
        }
        #expect(found == dir)
        #expect(items.map(\.url.lastPathComponent) == ["design.png", "Screenshot 2026-11-23 at 11.00.00.png", "スクリーンショット 2026-11-23 10.00.00.png"])
        #expect(items.first?.date == Date(timeIntervalSince1970: 400))
    }

    /// 画面の収録（印か、名前が「画面収録」「Screen Recording」で始まる動画）も並べる。動画を外すこともできる
    @Test func screenRecordingsAreListedToo() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        try file("Screenshot 1.png", in: dir, created: 100)
        try file("画面収録 2026-11-23 12.00.00.mov", in: dir, created: 200)
        try file("clip.mov", in: dir, created: 300, marked: true)
        try file("holiday.mov", in: dir, created: 400)
        guard case .found(let items, _) = ScreenshotFolder.recent(in: dir) else {
            Issue.record("見つからなかった")
            return
        }
        #expect(items.map(\.url.lastPathComponent) == ["clip.mov", "画面収録 2026-11-23 12.00.00.mov", "Screenshot 1.png"])
        #expect(items.map(\.isVideo) == [true, true, false])
        guard case .found(let images, _) = ScreenshotFolder.recent(in: dir, includesVideos: false) else { return }
        #expect(images.map(\.url.lastPathComponent) == ["Screenshot 1.png"])
    }

    @Test func showsAtMostTheLimit() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        for index in 0..<8 {
            try file("Screenshot \(index).png", in: dir, created: Double(index))
        }
        guard case .found(let items, _) = ScreenshotFolder.recent(in: dir, limit: 5) else {
            Issue.record("見つからなかった")
            return
        }
        #expect(items.map(\.url.lastPathComponent) == ["Screenshot 7.png", "Screenshot 6.png", "Screenshot 5.png", "Screenshot 4.png", "Screenshot 3.png"])
    }

    @Test func anEmptyFolderAndAMissingFolderAreToldApart() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(ScreenshotFolder.recent(in: dir) == .found([], folder: dir))
        let missing = dir.appending(path: "nothing", directoryHint: .isDirectory)
        #expect(ScreenshotFolder.recent(in: missing) == .missingFolder(missing))
    }

    @Test func aFolderItCannotReadIsNotPermitted() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
        #expect(ScreenshotFolder.listing(for: error, folder: dir, fileManager: .default) == .notPermitted(folder: dir))
        let posix = NSError(domain: NSCocoaErrorDomain, code: 256, userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))])
        #expect(ScreenshotFolder.listing(for: posix, folder: dir, fileManager: .default) == .notPermitted(folder: dir))
    }

    // MARK: 書式

    @Test func theTrayActionRoundTrips() throws {
        let action = Action.screenshots(ScreenshotTrayAction())
        let data = try JSONEncoder().encode(action)
        #expect(String(decoding: data, as: UTF8.self) == #"{"type":"screenshots"}"#)
        #expect(try JSONDecoder().decode(Action.self, from: data) == action)
        let custom = Action.screenshots(ScreenshotTrayAction(count: 12, includesVideos: false))
        #expect(try JSONDecoder().decode(Action.self, from: JSONEncoder().encode(custom)) == custom)
        // 選べない数は近いものに直す
        #expect(ScreenshotTrayAction(count: 7).count == 8)
        #expect(ScreenshotTrayAction(count: 100).count == 12)
        #expect(ScreenshotTrayAction(count: -3).count == 3)
        let odd = try JSONDecoder().decode(Action.self, from: Data(#"{"type":"screenshots","count":4,"includesVideos":"yes"}"#.utf8))
        #expect(odd == .screenshots(ScreenshotTrayAction(count: 5, includesVideos: true)))
        #expect(action.kind == .screenshots)
        #expect(action.summary == ModelFixtures.text("最近のスクショ"))
    }
}
