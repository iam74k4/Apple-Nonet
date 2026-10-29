# Nonet 技術検証（Phase 0）

[docs/feature-plan.md](../../docs/feature-plan.md) §4 の技術リスクを確かめるための、使い捨ての検証アプリ。本体には流用しない前提。結果は [docs/spike-results.md](../../docs/spike-results.md) にまとめる。

## ビルドと起動

```bash
./scripts/bundle.sh
```

```bash
open build/NonetSpike.app
```

- Apple Development 証明書があればそれで署名する。再ビルドしても権限の許可が消えない
- `build/NonetSpike.app/Contents/MacOS/NonetSpike --probe` で、画面を出さずにデバイスと権限の状態を表示する

## 権限

1. アプリの「アクセシビリティを要求」を押し、システム設定で「Nonet 技術検証」を ON にする
2. 「イベントタップ: HID レベルで動作中」になれば準備完了（1秒ごとに自動で確認する）
3. それでもキーに反応しなければ「入力監視を要求」も許可する

トラックパッドの指の位置は、権限が無くても取れる。

## テストの進め方

- 左上の「テスト」で T1〜T9 を選ぶと手順が表示され、ログに区切りが入る
- 気づいたことはメモ欄に書いて Enter（ログに残る）
- ログ: `~/Library/Logs/NonetSpike/spike.log`

## 困ったとき

トリガーを押している間はクリックやスクロールを捨てているので、効かなくなったら次のどれかで戻る。

- トリガーキーを押して離す
- 何かキーを押す（セッションが中断される）
- 15秒待つ（安全装置で自動的に解除される）
- ⌘Q でアプリを終了する

## 中身

| ファイル | 役割 |
|---|---|
| `Sources/CMultitouch` | 非公開の MultitouchSupport.framework を dlopen で読む C ラッパー（タッチ・触覚） |
| `EventTap.swift` | 全イベントのタップ。トリガー検出と入力の抑止に使う |
| `SpikeController.swift` | トリガー → 速押し / HUD → 実行 の状態遷移と計測 |
| `HUD.swift` / `ControlPanel.swift` | HUD と操作パネル |
