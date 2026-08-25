# STM32 オンボードLED テストケース

記録済みの NUCLEO-F446RE ターゲットに対して、すべてのテストを実行します。

```sh
checks/stm32/onboard_led/check.sh f446
```

英字名は`checks.yml`で使用するテスト識別名です。実装済みテストでは、同じ名前を
`samples/<英字名>.rb`、`expected/<英字名>.txt`、および実行結果を保存する
`.bareruby/checks/stm32/onboard_led/<英字名>/`に使用します。未実装テストの英字名は
予定名です。

## テストの仕組み

`OnboardLED`は意図してピン番号を知らないクラスです(stdlibの冒頭コメント参照)。
LEDの位置と駆動方法はボードのマニフェストが持ち、NUCLEO-F446REでは
`led: PA5, active_high: true`(基板のLD2)です。コンストラクタは引数なし、
`write(v)`・`on`・`off`はすべて`Nil`を返すので、戻り値の検査はなく、UART出力は
実行の進みを示すマーカーだけになります。

観測はGPIOスイートの`led_wire`と同じです。`bareruby emulate`の生成する機械は既に
PA5へRenodeのLEDモデルを接続しているので、LEDモデルの`State`と、ポートAのレジスタ
(MODER・ODR)の直接読みで行います(`checks/stm32/gpio/observe/led.resc`と同じ
観測行)。ハーネスもGPIO・I2Cスイートと同じスタブRenode方式です。ビルドには
Renodeの代わりにスタブを渡し(ELF・machine.repl・run.rescだけ作らせる)、生成された
run.rescへ観測行を差し込んで、本物のRenodeを自分で1回だけ起動します。検証結果は
UART(USART2)へ出力し、`expected/<英字名>.txt`と比較します。観測系は
`expected/<英字名>.registers`とも比較します。

観測は`quit`直前の1回、つまり実行の終端状態が基本です。途中の点灯を見たいテスト
(`write_cycle`)は、GPIOスイートがボタン押下に使う`emulation RunFor`の分割を流用し、
スライスの間に`State`の読みを挟みます(`checks.yml`の`during:`にプローブを指定
すると、check.shが最初の0.2秒スライスの後へ差し込む拡張)。

## 基本動作テスト

| テスト名 | ファイル・結果フォルダ名 | 実装状況 | 入力・設定 | 期待結果 | 確認すること |
| --- | --- | --- | --- | --- | --- |
| 点灯が配線先へ届く | `on_wire` | 実装済み | `OnboardLED.new`(引数なし)で作り、`on`してマーカー出力、停止。観測でLED状態とポートAのMODER・ODRを読む | マーカー、LED状態`True`、MODER `0xA80004A0`(リセット値+stdout用USART2のPA2/PA3 AF+PA5出力)、ODR `0x00000020` | プログラムがピン番号を一切書かずに、マニフェストのled(PA5、LD2)がモデルまで駆動されること。初期化がPA5をプッシュプル出力に設定すること(MODERの期待値はGPIOの`led_wire`と同値)。 |
| 消灯 | `off_after_on` | 実装済み | `on`のあと`off`して停止 | LED状態`False`、MODER `0xA80004A0`、ODR `0x00000000` | `off`が点灯状態を消灯へ戻すこと。`active_high: true`の解釈として、消灯=ODRビット5が0(RESET書き込み)であること(下の注記)。 |
| `write`の0/1と点灯1周期 | `write_cycle` | 実装済み | `write(1)`、`sleep_ms`、`write(0)`、`sleep_ms`、`write(2)`して停止。ハーネスが`RunFor`を分割し、点灯区間の途中でLED状態を読む。終端でLED状態とMODER・ODRも読む | 途中`True`、終端`True`、MODER `0xA80004A0`、ODR `0x00000020` | `write(1)`/`write(0)`が`on`/`off`と同じ点灯・消灯に落ちること(バインディングは`on`/`off`を`write`へ委譲する実装なので、3経路が同じボード書き込みへ合流することをAPIの表から固定する)。最後の`write(2)`で、0/非0をそのまま真理値に落とす契約(1に限らない)も固定する。時間経過を挟んだ点灯→消灯→点灯がモデルに現れること(点滅1周期のテストを兼ねる)。 |
| 初期化直後の状態 | `init_state` | 実装済み | `OnboardLED.new`だけしてマーカー出力、停止 | LED状態`False`、MODER `0xA80004A0`、ODR `0x00000000` | 初期化が消灯を明示的に書いて終わること(バインディングの`bareruby_board_led_initialize`は最後にoffを書く)。点灯系のどれとも独立に、作っただけのLEDの状態が定まっていること。 |

