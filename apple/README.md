# macOS / iPadOS アプリ

macOS（Mac Catalyst）と iPadOS 17 以降用の描画アプリです。M2 専用の制限はなく、M2 搭載 iPad Pro
（11インチ第4世代 / 12.9インチ第6世代）と、13インチ iPad Pro（M4 / M5）を対象にしています。
画面寸法に合わせてキャンバスを配置し、縦向き・横向きに対応します。
大きい画面でも作品自体の画素数は変えないので、同じファイルをそのまま開けます。

## 起動

1. Mac の Xcode で `apple/HastellColor.xcodeproj` を開きます。
2. `HastellColor` ターゲットの **Signing & Capabilities → Team** に自分の開発チームを設定します。
   Bundle Identifier が使えない場合は自分用の一意な値に変更します。
3. iPad を Mac に接続して信頼し、iPad の開発者モードを有効にします。
4. 実行先としてその iPad を選び、Run（⌘R）します。

Macでは実行先を **My Mac (Mac Catalyst)** にしてRunします。マウス／トラックパッドで描けます。
Macのペンタブレットの筆圧・傾きにはまだ対応していません。

生成済みの Metal コードを同梱しているので、アプリのビルドだけなら GHC は不要です。
Xcode が Metal Toolchain の不足を報告する場合は Xcode の設定から追加するか、
`xcodebuild -downloadComponent MetalToolchain` を実行します。
署名・実機へのインストール・App Store 配布はこのリポジトリだけでは完了しません。

