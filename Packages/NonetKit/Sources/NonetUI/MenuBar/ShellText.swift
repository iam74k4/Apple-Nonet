// 担当: ui-shell
import NonetCore

/// メニューバーと初回起動で使う文言。
/// 呼び方: 9マスの一覧は、画面で最初に出すときだけ「HUD（9マスの一覧）」、後は「HUD」。
/// 9つのセルは「マス」（「9つのボタン」はようこその一行だけ）。9マスの外側の枠は「外枠」。
/// 開き方は「上の縁から指を（下へ）滑らせる」（トラックパッドでは「押す」「長押し」と言わない。押すとクリックになる）
enum ShellText {
    /// ようこその説明
    static var welcomeSubtitle: String {
        String(localized: "トラックパッドの上の縁から指を滑らせると、トラックパッドがアプリごとに変わる9つのボタンになります", bundle: .module)
    }

    // MARK: - 練習

    /// 1つ目の課題: 開いて、目標のマスで離す（例: 「…「Safari」まで滑らせて、そこで指を離してください。」）。
    /// 少し長く止めてから実行するマスばかりのページでは、そのマスの止め方も添える
    static func practiceRunInstruction(_ target: OnboardingPracticeTarget) -> String {
        let base = String(localized: "トラックパッドの上の縁に指を置き、そのまま下へ滑らせると、ポインタの周りに HUD（9つのアイコン）が開きます。そのまま指を滑らせてポインタを「\(target.title)」の上へ動かし、そこで離してください。", bundle: .module)
        guard target.requiresHold else { return base }
        return base + String(localized: "このマスは、縁が一周するまで少し止めてから離してください。", bundle: .module)
    }

    /// 1つ目の課題の下に出す、開かないときの手がかり
    static var practiceOpenHint: String {
        String(localized: "うまく開かないときは、トラックパッドのいちばん奥の端に指を1本だけ置いて、すぐ下へ滑らせてください。2本指や手のひらでは開きません。", bundle: .module)
    }

    /// 開いて離したが、何も実行されなかった（reason 別に、どうすればよいかを知らせる）。
    /// whileCancelling は、やめる課題の途中（外枠で離す以外は、やめたことにならない）
    static func practiceNotRun(_ reason: SessionCancellation, target: OnboardingPracticeTarget?, whileCancelling: Bool) -> String {
        if whileCancelling {
            return String(localized: "まだ外枠で離していません。ポインタをアイコンの輪の外まで動かしてから離してください。", bundle: .module)
        }
        let title = target?.title ?? ""
        switch reason {
        case .liftedInFrame:
            return String(localized: "アイコンの輪の外で離すと、何も実行せずに閉じます。「\(title)」まで動かしてから離してください。", bundle: .module)
        case .liftedOnBoundary:
            return String(localized: "マスの境目の線の上で離すと、実行しません。マスの真ん中で離してください。", bundle: .module)
        case .liftedTooSoon:
            return String(localized: "通りかかっただけのマスは実行しません。マスで少し止めてから離してください。", bundle: .module)
        case .liftedOnEmptyCell:
            return String(localized: "空きマスでは何も起きません。「\(title)」まで滑らせてから離してください。", bundle: .module)
        case .liftedWithSeveralFingers, .liftedWithoutSliding:
            return String(localized: "指を1本にして、マスまで滑らせてから離してください。何も実行しませんでした。", bundle: .module)
        }
    }

    /// 2つ目の課題: 外枠（アイコンの輪の外）で離してやめる
    static var practiceCancelInstruction: String {
        String(localized: "もう一度上の縁から HUD を開き、今度はポインタをアイコンの輪の外まで動かしてから離してください。何も実行せずに閉じます。", bundle: .module)
    }

    /// 1つ目の課題ができた
    static var practiceRunDone: String {
        String(localized: "できました。マスで指を離すと実行します。", bundle: .module)
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
