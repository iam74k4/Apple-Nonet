// 担当: keys-license（公開 API は契約）
import Foundation

/// スクリプトや AI アクションに渡す、実行時の前面アプリの情報
public struct ScriptContextInfo: Equatable, Sendable {
    public var app: AppReference?
    /// 前面ウィンドウの書類（Xcode なら .xcodeproj / .xcworkspace）
    public var documentPath: String?
    /// ブラウザで表示中のページ
    public var browserURL: String?
    public var selectedText: String?

    public init(app: AppReference? = nil, documentPath: String? = nil, browserURL: String? = nil, selectedText: String? = nil) {
        self.app = app
        self.documentPath = documentPath
        self.browserURL = browserURL
        self.selectedText = selectedText
    }
}

public enum ScriptEnvironment {
    /// スクリプトに渡す環境変数。値の無いものは含めない。
    /// NONET_APP_BUNDLE_ID, NONET_APP_NAME, NONET_DOCUMENT_PATH, NONET_PROJECT_DIR, NONET_BROWSER_URL, NONET_SELECTED_TEXT,
    /// それと PROJECT_DIR（NONET_PROJECT_DIR と同じ。モックの `cd $PROJECT_DIR` 用）
    public static func variables(for info: ScriptContextInfo, projectDirectory: String?) -> [String: String] {
        fatalError("未実装: keys-license")
    }

    /// 書類の場所からプロジェクトのフォルダを決める。
    /// .xcodeproj / .xcworkspace / .swiftpm はその親、ファイルは上にたどって .git か Package.swift のあるフォルダ、見つからなければファイルのあるフォルダ
    public static func projectDirectory(forDocumentPath path: String, fileExists: (String) -> Bool) -> String {
        fatalError("未実装: keys-license")
    }
}
