# UIテストとシミュレータの終了確認

## 実行方法

XcodeとPython 3が必要です。対象にする**テスト用iPadシミュレータ**のUDIDを指定します。
このコマンドは対象端末をいったん停止し、Xcodeに起動から終了まで管理させます。
端末のデータを消去する操作は行いません。実機や起動中のMac版には触れません。

```sh
xcrun simctl list devices available
python3 -B scripts/check-apple-ui.py '対象iPadのUDID'
# 回転テストだけに絞る場合
python3 -B scripts/check-apple-ui.py '対象iPadのUDID' \
  --only-testing HastellColorUITests/StudioChecks/testColorSelectionAndLandscapeDrawing
# 終了判定の回帰テスト（シミュレータ不要）
python3 -B -m unittest discover -s scripts/tests -v
```

初期状態では全5シナリオを実行します。既定の結果保存先は
`apple/.build/ui/<日時>/`、ビルドキャッシュは一時ディレクトリ内の
`HastellColor-ui-build`です。`--results`で新しい結果ディレクトリ、
`--derived-data`でビルドキャッシュを指定できます。

- `xcodebuild.log`: 各テストの実行ログ。
- `Test.xcresult`: 成否と明示的に添付した画面・診断情報。
- `health.json`: 対象UDID、時刻、SpringBoardのPIDと終了状態、新規クラッシュ記録。

XCTestの失敗に加え、対象シミュレータの異常終了を検出した場合も終了コード1です。
XCTestの成功表示だけを見て合格にしません。SpringBoardの終了状態はテスト中と
テスト終了後約10秒間に確認し、クラッシュレポートも対象端末・発生時刻で絞ります。
Xcodeの準備段階で使われるSIGKILL（終了状態9）は、それだけでは異常扱いしません。
クラッシュレポートの生成がこの監視期間より遅れる場合まで保証するものではありません。
検証完了時、またはCtrl+Cによる中断時には対象端末だけを停止します。

Xcodeの詳細診断収集は、この環境で失敗後に長時間完了しなかったため無効です。
テストの成否、ログ、添付画像は引き続き保存します。

## 2026-09-27の発生箇所と対処

調査環境はmacOS 27.0、Xcode 27.0（27A266a）、iPadOS 26.2（23C54）です。
既存のM2・13インチM5シミュレータで、UIテスト終了時にSpringBoardが異常終了し、
その後の回転テストで画面が縦のままになる問題を確認しました。

### 横向きテスト

失敗箇所は`StudioChecks.testColorSelectionAndLandscapeDrawing`の画面寸法の判定です。
端末の向きを設定しただけでは合格にせず、アプリの画面が横長になることを待ちます。
従来の失敗時は13インチで1032 × 1376 ptの縦画面のままでした。
SpringBoardの同時刻のログには回転ロック解除要求と`user lock: NO`があり、
アプリの向きはportraitのままでした。

`Info.plist`は4方向を許可し、アプリ内に回転を固定する処理はありません。
アプリの製品コードを変更せず、新しいシミュレータでは同じテストが通りました。
失敗していたM2も、データを消さず端末を停止・起動し直すと通りました。
この結果から、描画レイアウトとシミュレータのセッション状態を切り分けています。
OS内部で向きの通知が止まった経緯までは断定していません。

回転テストは現在、左横向き→縦→右横向き→縦の各段階で、画面寸法、
キャンバスの収まり、色ボタンの操作可能性、用紙寸法の保持、描画を確認します。
回転待ちが失敗した場合はその画面と要素の状態を添付して止め、
縦のまま描いた画像を横向き成功の証拠として扱いません。
端末の向きとUIの向きが同じものではない点は
[AppleのXCUIDevice.orientationの説明](https://developer.apple.com/documentation/xcuiautomation/xcuidevice/orientation)も参照してください。

### SpringBoardの異常終了

9月27日10:28、10:32、16:27、16:33の記録は同じ箇所です。

| 項目 | 記録 |
| --- | --- |
| プロセス | シミュレータのSpringBoard（親は`launchd_sim`） |
| フレームワーク | `XCTAutomationSupport` 26.2 / 24507 |
| 関数 | `__66-[XCTAutomationSession initWithAccessibilityFramework:dataSource:]_block_invoke` |
| 関数内の位置 | +184（0xb8） |
| 例外 | `EXC_BAD_ACCESS / SIGSEGV`, アドレス`0x20` |

対象バイナリとクラッシュ時のレジスタを照合しました。この処理は
`Automation Mode has been disabled, existing connections will be invalidated.`
というログを出す、自動操作セッションの接続解除処理です。
弱参照を取得した直後、nil判定をせず`ldr x0, [x19, #0x20]`を実行し、
クラッシュ時の`x19`は0でした。HaskellやMetalの計算内での例外ではありません。

このリポジトリではAppleのフレームワークを変更せず、テスト前の端末停止と
Xcodeによる新規セッションでの起動・終了により、不調なセッションの再利用を避けます。
検出した異常終了を無視したり、回転の判定を省略したりする対処ではありません。
Apple側のバイナリ自体が修正されたという意味ではなく、この環境で検証するための回避策です。

### 対処後の確認

上記スクリプトで、以前失敗していた両方の端末の全UIテストを実行しました。

| シミュレータ（iPadOS 26.2） | 終了時刻（日本時間） | UIテスト | 終了監視 |
| --- | --- | --- | --- |
| 13インチiPad Pro M5 | 2026-09-27 17:27 | 5 / 5成功 | 異常終了・新規クラッシュ記録なし |
| 11インチiPad Pro 第4世代（M2） | 2026-09-27 17:32 | 5 / 5成功 | 異常終了・新規クラッシュ記録なし |

両方で、監視開始からXcodeが端末を停止するまでSpringBoardのPIDは変わりませんでした。
M2の左右横向き・縦向き復帰の添付画面も目視確認しています。
監視判定の回帰テスト5件も成功し、既存4件の実際のクラッシュ記録についても
対象端末と発生時刻を正しく識別することを確認しました。

実機の回転、Apple Pencil、表示色、描き心地の確認は別途必要です。
