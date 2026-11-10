// 担当: ui-shell
import AppKit

/// Nonet の画面（結果のパネル・設定）がクリップボードに書いたことを、アクションの ⌘C の見張りに伝える口。
/// NonetUI は NonetPlatform を知らないので、App が起動のときに NonetClipboard.noteWriteByNonet を入れる。
/// 伝えないと、AI やスクリプトの ⌘C の結果を待っている間（と、その後の見張りの間）に結果のパネルの「コピー」を押すと、
/// 遅れて届いた ⌘C の結果と取り違えて、元のクリップボードに戻してしまう（パネルは Nonet を前面にしない）
@MainActor
public enum ShellClipboard {
    public static var didWrite: () -> Void = {}
}
