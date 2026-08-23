# STM32 エミュレートテストの現状

`./checks/emulate.sh` が [emulate.yml](emulate.yml) を読んで回すテストの、サンプル別の現状表。
samples/ の全 38 本のうち **19 本がテスト済み、19 本が未テスト**。
テストの中身は「ホストビルドの出力を正とし、Renode 上の UART 出力と行単位で突き合わせる」。
入力が要るサンプルには `--input=` で同じバイト列をボード(UART RX)とホスト(stdin)の
両方に与える([checks/input/](input/) に実体)。

## テスト済み(19 本)

3 ボード(F446RE / F401RE / F4DISCOVERY)すべてでホストと一致することをエミュレーションで確認済み。
実機フラッシュでの確認ではない。

| サンプル | 備考 |
|---|---|
| samples/arena.rb | 初回チェックで発見した例外バグの修正後に復帰(full libstdc++ リンク) |
| samples/array.rb | |
| samples/block_parameters.rb | |
| samples/definite_assignment.rb | |
| samples/features.rb | 初回チェックで発見した Int64 printf バグの修正後に復帰 |
| samples/fixed.rb | |
| samples/implicit_return.rb | |
| samples/m25.rb | 初回チェックで発見した例外バグの修正後に復帰 |
| samples/nilable.rb | |
| samples/object.rb | |
| samples/peripheral_ruby.rb | |
| samples/require.rb | |
| samples/sleep_interrupt.rb | |
| samples/string.rb | |
| samples/uart_buffered.rb | |
| samples/uart_one_queue.rb | 入力: checks/input/uart_one_queue.txt |
| samples/uart_receive.rb | 入力: checks/input/uart_receive.txt |
| samples/uart_rx_buffer.rb | |
| samples/uart_rx_receive.rb | |

## 未テスト(19 本)

不在は修正待ちではなく、ハーネスかバインディングの都合による。emulate.yml のヘッダコメントと同内容。

| サンプル | 理由 | 対応の見込み |
|---|---|---|
| samples/logger.rb | UART ではなくボタン(GPIO)の入力待ち | v3 相当: GPIO エッジ注入 |
| samples/uart_line_ending.rb | 入力は与えられるが、ホスト突き合わせには生キャプチャが必要(uart.txt は LF 正規化済みで、改行こそが試験対象) | 試験内容は専用スイート [checks/stm32/uart/](stm32/uart/) が固定回答で担保済み(TX側 `line_ending_tx` の hex キャプチャ、RX側 `gets_crlf`)。ホスト突き合わせ自体は対象外のまま |
| samples/blink.rb | 無限ループで UART に何も言わない | v3: LED/デューティ比アサーション |
| samples/heartbeat.rb | 同上(手動では一度確認済み: デューティ比 0.1 ± 0.05) | v3 |
| samples/servo.rb | 同上 | v3 |
| samples/asleep.rb | 同上 | v3 |
| samples/gpio_pico_loop.rb | 同上 | v3 |
| samples/tenji.rb | 同上 | v3 |
| samples/tenji_int.rb | 同上 | v3 |
| samples/avs.rb | 同上 | v3 |
| samples/adc.rb | 同上 | v3 |
| samples/interrupt.rb | 出力がなく、GPIO エッジの注入が必要 | v3 相当のハーネス拡張 |
| samples/i2c.rb | I2C の先にデバイスがいない(ホストのスタブは答えるが、エミュレートのバスは答えない) | I2C デバイスモデルの追加 |
| samples/picoruby_interface.rb | 同上 | I2C デバイスモデルの追加 |
| samples/uart_format.rb | 7E1 についてホストと STM32 のバインディングが不一致(エミュレート側だけ "7E1 ready" と言う) | バインディング側の問題として別途 |
| samples/uart_flow_control.rb | STM32 ではフロー制御を設計として拒否しており、ホストと食い違うのが正しい | テスト対象外(意図的) |
| samples/peripheral_answers.rb | STM32 向けにビルドできない(バインディングに PWM ユニットがない) | バインディングに PWM が入れば |
| samples/require_helper.rb | require.rb が読み込むライブラリで、プログラムではない | 対象外(require.rb 経由で実質カバー) |
| samples/require_lib.rb | 同上 | 対象外(require.rb 経由で実質カバー) |
