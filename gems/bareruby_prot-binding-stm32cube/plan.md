# STM32F4 汎用ビルド基盤 実装計画

## 実装状況（2026-08-05）

「3. 配置と manifest の二層探索」の gem 配置で、F0/F7 を前提にした F4 実装が
このブランチに入った。固定 installer（sources.lock.yml + install.sh）、family 層
（clock 生成器・linker template・HAL 構成）、device/board manifest とその二層探索、
生成 board adapter、manifest 駆動の `targets.rb`、OpenOCD backend、文書を持つ。
旧 CubeIDE/CubeMX 経路（cube.sh、machine/、bareruby_entry.h、外部 project）は
削除済みである。

ボードは NUCLEO-F446RE、NUCLEO-F401RE、STM32F4DISCOVERY の3枚から始める。3枚とも
heartbeat / uart_receive / i2c が clean link し（release と debug）、project 層の
board 追加・上書きと provenance 記録、LED 非搭載ボードの compile-time 拒否も動作を
確認した。CubeF4 `Projects/` 全21ボードへの拡大は、この3枚の実機確認の後に
manifest 追加だけで行う。

`bareruby init stm32` も入った（2026-08-06、ecosystem 側 cli.rb への変更を承認の
うえ）。project 層の雛形（`.yml.sample`、全 field 注釈付き）を
`config/stm32cube/{boards,devices}/` へ書く。`.sample` のままでは build の
`*.yml` glob に掛からず、rename した瞬間から他の manifest と同じ検証を受ける。
CLI 側は dispatch のみで、何を書くかは binding の `init`（`Stm32CubeInit`）が
答える — `toolchain`/`flash` と同じ受け渡しである。board 雛形・device 雛形とも
rename して実ビルドが通ること、冪等（既存 skip）を確認した。

未完了なのは物理ボードを必要とする確認と、ecosystem 側の2変更である。

- [ ] 新しいOpenOCD backendでF446REへ書き込み、verify/resetを確認する。
- [ ] F446REでLD2、USART2、外付けI2Cデバイスを確認する。
- [ ] 利用可能な追加F4ボードでLED、クロック、UART/I2C配線を実機確認する。
- [ ] ローカルcommitをpushした後、GitHub Actions matrixの初回成功を確認する。
- [ ] ecosystem 側: `bareruby install` を追加し、Catalog が family.yml の静的
      `targets:` ではなく登録済み Target から一覧を導くようにする。後者が済むまで、
      project 層のボードはビルドできるが `target list` に現れない。install は
      `init` と同じ穴（CLI → binding の hook）で通せる。

旧CubeIDE/CubeMX経路は削除済みであるため、実機確認で問題が出た場合もboard/device
recordまたは生成器を修正し、外部Cubeプロジェクトへ戻さない。

## 目的

BareRuby の STM32 ターゲットを、STM32CubeIDE、STM32CubeMX、およびユーザーが
別途生成する Cube プロジェクトに依存せずビルドできるようにする。

最終的には、既知の Nucleo/Discovery ボードならターゲットを選ぶだけで、STM32F4
の別品種や自作基板なら小さな MCU/ボード定義を追加するだけで、同じビルド基盤から
ファームウェアを生成できる状態を目指す。

```sh
bareruby install
bareruby build --target=f446 samples/heartbeat.rb --no-exceptions
```

上の操作は ST アカウントを要求せず、必要なコンパイラ、HAL、CMSIS、デバイス情報、
書き込みツールを、バージョンを固定した GitHub 上の配布物から取得する。

## 完了条件

- クリーンな checkout から、明示的なインストールコマンドと `bareruby build` だけで
  NUCLEO-F446RE の ELF を生成できる。
- ビルド時に STM32CubeIDE、STM32CubeMX、`.project`、`.cproject`、`.ioc`、外部 Cube
  プロジェクトを必要としない。
- ビルドが参照する外部資産は `.tools/` 以下に閉じ、URL、バージョンまたは commit、
  SHA-256 をリポジトリ内で固定する。
