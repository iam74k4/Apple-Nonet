// 担当: ui-shell
import NonetCore

/// メニューバーと初回起動で使う文言。
/// 呼び方: 9つのアイコンの一覧は、画面で最初に出すときだけ「9つのアイコン（HUD）」、後は「HUD」。
/// 1つのセルは「マス」（「9つのボタン」はようこそと情報の一行だけ）。アイコンの輪の外側は「輪の外」（1つの文の中で「外枠」と混ぜない）。
/// 開き方は「上の縁から指を（下へ）滑らせる」（トラックパッドでは「押す」「長押し」と言わない。押すとクリックになる）
enum ShellText {
    /// ようこその説明。設定の「Nonet」のタブの情報（SettingsAboutView）も同じ一行を使う
    static var tagline: String {
        String(localized: "トラックパッドの上の縁から指を滑らせると、アプリごとに変わる9つのボタンが開きます", bundle: .module)
    }

    // MARK: - 練習

    /// 1つ目の課題: 開いて、目標のマスで離す（例: 「…「Safari」まで滑らせて、そこで指を離してください。」）。
    /// アイコンだけの HUD なので、向けたまま止めると名前が出ることも添える。少し長く止めてから実行するマスばかりのページでは、そのマスの止め方も
    /// 文をつなげずに、組み合わせごとに1つの文言にする（つなげると、英語で文と文の間の空白が抜ける）
    static func practiceRunInstruction(_ target: OnboardingPracticeTarget) -> String {
        guard target.requiresHold else {
            return String(localized: "トラックパッドの上の縁に指を置き、そのまま下へ滑らせると、ポインタの周りに9つのアイコン（HUD）が開きます。そのまま指を滑らせてポインタを「\(target.title)」の上へ動かし、そこで離してください。アイコンの意味に迷ったら、向けたまま少し止めると名前が出ます。", bundle: .module)
        }
        return String(localized: "トラックパッドの上の縁に指を置き、そのまま下へ滑らせると、ポインタの周りに9つのアイコン（HUD）が開きます。そのまま指を滑らせてポインタを「\(target.title)」の上へ動かし、そこで離してください。アイコンの意味に迷ったら、向けたまま少し止めると名前が出ます。このマスは、縁が一周するまで少し止めてから離してください。", bundle: .module)
    }

    /// 1つ目の課題の下に出す、開かないときの手がかり
    static var practiceOpenHint: String {
        String(localized: "うまく開かないときは、トラックパッドのいちばん奥の端に指を1本だけ置いて、すぐ下へ滑らせてください。2本指や手のひらでは開きません。", bundle: .module)
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
        String(localized: "もう一度上の縁から HUD を開き、今度はポインタをアイコンの輪の外まで動かしてから離してください。何も実行せずに閉じます。", bundle: .module)
    }

    /// 1つ目の課題ができた
    static var practiceRunDone: String {
        String(localized: "できました。アイコンで指を離すと実行します。", bundle: .module)
    }

    /// 2つの課題ができた後の一言: 練習では試さない、ページの移り方（下で止めるとどのアプリでも下のページ）。
    /// belowPage は下のページの題名。下のページが無ければ、右か左のことだけ言う
    static func practicePagesTip(belowPage: String?) -> String {
        guard let belowPage else {
            return String(localized: "輪のすぐ外の右か左で少し止めると、ページが変わります。", bundle: .module)
        }
        return String(localized: "次は、輪のすぐ外の下で少し止めてみてください。どのアプリの前でも「\(belowPage)」が開きます。右か左で止めるとページが変わります。", bundle: .module)
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
