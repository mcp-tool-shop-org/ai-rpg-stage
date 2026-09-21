<p align="center">
  <a href="README.ja.md">日本語</a> | <a href="README.md">English</a> | <a href="README.es.md">Español</a> | <a href="README.fr.md">Français</a> | <a href="README.hi.md">हिन्दी</a> | <a href="README.it.md">Italiano</a> | <a href="README.pt-BR.md">Português (BR)</a>
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

`ai-rpg-stage` 渲染了一个由其他事物决定的世界。它连接到一个正在运行的 [`ai-rpg-engine`](https://github.com/mcp-tool-shop-org/ai-rpg-engine)，通过 JSON-RPC 提交玩家想要执行的操作，并绘制返回的结果。它不包含任何规则。它不会推进时间。当它与模拟结果不一致时，模拟结果是正确的，并且舞台会大声地说明这一点。

这种约束就是产品的核心。一个确定性模拟，其客户端被允许进行猜测，就是一个具有两种真相的模拟，而第二种真相会悄悄地导致不同步。这里的一切都经过精心安排，以确保舞台不会成为第二种真相。

**状态：** `0.2.0`——可体验的港口已可运行。`main` 是支持的版本。Godot **4.7**。

## 它绘制的内容

游戏摄像机是 **2:1 等距视角**：一个连续的港口，位于 Godot `TileMapLayer` 中（等距视角，向下倾斜的菱形，256×128 个单元格），按 Y 轴排序，使用 [Sprite Foundry](https://github.com/mcp-tool-shop-org/sprite-foundry) HD 角色（8 个方向，漫反射 + 法线贴图，脚部支点），这些角色站在接触区域上。建筑物是经过投影门的板，并被切分成 128 像素的条，因此 Y 轴排序时，每个菱形都有一个可绘制的元素。火把是 `PointLight2D`，它们照亮角色的法线贴图。HUD 是一个铭牌，而不是一个占用屏幕空间的面板。

在引擎中，占用空间仍然是一个 **区域 ID**。光标下的一个菱形是一个区域的视图，而不是第二个空间模拟。双方都遵守的协议是 [Visual Clients](https://mcp-tool-shop-org.github.io/ai-rpg-engine/handbook/66-visual-clients/)，它在引擎手册中有所说明。

谁站在哪里是 **由上层程序确定的**，而不是在这里即兴创作。 [World Forge](https://github.com/mcp-tool-shop-org/world-forge) 将一个 `presentation` 块写入 `fixtures/pack.json`：每个已命名的城镇居民（角色、区域、单元格、朝向以及选择该单元格的原因）对应一行占用数据，再加上每个区域的 3×3 锚单元格。当数据包携带该块时，港口会优先使用该块；如果没有，则回退到 `fixtures/harbour-occupancy.json`，并且仅当两者都不存在时，才会推导出角单元格。该块是累加的，并且直接从已提交的固定数据中读取；引擎永远不会被要求理解它。

城镇艺术品位于 [`assets/dimetric/`](assets/dimetric/README.md) 下。每个板都通过 Blender 的正交摄像机以 X 60° / Z 45° 的角度进行渲染，并且必须通过 `assets/dimetric/andon/iso_andon.py` 才能被舞台加载。该门会拒绝错误的投影、缺失的 Alpha 通道、烘焙的背景以及任何不在瓦片网格上的内容。任何位于 `assets/iso/` 下的内容都不会被加载；该文件夹已失效。

## 这里有什么

| | |
|---|---|
| `client/` | 与引擎通信并将引擎的词汇表绑定到场景树的部分：网络客户端、事件总线、滴答队列、场景连接、Foundry 数据包加载器 |
| `stage/` | 渲染的世界：等距港口（`stage/iso/`）、灯光设置、可感知的混合器和声音、铭牌 HUD、驱动它们的会话 |
| `assets/dimetric/` | 城镇工具包：ANDON、摄像机脚本、地面瓦片、结构、道具、`MANIFEST.json` |
| `assets/characters/` | 提供的 Foundry HD 数据包（城镇居民） |
| `fixtures/` | 一个生成的世界及其线框侧视图，作为一对提交，以便可以检查它们之间的连接 |
| `tools/` | 无头测试运行器、屏幕截图工具、游戏启动器、辅助程序 |
| `tests/` | 十一个测试套件，每个套件都有一个控制项，可以使其失败 |

## 运行它

需要在 `PATH` 上运行 Godot **4.7.x**，作为 `godot`。引擎是一个并行的检出版本（`../ai-rpg-engine` 或 `AI_RPG_ENGINE_DIR`），使用 `npm run build` 构建。

**运行 Salt Road**（启动带有已加载港口的辅助程序，等待端口，打开舞台，在窗口关闭时关闭模拟）：

```bash
node tools/play.mjs
```

选项：`--seed <n>`（默认值为 71）、`--port <n>`（默认值为 47820）、`--shock <district:metric:delta@round>` 或 `--no-shock`、`--engine <dir>`、`--forge <dir>`、`--headless`（仅启动模拟并打印端口）。

| 按键 | 操作 |
|---|---|
| 点击一个菱形 | 移动到那里；邻近区域中的一个菱形会提交 `move` |
| `1`–`9` | 穿过那扇门 |
| `Space` | 等待一轮 |
| `I` | 显示散文日志 |
| `J` | 开启/关闭摄像机效果 |
| `M` | 静音 |
| `Esc` | 离开 |

**运行套件**（无头模式，没有窗口；需要实时模拟的套件会在没有引擎时跳过，并提供一个命名原因）：

```bash
./verify.sh
```

`verify.sh` 导入项目，运行每个 `tests/test_*.gd`，重新检查 `MANIFEST.json` 中的每个运行时板，并在 `site/` 存在时构建站点。手动执行相同操作：

```bash
godot --headless --path . --import
godot --headless --path . --script res://tools/headless.gd
godot --headless --path . --script res://tools/headless.gd -- --only=iso_world
```

运行器会打印 `PASS:` / `FAIL:` 行和 `verdict=` 行，并在任何失败、没有断言的测试以及 `--only=` 过滤器没有匹配任何内容时以非零状态退出。一个过滤器是 **一个** 套件名称；逗号列表不匹配任何内容，并且在此处，空运行被视为失败，而不是通过。

## 附加

舞台通过 TCP **向外连接**到由操作员命名的辅助程序（在 Godot 的命令行中为 `--attach=host:port`；`play.mjs` 会传递它）。握手请求 `capabilities.hashes`（每个滴答的延迟）和 `capabilities.audio`（`felt` 有效负载：区域茎、叠加字符串、所说的台词、摄像机效果）。如果哈希值不匹配，舞台会在状态行和日志中报告，停止信任自身，并重新快照。它永远不会修补模拟。

使用 `--content` 启动的辅助程序仍然需要 `--manifest`；启动器会传递 `fixtures/salt-road.manifest.json`。

## 连接，以及为什么它具有修改过的固定数据

模拟使用区域 ID 进行通信。舞台是一个节点树。`client/scene_join.gd` 将一个转换为另一个，并且 `fixtures/` 包含两个场景：真实的导出，以及一个只有一个区域 ID 被修改的场景。测试会协调两者。真实的一个必须在两个方向上都匹配；修改的一个必须在两个方向上都失败，并命名真实的 ID 缺失于场景，以及修改的 ID 缺失于线框。如果没有第二个固定数据，第一个只能证明两个列表在生成当天碰巧一致。

导出的场景也包含关于受限区域的`metadata/entry_gate*`信息。场景不会读取这些信息来做出任何决定。门是引擎规则：场景提交移动指令，并渲染返回的拒绝结果，包括拒绝的原因。`client/scene_join.gd`有意不提供任何评估门的方法。

场景组件由[World Forge](https://github.com/mcp-tool-shop-org/world-forge)生成，并提交到此处，因此此仓库不需要 JavaScript 工具链来运行或构建：

```bash
npx tsx dogfood/export-stage-fixture.ts --world=coverage --out=<this-repo>/fixtures --doctor
```

生成器拒绝写入包含零个区域、重复的区域 ID、与已创建世界不一致的门数量，或者场景中没有对应节点的区域的场景组件。

## 信任和威胁模型

**涉及的数据。** 场景读取此仓库中的场景、场景组件和图块，以及从其指向的单个引擎端点接收的 JSON-RPC 消息。它仅写入 Godot 自己的用户数据目录（编辑器缓存、日志）。

**未涉及的数据。** 不涉及项目之外的文件以及 Godot 的用户目录。不读取、存储或发送任何凭据；出于设计考虑，网络协议未进行身份验证，并假定为受信任的本地端点。**不收集或发送任何遥测数据**，无论是来自场景还是其捆绑的任何内容。不会在运行时下载或执行任何代码。

**权限。** 建立一个到操作员指定的宿主机和端口的单向 TCP 连接。没有默认端点、没有发现机制，也没有监听器：这里没有任何内容接受连接。控制端点的人控制渲染的内容，因此请仅将场景指向您信任的引擎，并指向您信任的网络。

**错误。** 传输故障、拒绝的连接和过时状态将作为纯文本句子报告在状态行和日志中（“[过时] 在第 N 帧发生状态漂移：模拟报告 X，场景记录 Y”），绝不会以原始异常的形式显示在 UI 中。Godot 自己的`--verbose`标志会启用引擎级别的日志记录；场景记录的任何内容都不包含任何秘密，因为它从不持有任何秘密。

完整策略和报告联系方式：[SECURITY.md](SECURITY.md)。

## 许可证

MIT © mcp-tool-shop。请参阅[LICENSE](LICENSE)和[CHANGELOG.md](CHANGELOG.md)。

---

<p align="center">Built by <a href="https://mcp-tool-shop.github.io/">MCP Tool Shop</a></p>