- F446RE 固有の define、startup、リンカスクリプト、UART/I2C ハンドルを共通
  binding から除去する。
- NUCLEO-F401RE と STM32F4DISCOVERY など、性質の異なる最低 2 種類の F4 ボードを
  追加し、同じ基盤で clean link できることを CI で確認する。
- NUCLEO-F446RE では LED、USART2、既存の BareRuby サンプルの動作を実機確認する。

## 対象外

- 一つの ELF を全 STM32F4 品種で共用すること。startup、割り込みベクタ、メモリ容量
  などが異なるため、ELF は MCU ごとに生成する。
- 未知の自作基板の物理配線を推測すること。MCU の能力と有効な alternate function は
  取得できるが、外付け水晶、LED、センサーなどの実配線はボード定義で指定する。
- 初期実装で STM32F0/F1/F7/H7 など F4 以外へ拡張すること。ただし後から family を
  追加できる構造にする。
- CubeMX の全機能を再実装すること。BareRuby が現在提供する GPIO、UART、I2C、tick、
  DWT delay に必要な範囲から実装する。

## 解消した依存

移行前もコンパイルとリンクは生成 Makefile と `arm-none-eabi-gcc/g++` で行っており、
STM32CubeIDE の builder は使用していなかった。しかし旧 `cube.sh` は次を要求していた。
いずれも削除済みである。

- ユーザー所有の CubeMX 生成済みプロジェクト
- `.project` と `.cproject`
- `Core/`、`Drivers/`、startup、リンカスクリプト
- `main.c` に手作業で追加した `bareruby_entry()` 呼び出し

また、旧共通実装には次の F446RE 固有値が埋め込まれていた。

- `-mcpu=cortex-m4 -mfpu=fpv4-sp-d16 -mfloat-abi=hard`
- `STM32F446xx`
- `huart2`
- `hi2c1`
- GPIOA から GPIOH まで存在するという仮定
- LD2、USART2、I2C1 を初期化済みとする前提

新しい基盤は、これらを family、device、board の三層へ分離した。

## 設計

### 1. 三層の責務

#### Family: STM32F4 共通

- STM32F4 HAL/CMSIS の include と source 構成
- GCC/Makefile の共通規則
- Cortex-M4 の共通ランタイム処理
- HAL tick と DWT delay
- GPIO、UART、I2C の BareRuby binding
- OpenOCD の STM32F4 共通設定

#### Device: MCU 品種・パッケージ固有

- 正式な part number とコンパイル define
- CPU、FPU、float ABI
- startup ファイルの選択
- Flash、SRAM、CCM などのメモリ領域
- 利用可能な GPIO ポートと周辺機能
- 最大クロックと PLL 制約
- リンカスクリプト生成に必要な情報

#### Board: 基板固有

- 搭載 MCU
- HSI/HSE、外付け水晶周波数、PLL プロファイル
- オンボード LED とボタン
- ST-LINK Virtual COM Port に接続された UART
- BareRuby の UART/I2C 論理 ID と実ペリフェラルの対応
- UART/I2C のピン、alternate function、pull、speed
- 書き込み時に使用する probe/transport

### 2. 外部データの取得元

初期バージョンは以下を使用し、`master` や `latest` は参照しない。

| 資産 | 取得元 | 固定方法 |
| --- | --- | --- |
| ARM GCC/Newlib | `xpack-dev-tools/arm-none-eabi-gcc-xpack` の GitHub Release | release と SHA-256 |
| HAL/CMSIS 一式 | `STMicroelectronics/STM32CubeF4` | `v1.28.3` と submodule commit |
| startup/device header | `STMicroelectronics/cmsis-device-f4`。当面は CubeF4 の pinned submodule 経由 | commit |
| MCU pin/AF・公式 board 情報 | `STMicroelectronics/STM32_open_pin_data` | CubeF4 と検証した commit |
| 書き込み/debug | `xpack-dev-tools/openocd-xpack` | release と SHA-256 |

