// 担当: ui-shell
import NonetCore

/// メニューバーと初回起動で使う文言。
/// 呼び方: 9つのアイコンの一覧は、画面で最初に出すときだけ「9つのアイコン（HUD）」、後は「HUD」。
/// 1つのセルは「マス」（「9つのボタン」はようこそと情報の一行だけ）。アイコンの輪の外側は「輪の外」（1つの文の中で「外枠」と混ぜない）。
/// 開き方は「強く押し込んで（少し）止める」（ただの「押す」「長押し」は、ふつうのクリックと区別できないので使わない）。
/// 強く押し込んだ手応えは macOS の強めのクリックの「2回目のカチッ」
enum ShellText {
    /// ようこその説明。設定の「Nonet」のタブの情報（SettingsAboutView）も同じ一行を使う
    static var tagline: String {
        String(localized: "トラックパッドのどこかを強く押し込んで少し止めると、アプリごとに変わる9つのボタンが開きます", bundle: .module)
    }

    // MARK: - 練習

    /// 1つ目の課題: 開いて、目標のマスで離す（例: 「…「Safari」まで滑らせて、そこで指を離してください。」）。
    /// アイコンだけの HUD なので、向けたまま止めると名前が出ることも添える。少し長く止めてから実行するマスばかりのページでは、そのマスの止め方も
    /// 文をつなげずに、組み合わせごとに1つの文言にする（つなげると、英語で文と文の間の空白が抜ける）
    static func practiceRunInstruction(_ target: OnboardingPracticeTarget) -> String {
        guard target.requiresHold else {
            return String(localized: "トラックパッドのどこかに指を1本置いて強く押し込み（2回目のカチッまで）、そのまま少し止めると、ポインタの周りに9つのアイコン（HUD）が開きます。力を抜いて指を置いたまま滑らせ、ポインタを「\(target.title)」の上へ動かして、そこで離してください。アイコンの意味に迷ったら、向けたまま少し止めると名前が出ます。", bundle: .module)
        }
        return String(localized: "トラックパッドのどこかに指を1本置いて強く押し込み（2回目のカチッまで）、そのまま少し止めると、ポインタの周りに9つのアイコン（HUD）が開きます。力を抜いて指を置いたまま滑らせ、ポインタを「\(target.title)」の上へ動かして、そこで離してください。アイコンの意味に迷ったら、向けたまま少し止めると名前が出ます。このマスは、縁が一周するまで少し止めてから離してください。", bundle: .module)
    }

    /// 1つ目の課題の下に出す、開かないときの手がかり
    static var practiceOpenHint: String {
        String(localized: "うまく開かないときは、指を1本だけ置いて、2回目のカチッと感じるまで強く押し込み、そのまま少し止めてください。システム設定 › トラックパッド の「強めのクリックと触覚フィードバック」がオフだと開きません。", bundle: .module)
    }

    /// 開いて離したが、何も実行されなかった（reason 別に、どうすればよいかを知らせる）。
    /// whileCancelling は、やめる課題の途中（輪の外で離す以外は、やめたことにならない）
    static func practiceNotRun(_ reason: SessionCancellation, target: OnboardingPracticeTarget?, whileCancelling: Bool) -> String {
        if whileCancelling {
            return String(localized: "まだ輪の外で離していません。ポインタをアイコンの輪の外まで動かしてから離してください。", bundle: .module)
        }
        let title = target?.title ?? ""
        switch reason {
        case .liftedInFrame:
            return String(localized: "アイコンの輪の外で離すと、何も実行せずに閉じます。「\(title)」まで動かしてから離してください。", bundle: .module)
        case .liftedOnBoundary:
            return String(localized: "どのアイコンを狙ったか分からない場所で離したので、実行しませんでした。ポインタをアイコンに重ねてから離してください。", bundle: .module)
        case .liftedTooSoon:
            return String(localized: "通りかかっただけのマスは実行しません。マスで少し止めてから離してください。", bundle: .module)
        case .liftedOnEmptyCell:
            return String(localized: "空きマスでは何も起きません。「\(title)」まで滑らせてから離してください。", bundle: .module)
        case .liftedWithSeveralFingers, .liftedWithoutSliding:
            return String(localized: "指を1本にして、マスまで滑らせてから離してください。何も実行しませんでした。", bundle: .module)
        }
    }

    /// 2つ目の課題: アイコンの輪の外で離してやめる
    static var practiceCancelInstruction: String {
        String(localized: "もう一度強く押し込んで HUD を開き、今度はポインタをアイコンの輪の外まで動かしてから離してください。何も実行せずに閉じます。", bundle: .module)
    }

    /// 1つ目の課題ができた
    static var practiceRunDone: String {
        String(localized: "できました。アイコンで指を離すと実行します。", bundle: .module)
    }

    /// 2つ目の課題ができた
    static var practiceCancelDone: String {
        String(localized: "できました。迷ったらアイコンの輪の外で離せば、何も実行しません。", bundle: .module)
    }

    /// 違うマスを実行した（例: 「いまのは左下の「Finder」です。「Safari」は右上にあります」）
    static func practiceWrongCell(index: Int, title: String, target: OnboardingPracticeTarget) -> String {
        String(localized: "いまのは\(HUDAnnouncement.positionName(index))の「\(title)」です。「\(target.title)」は\(HUDAnnouncement.positionName(target.index))にあります。", bundle: .module)
    }

    /// やめる課題で、マスを実行した
    static func practiceRanInsteadOfCancelling(_ title: String) -> String {
        String(localized: "「\(title)」で離しました。やめるときは、ポインタをアイコンの輪の外まで動かしてから離してください。", bundle: .module)
    }

    /// HUD の図の読み上げ（目標のマス）
    static func practiceFigureLabel(_ target: OnboardingPracticeTarget) -> String {
        String(localized: "HUD の図。目標は\(HUDAnnouncement.positionName(target.index))の「\(target.title)」です。", bundle: .module)
    }

    /// HUD の図の読み上げ（やめる課題。輪の外が目標）
    static var practiceFigureCancelLabel: String {
        String(localized: "HUD の図。目標はアイコンの輪の外です。", bundle: .module)
    }
}
