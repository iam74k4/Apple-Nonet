import CoreGraphics

enum TriggerKey: String, CaseIterable, Identifiable {
    case rightOption = "右 ⌥ Option"
    case rightCommand = "右 ⌘ Command"
    case rightShift = "右 ⇧ Shift"

    var id: Self { self }

    var keyCode: Int64 {
        switch self {
        case .rightOption: 61
        case .rightCommand: 54
        case .rightShift: 60
        }
    }

    /// NX_DEVICER*KEYMASK: 右側のキーが押されている
    var deviceMask: UInt64 {
        switch self {
        case .rightOption: 0x40
        case .rightCommand: 0x10
        case .rightShift: 0x04
        }
    }

    /// NX_DEVICEL*KEYMASK: 同じ修飾キーの左側が押されている
    var leftDeviceMask: UInt64 {
        switch self {
        case .rightOption: 0x20
        case .rightCommand: 0x08
        case .rightShift: 0x02
        }
    }

    var flag: CGEventFlags {
        switch self {
        case .rightOption: .maskAlternate
        case .rightCommand: .maskCommand
        case .rightShift: .maskShift
        }
    }

    var symbol: String {
        switch self {
        case .rightOption: "⌥"
        case .rightCommand: "⌘"
        case .rightShift: "⇧"
        }
    }
}

enum FireMode: String, CaseIterable, Identifiable {
    case onRelease = "キーを離したとき"
    case onTap = "マスから指を離したとき"

    var id: Self { self }
}

enum Suppression: String, CaseIterable, Identifiable {
    case none = "しない"
    case drop = "イベントを捨てる"
    case dropDecouple = "捨てる＋カーソル切り離し"
    case dropWarp = "捨てる＋カーソルを戻す"

    var id: Self { self }
}

enum HUDPosition: String, CaseIterable, Identifiable {
    case center = "画面中央"
    case cursor = "カーソルの近く"

    var id: Self { self }
}

enum Phase: String {
    case idle = "待機中"
    case armed = "トリガー押下中"
    case hud = "HUD 表示中"
}

struct SampleCell {
    let label: String
    let symbol: String
}

/// モックの Xcode プロファイルと同じ並び
let sampleCells = [
    SampleCell(label: "ビルド", symbol: "play.fill"),
    SampleCell(label: "テスト", symbol: "checkmark.circle"),
    SampleCell(label: "シミュレータ", symbol: "iphone"),
    SampleCell(label: "ターミナル", symbol: "terminal"),
    SampleCell(label: "Claude Code", symbol: "sparkles"),
    SampleCell(label: "Commit", symbol: "arrow.triangle.branch"),
    SampleCell(label: "Slack", symbol: "message"),
    SampleCell(label: "ミュート", symbol: "mic.slash"),
    SampleCell(label: "スクショ", symbol: "camera.viewfinder"),
]

enum SpikeTest: String, CaseIterable, Identifiable {
    case t1, t2, t3, t4, t5, t6, t7, t8, t9

    var id: Self { self }

    var title: String {
        switch self {
        case .t1: "T1 指の位置と範囲"
        case .t2: "T2 トリガーキー"
        case .t3: "T3 速押し"
        case .t4: "T4 迷ったときHUD"
        case .t5: "T5 カーソル・クリックの抑止"
        case .t6: "T6 境界の触覚"
        case .t7: "T7 2本指スワイプ"
        case .t8: "T8 他のキーとの同時押し"
        case .t9: "T9 トリガーキーを渡さない"
        }
    }

    /// key は「右⌘」のようなトリガーキーの呼び名
    func steps(key: String) -> String {
        switch self {
        case .t1:
            """
            1. まだ権限を許可していなければ、その状態でトラックパッドを触り、フレーム数が増えるか見る
            2. メモなど別のアプリをクリックして前面にする
            3. 1本指で四隅 → 各辺の中央 → 真ん中の順に触る
            4. 左の図の点とマスが指の位置と合っているか確かめる
            """
        case .t2:
            """
            1. 別のアプリを前面にする
            2. \(key)を押して離す → 状態が「トリガー押下中」→「待機中」に変わる
            3. 同じキーの左側を押して離す → 反応しないのが正しい
            """
        case .t3:
            """
            1. 別のアプリを前面にする
            2. \(key)を押しながら、すぐ（0.3秒以内）に右上をタップ
            3. HUD が出ずに「▶ シミュレータ」と出れば成功
            4. ほかのマスでも数回ためす。わざと少しゆっくりタップしても速押しになるか
            5. \(key)を押したまま、続けて別のマスをタップ → タップごとに実行される
            """
        case .t4:
            """
            1. 別のアプリを前面にする
            2. \(key)を押したまま指を置いて止める → HUD が出る
            3. 指を動かすとハイライトが追従するか
            4. キーを離すと実行される
            5. もう一度 HUD を出し、先に指を離してからキーを離す → キャンセルになるのが正しい
            """
        case .t5:
            """
            1. 右の「入力の抑止」を1つ選ぶ
            2. メモなど別のアプリを前面にする
            3. \(key)を押したまま、指を大きく動かす・クリックする・2本指でスクロールする
            4. カーソルが動かないか、前面アプリでクリックやスクロールが起きないか
            5. 抑止の方式を変えて繰り返す（ログに「カーソルのずれ」が残る）
            """
        case .t6:
            """
            1. 右下の「触覚テスト」→「全方式を順番に」で、まずこのアプリが前面のときに鳴るか確かめる
            2. 感じた番号をメモに書く
            3. 右の「触覚」で方式を選び、別のアプリを前面にする
            4. \(key)を押したまま HUD を出し、マスの境界をまたぐ
            5. 振動を感じたか、方式ごとにメモする
            """
        case .t7:
            """
            1. Safari で何ページか進んでおき、Safari を前面にする
            2. \(key)を押しながら、2本指で左右にスワイプ
            3. Safari が戻ったり進んだりしなければ成功
            4. ログに「2本指 ←」などが出るか
            5. 「入力の抑止」を「しない」にして比べる
            """
        case .t8:
            """
            1. テキスト入力欄で文字を選ぶ
            2. \(key)+C など、普段使う組み合わせを押す（右⌥なら右⌥+E など）
            3. いつもどおりに動けば成功。ログに「中断: 他のキー」が出る
            """
        case .t9:
            """
            1. 右の「トリガーキーを前面アプリに渡さない」を OFF / ON で比べる
            2. Figma など修飾キーの押しっぱなしに反応するアプリで違いを見る
            3. ⌘英かな や Karabiner-Elements など、\(key)の単押しを使うツールへの影響を見る
            """
        }
    }
}
