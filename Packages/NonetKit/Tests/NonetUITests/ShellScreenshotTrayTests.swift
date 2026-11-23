// 担当: ui-shell。「最近のスクショ」のトレイ: 並べる・選ぶ・コピーして閉じる・知らせ
import AppKit
import NonetCore
@testable import NonetUI
import Testing

@MainActor
@Suite struct ShellScreenshotTrayTests {
    private let screen = HUDScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875)
    )
    private let folder = URL(filePath: "/tmp/shots", directoryHint: .isDirectory)

    private func items(_ count: Int) -> [ScreenshotItem] {
        (0..<count).map { ScreenshotItem(url: folder.appending(path: "Screenshot \($0).png"), date: Date(timeIntervalSince1970: Double(1000 - $0))) }
    }

    private func tray(_ listing: ScreenshotListing) -> (HUDScreenshotTrayController, Box) {
        let box = Box()
        let tray = HUDScreenshotTrayController()
        tray.findScreenshots = { _ in listing }
        tray.writeToPasteboard = { box.written.append($0); return true }
        tray.openURL = { box.opened.append($0) }
        tray.revealInFinder = { box.revealed.append($0) }
        tray.moveToTrash = { box.trashed.append($0) }
        tray.onCopied = { box.copied.append($0) }
        return (tray, box)
    }

    final class Box {
        var written: [ScreenshotItem] = []
        var opened: [URL] = []
        var copied: [ScreenshotItem] = []
        var revealed: [URL] = []
        var trashed: [URL] = []
    }

    @Test func showsTheNewestScreenshotsAndCopiesTheClickedOne() async {
        let shots = items(3)
        let (tray, box) = tray(.found(shots, folder: folder))
        tray.show(centeredAt: CGPoint(x: 700, y: 400), on: screen)
        await tray.waitForListing()
        #expect(tray.isVisible)
        #expect(tray.listing == .found(shots, folder: folder))
        tray.copy(shots[1])
        #expect(box.written == [shots[1]])
        #expect(box.copied == [shots[1]])
        // コピーしたら閉じる
        #expect(!tray.isVisible)
    }

    /// 開いた直後は「探しています」（探すのはメインスレッドの外）。探し終えたら並べる
    @Test func listsInTheBackground() async {
        let shots = items(2)
        let (tray, _) = tray(.found(shots, folder: folder))
        tray.show(centeredAt: CGPoint(x: 700, y: 400), on: screen)
        #expect(tray.listing == nil)
        #expect(tray.isVisible)
        await tray.waitForListing()
        #expect(tray.listing == .found(shots, folder: folder))
        tray.close()
    }

    /// 右クリックや ⌘⌫ で、デスクトップを片付けられる（ゴミ箱に入れてもトレイは開いたまま）
    @Test func trashingRemovesTheItemAndKeepsTheTrayOpen() async {
        let shots = items(3)
        let (tray, box) = tray(.found(shots, folder: folder))
        tray.show(centeredAt: CGPoint(x: 700, y: 400), on: screen)
        await tray.waitForListing()
        tray.moveSelection(by: 2)
        await tray.trash(shots[2])
        #expect(box.trashed == [shots[2].url])
        #expect(tray.listing == .found(Array(shots.prefix(2)), folder: folder))
        #expect(tray.selection == 1)
        #expect(tray.isVisible)
        tray.reveal(shots[0])
        #expect(box.revealed == [shots[0].url])
        #expect(!tray.isVisible)
    }

    @Test func aFailedTrashLeavesTheItem() async {
        let shots = items(2)
        let (tray, _) = tray(.found(shots, folder: folder))
        struct Refused: Error {}
        tray.moveToTrash = { _ in throw Refused() }
        var failed: [ScreenshotItem] = []
        tray.onTrashFailed = { failed.append($0) }
        tray.show(centeredAt: CGPoint(x: 700, y: 400), on: screen)
        await tray.waitForListing()
        await tray.trash(shots[0])
        #expect(failed == [shots[0]])
        #expect(tray.listing == .found(shots, folder: folder))
        tray.close()
    }

    @Test func theArrowKeysChooseAndReturnCopies() async {
        let shots = items(3)
        let (tray, box) = tray(.found(shots, folder: folder))
        tray.show(centeredAt: CGPoint(x: 700, y: 400), on: screen)
        await tray.waitForListing()
        #expect(tray.selection == 0)
        tray.moveSelection(by: -1)
        #expect(tray.selection == 0)
        tray.moveSelection(by: 1)
        tray.moveSelection(by: 5)
        #expect(tray.selection == 2)
        tray.copySelection()
        #expect(box.written == [shots[2]])
        // 開き直すと、いちばん新しいものから
        tray.show(centeredAt: CGPoint(x: 700, y: 400), on: screen)
        await tray.waitForListing()
        #expect(tray.selection == 0)
        tray.close()
    }

    @Test func aFailedCopyKeepsTheTrayOpen() async {
        let shots = items(1)
        let (tray, box) = tray(.found(shots, folder: folder))
        tray.writeToPasteboard = { _ in false }
        tray.show(centeredAt: CGPoint(x: 700, y: 400), on: screen)
        await tray.waitForListing()
        tray.copy(shots[0])
        #expect(box.copied.isEmpty)
        #expect(tray.isVisible)
        tray.close()
    }

    @Test func emptyOrUnreadableFoldersSayWhatToDo() async {
        #expect(HUDScreenshotTrayController.announcement(for: .found([], folder: folder)) == L10n.ui("スクリーンショットはまだありません"))
        #expect(HUDScreenshotTrayController.announcement(for: .notPermitted(folder: folder)) == L10n.ui("スクリーンショットの保存先を読めません"))
        #expect(HUDScreenshotTrayController.announcement(for: .missingFolder(folder)) == L10n.ui("スクリーンショットの保存先が見つかりません"))
        let (tray, _) = tray(.found([], folder: folder))
        tray.show(centeredAt: CGPoint(x: 700, y: 400), on: screen)
        await tray.waitForListing()
        #expect(tray.isVisible)
        // 何も無くてもコピーしない
        tray.copySelection()
        #expect(tray.isVisible)
        tray.close()
    }

    /// 12枚は 6 × 2 段。↑ ↓ で段を移る
    @Test func manyItemsWrapIntoRows() async {
        #expect(HUDScreenshotTrayLayout.columns(count: 12) == 6)
        #expect(HUDScreenshotTrayLayout.rows(count: 12) == 2)
        #expect(HUDScreenshotTrayLayout.columns(count: 8) == 4)
        #expect(HUDScreenshotTrayLayout.rows(count: 8) == 2)
        #expect(HUDScreenshotTrayLayout.rows(count: 5) == 1)
        #expect(HUDScreenshotTrayLayout.panelSize(count: 12).height > HUDScreenshotTrayLayout.panelSize(count: 5).height)
        let shots = items(12)
        let (tray, _) = tray(.found(shots, folder: folder))
        tray.show(ScreenshotTrayAction(count: 12), centeredAt: CGPoint(x: 700, y: 400), on: screen)
        await tray.waitForListing()
        tray.moveSelection(by: 6)
        #expect(tray.selection == 6)
        tray.close()
    }

    /// 収録（動画）は「収録・」を付け、ファイルとしてコピーする
    @Test func recordingsAreMarkedAndCopiedAsFiles() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let video = ScreenshotItem(url: folder.appending(path: "画面収録.mov"), date: now.addingTimeInterval(-10))
        #expect(video.isVideo)
        #expect(HUDScreenshotTrayView.label(of: video, now: now) == L10n.ui("収録・\(L10n.ui("たった今"))"))
        let dir = FileManager.default.temporaryDirectory.appending(path: "ShellScreenshotTrayTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "Screen Recording.mov")
        try Data([0, 0, 0, 0]).write(to: url)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ShellScreenshotTrayTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        #expect(HUDScreenshotTrayController.write(ScreenshotItem(url: url, date: now), to: pasteboard))
        #expect(pasteboard.pasteboardItems?.first?.types == [.fileURL])
    }

    @Test func theTrayFitsItsThumbnails() async {
        let three = HUDScreenshotTrayLayout.panelSize(count: 3)
        let five = HUDScreenshotTrayLayout.panelSize(count: 5)
        #expect(five.width > three.width)
        // 無い・1枚でも、案内が入る幅は取る
        #expect(HUDScreenshotTrayLayout.panelSize(count: 0).width == three.width)
        #expect(HUDScreenshotTrayLayout.panelSize(count: 0).height < three.height)
    }

    @Test func agesAndFolderNamesAreShort() async {
        let now = Date(timeIntervalSince1970: 10_000)
        #expect(HUDScreenshotTrayView.age(of: now.addingTimeInterval(-20), now: now) == L10n.ui("たった今"))
        #expect(!HUDScreenshotTrayView.age(of: now.addingTimeInterval(-180), now: now).isEmpty)
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(HUDScreenshotTrayView.folderName(home.appending(path: "Desktop", directoryHint: .isDirectory)) == "~/Desktop")
        #expect(HUDScreenshotTrayView.folderName(URL(filePath: "/Volumes/Work/Shots/", directoryHint: .isDirectory)) == "/Volumes/Work/Shots")
    }

    /// 画像（PNG）とファイルの場所を1つの項目として書く（入力欄には画像、Finder にはファイルとして貼り付く）
    @Test func copyingWritesTheImageAndTheFile() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "ShellScreenshotTrayTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "Screenshot.png")
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.systemBlue.setFill()
            rect.fill()
            return true
        }
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: url)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ShellScreenshotTrayTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        #expect(HUDScreenshotTrayController.write(ScreenshotItem(url: url, date: Date()), to: pasteboard))
        let types = pasteboard.pasteboardItems?.first?.types ?? []
        #expect(types.contains(.png))
        #expect(types.contains(.fileURL))
        #expect(pasteboard.data(forType: .png) == png)
        // 読めないファイルは書かない
        #expect(!HUDScreenshotTrayController.write(ScreenshotItem(url: dir.appending(path: "missing.jpg"), date: Date()), to: pasteboard))
    }
}
