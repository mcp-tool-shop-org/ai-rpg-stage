<p align="center">
  <a href="README.ja.md">日本語</a> | <a href="README.zh.md">中文</a> | <a href="README.es.md">Español</a> | <a href="README.fr.md">Français</a> | <a href="README.hi.md">हिन्दी</a> | <a href="README.it.md">Italiano</a> | <a href="README.md">English</a>
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

`ai-rpg-stage` renderiza um mundo que outra coisa decide. Ele se conecta a
um processo em execução [`ai-rpg-engine`](https://github.com/mcp-tool-shop-org/ai-rpg-engine) sobre
JSON-RPC, envia o que o jogador está tentando fazer e desenha o que retorna. Ele
não possui regras. Não avança o tempo. Quando discorda da simulação, a
simulação está correta e o cenário diz isso em voz alta.

Essa restrição é o produto. Uma simulação determinística cujo cliente tem permissão
para adivinhar é uma simulação com duas verdades, e a segunda se dessincroniza
silenciosamente. Tudo aqui está organizado de forma que o cenário não possa se tornar a segunda verdade.

**Status:** `0.2.0` — o cenário simulado está jogável. `main` é a linha suportada. Godot **4.7**.

## O que ele desenha

A câmera de jogo é **2:1 dimétrica**: um cenário contínuo em um Godot
`TileMapLayer` (isométrico, diamante para baixo, 256×128 células), ordenado em Y, com
personagens [Sprite Foundry](https://github.com/mcp-tool-shop-org/sprite-foundry) HD
(8 direções, albedo + normal, ponto de pivô do pé) em contato com áreas.
Os edifícios são placas que passam por uma projeção e são divididas em faixas de 128 px, para que a ordenação em Y tenha um elemento desenhável por diamante. As tochas são `PointLight2D`s que
iluminam os mapas de normal dos personagens. A HUD é uma placa, não um painel que ocupa espaço.

A ocupação no motor ainda é um **ID de zona**. Um diamante sob o cursor é uma
visão de uma zona, nunca uma segunda simulação espacial. O contrato que ambos os lados mantêm é
[Visual Clients](https://mcp-tool-shop-org.github.io/ai-rpg-engine/handbook/66-visual-clients/)
no manual do motor.

Quem está onde é **definido previamente**, não improvisado aqui.
[World Forge](https://github.com/mcp-tool-shop-org/world-forge) escreve um
bloco `presentation` em `fixtures/pack.json`: uma linha de ocupação por morador nomeado (personagem, zona, célula, direção e o motivo pelo qual essa célula foi escolhida)
mais a célula âncora de cada zona 3×3. O cenário prefere esse bloco quando o
pacote o carrega, volta para `fixtures/harbour-occupancy.json` quando não o faz e deriva uma célula de canto apenas quando nenhum dos dois existe. O bloco é aditivo
e lido diretamente do objeto fixo; o motor nunca é solicitado a
compreendê-lo.

A arte da cidade está em [`assets/dimetric/`](assets/dimetric/README.md). Cada placa
foi renderizada por meio de uma câmera ortográfica do Blender em X 60° / Z 45° e deve passar
por `assets/dimetric/andon/iso_andon.py` antes que o cenário a carregue. O portão rejeita
a projeção incorreta, alfa ausente, fundos pré-renderizados e qualquer coisa que não esteja na grade de blocos. Nada em `assets/iso/` é carregado; essa pasta está inativa.

## O que existe aqui

| | |
|---|---|
| `client/` | As partes que se comunicam com o motor e vinculam seu vocabulário à árvore de cena: cliente de rede, verificador de resumo canônico, barramento de eventos, fila de ticks, junção de cena, manifesto de eventos, carregador de pacotes Foundry |
| `stage/` | O mundo renderizado: o cenário dimétrico (`stage/iso/`), a iluminação, o mixer e a voz, a HUD de placa, a sessão que os controla |
| `assets/dimetric/` | O kit da cidade: ANDON, script da câmera, blocos de terreno, estruturas, adereços, `MANIFEST.json` |
| `assets/characters/` | Pacotes Foundry HD fornecidos (moradores da cidade) |
| `fixtures/` | Um mundo gerado e sua verdade do lado do fio, comprometidos como um par para que a junção entre eles possa ser verificada |
| `tools/` | O executor de teste sem interface gráfica, a ferramenta de captura de tela, o iniciador de jogo, o conjunto de ferramentas secundárias |
| `tests/` | Dezessete conjuntos de testes, cada um com um controle que faz com que ele falhe |

## Executando-o

Requer Godot **4.7.x** em `PATH` como `godot`. O motor é um checkout irmão
(`../ai-rpg-engine` ou `AI_RPG_ENGINE_DIR`), construído com `npm run build`.

**Play Salt Road** (inicia o processo secundário com o cenário carregado, aguarda a
porta, abre o cenário, desliga a simulação quando a janela é fechada):

```bash
node tools/play.mjs
```

Opções: `--seed <n>` (padrão 71), `--port <n>` (padrão 47820 ou `0` para efêmero),
`--shock <district:metric:delta@round>` ou `--no-shock`, `--engine <dir>`,
`--forge <dir>`, `--unresolved-ai-profile <fail|warn>` (padrão `fail`;
`--release` seleciona `warn` e encaminha `--sidecar-stderr=<log>` para o Godot),
`--godot <bin>` (caminho executável do Godot, padrão `GODOT_BIN` ou `godot`),
`--headless` (inicia a simulação apenas, imprime a porta e aguarda),
`--stage-headless` (inicia o Godot com `--headless` e stdin fechado junto com
a simulação) e `--quit-after-sync <path>` (passa `--quit-after-sync=<path>` para
o Godot para que `Playable` escreva um resumo de sincronização JSON após a anexação e o snapshot de linha de base, desconecte e saia `0`). Observe que um cenário exportado para lançamento nunca inicia a simulação diretamente (ele apenas se anexa por meio de `--attach`):
`fail` vs `warn` vem de `tools/play.mjs` (`--release`), `tools/sidecar_harness.gd`
(`OS.is_debug_build()`) ou CI's `--unresolved-ai-profile fail` explícito.

| Chave | Faz |
|---|---|
| clica em um diamante | caminha até lá; um diamante em uma zona vizinha envia `move` |
| `1`–`9` | caminha por aquela porta |
| `Space` | aguarda uma rodada |
| `I` | mostra o log em prosa |
| `J` | liga/desliga a iluminação da câmera |
| `M` | silencia |
| `Esc` | sai |

**Executa o conjunto** (sem interface gráfica, sem janela; os conjuntos que precisam de uma simulação ativa são ignorados
com uma razão nomeada quando nenhum motor está presente):

```bash
./verify.sh
```

`verify.sh` importa o projeto, executa cada `tests/test_*.gd`, reavalia cada
placa de tempo de execução em `MANIFEST.json` e constrói o site quando `site/` existe.
A mesma coisa manualmente:

```bash
godot --headless --path . --import
godot --headless --path . --script res://tools/headless.gd
godot --headless --path . --script res://tools/headless.gd -- --only=iso_world
```

O executor imprime `PASS:` / `FAIL:` linhas e uma linha `verdict=` e sai
com código de erro em qualquer falha, em um teste que não afirmou nada e em um filtro `--only=`
que não correspondeu a nada. Um filtro é **um** nome de conjunto; uma lista separada por vírgulas não corresponde a nada, e uma execução vazia é uma falha aqui, não um sucesso.

**Gatilhos de CI e filtros de caminho.** GitHub As ações iniciam execuções nos caminhos de projeto monitorados (`project.godot`, `client/**`, `stage/**`, `tools/**`, `tests/**`, `fixtures/**`, `entities/**`, `transitions/**`, `assets/**`, `.github/workflows/**`, `.github/upstream-pins.env`, `atlas/**`) e ignoram `pull_request` tarefas de ramos do mesmo repositório porque os testes correspondentes `push` são executados ao fazer o commit.
Como `on.push.paths` inspeciona apenas o intervalo enviado (`before..after`), enquanto `on.pull_request.paths` inspeciona toda a diferença do PR (`base...head`), um PR do mesmo repositório com commits monitorados anteriores deixa seu SHA no final sem uma execução `headless` após (1) um commit de acompanhamento que não foi monitorado (`README.md`, `CHANGELOG.md`, `site/**`, docs) ou (2) um envio forçado `--amend` que contém apenas a mensagem do commit ou que não foi monitorado — as edições monitoradas já foram executadas no envio, são executadas novamente na mesclagem para `main` (`main^..main`) ou podem ser executadas por meio de `workflow_dispatch`. Em `main`, a concorrência de tarefas mantém uma tarefa em execução mais, no máximo, uma tarefa pendente (`cancel-in-progress: false`), portanto, duas mesclagens rápidas são executadas simultaneamente, enquanto uma terceira mesclagem antes que a primeira termine substitui a segunda, que estava na fila e cujo árvore está incluída.

## Anexando

O estágio estabelece uma conexão **de saída** via TCP com um processo auxiliar que o operador define
(`--attach=host:port` na linha de comando do Godot; `play.mjs` o passa como argumento). O
processo de handshake solicita `capabilities.hashes` (hashes por quadro),
`capabilities.canonicalHashes` (especificação de hash v2 para verificação entre linguagens),
e `capabilities.audio` (a carga útil `felt`: elementos da zona, elementos de sobreposição, a
linha falada, trauma da câmera). `digest_spec_version` não suportado ou ausente faz com que
a conexão falhe, exibindo um erro visível. Até que o `snapshot` inicial e autoritativo
seja recebido, a HUD exibe um estado `syncing` e impede a entrada de comandos (`submitAction`,
`advance` e controles de navegação da HUD). Após cada envio de comando, o estágio
recalcula o hash do estado canônico em relação ao espelho modificado e o compara
com o `canonicalHash` do motor. Em caso de incompatibilidade, registra o primeiro byte diferente
no pré-imagem, solicita um snapshot autoritativo completo, substitui seu espelho e
verifica o hash do snapshot imediatamente; resincronizações consecutivas são limitadas a
3 antes que o jogo pare com um erro visível. Ele nunca modifica a simulação. Apenas
`world.zone.entered` eventos que carregam um `actorId` de nível superior correspondente ao
`playerId` resolvido da sessão movem o nó do jogador, atualizam `_player_zone` e emitem linhas
de chegada à sala.

Um processo auxiliar iniciado com `--content` ainda precisa de `--manifest`; o iniciador passa
`fixtures/salt-road.manifest.json`.

## A conexão e o motivo pelo qual ela possui uma configuração modificada

A simulação se comunica usando IDs de zona. O estágio é uma árvore de nós.
`client/scene_join.gd` transforma um no outro, e `fixtures/` carrega duas
cenas: a exportação real e uma com um único ID de zona alterado. O teste
reconcilia ambas. A cena real deve corresponder em ambas as direções; a cena alterada deve
falhar em ambas as direções, indicando que o ID real está ausente da cena e o
ID alterado está ausente na configuração. Sem a segunda configuração, a primeira prova
apenas que duas listas coincidiram no dia em que foram geradas.

A cena exportada também carrega `metadata/entry_gate*` em zonas restritas. O estágio
nunca a lê para tomar qualquer decisão. As restrições são regras do motor: o estágio envia o
comando e renderiza a recusa que recebe, incluindo o motivo que a pessoa deu para
isso. `client/scene_join.gd` não oferece nenhuma maneira de avaliar uma restrição, intencionalmente.

As configurações são produzidas pelo [World Forge](https://github.com/mcp-tool-shop-org/world-forge)
e registradas aqui, portanto, este repositório não precisa de nenhuma JavaScript cadeia de ferramentas para executar ou
compilar:

```bash
npx tsx dogfood/export-stage-fixture.ts --world=coverage --out=<this-repo>/fixtures --doctor
```

O gerador se recusa a escrever uma configuração com zonas zero, IDs de zona duplicados, uma
contagem de restrições que não corresponde ao mundo definido ou uma zona para a qual a cena não possui
nenhum nó.

## Modelo de confiança e ameaças

**Dados acessados.** O estágio lê a cena, as configurações e as placas neste
repositório, e as JSON-RPC mensagens do único ponto de extremidade do motor ao qual foi direcionado.
Ele grava apenas no diretório de dados do usuário do Godot (cache do editor, logs).

**Dados não acessados.** Nenhum arquivo fora do projeto e do diretório do usuário do Godot.
Nenhuma credencial é lida, armazenada ou enviada; o protocolo de comunicação não é autenticado por
projeto e assume um ponto de extremidade local confiável. **Nenhuma telemetria** é coletada ou
enviada, pelo estágio ou por qualquer coisa que ele inclua. Nenhum código é baixado ou executado
em tempo de execução.

**Permissões.** Uma conexão TCP de saída para o host e a porta que o operador
passa. Não há ponto de extremidade padrão, descoberta ou ouvinte: nada aqui
aceita uma conexão. Quem controla o ponto de extremidade controla o que é renderizado, portanto,
direcione o estágio apenas para um motor em que você confia, em uma rede em que você confia.

**Erros.** Falhas de transporte, conexões recusadas, incompatibilidades de versão do handshake,
obsolescência e limites de sincronização interrompidos são relatados como frases simples na linha de status
e no log (`[stale] state drift at tick N: expected X, mirror Y, first
differing pre-image offset K (resync 1/3)`), nunca como exceções brutas na interface do usuário.
O próprio `--verbose` do Godot ativa o registro em nível de motor; nada que o estágio
registra contém um segredo porque ele nunca o possui.

Política completa e informações de contato para relatórios: [SECURITY.md](SECURITY.md).

## Licença

MIT © mcp-tool-shop. Veja [LICENSE](LICENSE) e [CHANGELOG.md](CHANGELOG.md).

---

<p align="center">Built by <a href="https://mcp-tool-shop.github.io/">MCP Tool Shop</a></p>
