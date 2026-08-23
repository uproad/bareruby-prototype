# STM32 ボードで動かすまで（日本語ガイド）

BareRuby は Ruby のプログラムをマイコンのファームウェアに変換します。このガイドは
プロジェクト作成から、ビルド・書き込み・シリアル確認までを最短の手順で通します。
STM32CubeIDE も CubeMX も ST のアカウントも要りません。ボードが手元になくても、
ビルドしたファームウェアをエミュレータで動かして出力を確認できます（手順 5）。

詳しい背景は [README.md](README.md)、環境構築の詳細は [setup.md](setup.md)、
ビルドとトラブル対応は [build.md](build.md)（いずれも英語）にあります。

## 対応ボード

| `--target=` に渡す名前 | ボード |
| --- | --- |
| `f446` | NUCLEO-F446RE |
| `f401` | NUCLEO-F401RE |
| `f4disco` | STM32F4DISCOVERY |

`--target=` に渡す名前は手順 2 の `target add` で自分が付けるものです。このガイドは
上の表の通りに付けた前提で、以下の例は `f446` で書きます。手元のボードに
読み替えてください。

## 0. 準備するもの

- Linux または WSL2（Windows の場合）
- Ruby 4.x
- git と curl
- 対応ボードと、データ通信できる USB ケーブル

Ruby はこのチェックアウトが `.tools/ruby/bin` に持っているものが使えます。ただし
シェルは PATH 上のコマンドしか見つけないので、まず教えます:

```sh
export PATH="$PWD/.tools/ruby/bin:$PATH"   # チェックアウトの root で
```

`ruby --version` が `ruby 4.x` を返せば準備完了です。シェルを開くたびに打ちたく
なければ、同じ行を絶対パスにして `~/.bashrc` に追記してください。

## 1. プロジェクトを作る

bareruby-prototype のチェックアウトの root で:

```sh
./bareruby new my_project
cd my_project
```

そのままビルドできるプロジェクトができます。`app/main.rb` が書き込むプログラムで、
最初から LED を 0.5 秒間隔で点滅させる内容になっています。

作る場所はチェックアウトの中でなくて構いません。名前の代わりにパスを渡せます:

```sh
./bareruby new ~/projects/my_project
```

コマンドを実行するのがチェックアウトの root、というだけです。できたプロジェクトは
gem をチェックアウトから絶対パスで参照するので、どこに置いてもビルドできます。

## 2. STM32 を有効にする

`Gemfile` のこの行の `#` を外して:

```ruby
gem "bareruby_prot-binding-stm32cube"
```

インストールします:

```sh
bundle install
```

確認: `bin/bareruby target list` の一覧に STM32 のボードが並べば成功です。

続けて、このプロジェクトがどのボード向けかを記録します:

```sh
bin/bareruby target add
```

矢印キーでボード（NUCLEO-F446RE など）を選び、名前を聞かれたら `f446` と
入力します。この名前が以降のすべてのコマンドで `--target=` に渡す名前で、
`config/target.yml` に書き込まれます。

## 3. ツールをインストールする（初回のみ）

プロジェクトの root で:

```sh
"$(bundle info bareruby_prot-binding-stm32cube --path)/lib/bareruby_prot/binding/stm32cube/install.sh"
```

コンパイラ（ARM GCC）、書き込みツール（OpenOCD）、ST の HAL（STM32CubeF4）、
エミュレータ（Renode、Linux x64 のみ）がプロジェクトの `.tools/` に入ります。
すべてバージョンとチェックサムを検証してから使うので、何度実行しても安全です。

## 4. ビルドする

```sh
bin/bareruby build --target=f446
```

`app/main.rb` がコンパイルされ、`build/` の下にファームウェア
（`bareruby_program.elf`）ができます。

## 5. ボードなしで動かす（エミュレート）

```sh
bin/bareruby emulate --target=f446
```

