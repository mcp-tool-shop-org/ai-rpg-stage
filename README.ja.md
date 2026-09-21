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

`ai-rpg-stage`は、他の何かが決定する世界をレンダリングします。JSON-RPCを介して実行中の[`ai-rpg-engine`](https://github.com/mcp-tool-shop-org/ai-rpg-engine)に接続し、プレイヤーが実行しようとしていることを送信し、その結果を描画します。ルールは一切保持しません。時間経過も進めません。シミュレーションと意見が異なる場合、シミュレーションが正しく、そのことがステージで大声で伝えられます。

その制約が製品です。クライアントが推測することを許可された決定論的なシミュレーションは、2つの真実を持つシミュレーションであり、2番目の真実は静かに同期解除されます。ここではすべて、ステージが2番目の真実にならないように構成されています。

**状況:** `0.2.0` — 実際に使用できる港の地形が作成されました。`main`はサポートされている行です。Godot **4.7**。

## 描画されるもの

ゲームカメラは**2:1のアイソメトリック**です。Godotの`TileMapLayer`（アイソメトリック、ダイヤモンド型、256×128セル）上に、Y軸でソートされた、連続した港が配置されています。また、[Sprite Foundry](https://github.com/mcp-tool-shop-org/sprite-foundry)のHDキャラクター（8方向、アルベド+ノーマル、足のピボット）が、接触するオブジェクトの上に立っています。建物は、投影ゲートを通過し、128ピクセルのストリップに分割されるプレートです。そのため、Y軸ソートでは、ダイヤモンドごとに1つの描画可能なオブジェクトが存在します。トーチは`PointLight2D`であり、キャラクターのノーマルマップを照らします。HUDはパネルではなく、地面に設置されたプレートです。

エンジン内での占有は、依然として**ゾーンID**です。カーソルの下のダイヤモンドは、ゾーンのビューであり、2番目の空間シミュレーションではありません。両者が守る契約は、エンジンハンドブックの[Visual Clients](https://mcp-tool-shop-org.github.io/ai-rpg-engine/handbook/66-visual-clients/)です。

誰がどこにいるかは、ここで即興で決めるのではなく、事前に設定されています。
[World Forge](https://github.com/mcp-tool-shop-org/world-forge) は、
`presentation` ブロックを `fixtures/pack.json` に書き込みます。各名前付きの町民（キャラクター、ゾーン、セル、向き、およびそのセルが選択された理由）に対して、1行の占有情報が記述されます。
さらに、各ゾーンの3×3のアンカーセルも記述されます。港は、そのブロックがパックに含まれている場合に優先的に使用し、含まれていない場合は `fixtures/harbour-occupancy.json` にフォールバックし、どちらも存在しない場合にのみ、角のセルを生成します。このブロックは加算的に処理され、コミットされた固定データから直接読み込まれます。エンジンは、このブロックの内容を理解する必要はありません。

町のグラフィックは、[`assets/dimetric/`](assets/dimetric/README.md)にあります。すべてのプレートは、Blenderの直交投影カメラを使用して、X 60° / Z 45°でレンダリングされ、ステージがロードする前に`assets/dimetric/andon/iso_andon.py`に合格する必要があります。ゲートは、間違った投影、アルファチャンネルの欠落、ベイクされた背景、タイルグリッドにないオブジェクトを拒否します。`assets/iso/`以下のものはロードされません。そのフォルダーは使用されません。

## ここに存在する要素

| | |
|---|---|
| `client/` | エンジンと通信し、その語彙をシーンツリーにバインドする部分：ネットワーククライアント、イベントバス、ティックキュー、シーン結合、Foundryパックローダー |
| `stage/` | レンダリングされた世界：アイソメトリックの港（`stage/iso/`）、照明システム、フェルトミキサーと音声、プレートHUD、それらを駆動するセッション |
| `assets/dimetric/` | 町のキット：ANDON、カメラースクリプト、地面タイル、構造物、小道具、`MANIFEST.json` |
| `assets/characters/` | ベンダー提供のFoundry HDパック（町の人々） |
| `fixtures/` | 生成された世界とそのワイヤーフレームの真実。これらはペアとしてコミットされ、それらの間の結合をチェックできます。 |
| `tools/` | ヘッドレスのテストランナー、スクリーンショットツール、プレイランチャー、サイドカーハーネス |
| `tests/` | 11個のテストスイート。それぞれに、テストが失敗するように設定されたコントロールがあります。 |

## 実行方法

Godot **4.7.x**を`PATH`にインストールし、`godot`として設定する必要があります。エンジンは、兄弟チェックアウト（`../ai-rpg-engine`または`AI_RPG_ENGINE_DIR`）であり、`npm run build`でビルドされます。

**Play Salt Road**（港をロードした状態でサイドカーを開始し、ポートを待ち、ステージを開き、ウィンドウが閉じるとシミュレーションを停止します）。

```bash
node tools/play.mjs
```

オプション：`--seed <n>`（デフォルトは71）、`--port <n>`（デフォルトは47820）、`--shock <district:metric:delta@round>`または`--no-shock`、`--engine <dir>`、`--forge <dir>`、`--headless`（シミュレーションのみを開始し、ポートを出力します）。

| キー | 操作 |
|---|---|
| ダイヤモンドをクリック | そこに移動します。隣接するゾーンのダイヤモンドが`move`を送信します。 |
| `1`–`9` | そのドアを通過します。 |
| `Space` | 1ラウンド待ちます。 |
| `I` | プロットログを表示します。 |
| `J` | カメラエフェクトのオン/オフを切り替えます。 |
| `M` | ミュート |
| `Esc` | 終了 |

**Run the suite**（ヘッドレス、ウィンドウなし。ライブシミュレーションを必要とするスイートは、エンジンが存在しない場合に、名前付きの理由とともにスキップされます）。

```bash
./verify.sh
```

`verify.sh`はプロジェクトをインポートし、すべての`tests/test_*.gd`を実行し、`MANIFEST.json`内のすべてのランタイムプレートを再ゲートし、`site/`が存在する場合はサイトをビルドします。手動で同じことを行うと：

```bash
godot --headless --path . --import
godot --headless --path . --script res://tools/headless.gd
godot --headless --path . --script res://tools/headless.gd -- --only=iso_world
```

ランナーは、`PASS:` / `FAIL:`行と、1つの`verdict=`行を出力し、いずれかのテストが何もアサートしなかった場合、または`--only=`フィルターが何も一致しなかった場合に、ゼロ以外の値で終了します。フィルターは**1つの**スイート名です。カンマ区切りのリストは何も一致せず、空の実行はここで失敗であり、成功ではありません。

## アタッチ

ステージは、オペレーターが指定するサイドカーに**アウトバウンド**でTCP経由で接続します（Godotのコマンドラインで`--attach=host:port`、または`play.mjs`で渡します）。ハンドシェイクでは、`capabilities.hashes`（1ティックあたりの遅延）と`capabilities.audio`（`felt`ペイロード：ゾーンのステム、オーバーレイのストリング、発話された行、カメラのトラウマ）が要求されます。ハッシュが一致しない場合、ステージはステータス行とログに報告し、自己信頼を停止し、再スナップショットします。シミュレーションをパッチすることはありません。

`--content`で起動されたサイドカーは、それでも`--manifest`を必要とします。ランチャーは`fixtures/salt-road.manifest.json`を渡します。

## 結合と、その理由、および修正されたフィクスチャ

シミュレーションはゾーンIDで通信します。ステージはノードのツリーです。`client/scene_join.gd`は、それらを相互に変換し、`fixtures/`は2つのシーンを保持します。1つは実際の出力であり、もう1つは単一のゾーンIDが変更されています。テストは、それらを調整します。実際のものは両方向で一致する必要があり、変更されたものは両方向で失敗する必要があり、実際のIDがシーンに存在しないこと、および変更されたIDがワイヤーに存在しないことを示します。2番目のフィクスチャがない場合、最初のものは、2つのリストが生成された日にたまたま一致したことを証明するだけです。

エクスポートされたシーンには、ゲートされたゾーンに`metadata/entry_gate*`も含まれています。ステージは、これを読み取って何も決定することはありません。ゲートはエンジンルールです。ステージは移動を送信し、受け取った拒否をレンダリングします。これには、その理由も含まれます。`client/scene_join.gd`は、ゲートを評価する方法を提供しません。これは意図的なものです。

フィクスチャは、[World Forge](https://github.com/mcp-tool-shop-org/world-forge)によって生成され、ここにコミットされるため、このリポジトリは、実行またはビルドするためにJavaScriptツールチェーンを必要としません。

```bash
npx tsx dogfood/export-stage-fixture.ts --world=coverage --out=<this-repo>/fixtures --doctor
```

ジェネレーターは、ゾーンがゼロ、重複するゾーンID、作成された世界と一致しないゲート数、またはシーンにノードが存在しないゾーンを含むフィクスチャを書き込むことを拒否します。

## 信頼と脅威モデル

**データへのアクセスあり。** このステージは、指定されたリポジトリ内のシーン、フィクスチャ、およびプレートを読み込み、そのエンジンエンドポイントから JSON-RPC メッセージを受信します。書き込み先は、Godot のユーザーデータディレクトリ（エディターキャッシュ、ログ）のみです。

**データへのアクセスなし。** プロジェクト外のファイルや Godot のユーザーディレクトリ外のファイルにはアクセスしません。認証情報は読み込まれたり、保存されたり、送信されたりしません。ワイヤプロトコルは、設計上認証されておらず、信頼できるローカルエンドポイントを前提としています。ステージまたはステージにバンドルされているものによって、**テレメトリデータは収集または送信されません**。実行時にコードがダウンロードまたは実行されることもありません。

**権限。** 1つのアウトバウンド TCP 接続が、オペレーターが指定するホストとポートに対して確立されます。デフォルトのエンドポイント、ディスカバリー、リスナーはありません。ここでは接続を受け入れるものは何もありません。エンドポイントを制御するものが、レンダリングされる内容を制御するため、信頼できるネットワーク上の信頼できるエンジンのみをステージのターゲットとして指定してください。

**エラー。** 転送エラー、接続拒否、およびタイムアウトは、ステータス行とログにプレーンテキストで報告されます（例：`[stale] state drift at tick N: sim reports X, stage recorded Y`）。UI で生の例外として表示されることはありません。Godot 独自の `--verbose` フラグを有効にすると、エンジンレベルのロギングが有効になります。ステージがログに記録する内容に秘密は含まれません。なぜなら、秘密を保持することがないからです。

完全なポリシーと報告先：[SECURITY.md](SECURITY.md)。

## ライセンス

MIT © mcp-tool-shop。詳細については、[LICENSE](LICENSE) および [CHANGELOG.md](CHANGELOG.md) を参照してください。

---

<p align="center">Built by <a href="https://mcp-tool-shop.github.io/">MCP Tool Shop</a></p>