ODRビット5の期待値は「バインディングが`active_high`をどう解釈したか」の観測です。
NUCLEO-F446REは`active_high: true`なので点灯=ビット1・消灯=ビット0ですが、
active_lowのボードでは同じ`on`/`off`でODRの期待が反転します(LEDモデル側は接続時の
`invert:`が極性を吸収するので、`State`の期待`True`/`False`は変わりません)。
このスイートのレジスタ期待値はNUCLEO-F446RE固有です。なおMODERの期待値
`0xA80004A0`は、マーカーのUART出力によってUSART2(PA2/PA3のAF)が初期化されて
いることに依存します — マーカーを出さないサンプルに変えるならMODERの期待も
変わります(GPIOの`led_wire`と同じ依存)。

## 異常系・既知の制約の記録

コンストラクタは引数を取らず、`write`は0/非0をそのまま真理値に落とすため、GPIOの
`invalid_pin`・`missing_port`に相当する**実行時の拒否経路がそもそもありません**。
実行時異常系のテストは置きません(無いことの記録)。このクラスの拒否はただ1つ、
コンパイル時にあります。

| テスト名 | ファイル・結果フォルダ名 | 実装状況 | 入力・設定 | 期待結果 | 確認すること |
| --- | --- | --- | --- | --- | --- |
| LEDの無いボードの拒否 | `missing_led_board` | 未実装 | ledの無いマニフェストのターゲットで、`OnboardLED.new`を含むサンプルをビルド | ビルドが`error: <board> has no onboard LED ...`を出してstatus 10で拒否される(Renode実行なし) | 拒否がユニット解決の時点(バインディングの`self.unit`)で起き、Cが生成される前に答えが出ること。コンパイル時の答えなので、エミュレータもELFも要らない。 |

現在のリポジトリの3マニフェスト(F446RE・F401RE・F4DISCOVERY)はすべてledを
持つため、このテストはledの無いマニフェスト(例: STM32446E-EVAL — 公式データが
LED相当のピンを入力として配線しているためledが載らない。binding.rbのコメント参照)
が入った時点で実装します。ハーネス側も、ビルド拒否をFAIL扱いする現行の形ではなく
「status 10とメッセージが期待どおりなら成功」とする分岐が要ります。

## 実機で確認するテスト

エミュレータで固定できるのはLEDモデルの状態とレジスタまでで、光ることと配線の極性
そのものはボードの実物が答えです。

| テスト名 | 予定ファイル・結果フォルダ名 | 実装状況 | 確認すること |
| --- | --- | --- | --- |
| LD2の目視点灯 | `ld2_visual` | 未実装 | `samples/heartbeat.rb`(OnboardLEDで100ms点灯・900ms消灯)を実機へ書き込み、LD2が目視で心拍点滅すること。 |
| active_high配線の実証 | `active_high_wiring` | 未実装 | `on`でPA5がhigh(3.3V)かつLD2点灯、`off`でlowかつ消灯であることを実測すること。エミュレータのODR観測は解釈の確認までで、マニフェストの`active_high: true`が実配線と一致することはここで実証する。 |

オンボードLEDの検証結果はUART出力として、それぞれ`expected/<英字名>.txt`と
比較します。全テストでLED状態とポートAのレジスタを直接読み、
`expected/<英字名>.registers`とも比較します。失敗時の出力や差分は
`.bareruby/checks/stm32/onboard_led/<英字名>/`に残ります。