`build` したのと同じ ELF を、ボードをつながずに Renode 上で実行します。マシンは
ボード定義（メモリサイズ・LED・クロック）から自動生成されるので、何も設定は
要りません。プログラムの `puts` が画面に出て、同じ内容が
`.bareruby/emulate/f446/uart.txt` に改行を LF に揃えて残ります。

`new` が書いた直後の `app/main.rb` は LED を点滅させるだけで `puts` がないので、
このままだと画面には何も出ません（それで正常です）。出力を見るには `app/main.rb`
のループに 1 行足します:

```ruby
puts "blink"
```

実行時間は仮想時間で区切ります。省略時は 3 秒、変えるときは:

```sh
bin/bareruby emulate --target=f446 --for=10
```

仮想時間なので結果は毎回・どのマシンでもバイト単位で同一です。これを使うと、
ホスト向けビルドの出力との比較がそのままテストになります:

```sh
bin/bareruby build --target=host
./build/host/bareruby_program > expected.txt      # ホストで実行した期待値
bin/bareruby emulate --target=f446
diff .bareruby/emulate/f446/uart.txt expected.txt  # 差分なし = 一致
```

注意点は 2 つ。エミュレーションはロジックと出力の確認であって実機の証明では
ありません（クロックは設定済みとして扱われ、I2C の先にデバイスはいません）。
また Renode の Linux x64 ビルドだけがピン留めされているので、それ以外の環境では
この手順は動きません（ビルドと書き込みは動きます）。

## 6. ボードをつなぐ

ボードを USB で接続します。WSL2 の場合は Windows の PowerShell（管理者）から
WSL へ渡します:

```powershell
usbipd list
usbipd attach --wsl --busid <ST-LINKのID>
```

確認: WSL 側の `lsusb` に STMicroelectronics ST-LINK が見えれば成功です。

## 7. 書き込む

```sh
bin/bareruby deploy --target=f446
```

ビルドと書き込み（write → verify → reset）を続けて行います。書き込みだけを
やり直すときは `deploy` の代わりに `flash` です。

成功すると、ボードの LED が 0.5 秒間隔で点滅を始めます。

## 8. シリアル出力を見る

プログラムの `puts` は ST-LINK の仮想 COM ポートに出ます（115200 8N1）:

```sh
picocom -b 115200 /dev/ttyACM0
```

終了は `Ctrl+A` → `Ctrl+X`。端末を開いてからボードのリセットボタンを押すと、
最初の行から見えます。

## 9. 自分のボードを追加する（必要なときだけ）

```sh
bin/bareruby init stm32
```

`config/stm32cube/` に、全項目にコメントの付いた雛形（`.yml.sample`）ができます。
ファイル名の `.sample` を外して中身を書き換えると、そのボードが
`--target=` で指定できるようになります。書き方は [setup.md](setup.md) を
見てください。

## うまくいかないとき

1. `the pinned ARM toolchain is not at ...` と言われる
   → 手順 3 の install.sh をプロジェクトの root から実行してください。
2. `clock: ...` でビルドが止まる
   → ボード設定のクロックがチップの上限を超えています。メッセージがどの数値と
   どの上限かを言っています。
3. ST-LINK が見つからない
   → 手順 6 の usbipd を確認。ケーブルが充電専用でないかも確認してください。
4. シリアルが文字化けする
   → 115200 8N1 になっているか確認し、端末を開いてからリセットしてください。
5. `the pinned Renode is not at ...` と言われる
   → 手順 3 の install.sh をプロジェクトの root から実行してください。実行済みで
   こうなるのは Linux x64 以外の環境で、そこではエミュレートは使えません。

その他は [build.md](build.md) の Troubleshooting にあります。

## 補足: このチェックアウト自体で試す場合

プロジェクトを作らず bareruby-prototype の中で直接試すときは、こう読み替えます。

- `bin/bareruby ...` → `bundle exec ./bareruby ...`
- プログラムは `samples/heartbeat.rb` などを明示する:
  `bundle exec ./bareruby build samples/heartbeat.rb --target=f446`
- install.sh は `gems/bareruby_prot-binding-stm32cube/lib/bareruby_prot/binding/stm32cube/install.sh`
