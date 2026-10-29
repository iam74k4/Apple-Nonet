// 担当: presets
// グローバル（ランチャー）に並べるアプリの候補
import Foundation

/// ランチャーの候補。title はマスに出す名前で、長い製品名だけ短くする
struct LauncherEntry: Sendable {
    var app: AppReference
    var title: String

    init(_ app: AppReference, title: String? = nil) {
        self.app = app
        self.title = title ?? app.name
    }
}

extension PresetData {
    /// 優先順。上から9個ずつ、最大3ページに並べる。
    /// Arc は 2026年12月22日に動かなくなるので入れず、後継の Dia を入れる
    /// （https://resources.arc.net/hc/en-us/articles/44412972248471-Arc-Sunset-Key-Dates-and-What-to-Expect ）
    static var launcherEntries: [LauncherEntry] {
        [
            LauncherEntry(KnownApp.mail),
            LauncherEntry(KnownApp.calendar),
            LauncherEntry(KnownApp.notes),
            LauncherEntry(KnownApp.safari),
            LauncherEntry(KnownApp.chrome, title: "Chrome"),
            LauncherEntry(KnownApp.claude),
            LauncherEntry(KnownApp.chatGPT),
            LauncherEntry(KnownApp.slack),
            LauncherEntry(KnownApp.notion),
            LauncherEntry(KnownApp.figma),
            LauncherEntry(KnownApp.terminal),
            LauncherEntry(KnownApp.finder),
            LauncherEntry(KnownApp.messages),
            LauncherEntry(KnownApp.music),
            LauncherEntry(KnownApp.xcode),
            LauncherEntry(KnownApp.vsCode, title: "VS Code"),
            LauncherEntry(KnownApp.cursor),
            LauncherEntry(KnownApp.zoom),
            LauncherEntry(KnownApp.teams, title: "Teams"),
            LauncherEntry(KnownApp.reminders),
            LauncherEntry(KnownApp.photos),
            LauncherEntry(KnownApp.systemSettings),
            LauncherEntry(KnownApp.spotify),
            LauncherEntry(KnownApp.line),
            LauncherEntry(KnownApp.discord),
            LauncherEntry(KnownApp.obsidian),
            LauncherEntry(KnownApp.dia),
            LauncherEntry(KnownApp.outlook, title: "Outlook"),
            LauncherEntry(KnownApp.word, title: "Word"),
            LauncherEntry(KnownApp.excel, title: "Excel"),
            LauncherEntry(KnownApp.powerPoint, title: "PowerPoint"),
            LauncherEntry(KnownApp.edge, title: "Edge"),
            LauncherEntry(KnownApp.firefox),
            LauncherEntry(KnownApp.maps),
            LauncherEntry(KnownApp.preview),
            LauncherEntry(KnownApp.faceTime),
            LauncherEntry(KnownApp.appStore),
        ]
    }
}
