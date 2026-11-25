<p align="center">
  <a href="README.md">English</a> | <a href="README.zh.md">中文</a> | <a href="README.es.md">Español</a> | <a href="README.fr.md">Français</a> | <a href="README.hi.md">हिन्दी</a> | <a href="README.it.md">Italiano</a> | <a href="README.pt-BR.md">Português (BR)</a>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/mcp-tool-shop-org/brand/main/logos/ai-rpg-stage/readme.png" width="400" alt="AI RPG Stage">
</p>

<p align="center">
  <a href="https://github.com/mcp-tool-shop-org/ai-rpg-stage/actions/workflows/ci.yml"><img src="https://github.com/mcp-tool-shop-org/ai-rpg-stage/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT"></a>
  <a href="https://mcp-tool-shop-org.github.io/ai-rpg-stage/"><img src="https://img.shields.io/badge/Landing_Page-live-blue" alt="Landing Page"></a>
  <a href="https://mcp-tool-shop-org.github.io/ai-rpg-stage/handbook/"><img src="https://img.shields.io/badge/Handbook-read-orange" alt="Handbook"></a>
</p>

<p align="center"><em>A Godot 4 client for a simulation it does not own.</em></p>

---

`ai-rpg-stage`は、他の何かが決定する世界を描き出す。それは、実行中の[`ai-rpg-engine`](https://github.com/mcp-tool-shop-org/ai-rpg-engine)に接続され、
JSON-RPCを通じて、プレイヤーが実行しようとしていることを送信し、その結果を描き出す。ルールは存在しない。時間は進まない。シミュレーションと矛盾する場合、シミュレーションが正しく、ステージがそれを声に出して伝える。

その制約が製品である。クライアントが推測することを許可された決定論的なシミュレーションは、2つの真実を持つシミュレーションであり、2番目の真実は静かに同期が外れる。ここではすべてが、ステージが2番目の真実になることがないように構成されている。

**ステータス:** 体感できる港はプレイ可能である。`main`はサポートされているラインである。Godot **4.7**。

## 描画されるもの

プレイカメラは**2:1のアイソメトリック**である：Godotの`TileMapLayer`（アイソメトリック、ダイヤモンド型、256×128セル）上に、Y軸でソートされた、連続した港があり、[Sprite Foundry](https://github.com/mcp-tool-shop-org/sprite-foundry) HDの
キャラクター（8方向、アルベド+ノーマル、足のピボット）が、接触する領域の上に立っている。建物は、投影ゲートを通過し、128ピクセルのストリップに分割されるプレートであり、そのためY軸ソートでは、ダイヤモンドごとに1つの描画可能なオブジェクトが存在する。トーチは`PointLight2D`であり、キャラクターのノーマルマップを照らす。HUDはパネルではなく、地面を占有しないプレートである。

エンジン内での占有は、依然として**ゾーンID**である。カーソルの下のダイヤモンドは、ゾーンのビューであり、2番目の空間シミュレーションではない。両者が守る契約は、エンジンハンドブックの[Visual Clients](https://mcp-tool-shop-org.github.io/ai-rpg-engine/handbook/66-visual-clients/)である。

誰がどこにいるかは、**事前に定義されており**、ここで即興で作成されるものではない。
[World Forge](https://github.com/mcp-tool-shop-org/world-forge)は、`presentation`ブロックを`fixtures/pack.json`に書き込む：名前付きの町民（キャラクター、ゾーン、セル、向き、およびそのセルが選択された理由）ごとに1つの占有行と、各ゾーンの3×3のアンカーセル。港は、パックがそれを運んでいるときにそのブロックを優先し、そうでない場合は`fixtures/harbour-occupancy.json`にフォールバックし、どちらも存在しない場合にのみコーナーセルを派生させる。ブロックは加算され、コミットされたフィクスチャから直接読み取られる。エンジンは、それを理解する必要はない。

町の美術アセットは、[`assets/dimetric/`](assets/dimetric/README.md)の下に存在する。すべてのプレートは、Blenderの直交カメラを通して、X 60° / Z 45°でレンダリングされ、ステージがそれをロードする前に`assets/dimetric/andon/iso_andon.py`に合格する必要がある。ゲートは、間違った投影、欠落したアルファ、ベイクされた背景、およびタイルグリッド上にないものを拒否する。`assets/iso/`の下にあるものはロードされない。そのフォルダーは使用されない。

## ここに存在するものは

| | |
|---|---|
| `client/` | エンジンと通信し、その語彙をシーンツリーにバインドする部分：ネットワーククライアント、カノニカルダイジェスト検証器、イベントバス、ティックキュー、シーン結合、イベントマニフェスト、Foundryパックローダー |
| `stage/` | レンダリングされた世界：アイソメトリックの港（`stage/iso/`）、照明リグ、体感ミキサーと音声、プレートHUD、それらを駆動するセッション |
| `assets/dimetric/` | 町のキット：ANDON、カメラースクリプト、地面タイル、構造物、プロップス、`MANIFEST.json` |
| `assets/characters/` | ベンダー提供のFoundry HDパック（町民） |
| `fixtures/` | 生成された世界とそのワイヤーフレームの真実。これらはペアとしてコミットされ、それらの間の結合をチェックできる。 |
| `tools/` | ヘッドレスのテストランナー、スクリーンショットツール、プレイランチャー、サイドカーハーネス |
| `tests/` | 17のテストスイート。それぞれに、失敗させるための制御が存在する。 |

## 実行

Godot **4.7.x**を`PATH`にインストールし、`godot`として実行する必要がある。エンジンは、サイドバイサイドのチェックアウト（`../ai-rpg-engine`または`AI_RPG_ENGINE_DIR`）であり、`npm run build`でビルドされる。

**Play Salt Road**（港をロードした状態でサイドカーを開始し、ポートを待機し、ステージを開き、ウィンドウが閉じられたときにシミュレーションを停止する）：

```bash
node tools/play.mjs
```

オプション：`--seed <n>`（既定値 71）、`--port <n>`（既定値 47820、エフェメラルポートの場合は `0`）、`--shock <district:metric:delta@round>` または `--no-shock`、`--engine <dir>`、`--forge <dir>`、`--unresolved-ai-profile <fail|warn>`（既定値 `fail`。`--release` を指定すると `warn` を選択し、`--sidecar-stderr=<log>` を Godot に渡します）、`--godot <bin>`（Godot 実行ファイルのパス。既定値は `GODOT_BIN` または `godot`）、`--headless`（シミュレーションのみを起動し、ポートを表示して待機します）、`--stage-headless`（シミュレーションと並行して、`--headless` と閉じた標準入力で Godot を起動します）、`--quit-after-sync <path>`（`--quit-after-sync=<path>` を Godot に渡し、`Playable` がアタッチとベースラインスナップショットの後に JSON の同期サマリーを書き込み、切断して `0` で終了します）。リリース用にエクスポートされた Godot ステージはシミュレーションを直接起動せず、`--attach` で接続するだけです。`fail` と `warn` のどちらを使うかは、`tools/play.mjs`（`--release`）、`tools/sidecar_harness.gd`（`OS.is_debug_build()`）、または CI が明示的に渡す `--unresolved-ai-profile fail` で決まります。

| キー | 実行 |
|---|---|
| ダイヤモンドをクリックする | そこに移動する。隣接するゾーンのダイヤモンドは、`move`を送信する。 |
| `1`–`9` | そのドアを通り抜ける |
| `Space` | 1ラウンド待つ |
| `I` | プロザログを表示する |
| `J` | カメラエフェクトのオン/オフ |
| `M` | ミュート |
| `Esc` | 終了 |

**スイートを実行する**（ヘッドレス、ウィンドウなし。ライブシミュレーションを必要とするスイートは、エンジンが存在しない場合に、名前付きの理由とともにスキップされる）。

```bash
./verify.sh
```

`verify.sh`はプロジェクトをインポートし、すべての`tests/test_*.gd`を実行し、`MANIFEST.json`内のすべてのランタイムプレートを再ゲートし、`site/`が存在する場合はサイトをビルドする。手動で同じことを行う：

```bash
godot --headless --path . --import
godot --headless --path . --script res://tools/headless.gd
godot --headless --path . --script res://tools/headless.gd -- --only=iso_world
```

ランナーは、`PASS:` / `FAIL:`行と、1つの`verdict=`行を出力し、いずれかの失敗、アサートされていないテスト、または一致するものがない`--only=`フィルターが発生した場合に、ゼロ以外の値で終了する。フィルターは**1つの**スイート名である。カンマ区切りのリストは一致せず、空の実行はここで失敗であり、成功ではない。

**CIトリガーとパスフィルター。** GitHub Actionsは、監視対象のプロジェクトパス（`project.godot`、`client/**`、`stage/**`、`tools/**`、`tests/**`、
`fixtures/**`、`entities/**`、`transitions/**`、`assets/**`、`.github/workflows/**`、
`.github/upstream-pins.env`、`atlas/**`）で実行をゲートし、同じリポジトリのブランチからの`pull_request`ジョブをスキップする。これは、一致する`push`実行がコミットされるためである。
`on.push.paths`は、プッシュされた範囲（`before..after`）のみを検査するのに対し、`on.pull_request.paths`はPR全体の差分（`base...head`）を検査するため、以前に監視対象のコミットを含む同じリポジトリのPRは、どちらかの後に、（1）監視対象ではない後続のコミット（`README.md`、
`CHANGELOG.md`、`site/**`、ドキュメント）または（2）コミットメッセージのみまたは監視対象ではない`--amend`の強制プッシュが発生した場合、その先端SHAに`headless`実行がない状態で終了する。監視対象の編集は、プッシュ時にすでに実行され、`main`（`main^..main`）へのマージ時にもう一度実行するか、または`workflow_dispatch`を介して実行できる。
`main`では、ジョブの同時実行により、1つの実行中のジョブと、最大1つの保留中のジョブが維持される（`cancel-in-progress: false`）。そのため、2つの迅速なマージが両方実行され、最初のマージが完了する前に3番目のマージが発生すると、キューに入れられた2番目のマージが上書きされる。そのマージには、最初のマージのツリーが含まれている。

## アタッチ

ステージはTCP経由で**外部**に接続し、オペレーターが指定するサイドカーに接続する（Godotのコマンドラインで`--attach=host:port`、`play.mjs`を渡す）。ハンドシェイクでは、`capabilities.hashes`（ティックごとのハッシュ）、`capabilities.canonicalHashes`（ダイジェスト仕様v2、クロス言語ミラー検証）、および`capabilities.audio`（`felt`ペイロード：ゾーンステム、オーバーレイストリング、発せられるセリフ、カメラのトラウマ）が要求される。サポートされていない、または欠落している`digest_spec_version`があると、アタッチが失敗し、目に見えるロードエラーが発生する。最初の信頼できる`snapshot`が送信されるまで、HUDには`syncing`状態が表示され、プレイ入力は拒否される（`submitAction`、`advance`、およびHUDナビゲーションコントロール）。プレイが送信されるたびに、ステージはパッチされたミラー上でカノニカル状態ダイジェストを再計算し、エンジンの`canonicalHash`と比較する。不一致がある場合、最初に異なるプリイメージバイトオフセットをログに記録し、完全な信頼できるスナップショットを要求し、ミラーを置き換え、スナップショットのダイジェストを直ちに検証する。連続した再同期は3回に制限され、それ以降はプレイが停止し、目に見えるエラーが発生する。シミュレーションはパッチされない。唯一、トップレベルの`actorId`がセッションで解決された`playerId`と一致する`world.zone.entered`イベントのみが、プレイヤーノードを移動させ、`_player_zone`を更新し、ルーム到着のセリフを発する。

`--content`で起動されたサイドカーは、依然として`--manifest`を必要とする。ランチャーが`fixtures/salt-road.manifest.json`を渡す。

## ジョイン処理と、その理由、および改ざんされたフィクスチャ

シミュレーションはゾーンIDで通信する。ステージはノードのツリーである。`client/scene_join.gd`は、あるノードを別のノードに変換し、`fixtures/`は2つのシーンを保持する：実際のシーンと、単一のゾーンIDが変更されたシーン。テストはこれら両方を調整する。実際のシーンは両方向で一致する必要があり、変更されたシーンは両方向で失敗する必要があり、実際のIDがシーンに存在しないこと、および変更されたIDがワイヤーに存在しないことを示す。2番目のフィクスチャがない場合、最初のフィクスチャは、2つのリストが生成された日に偶然一致したことを示すだけである。

エクスポートされたシーンには、ゲートされたゾーンに`metadata/entry_gate*`も含まれる。ステージは、これを読み込んで、何かを決定することはない。ゲートはエンジンルールである：ステージは移動を送信し、得られた拒否をレンダリングする。これには、その理由も含まれる。`client/scene_join.gd`は、ゲートを評価する方法を提供しない。

フィクスチャは[World Forge](https://github.com/mcp-tool-shop-org/world-forge)によって生成され、ここにコミットされるため、このリポジトリは、実行またはビルドするために、どのJavaScriptツールチェーンも必要としない。

```bash
npx tsx dogfood/export-stage-fixture.ts --world=coverage --out=<this-repo>/fixtures --doctor
```

ジェネレーターは、ゾーンがゼロ、重複するゾーンID、作成された世界と一致しないゲート数、またはシーンにノードが存在しないゾーンを含むフィクスチャの作成を拒否する。

## 信頼と脅威モデル

**アクセスされるデータ。**ステージは、このリポジトリ内のシーン、フィクスチャ、およびプレートと、指定されたエンジンのエンドポイントから受信するJSON-RPCメッセージを読み取る。書き込み先は、Godot自身のユーザーデータディレクトリ（エディターキャッシュ、ログ）のみである。

**アクセスされないデータ。**プロジェクトとGodotのユーザーディレクトリ外のファイルは存在しない。資格情報は読み込まれず、保存されず、送信されない。ワイヤプロトコルは、設計上認証されておらず、信頼できるローカルエンドポイントを前提としている。ステージまたはステージがバンドルするものでも、**テレメトリは収集または送信されない**。実行時にコードはダウンロードまたは実行されない。

**権限。**オペレーターが渡すホストとポートへの単一のTCPアウトバウンド接続。デフォルトのエンドポイント、ディスカバリー、リスナーは存在しない。ここに接続を受け入れるものは何もない。エンドポイントを制御するものが、レンダリングされるものを制御するため、ステージを信頼できるネットワーク上の信頼できるエンジンにのみ接続する。

**エラー。**トランスポート障害、拒否された接続、ハンドシェイクバージョンの不一致、古い状態、および停止した同期キャップは、ステータス行とログにプレーンテキストで報告される（`[stale] state drift at tick N: expected X, mirror Y, first
differing pre-image offset K (resync 1/3)`）。UIに生の例外として表示されることはない。Godot自身の`--verbose`フラグは、エンジンレベルのロギングを有効にする。ステージがログに記録する内容に秘密は含まれない。なぜなら、ステージは秘密を保持しないからである。

完全なポリシーと報告先：[SECURITY.md](SECURITY.md)。

## ライセンス

MIT © mcp-tool-shop。 [LICENSE](LICENSE)および[CHANGELOG.md](CHANGELOG.md)を参照。

---

<p align="center">Built by <a href="https://mcp-tool-shop.github.io/">MCP Tool Shop</a></p>