`STM32_open_pin_data` は CubeMX 内部データベースの公開サブセットであり、CubeMX に
依存しない pin/board configuration generator のために公開されている。巨大な XML を
通常ビルドのたびに解析せず、更新ツールが必要な部分だけ正規化してリポジトリ内の
device/board manifest を更新する。

### 3. 配置と manifest の二層探索

binding は gem `bareruby_prot-binding-stm32cube` として配布する。コンパイラは
`bareruby_prot/binding/*/targets.rb` の glob で binding を発見するので、リポジトリ
直下に特別な path は持たない。コードと組み込みデータは gem が持ち、基板固有の
定義はプロジェクトが持つ。二層である。

#### 組み込み層: gem

```text
gems/bareruby_prot-binding-stm32cube/
├── lib/bareruby_prot/binding/stm32cube/
│   ├── targets.rb              # 二層の boards を読み Target/Machine を登録する
│   ├── family.yml              # target add が machine の他に尋ねる事項
│   ├── binding.rb
│   ├── build.rb
│   ├── toolchain.rb
│   ├── flash.rb
│   ├── install.sh              # bareruby install の実体。単体でも実行できる
│   ├── family/
│   │   └── stm32f4/
│   │       ├── runtime/        # 共通 main と board adapter の template
│   │       ├── linker.ld.erb
│   │       └── clock.rb
│   └── data/
│       ├── sources.lock.yml
│       ├── devices/            # stm32f446retx.yml など。全 F4 品種へ拡張できる
│       └── boards/             # CubeF4 Projects を網羅する 21 board records
└── tools/
    ├── update_data.rb          # upstream XML から data/ を正規化する。開発時と CI のみ
    └── validate_data.rb
```

`data/` を lib の下に置くのは、cube.sh と同じく `__dir__` 相対で読むためである。
`tools/` は load path の外へ置き、実行時に読まれないことを配置で言う。

#### ユーザー層: プロジェクト

```text
<project>/config/stm32cube/
├── devices/                    # gem が持たない品種を使うとき
└── boards/                     # 自作基板の定義と、組み込み定義の上書き
```

実行プロセスは Bundler.root に立つので、この path は固定で読める。ここに YAML を
置くだけで target になり、gem の編集も fork も要らない。これが「自作基板は小さな
定義を追加するだけ」の成立条件である。board/device manifest はプロジェクトの事実
なので追跡する。`config/target.yml` が答える「どの composition を建てるか」とは
別の問いである: この層は選択ではなく語彙を増やすので、`compile` が config を
読まない原則とも矛盾しない。

#### 探索と優先

- 同じ key が両層にあればプロジェクト層が勝つ。STM32446E-EVAL の LED のような
  公式データの誤りを、gem のリリースを待たずに机上で正すための経路である。
- どの record がどの層（と gem のどの版）から来たかを build manifest に記録し、
  上書きの発生は `target list` にも表示する。沈黙の shadowing を許さない。
- 許すのはファイル単位の置き換えだけで、フィールド単位の merge はしない。層を
  またぐ参照は board → device の key 参照のみとする。自作基板の大半は「既存
  device + 独自配線」なので、board YAML が組み込み device を指せれば足りる。
- 組み込み層の版は Gemfile が固定する。board/device/sources.lock は gem の版で
  一括して動き、ボード定義の「依存の切り替え」は gem の版指定で行う。

#### 登録の駆動

`targets.rb` は Target.register の静的列挙をやめ、二層の boards/ を読んで
Target.register と Machine.register を回す。`machine/*.rb` の板ごと module は
manifest へ吸収し、生成コードでは書けない特殊処理を持つ板だけが Ruby を持つ。

`family.yml` の `targets:` 静的リストは、manifest と食い違い得る二つ目のリストに
なるので廃止する。Catalog が binding の登録済み Target から一覧を導くよう、
ecosystem 側（`bareruby_prot`）の変更が要る。`bareruby install` の追加と合わせ、
この gem の外へ波及する変更はこの二つだけである。

