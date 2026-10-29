// 担当: ui-settings
// 情報のタブ: バージョン・アップデートの確認・利用ガイド・プライバシー・サードパーティのライセンス
import AppKit
import NonetCore
import SwiftUI

struct SettingsAboutView: View {
    let model: SettingsModel
    var bundle: Bundle = .main
    @State private var showsNotices: Bool

    init(model: SettingsModel, bundle: Bundle = .main, showsNotices: Bool = false) {
        self.model = model
        self.bundle = bundle
        _showsNotices = State(initialValue: showsNotices)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 8) {
                    Image(nsImage: NSApp?.applicationIconImage ?? NSImage())
                        .resizable()
                        .frame(width: 96, height: 96)
                        .accessibilityHidden(true)
                    Text(verbatim: "Nonet")
                        .font(.system(size: 26, weight: .bold))
                    if let version = SettingsText.version(
                        short: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                        build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
                    ) {
                        Text(version)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Text("キーを押している間だけ、トラックパッドが9つのボタンになる", bundle: .module)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 12) {
                    if let check = model.onCheckForUpdates {
                        Button(action: check) {
                            Text("アップデートを確認", bundle: .module)
                        }
                    }
                    if let support = model.links.support {
                        Button {
                            model.openURL(support)
                        } label: {
                            Label {
                                Text("利用ガイド", bundle: .module)
                            } icon: {
                                Image(systemName: "book")
                            }
                        }
                    }
                    if let privacy = model.links.privacy {
                        Button {
                            model.openURL(privacy)
                        } label: {
                            Label {
                                Text("プライバシー", bundle: .module)
                            } icon: {
                                Image(systemName: "hand.raised")
                            }
                        }
                    }
                }
                if let copyright = bundle.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String, !copyright.isEmpty {
                    Text(copyright)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                DisclosureGroup(isExpanded: $showsNotices) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(SettingsThirdPartyNotices.notices) { notice in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(verbatim: notice.name)
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(verbatim: notice.url)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                Text(verbatim: notice.license)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("サードパーティのソフトウェア", bundle: .module)
                        .font(.system(size: 12, weight: .medium))
                }
                .frame(maxWidth: 560)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 36)
            .frame(maxWidth: .infinity)
        }
    }
}
