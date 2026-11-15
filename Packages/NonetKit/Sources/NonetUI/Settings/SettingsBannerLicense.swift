// 担当: ui-settings
// 設定のどのタブでも上に出す「試用期間が終了しました」の帯。購入とライセンスキーの入力へすぐ行けるようにする
import NonetCore
import SwiftUI

struct SettingsExpiredBanner: View {
    let model: SettingsModel

    var body: some View {
        if model.showsExpiredBanner {
            SettingsBanner(
                symbol: "exclamationmark.triangle",
                title: String(localized: "試用期間が終了しました", bundle: .module),
                message: String(localized: "設定はそのまま残っています。ライセンスキーを登録すると、すぐに元どおり使えます。", bundle: .module)
            ) {
                HStack(spacing: 8) {
                    if let purchase = model.links.purchase {
                        Button {
                            model.openURL(purchase)
                        } label: {
                            Text("購入する", bundle: .module)
                        }
                    }
                    Button {
                        model.showLicenseKeyEntry()
                    } label: {
                        Text("ライセンスキーを入力…", bundle: .module)
                    }
                }
            }
        }
    }
}
