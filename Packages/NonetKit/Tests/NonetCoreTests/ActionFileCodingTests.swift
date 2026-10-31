// 担当: core-model（ファイルのアクションの書式と決まり）
import Foundation
import Testing
@testable import NonetCore

/// Finder で選んでいるファイルへの操作。移す先は、移すときだけ書く
@Suite struct ActionFileCodingTests {
    @Test(arguments: FileOperation.allCases)
    func everyOperationRoundTrips(operation: FileOperation) throws {
        let action = Action.file(FileAction(operation: operation, destination: operation == .move ? "~/Documents" : ""))
        #expect(try ModelFixtures.roundTrip(action) == action)
        #expect(action.kind == .file)
    }

    @Test func destinationIsWrittenOnlyForMove() throws {
        // 移さない操作に残っていた移す先は、書き出さない
        let trash = Action.file(FileAction(operation: .trash, destination: "/stale"))
        #expect(try ModelFixtures.jsonObject(trash) == ModelFixtures.jsonObject(#"{"type":"file","operation":"trash"}"#))
        let move = Action.file(FileAction(operation: .move))
        #expect(try ModelFixtures.jsonObject(move) == ModelFixtures.jsonObject(#"{"type":"file","operation":"move","destination":""}"#))
    }

    @Test func aMissingOrBrokenDestinationReadsAsEmpty() throws {
        for json in [#"{"type":"file","operation":"move"}"#, #"{"type":"file","operation":"move","destination":3}"#, #"{"type":"file","operation":"move","destination":null}"#] {
            #expect(try ModelFixtures.decode(Action.self, json) == .file(FileAction(operation: .move)), "\(json)")
        }
    }

    /// 知らない操作を、別の操作（ゴミ箱に入れる・移すなど）として読まない。読めなければ、そのマスは空きになる
    @Test(arguments: [#"{"type":"file","operation":"delete"}"#, #"{"type":"file"}"#, #"{"type":"file","operation":null}"#, #"{"type":"file","operation":7}"#])
    func anUnknownOperationIsNotReadAsAnother(json: String) {
        #expect(throws: DecodingError.self) { try ModelFixtures.decode(Action.self, json) }
    }

    @Test func anUnreadableFileCellBecomesAnEmptyCell() throws {
        let json = #"{"cells":[{"title":"消す","icon":{"type":"symbol","name":"trash"},"action":{"type":"file","operation":"erase"}}, null, null, null, null, null, null, null, null]}"#
        let page = try ModelFixtures.decode(Page.self, json)
        #expect(page.cells.allSatisfy { $0 == nil })
    }

    @Test func onlyOpeningLeavesTheFilesAlone() {
        #expect(FileOperation.allCases.filter { !$0.changesFiles } == [.open])
    }

    @Test func destinationNameIsTheLastFolder() {
        #expect(FileAction(operation: .move, destination: "/Users/me/Documents/整理/").destinationName == "整理")
        #expect(FileAction(operation: .move, destination: "~").destinationName == "~")
        #expect(FileAction(operation: .move, destination: "/").destinationName == "/")
        #expect(FileAction(operation: .move, destination: "  ").destinationName == nil)
    }

    @Test func fileActionsDoNotSendInputOrDependOnTheClipboard() {
        let action = Action.file(FileAction(operation: .trash))
        #expect(!ControllerExecutionPolicy.sendsInputToFrontmostApp(action))
        #expect(!ControllerExecutionPolicy.isLongRunning(action))
        // Finder が前面かどうかで動きが変わる（テスト実行で前のアプリを前面に戻す）
        #expect(ControllerExecutionPolicy.dependsOnFrontmostApp(action))
    }
}