生成された C、Makefile、リンカースクリプトおよび ELF は従来どおり
`build/<composition>/` 以下に置き、commit しない。外部 SDK と実行バイナリは
`.tools/` 以下へインストールし、commit しない。

### 4. 安定した board adapter

共通 binding から `huart2`、`hi2c1`、`LD2_GPIO_Port` などの CubeMX 生成シンボルを
参照しない。生成された `bareruby_board.h/.c` が、次のような安定した境界を提供する。

```c
void bareruby_board_initialize(void);
UART_HandleTypeDef *bareruby_board_uart(int32_t id);
I2C_HandleTypeDef *bareruby_board_i2c(int32_t id);
GPIO_TypeDef *bareruby_board_gpio_port(int32_t index);
void bareruby_board_onboard_led_write(bool value);
```

board adapter は HAL handle の定義、GPIO clock、MSP 初期化、alternate function、
クロック初期化を所有する。共通 binding は論理 ID のみを渡す。

使用した機能だけを生成・リンクする現在の性質は維持する。例えば OnboardLED を持たない
ボードでも通常プログラムはビルドでき、OnboardLED を実際に使用したときだけ明確な
compile-time error を返す。

### 5. startup とエントリポイント

device manifest が CMSIS Device 内の正しい startup ファイルを選択する。startup は
外部 checkout から直接コンパイルするか build tree へコピーし、BareRuby 側には複製を
持たない。

CubeMX の `main.c` は使用しない。BareRuby が所有する小さな共通 `main` が次を行う。

1. `HAL_Init()`
2. `bareruby_board_initialize()`
3. `bareruby_startup()`
4. `bareruby_main()`

これにより `USER CODE` section と `bareruby_entry()` の手作業統合を廃止する。

### 6. リンカスクリプト生成

リンカスクリプトは device manifest のメモリ領域から生成する。最低限、次を明示する。

- vector table と code を置く Flash
- data/bss/heap/stack を置く SRAM
- MCU が持つ場合の CCM または追加 SRAM bank
- stack/heap の既定サイズ
- entry symbol

単純に全 RAM を一つへ結合せず、異なるバス特性や DMA 制約を持つ領域は別 region として
保持する。初期段階では通常の `.data/.bss/heap/stack` を主 SRAM に置き、CCM 等は名前付き
section として将来利用できるようにする。

生成後に `arm-none-eabi-size`、map file、`readelf -S/-l` で領域外配置がないことを検証する。

### 7. クロック生成

クロックは二つのプロファイルを持つ。

- `hsi-safe`: 外部部品を仮定しない内蔵 HSI ベースの安全な設定。MCU 単体ターゲットの
  既定値とする。
- board profile: 既知の Nucleo/Discovery の HSE/bypass/PLL、bus prescaler、Flash
  latency を明示し、ボードの想定周波数で動かす。

生成器は device の最大 SYSCLK/APB 制約と PLL 入出力範囲を検証し、不正な組み合わせを
ビルド前に拒否する。暗黙の「最大クロックへ設定」は行わない。

### 8. ピンと周辺機能

`STM32_open_pin_data` から得た情報は、次の二つに使う。

- 指定ピンで目的の UART/I2C alternate function が有効かを更新時・テスト時に検証する。
- 公式ボードの LED、VCP UART、Arduino connector などを board manifest の初期値へ変換する。

MCU 単体ターゲットでは周辺機能の「有効な候補」は自動提示できるが、複数候補から勝手に
一つを選ばない。既定値を提供する場合も manifest に明記し、生成 manifest に選択結果を
記録する。

### 9. ツールチェーンのインストール

入口は `bareruby install` である。command 本体は ecosystem gem が持ち、
`config/target.yml` が名指す binding（なければ installed binding 全部）の installer
を呼ぶ。installed gem の中の script への path はユーザーに打たせない。stm32cube の
実体は gem 内の `install.sh` で、CI からは単体でも実行できる。`install.sh` は
次を行う。