シミュレータではマウスで描けるよう「指でも描く」が最初から有効です。
実機の初期設定では Apple Pencil のみを受け付けます。
指でこする場合は入力メニューの「指でこする」を有効にします。指の入力には選択中の道具より
「指でこする」が優先され、Pencilには選択中の道具が適用されます。この設定では指の接触も
描画操作として受け付けるため、手のひらを置く際の誤操作に注意してください。
Apple Pencil（USB-C）は筆圧センサーがないため、入力設定の「筆圧を固定」を有効にします。
M2 iPad Pro で筆圧を使う場合は Apple Pencil 第2世代が対応します。
13インチ iPad Pro（M4 / M5）では Apple Pencil Pro が対応します。
Apple Pencil 第2世代は13インチモデルには対応しません。
機種の対応は [13インチ M4 の仕様](https://support.apple.com/en-us/119891)と
[現行 iPad Pro の仕様](https://www.apple.com/ipad-pro/specs/)を参照してください。
仕様は [Apple の Pencil 比較](https://www.apple.com/newsroom/2023/10/apple-introduces-new-apple-pencil-bringing-more-value-and-choice-to-the-lineup/)を参照してください。

## 操作と保存

- 道具メニューからパステル・消しゴム・指・擦筆・シリコン・練り消しを切り替えます。
  半径スライダーで接触範囲を調整します。
- 指は広く柔らかく混ぜ、擦筆は狭い範囲を伸ばします。シリコンは縁を比較的はっきり保って
  顔料を押し、練り消しは色を追加せず少しずつ薄くします。選択中のインク色は使いません。
  「こする強さ」と筆圧を反映し、擦筆とシリコンはペンの傾き・向きも反映します。
  練り消しは通常の消しゴムより穏やかに顔料を持ち上げる近似です。
  実物のオイルパステルが練り消しで同じように消せることを保証するものではありません。
- 下部の「色を選ぶ」からカラーパレット、または Display P3 の RGB 調整を開きます。
  赤・緑・青をそれぞれ0〜1023のスライダーと＋/−で調整し、選択色をプレビューできます。
  変更は次に描く線へ反映します。開いて閉じるだけでは元の色を丸めません。
  画面幅が狭い場合は下部の色見本を横にスクロールできます。
- 「塗りの強さ」は25〜250%。次のパステルの付着量を変えます。消しゴムには適用しません。
  色そのもの、強さ、筆圧を分けて調整できます。
- 「ファイル → 新しい用紙」で用途・規格・mmまたはpx・解像度・紙色・紙目を設定します。
  初期値は印刷用がA4 / 300 dpi、画面用が2048px正方形 / 72 dpi、漫画がA4 / 600 dpiです。
  mm表示は丸めた画素数から求めた実寸です。
- 上部の寸法表示または「用紙の設定」から紙色と紙目を変更できます。紙色は6色の見本と自由な色選択、
  紙目は粗・中・細です。粗は凹凸の間隔と深さが大きく、細は滑らかに付きます。
  紙目の間隔はmmとdpiから決めるので、用紙の解像度に応じて変わります。
  紙目変更は既存の全ストロークを再計算します。紙色・紙目の変更も取り消せます。
  既存の線を拡大縮小する機能はまだありません。
- 左上の矢印で取り消し / やり直し。履歴は直近50操作です。
- ペンの筆圧、紙面からの傾き、方位を反映し、イベントにまとめられた中間サンプルも取得します。
  UIKit から後で届く筆圧などの推定値の訂正を保存データと表示へ反映します。
- 作品はアプリの Documents 内の `Autosave.hastell` に自動保存し、次回起動で復元します。
  Macでは `~/Library/Application Support/HastellColor/Autosave.hastell` を使います。
  「作品を保存」で任意の場所に別名保存し、「作品を開く」で再編集できます。
- `.hastell` はバージョン・色空間・寸法・dpi・紙色・紙目・ストロークとペン入力を持つ JSON です。
  バージョン3では紙目とこする道具も保存します。旧v1・v2は従来の紙目を維持し、
  用紙設定では「従来」と表示します。旧v1は白い紙・300 dpi・強さ100%として読み込みます。
  画像に焼き込まないため、8ビットへの量子化を伴いません。
- 「PNGを書き出す」で選択した紙色を含む16ビット/成分の Display P3 PNG を保存します。
  dpiもPNGに記録します。
  PNG の再読み込み・レイヤー編集はまだありません。再編集用には `.hastell` を保存してください。
- キャンバスを空にする操作も取り消せます。別の作品を開く・新しい用紙を作ると取り消し履歴はリセットされます。
  線がある作品は、自動保存と同じ場所の `BeforeReplace-….hastell` に退避します。
  復元できない自動保存も `Unreadable-….hastell` に保全してから新しい自動保存に切り替えます。

## Haskell と Metal の分担

`src/HastellColor/Brush/Kernel.hs` がブラシ形状、紙目への接触、塗りの強さ、顔料付着、堆積面の主要な式を
定義します。同じ式を CPU の `Double` 計算と Metal の関数生成に使用します。
`Grain.hs` と `Brush/Rubbing.hs` が紙目・道具の係数とCPU参照計算を持ち、係数もMetalへ生成します。
こする処理は顔料量と色ごとの量を移動・交換します。白紙から色を作らず、紙の外に顔料を捨てません。
GPUでは1px間隔で軌跡を補間して計算し、入力イベントの分割による濃さの違いを抑えます。
`metal/Paint.metal.in` は GPU の並列走査、ストロークごとの最大接触量、画面表示を実装します。
Swift は UIKit 入力・画面・文書管理・GPU コマンドの発行を担当します。

```sh
# リポジトリのルートで実行
cabal run hastellcolor-metal
cabal run hastellcolor-metal -- --check
```

`apple/HastellColor/Generated/Paint.metal` は生成物ですが、Xcode 単独でビルドできるよう管理します。
式・テンプレートの変更後は生成し直してください。`--check` は古い生成物を検出します。

**現時点では GHC を iPad 向けにクロスコンパイルしていません。**
アプリ内で Haskell ランタイムを動かす構成を完成させたものではなく、Haskell の式を
Metal に変換して iPad 上で実行する構成です。CPU 版にある顔料消費・摩耗は GPU 版には
まだ移していません。パステルは毎回補充された状態として描きます。
既存 CPU 版の PPM 出力と色空間の扱いは従来どおりです。

## 色について

内部の顔料テクスチャと画面出力は `RGBA16Float`、色空間は線形 Display P3 です。
画面の `CAMetalLayer.colorspace` に色空間を明示し、OS の色管理に渡します。
PNG は Display P3 の伝達関数で変換し、16ビット/成分と ICC プロファイルを保ちます。
色選択の RGB は Display P3 の符号化値で、各1024段階の組み合わせは1,073,741,824通りです。
選択時に線形光へ変換し、浮動小数点のまま Metal と文書に渡します。
Haskell でも高精度の色は計算できます。画材の計算を Haskell、GPU 描画を Metal、
色を選ぶ画面を Swift が担当する分担です。

「10億色」は一般に RGB 各10ビットの組み合わせ（1024³ ≈ 10.7億）を指します。
広色域（P3）、階調数（ビット深度）、HDR の明るさは別の性質です。
Metal を使うだけでパネルが10億色になるわけではありません。この実装は8ビットへの
早期の丸めを避けますが、M2 iPad の物理表示色数・HDR 出力・色校正を保証しません。
HDR の高輝度出力は未実装です。

Apple の対象機種仕様:
[11インチ第4世代](https://support.apple.com/en-us/111842) /
[12.9インチ第6世代](https://support.apple.com/en-us/111841)。
入力処理は [Apple Pencil の入力仕様](https://developer.apple.com/documentation/uikit/handling-input-from-apple-pencil)を参照しています。

## 検証

```sh
cabal test all --test-show-details=direct
cabal check
sh scripts/check-apple.sh
xcodebuild -project apple/HastellColor.xcodeproj -scheme HastellColor \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath apple/build CODE_SIGNING_ALLOWED=NO build
# 実行先の iPad シミュレータ名はインストール済みのものに合わせる
xcodebuild -project apple/HastellColor.xcodeproj -scheme HastellColor \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5),OS=latest' \
  -parallel-testing-enabled NO \
  -derivedDataPath apple/build CODE_SIGNING_ALLOWED=NO test
# Macのローカルビルド。クラウド同期由来のFinder属性を避けるため/tmpを使う
xcodebuild -project apple/HastellColor.xcodeproj -scheme HastellColor \
  -destination 'generic/platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath /tmp/HastellColor-Mac-build \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build
```

`check-apple.sh` は Metal を利用できる Mac と Xcode が必要です。Haskell で生成した参照値と
GPU の顔料状態をパステル10ケース・紙目とこする道具7ケースで比較し、入力の分割、文書の往復、破損データ、消去、
PNG の16ビット・P3保持を検証します。GPU の半精度保存による誤差を許容します。
指・擦筆・シリコンの移動前後の顔料量と色ごとの総量、白紙・筆圧ゼロ・紙の端での動作、
練り消しの除去、v1/v2からの紙目の保持も検証します。`apple/.build/` には実際のGPUで描いた
`grain-*.png` と `rub-*.png` の比較見本も出力します。
判定失敗や読み込みエラーは標準エラーへ理由を出力し、終了コード1で終了します。
テスト失敗を `fatalError` によるmacOSのクラッシュ通知として扱わないようにしています。
UI テストは実際に線を描き、取り消し・やり直し・再起動後の自動保存復元を確認します。
色選択画面の開閉、RGB変更の反映、横向きでの描画も検証します。
2026-09-27に13インチM5（iPadOS 26.2）のシミュレータで、描画と保存復元、色選択と横向き、
用紙設定、紙目と4種類のこする道具の4シナリオが通過しました。
M2（11インチ第4世代・iPadOS 26.2）でも紙目と4種類の道具・取り消し・保存復元が通過しました。
M4（13インチ・iPadOS 26.0）は前バージョンで確認しています。
2026-09-27にApple描画・文書テスト105項目がM2 Maxで通過しました。Haskellは74項目が通過しています。
紙目・こする道具のCPU/GPU比較は最大誤差0.00118以下（顔料量・乗算済みRGBの0〜1範囲）でした。
連続してこすった際の色の偏りを抑えるため、移動後の半精度保存には最近接・偶数丸めを明示しています。
Apple 描画・文書テストには、RGB 各1024段階の往復、半精度GPU保存での区別、
色の伝達関数、選択色の保存とGPU描画も含まれます。
さらに用紙の単位換算、旧文書の移行、紙色とdpiのPNG保存、塗りの強さ、
A4 / 600 dpi（4961×7016）のGPU描画とPNG書き出しをM2 MaxのMacで検証します。
Mac Catalystは今回の変更でarm64 / x86_64のビルドを確認しています。
アプリ起動・描画表示は前バージョンで確認済みです。
MacのXCTestはローカル署名のテストランナーでTeam IDの不一致が起き、実行完了できていません。
また、2026-09-27の10:28と10:32（日本時間）に、UIテスト終了と同時刻の
シミュレータのSpringBoard異常終了を確認しました。両方とも記録上の先頭フレームは
`XCTAutomationSession` の自動操作処理で、HastellColor本体のクラッシュ記録はありません。
テスト項目は通過しましたが、このテスト環境の終了時の問題は未解決です。

シミュレータでの確認では、実物の Pencil 入力、パネルの色、120 Hz の描き心地は評価できません。
実機では弱い線 / 強い線、ペンを寝かせた線、素早い曲線、手のひらを置いた描画、
回転後の座標、再起動からの復元、他のカラーマネージメント対応アプリでのPNG表示を確認します。

## 今の制限

初回キャンバスは1536×2048です。「新しい用紙」でサイズと色を選べます。
1辺8192px・合計4000万画素までで、A4 / 600 dpiは収まりますがB4 / 600 dpiは上限を超えます。
作業用GPUテクスチャだけで最大800MBを使い、PNG書き出しには追加メモリが必要です。
大きな用紙の実機iPadでのメモリ・速度測定はまだ行っていません。

紙目のかすれ、筆圧による付着、寝かせた芯の幅、重ね塗りを近似しています。
指・擦筆・シリコンで顔料を移動・混合できますが、油分の粘性、温度、溶剤、
道具に付いた顔料の持ち越し、実際の顔料の吸収・散乱は未実装です。
実物のオイルパステルと比較した再現性は、まだ確認できていません。
漫画用の設定は用紙寸法と解像度の入口です。トンボ、塗り足しのガイド、コマ割り、
網点、モノクロ2値出力、複数ページ、CMYK入稿には対応していません。
単一レイヤーで、紙目は3種類、乱数シードは固定です。
拡大縮小・回転操作、レイヤー、水彩、予測タッチ、ホバー表示、ダブルタップは未実装です。
取り消しと入力の推定値訂正ではストロークを再描画するため、長い作品では重くなる余地があります。
通常の入力は変更された矩形だけをGPUで更新し、ペンを離すたびの全履歴再描画は避けています。
長時間の作品制作に向けた性能・メモリ使用量の実機測定は今後必要です。
