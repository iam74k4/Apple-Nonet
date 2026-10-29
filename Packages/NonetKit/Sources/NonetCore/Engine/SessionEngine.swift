// 担当: engine
// トリガーを押してから離すまで（セッション）の状態遷移。時間とタッチを入力として受け、
// HUD・触覚・実行などの出力を返す純粋なロジックにする（docs/architecture.md の「操作の仕様」）。
// 公開 API は engine 担当が決めてよい（NonetController だけが使う）。
import Foundation