1. host OS/architecture を検出する。
2. `sources.lock.yml` の GitHub URLから対応 archive/repository を取得する。
3. archive の SHA-256 を検証してから展開する。
4. STM32CubeF4 の必要 submodule を pinned commit で初期化する。
5. プロジェクト root の `.tools/common/arm/<版>/`、`.tools/stm32cube/<版>/` に、
   版でキーして配置する。lock の変更や branch の切替で別の版が要るとき、再展開
   ではなく共存で切り替わる。
6. `gcc --version`、必要 header、startup、OpenOCD の存在を検証する。

通常の `build` はネットワークアクセスや自動更新を行わない。依存がなければ、実行すべき
インストールコマンドを一行で案内して失敗する。これによりローカルと CI の入力を同じに
する。

### 10. ビルドと書き込み

新しい `build.sh` は外部プロジェクトへファイルをコピーせず、対象の build directory
だけを操作する。

1. device/board manifest を検証する。
2. board adapter、HAL config、main、リンカスクリプトを生成する。
3. pass 12 が到達した BareRuby translation unit を集める。
4. pinned GCC で startup、CMSIS、必要な HAL source、board adapter、BareRuby source を
   コンパイル・リンクする。
5. ELF、map、サイズ情報を composition の build directory に残す。

書き込みは OpenOCD を既定にする。

```sh
openocd \
  -f interface/stlink.cfg \
  -f target/stm32f4x.cfg \
  -c "program bareruby_program.elf verify reset exit"
```

既存の `STM32_PROGRAMMER_CLI` は、環境変数で明示された場合の互換 backend として当面
残せるが、標準セットアップには含めない。

## 実装フェーズ

### Phase 0: 現行 F446RE の基準を固定

- `heartbeat.rb`、`uart_receive.rb`、`i2c.rb` の現行生成物と build manifest を記録する。
- F446RE で必要な HAL module、define、compile/link option をテストとして固定する。
- 実機で LED と USART2 の現行挙動を再確認する。

### Phase 1: GitHub 由来ツールチェーンの固定

- `sources.lock.yml` と `install.sh` を gem 内へ追加し、ecosystem 側へ
  `bareruby install` を追加する。
- xPack GCC 13.2 系、STM32CubeF4 v1.28.3、OpenOCD、open pin data の commit を固定する。
- SHA-256 検証と host architecture 判定を実装する。
- GitHub Actions から同じ installer を使用して toolchain を cache する。

### Phase 2: F446RE プロジェクトをリポジトリ所有へ移行

- F446RE device manifest と NUCLEO-F446RE board manifest を gem の `data/` へ追加する。
- `targets.rb` を manifest 駆動へ変え、`machine/nucleo_f446re.rb` を吸収する。
- Catalog が `family.yml` の `targets:` ではなく登録済み Target から一覧を導くよう
  ecosystem 側を変更する。
- `config/stm32cube/` のユーザー層探索と、プロジェクト層優先・出所の manifest 記録を
  実装する。二層目の実データはまだ要らない。fixture で検査する。
- main、clock、GPIO、USART2、I2C1、MSP、HAL config、リンカスクリプトを生成する。
- `.project/.cproject` の確認と外部 Cube project への同期を削除する。
- 現在の `cube.sh` を build-directory 内だけを扱う `build.sh` に置き換える。
- 現在対応している代表サンプルが clean link することを確認する。

### Phase 3: binding の汎用化

- UART/I2C/LED/GPIO を board adapter 経由へ変更する。
- F446RE 固有 define と CPU option を `build.rb` から device manifest へ移す。
- 存在しない GPIO port や未設定 peripheral を安全に拒否する。
- manifest に MCU、board、clock、pin mapping、依存 commit を出力する。

### Phase 4: upstream data の取り込み器

- `STM32_open_pin_data` XML を読む `tools/update_data.rb` を実装する。
- MCU の pin/AF と公式 board 配線を正規化する。
- 手書き override と upstream 由来値を区別し、更新で手書き設定を消さない。
- `tools/validate_data.rb` で重複ピン、不正 AF、存在しない peripheral、クロック制約違反を
  CI から検査する。

