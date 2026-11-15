// 担当: core-model（ファイルのアクションの書式と決まり）
import Foundation
import Testing
@testable import NonetCore

/// Finder で選んでいるファイルへの操作
@Suite struct ActionFileCodingTests {
    @Test(arguments: FileOperation.allCases)
    func everyOperationRoundTrips(operation: FileOperation) throws {
        let action = Action.file(FileAction(operation: operation))
        #expect(try ModelFixtures.roundTrip(action) == action)
        #expect(action.kind == .file)
        #expect(action.summary == operation.title)
    }

    @Test func theFormatIsJustTheOperation() throws {
        #expect(try ModelFixtures.jsonObject(Action.file(FileAction(operation: .trash))) == ModelFixtures.jsonObject(#"{"type":"file","operation":"trash"}"#))
    }

    /// 知らない操作（前に試した open・move も）を、別の操作として読まない。読めなければ、そのマスは空きになる
    @Test(arguments: [#"{"type":"file","operation":"delete"}"#, #"{"type":"file","operation":"open"}"#, #"{"type":"file","operation":"move","destination":"~"}"#, #"{"type":"file"}"#, #"{"type":"file","operation":null}"#])
    func anUnknownOperationIsNotReadAsAnother(json: String) {
        #expect(throws: DecodingError.self) { try ModelFixtures.decode(Action.self, json) }
    }

    @Test func anUnreadableFileCellBecomesAnEmptyCell() throws {
        let json = #"{"cells":[{"title":"消す","icon":{"type":"symbol","name":"trash"},"action":{"type":"file","operation":"erase"}}, null, null, null, null, null, null, null, null]}"#
        let page = try ModelFixtures.decode(Page.self, json)
        #expect(page.cells.allSatisfy { $0 == nil })
    }

    @Test func fileActionsDoNotSendInputAndDependOnTheFrontApp() {
        let action = Action.file(FileAction(operation: .trash))
        #expect(!ControllerExecutionPolicy.sendsInputToFrontmostApp(action))
        #expect(!ControllerExecutionPolicy.isLongRunning(action))
        #expect(ControllerExecutionPolicy.isLongRunning(.file(FileAction(operation: .duplicate))))
        // Finder が前面かどうかで動きが変わる（テスト実行で前のアプリを前面に戻す）
        #expect(ControllerExecutionPolicy.dependsOnFrontmostApp(action))
    }
}
