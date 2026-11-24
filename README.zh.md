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

`ai-rpg-stage` 渲染了一个由其他事物决定的世界。它连接到一个正在运行的 [`ai-rpg-engine`](https://github.com/mcp-tool-shop-org/ai-rpg-engine) 上，通过 JSON-RPC，提交玩家想要执行的操作，并绘制返回的结果。它不包含任何规则。它不会推进时间。当它与模拟结果不一致时，模拟结果是正确的，并且场景会大声地说明这一点。

这种约束就是产品。一个确定性模拟，其客户端被允许进行猜测，就是一个具有两种真相的模拟，而第二种真相会悄悄地不同步。这里的一切都经过精心安排，以确保场景不会成为第二种真相。

**状态：** `0.2.0` ——可体验的港口已可运行。`main` 是支持的线路。Godot **4.7**。

## 它绘制的内容

游戏摄像机是 **2:1 等距视角**：一个连续的港口，位于 Godot `TileMapLayer` 上（等距视角，向下钻石形，256×128 单元），Y 轴排序，使用 [Sprite Foundry](https://github.com/mcp-tool-shop-org/sprite-foundry) HD 角色（8 个方向，漫反射 + 法线，脚部支点），这些角色站在接触区域上。建筑物是经过投影门的板，并被切分成 128 像素的条，因此 Y 轴排序时，每个钻石只有一个可绘制的元素。火炬是 `PointLight2D`，它们照亮角色的法线贴图。HUD 是一个铭牌，而不是一个占用空间的面板。

在引擎中，占用空间仍然是一个 **区域 ID**。光标下的一个钻石是一个区域的视图，而不是第二个空间模拟。双方都遵守的协议是 [Visual Clients](https://mcp-tool-shop-org.github.io/ai-rpg-engine/handbook/66-visual-clients/)，它包含在引擎手册中。

谁站在哪里是 **由上游确定的**，而不是在这里即兴创作。 [World Forge](https://github.com/mcp-tool-shop-org/world-forge) 将一个 `presentation` 块写入 `fixtures/pack.json`：每个已命名的城镇居民（角色、区域、单元、朝向以及选择该单元的原因）对应一行占用空间，再加上每个区域的 3×3 锚单元。当数据包携带该块时，港口会优先使用该块；如果没有，则回退到 `fixtures/harbour-occupancy.json`；并且仅当两者都不存在时，才会派生出一个角单元。该块是累加的，并且直接从已提交的固定资产中读取；引擎不需要理解它。

城镇艺术位于 [`assets/dimetric/`](assets/dimetric/README.md) 下。每个板都通过 Blender 正交摄像机以 X 60° / Z 45° 的角度进行渲染，并且必须通过 `assets/dimetric/andon/iso_andon.py` 才能被场景加载。该门会拒绝错误的投影、缺失的 Alpha 通道、烘焙的背景以及任何不在瓦片网格上的内容。任何位于 `assets/iso/` 下的内容都不会被加载；该文件夹已失效。

## 这里有什么

| | |
|---|---|
| `client/` | 与引擎通信并将引擎的词汇表绑定到场景树的部分：网络客户端、规范摘要验证器、事件总线、滴答队列、场景连接、事件清单、Foundry 数据包加载器 |
| `stage/` | 渲染的世界：等距港口（`stage/iso/`）、灯光设置、可感知的混合器和声音、铭牌 HUD、驱动它们的会话 |
| `assets/dimetric/` | 城镇工具包：ANDON、摄像机脚本、地面瓦片、结构、道具、`MANIFEST.json` |
| `assets/characters/` | 提供的 Foundry HD 数据包（城镇居民） |
| `fixtures/` | 一个生成的世界及其线框侧的真相，作为一对提交，以便可以检查它们之间的连接 |
| `tools/` | 无头测试运行器、屏幕截图工具、游戏启动器、辅助程序 |
| `tests/` | 十七个测试套件，每个套件都有一个控制项，可以使其失败 |

## 运行它

需要在 `PATH` 上运行 Godot **4.7.x**，作为 `godot`。引擎是一个并行检出（`../ai-rpg-engine` 或 `AI_RPG_ENGINE_DIR`），使用 `npm run build` 构建。

**运行 Salt Road**（启动带有已加载港口的辅助程序，等待端口，打开场景，在窗口关闭时关闭模拟）：

```bash
node tools/play.mjs
```

选项：`--seed <n>`（默认 71），`--port <n>`（默认 47820，或 `0` 用于临时使用），`--shock <district:metric:delta@round>` 或 `--no-shock`，`--engine <dir>`，`--forge <dir>`，`--unresolved-ai-profile <fail|warn>`（默认 `fail`；`--release` 选择 `warn` 并将 `--sidecar-stderr=<log>` 转发到 Godot），`--godot <bin>`（Godot 可执行文件路径，默认 `GODOT_BIN` 或 `godot`），`--headless`（仅启动模拟，打印端口并等待），`--stage-headless`（与模拟一起以 `--headless` 和关闭的 stdin 启动 Godot），以及 `--quit-after-sync <path>`（将 `--quit-after-sync=<path>` 传递给 Godot，以便 `Playable` 在连接和基线快照后写入 JSON 同步摘要，断开连接并退出 `0`）。请注意，发布导出的 Godot 场景不会直接启动模拟（它仅通过 `--attach` 进行连接）：`fail` 与 `warn` 来自 `tools/play.mjs`（`--release`）、`tools/sidecar_harness.gd`（`OS.is_debug_build()`）或 CI 的显式 `--unresolved-ai-profile fail`。

| 关键 | 执行 |
|---|---|
| 点击一个钻石 | 移动到那里；相邻区域中的一个钻石提交 `move` |
| `1`–`9` | 穿过那扇门 |
| `Space` | 等待一轮 |
| `I` | 显示文本日志 |
| `J` | 打开/关闭摄像机效果 |
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

运行器会打印 `PASS:` / `FAIL:` 行和一行 `verdict=` 行，并在任何失败、没有断言的测试以及与 `--only=` 过滤器不匹配时退出，返回非零值。一个过滤器是 **一个** 套件名称；逗号列表不匹配任何内容，并且空运行在这里是一个失败，而不是一个通过。

**CI 触发器和路径过滤器。** GitHub Actions 根据监视的项目路径（`project.godot`、`client/**`、`stage/**`、`tools/**`、`tests/**`、`fixtures/**`、`entities/**`、`transitions/**`、`assets/**`、`.github/workflows/**`、`.github/upstream-pins.env`、`atlas/**`）来启动运行，并跳过来自相同仓库分支的 `pull_request` 作业，因为匹配的 `push` 运行测试会提交。由于 `on.push.paths` 仅检查推送的范围（`before..after`），而 `on.pull_request.paths` 检查整个 PR 差异（`base...head`），因此具有早期监视提交的相同仓库 PR，在两者之后（1）一个仅包含未监视的后续提交（`README.md`、`CHANGELOG.md`、`site/**`、文档）或（2）仅包含提交消息或未监视的 `--amend` 强制推送后，其末尾 SHA 将不会进行 `headless` 运行——已监视的编辑已经在推送时运行，在合并到 `main`（`main^..main`）时再次运行，或者可以通过 `workflow_dispatch` 运行。在 `main` 上，作业并发性保持一个正在运行的作业，最多还有一个待处理的作业（`cancel-in-progress: false`），因此，两次快速合并都会在第一个完成之前运行，而第三次合并会取代排队的第二个作业，因为第三次合并包含了第二个作业。

## 连接

该阶段通过 TCP 连接到操作员命名的辅助进程，实现**出站**通信（在 Godot 的命令行中为 `--attach=host:port`；通过 `play.mjs` 传递）。握手阶段会请求 `capabilities.hashes`（每个帧的哈希值）、`capabilities.canonicalHashes`（摘要规范 v2，用于跨语言镜像验证）以及 `capabilities.audio`（`felt` 有效负载：区域片段、叠加片段、对话内容、摄像机视角）。如果缺少或不支持 `digest_spec_version`，则连接会失败，并显示明显的加载错误。在初始权威 `snapshot` 传输完成之前，HUD 会显示 `syncing` 状态，并拒绝任何游戏输入（`submitAction`、`advance` 以及 HUD 导航控件）。每次提交游戏后，该阶段都会根据其已修补的镜像重新计算规范状态摘要，并将其与引擎的 `canonicalHash` 进行比较。如果两者不匹配，它会记录第一个不同的预图像字节偏移量，请求完整的权威快照，替换其镜像，并立即验证快照的摘要；连续的重新同步次数限制为 3 次，之后游戏将停止，并显示明显的错误。它绝不会修补模拟。只有携带与会话解析的 `playerId` 匹配的顶级 `actorId` 的 `world.zone.entered` 事件才会移动玩家节点，更新 `_player_zone`，并触发房间到达事件。

使用 `--content` 启动的辅助进程仍然需要 `--manifest`；启动器传递 `fixtures/salt-road.manifest.json`。

## 连接以及它为何具有经过修改的测试环境

模拟使用区域 ID 进行通信。该阶段是一个节点树。`client/scene_join.gd` 将一个转换为另一个，并且 `fixtures/` 包含两个场景：真实的导出场景和一个只修改了单个区域 ID 的场景。测试会协调这两个场景。真实的场景在两个方向上都必须匹配；修改后的场景在两个方向上都必须失败，并将真实的 ID 标记为场景中缺失，并将修改后的 ID 标记为线路中缺失。如果没有第二个测试环境，第一个测试只能证明两个列表在生成当天碰巧一致。

导出的场景还包含 `metadata/entry_gate*`，用于在受限区域中。该阶段绝不会读取它来决定任何事情。门是引擎规则：该阶段提交移动，并呈现它收到的拒绝信息，包括某人给出的理由。`client/scene_join.gd` 不提供任何评估门的方法，这是故意的。

测试环境由 [World Forge](https://github.com/mcp-tool-shop-org/world-forge) 生成，并在此处提交，因此此仓库不需要任何 JavaScript 工具链来运行或构建：

```bash
npx tsx dogfood/export-stage-fixture.ts --world=coverage --out=<this-repo>/fixtures --doctor
```

生成器拒绝写入包含零个区域、重复的区域 ID、与已编写的世界不一致的门计数，或者场景中没有对应节点的区域的测试环境。

## 信任和威胁模型

**涉及的数据。** 该阶段读取此仓库中的场景、测试环境和图块，以及它指向的唯一引擎端点发送的 JSON-RPC 消息。它仅写入 Godot 自己的用户数据目录（编辑器缓存、日志）。

**不涉及的数据。** 不读取、存储或发送项目和 Godot 用户目录之外的任何文件。不读取、存储或发送任何凭据；线路协议的设计中不进行身份验证，并假定为受信任的本地端点。**不收集或发送任何遥测数据**，无论是来自该阶段还是它捆绑的任何内容。运行时不下载或执行任何代码。

**权限。** 向操作员传递的主机和端口建立一个向外的 TCP 连接。没有默认端点、没有发现机制，也没有监听器：这里没有任何东西接受连接。控制端点的人控制呈现的内容，因此请仅将该阶段指向您信任的引擎，并指向您信任的网络。

**错误。** 传输故障、拒绝的连接、握手版本不匹配、过时和停止的同步都会报告为状态行和日志中的纯文本句子（`[stale] state drift at tick N: expected X, mirror Y, first
differing pre-image offset K (resync 1/3)`），而不是 UI 中的原始异常。Godot 自己的 `--verbose` 标志会启用引擎级别的日志记录；该阶段记录的任何内容都不包含任何秘密，因为它从不持有任何秘密。

完整策略和报告联系方式：[SECURITY.md](SECURITY.md)。

## 许可证

MIT © mcp-tool-shop。请参阅 [LICENSE](LICENSE) 和 [CHANGELOG.md](CHANGELOG.md)。

---

<p align="center">Built by <a href="https://mcp-tool-shop.github.io/">MCP Tool Shop</a></p>