### Phase 5: 複数 F4 デバイスで検証

- NUCLEO-F401RE を追加し、Flash/RAM、startup、device define の違いを検証する。
- STM32F4DISCOVERY（STM32F407VG）を追加し、別クロック、別 LED、別 UART mapping を
  検証する。
- F446RE を含む三つを GitHub Actions の build matrix にする。
- 少なくとも F446RE は実機、可能なら追加ボードも LED/UART まで確認する。

### Phase 6: 書き込みと文書の切り替え

- OpenOCD backend を `flash.rb` に追加して既定にする。
- setup/build/README から CubeMX project 作成手順と STM32CubeProgrammer 必須記述を除く。
- `options.cube_project` と `configuration` の旧形式を廃止し、必要なら一リリースだけ明確な
  migration error を出す。
- API 名 `stm32cube` は STM32Cube HAL を使用する意味で維持する。IDEを指す名称ではない
  ことを文書化する。

## テスト計画

### 単体テスト

- device/board manifest の schema と参照整合性
- 二層探索の優先順位と、上書きの出所が build manifest に記録されること
- target から device/board が一意に選択されること
- GCC option と device define の生成
- リンカスクリプトの memory region と section 配置
- UART/I2C 論理 ID の解決
- GPIO port の存在判定
- HSI/PLL クロック制約
- 不正 pin/alternate function の拒否
- OnboardLED がないボードで未使用なら成功、使用時は明確に失敗すること

### CI build matrix

| Board | MCU | 主な検証点 |
| --- | --- | --- |
| NUCLEO-F446RE | STM32F446RETx | 現行互換、180 MHz profile、USART2、I2C1 |
| NUCLEO-F401RE | STM32F401RETx | 異なる device define、startup、メモリ容量 |
| STM32F4DISCOVERY | STM32F407VGTx | 異なる board clock、LED、peripheral mapping |

各ターゲットで少なくとも `heartbeat.rb` と platform-independent sample を build し、
利用可能な peripheral を持つターゲットでは UART/I2C sample も build する。

### 実機テスト

- OpenOCD による ELF の write、verify、reset
- heartbeat の LED 周期
- `puts` の baud/8N1 と連続出力
- UART receive
- I2C read/write と外部 pull-up
- Debug/Release の双方で起動すること

## リスクと対策

- **upstream の構造変更**: 通常ビルドは正規化済み manifest のみを読み、更新ツールだけを
  upstream XML に依存させる。commit 固定と fixture test で検出する。
- **CMSIS/HAL の版不整合**: STM32CubeF4 の一つの release とその submodule commit を
  lock file で一組として扱い、個別に latest へ更新しない。
- **リンカスクリプト誤り**: map/readelf 検査、メモリ上限 assertion、複数 MCU の link test
  を必須にする。
- **クロック設定誤り**: HSI-safe を fallback にし、PLL は制約検査済みの board profile
  だけを許可する。
- **公式 board data の不足**: upstream 値と手書き override を別レイヤーにし、出典と理由を
  manifest に残す。
- **未使用 HAL の肥大化**: HAL config と source list を機能到達情報から選び、
  `--gc-sections` を維持する。
- **第三者 binary の供給リスク**: GitHub Release URL と SHA-256 を固定し、将来必要なら
  Arm 公式配布物を選べる backend を追加する。GitHub 配布を標準とする場合は xPack が
  Arm 公式 binary そのものではないことを文書化する。

## 最初の実装単位

最初の pull request は Phase 0 から Phase 2 までに限定する。

1. 依存 lock と installer を追加する。
2. F446RE/NUCLEO-F446RE manifest を追加する。
3. F446RE 用 main、clock、pin、HAL config、linker を build tree に生成する。
4. 外部 Cube project なしで既存の代表サンプルを link する。
5. 現行 F446RE 実機挙動を維持する。

この時点では upstream 全 MCU の自動変換を先に作らない。まず既知の F446RE を新しい
境界で成立させ、その後に二つ目の MCU を追加して初めて共通化の妥当性を確認する。
