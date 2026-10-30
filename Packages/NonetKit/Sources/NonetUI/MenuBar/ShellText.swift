// 担当: ui-shell
import NonetCore

/// メニューバーと初回起動で使う文言。
/// 呼び方: 9マスの一覧は、画面で最初に出すときだけ「HUD（9マスの一覧）」、後は「HUD」。
/// 速押しは「すぐにタップ」。ふだんの名詞は「ボタン」、位置が大事なときは「マス」
enum ShellText {
    /// 「右⌘」など。利用ガイドの呼び方に合わせる
    static func triggerName(_ trigger: TriggerKey) -> String {
        switch trigger {
        case .rightCommand: String(localized: "右⌘", bundle: .module)
        case .rightOption: String(localized: "右⌥", bundle: .module)
        case .rightShift: String(localized: "右⇧", bundle: .module)
        case .function: String(localized: "fn", bundle: .module)
        }
    }

    /// ようこその説明。実際のトリガーキーで言う（例: 「右⌘キーを押している間だけ、…」）
    static func welcomeSubtitle(_ trigger: TriggerKey) -> String {
        String(localized: "\(triggerName(trigger))キーを押している間だけ、トラックパッドがアプリごとに変わる9つのボタンになります", bundle: .module)
    }

    // MARK: - 練習

    /// 1つ目の課題: HUD から選ぶ。実行のタイミングの設定で、最後にすることが変わる
    static func practiceHUDInstruction(trigger: TriggerKey, fireMode: FireMode, target: OnboardingPracticeTarget) -> String {
        let key = triggerName(trigger)
        switch fireMode {
        case .onTriggerRelease:
            return String(localized: "\(key)を押したまま、トラックパッドに指を置いて止めます。HUD が出たら、指を滑らせて「\(target.title)」に合わせ、\(key)を離してください", bundle: .module)
        case .onFingerLift:
            return String(localized: "\(key)を押したまま、トラックパッドに指を置いて止めます。HUD が出たら、指を滑らせて「\(target.title)」に合わせ、指を離してください", bundle: .module)
        }
    }

    /// 2つ目の課題: すぐにタップ（例: 「右⌘を押して、右上の「Safari」をすぐにタップしてください」）
    static func practiceQuickTapInstruction(trigger: TriggerKey, target: OnboardingPracticeTarget) -> String {
        String(localized: "\(triggerName(trigger))を押して、\(HUDAnnouncement.positionName(target.index))の「\(target.title)」をすぐにタップしてください", bundle: .module)
    }

    /// 1つ目の課題ができた
    static var practiceHUDDone: String {
        String(localized: "できました。迷ったときはこのやり方で", bundle: .module)
    }

    /// 2つ目の課題ができた（例: 「…右上のマスは「Safari」です。…」）
    static func practiceQuickTapDone(_ target: OnboardingPracticeTarget) -> String {
        String(localized: "すぐにタップできました。\(HUDAnnouncement.attributivePositionName(target.index))のマスは「\(target.title)」です。慣れたら、これがいちばん速い使い方です", bundle: .module)
    }

    /// 違うマスを押した（例: 「いまのは左下の「Finder」です。「Safari」は右上にあります」）
    static func practiceWrongCell(index: Int, title: String, target: OnboardingPracticeTarget) -> String {
        String(localized: "いまのは\(HUDAnnouncement.positionName(index))の「\(title)」です。「\(target.title)」は\(HUDAnnouncement.positionName(target.index))にあります", bundle: .module)
    }

    /// HUD の課題で、HUD が出る前に実行された
    static var practiceTooQuick: String {
        String(localized: "HUD が出る前に実行されました。今度は指を置いたまま、HUD が出るまで止めてください", bundle: .module)
    }

    /// すぐにタップの課題で、HUD から実行した
    static var practiceUsedHUD: String {
        String(localized: "HUD から実行しました。今度は指を止めずに、すぐにタップしてください", bundle: .module)
    }

    /// トラックパッドの図の読み上げ（目標のマス）
    static func practiceFigureLabel(_ target: OnboardingPracticeTarget) -> String {
        String(localized: "トラックパッドの図。目標は\(HUDAnnouncement.positionName(target.index))の「\(target.title)」です", bundle: .module)
    }

    // MARK: - 角の長押し

    /// 角の呼び方（名詞の前に置く。英語は top-left）
    static func cornerName(_ corner: TouchActivation) -> String {
        HUDAnnouncement.attributivePositionName(corner == .topLeft ? 0 : 2)
    }

    /// 選んだ角で試してもらう
    static func cornerTrialInstruction(_ corner: TouchActivation) -> String {
        String(localized: "\(cornerName(corner))の角に指を1本置いて、そのまま少し待ちます。HUD が出たら、指を滑らせて選び、離すと実行します", bundle: .module)
    }

    static var cornerTrialDone: String {
        String(localized: "できました。キーを使わずに HUD を出せました。設定 › 一般 でいつでも変えられます", bundle: .module)
    }

    // MARK: - 完了

    /// こつ「迷ったら、指を止める」。実行のタイミングの設定で、実行のしかたが変わる
    static func doneHUDTip(_ fireMode: FireMode) -> String {
        switch fireMode {
        case .onTriggerRelease:
            String(localized: "キーを押したまま指を置いて止めると、HUD（9マスの一覧）が出ます。指を滑らせて選び、指を置いたままキーを離すと実行します。慣れたら、すぐにタップするだけで実行できます。", bundle: .module)
        case .onFingerLift:
            String(localized: "キーを押したまま指を置いて止めると、HUD（9マスの一覧）が出ます。指を滑らせて選び、指を離すと実行します。慣れたら、すぐにタップするだけで実行できます。", bundle: .module)
        }
    }

    /// こつ「ボタンを変える」。menuTitle はメニューの項目（「Xcode のボタンを編集…」など）
    static func doneEditTip(_ menuTitle: String) -> String {
        String(localized: "メニューバーの 3×3 のアイコン ›「\(menuTitle)」で、いま使っているアプリのボタンを変えられます", bundle: .module)
    }

    /// こつ「片手で使うときは、角を長押し」
    static func doneCornerTip(_ activation: TouchActivation) -> String {
        switch activation {
        case .off:
            String(localized: "設定 › 一般 の「トラックパッドだけで呼び出す」をオンにすると、トラックパッドの角を押したまま少し待つだけで HUD が出ます", bundle: .module)
        case .topLeft, .topRight:
            String(localized: "トラックパッドの\(cornerName(activation))の角を押したまま少し待つと、HUD が出ます。設定 › 一般 で変えられます", bundle: .module)
        }
    }

    /// 試用期間の残り。数で文が変わる（1 day / 2 days）
    static func trialNote(daysLeft: Int) -> String {
        String(localized: "試用期間はあと\(daysLeft)日です。購入はメニューバーからいつでもできます", bundle: .module, locale: .nonetUI)
    }

    // MARK: - そのほか

    /// 案内をもう一度見るときに足すアプリの数。数で文が変わる（1 app profile / 2 app profiles）
    static func additionNote(_ count: Int) -> String {
        String(localized: "\(count)個のアプリのプロファイルを追加します", bundle: .module, locale: .nonetUI)
    }
}
