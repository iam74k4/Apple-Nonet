# Nonet

キーを押している間だけ、MacBook のトラックパッドが「アプリごとに変わる 3×3 の9つのボタン」になる macOS のメニューバーアプリ。

- トリガーキー（JIS 配列は右⌘、それ以外は右⌥）を押してすぐタップすれば、その場で実行。迷って指を止めたときだけ HUD が出る
- 前面のアプリごとに9マス×最大3ページ。プリセット・メニューからの割り当て・ランチャー・触覚・スクリプトと AI
- macOS 14 以降。非公開の `MultitouchSupport.framework` を使うので Mac App Store ではなく直販（Developer ID 署名と公証、Sparkle でアップデート）。14日間の試用 → 買い切り。アカウントもサーバーも無い

## リポジトリの構成

| 場所 | 中身 |
|---|---|
| `project.yml` | XcodeGen の設定。`Nonet.xcodeproj` は生成物でコミットしない |
| `Config/Nonet.xcconfig` | 販売用の値（appcast の URL・Sparkle の公開鍵・購入ページ・ライセンスの公開鍵） |
| `App/` | アプリ本体の組み立て（AppDelegate・Sparkle） |
| `Packages/NonetKit/` | それ以外のすべて（ロジック・macOS の実装・画面・`nonet-license`）。`swift build` と `swift test` で動く |
| `scripts/` | ビルド・テスト・リリース・販売ページの確認。`scripts/tests/` はそのテスト |
| `site/` | 販売ページ（静的な HTML。日本語と `en/`） |
| `docs/` | 設計・リリースの手順・利用ガイド・プライバシーポリシー |
| `Spikes/NonetSpike/` | フェーズ0の技術検証アプリ（使い捨て） |
| `.github/workflows/ci.yml` | プッシュとプルリクエストで `scripts/test.sh` を動かす |

## はじめる

必要なもの: Xcode 27 以降（Swift 6 のツール）と XcodeGen（`brew install xcodegen`）。

```bash
scripts/build.sh                  # Debug ビルド（build/DerivedData）。できた .app の場所を表示する
open "$(scripts/build.sh)"        # ビルドして起動する
scripts/test.sh                   # テスト一式（CI と同じ）。失敗したら 0 以外で終わる
```

- `scripts/build.sh` は Apple Development 証明書で署名する（再ビルドしてもアクセシビリティの許可が消えない）。証明書が無ければアドホック署名にする。引数は xcodebuild に渡る（例: `scripts/build.sh CODE_SIGNING_ALLOWED=NO`）
- `scripts/test.sh` は `scripts/tests/run.sh`（スクリプト・販売ページ・ドキュメントのテスト）→ `swift build` / `swift test` → 署名なしのアプリのビルド（build/TestDerivedData）の順に動かす
- パッケージだけなら `cd Packages/NonetKit && swift test`。スクリプトのテストだけなら `scripts/tests/run.sh [名前の一部]`
- スクリプトのテストは外部のツール（xcodebuild・notarytool・hdiutil など）を `scripts/tests/fakes/` の偽物に差し替えて動くので、証明書もネットワークも要らない。`shellcheck` と `node` があれば、それを使うテスト（シェルの静的解析・販売ページのデモの動き）も動く（無ければ飛ばす）
- どのスクリプトも、どのフォルダから動かしてもよい

## リリース

一度だけの準備（Developer ID 証明書・notarytool のプロファイル・Sparkle とライセンスの鍵・`Config/Nonet.xcconfig`）は [docs/release.md](docs/release.md) を参照。準備ができたら:

```bash
scripts/release.sh --dry-run 1.2.0 42                                         # 公証せずに通しで試す
NONET_NOTARY_PROFILE=nonet-notary scripts/release.sh --notes notes/1.2.0.md 1.2.0 42
```

アーカイブ → 書き出し → 署名の確認 → 公証とステープル → DMG（署名・公証・ステープル）→ appcast の更新までを行う。足りないものがあれば、ビルドの前にまとめて知らせて止まる。公開前には `scripts/check-site.sh --strict` で販売ページの仮の値が残っていないかを確かめる。

- 初めてのリリース（まだ appcast を公開していない）ときだけ `--first-release` を付ける。それ以外で公開中の appcast を取れなければ、過去の項目を消さないよう止まる
- `--notes` のファイルはコミットしていなくてよい（コミットしていない変更の確認から外す）。残すならタグの前にコミットする

## ドキュメント

- [docs/architecture.md](docs/architecture.md): 設計・担当・共通の決まり・操作と機能の仕様
- [docs/feature-plan.md](docs/feature-plan.md): 機能の検討（モックからの整理）
- [docs/spike-results.md](docs/spike-results.md): フェーズ0の技術検証の結果
- [docs/release.md](docs/release.md): リリースと販売の手順、公開前のチェックリスト
- [docs/user-guide.md](docs/user-guide.md): 利用ガイド（利用者向け）
- [docs/privacy.md](docs/privacy.md): プライバシーポリシー（日本語・英語）

© 2026 Takanari Okazaki
