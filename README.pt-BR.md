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

`ai-rpg-stage` renderiza um mundo que outra coisa decide. Ele se conecta a um
[`ai-rpg-engine`](https://github.com/mcp-tool-shop-org/ai-rpg-engine) em execução através de
JSON-RPC, envia o que o jogador está tentando fazer e desenha o que retorna. Ele
não possui regras. Não avança o tempo. Quando discorda da simulação, a
simulação está correta e o cenário diz isso em voz alta.

Essa restrição é o produto. Uma simulação determinística cujo cliente tem permissão
para adivinhar é uma simulação com duas verdades, e a segunda se dessincroniza
silenciosamente. Tudo aqui está organizado para que o cenário não possa se tornar a segunda verdade.

**Status:** `0.x`, ainda sem versão com tags; `main` é a versão suportada. Godot **4.7**.

## O que ele desenha

A câmera do jogo é **2:1 dimétrica**: um porto contínuo em um Godot
`TileMapLayer` (isométrico, diamante para baixo, 256×128 células), ordenado em Y, com
personagens HD [Sprite Foundry](https://github.com/mcp-tool-shop-org/sprite-foundry)
(8 direções, albedo + normal, pivô do pé) em pé sobre manchas de contato.
Os edifícios são placas que passam por uma porta de projeção e são divididas em faixas de 128 px, para que a ordenação em Y tenha um elemento desenhável por diamante. As tochas são `PointLight2D`s que
iluminam os mapas de normal dos personagens. A HUD é uma placa, não um painel que ocupa espaço.

A ocupação no motor ainda é um **ID de zona**. Um diamante sob o cursor é uma
visão de uma zona, nunca uma segunda simulação espacial. O contrato que ambos os lados mantêm é
[Visual Clients](https://mcp-tool-shop-org.github.io/ai-rpg-engine/handbook/66-visual-clients/)
no manual do motor.

A arte da cidade está localizada em [`assets/dimetric/`](assets/dimetric/README.md). Cada placa
foi renderizada por meio de uma câmera ortográfica do Blender em X 60° / Z 45° e deve passar
por `assets/dimetric/andon/iso_andon.py` antes que o cenário a carregue. A porta rejeita
a projeção incorreta, alfa ausente, fundos pré-renderizados e qualquer coisa que não esteja na grade de blocos. Nada abaixo de `assets/iso/` é carregado; essa pasta está inativa.

## O que existe aqui

| | |
|---|---|
| `client/` | As partes que se comunicam com o motor e vinculam seu vocabulário à árvore de cena: cliente de rede, barramento de eventos, fila de ticks, junção de cena, carregador de pacotes Foundry |
| `stage/` | O mundo renderizado: o porto dimétrico (`stage/iso/`), a iluminação, o mixer e a voz, a HUD de placa, a sessão que os controla |
| `assets/dimetric/` | O kit da cidade: ANDON, script da câmera, blocos de terreno, estruturas, adereços, `MANIFEST.json` |
| `assets/characters/` | Pacotes HD Foundry fornecidos (cidadãos) |
| `fixtures/` | Um mundo gerado e sua verdade do lado do código, armazenados como um par para que a junção entre eles possa ser verificada |
| `tools/` | O executor de testes sem interface gráfica, a ferramenta de captura de tela, o iniciador do jogo, o conjunto de ferramentas secundárias |
| `tests/` | Onze conjuntos de testes, cada um com um controle que faz com que ele falhe |

## Executando-o

Requer Godot **4.7.x** em `PATH` como `godot`. O motor é um checkout irmão
(`../ai-rpg-engine` ou `AI_RPG_ENGINE_DIR`), construído com `npm run build`.

**Play Salt Road** (inicia o processo secundário com o porto carregado, aguarda a
porta, abre o cenário, desliga a simulação quando a janela é fechada):

```bash
node tools/play.mjs
```

Opções: `--seed <n>` (padrão 71), `--port <n>` (padrão 47820),
`--shock <district:metric:delta@round>` ou `--no-shock`, `--engine <dir>`,
`--forge <dir>`, `--headless` (inicia a simulação apenas e imprime a porta).

| Chave | Faz |
|---|---|
| clique em um diamante | vá até lá; um diamante em uma zona vizinha envia `move` |
| `1`–`9` | atravessar aquela porta |
| `Space` | espere uma rodada |
| `I` | mostre o log de prosa |
| `J` | liga/desliga os efeitos visuais da câmera |
| `M` | silenciar |
| `Esc` | sair |

**Executar o conjunto** (sem interface gráfica, sem janela; os conjuntos que precisam de uma simulação ativa são ignorados
com uma razão nomeada quando nenhum motor está presente):

```bash
./verify.sh
```

`verify.sh` importa o projeto, executa cada `tests/test_*.gd`, re-aplica cada
placa de tempo de execução em `MANIFEST.json` e constrói o site quando `site/` existir.
A mesma coisa manualmente:

```bash
godot --headless --path . --import
godot --headless --path . --script res://tools/headless.gd
godot --headless --path . --script res://tools/headless.gd -- --only=iso_world
```

O executor imprime `PASS:` / `FAIL:` linhas e uma linha `verdict=` e sai
com um código de erro diferente de zero em qualquer falha, em um teste que não afirmou nada e em um filtro `--only=`
que não correspondeu a nada. Um filtro é **um** nome de conjunto; uma lista separada por vírgulas não corresponde a nada, e uma execução vazia é uma falha aqui, não um sucesso.

## Anexando

O cenário se conecta **de saída** por meio de TCP a um processo secundário que o operador nomeia
(`--attach=host:port` na linha de comando do Godot; `play.mjs` o passa).
O handshake solicita `capabilities.hashes` (estagnação por tick) e
`capabilities.audio` (a carga útil `felt`: troncos de zona, strings de sobreposição, a linha falada, trauma da câmera). Em caso de incompatibilidade de hash, o cenário relata isso na linha de status
e no log, para de confiar em si mesmo e faz um novo snapshot. Ele nunca corrige a simulação.

Um processo secundário iniciado com `--content` ainda precisa de `--manifest`; o iniciador passa
`fixtures/salt-road.manifest.json`.

## A junção e por que ela tem um dispositivo modificado

A simulação se comunica em IDs de zona. O cenário é uma árvore de nós.
`client/scene_join.gd` transforma um no outro, e `fixtures/` carrega duas
cenas: a exportação real e uma com um único ID de zona alterado. O teste
reconcilia ambos. O real deve corresponder em ambas as direções; o alterado deve
falhar em ambas as direções, nomeando o ID real como ausente da cena e o
ID alterado como ausente no código. Sem o segundo dispositivo, o primeiro prova
apenas que duas listas por acaso concordaram no dia em que foram geradas.

A cena exportada também carrega `metadata/entry_gate*` em zonas com portões. O cenário
nunca a lê para decidir nada. Os portões são regras do motor: o cenário envia o
movimento e renderiza a recusa que recebe, incluindo o motivo pelo qual uma pessoa deu para isso. `client/scene_join.gd` não oferece nenhuma maneira de avaliar um portão, de propósito.

Os dispositivos são produzidos pelo [World Forge](https://github.com/mcp-tool-shop-org/world-forge)
e armazenados aqui, portanto, este repositório não precisa de nenhuma ferramenta JavaScript para executar ou
construir:

```bash
npx tsx dogfood/export-stage-fixture.ts --world=coverage --out=<this-repo>/fixtures --doctor
```

O gerador se recusa a escrever um dispositivo com zero zonas, IDs de zona duplicados, uma
contagem de portões que não corresponde ao mundo criado ou uma zona para a qual a cena não tem
nenhum nó.

## Modelo de confiança e ameaças

**Dados acessados.** O módulo lê a cena, os objetos e as texturas neste repositório, bem como as mensagens JSON-RPC do único ponto de extremidade do motor ao qual foi direcionado. Ele grava apenas no diretório de dados do usuário do Godot (cache do editor, logs).

**Dados não acessados.** Nenhum arquivo fora do projeto e do diretório de usuário do Godot. Nenhuma credencial é lida, armazenada ou enviada; o protocolo de comunicação não é autenticado por design e assume um ponto de extremidade local confiável. **Nenhuma telemetria** é coletada ou enviada, nem pelo módulo nem por qualquer componente que ele inclua. Nenhum código é baixado ou executado em tempo de execução.

**Permissões.** Uma única conexão TCP de saída para o host e a porta especificados pelo operador. Não há ponto de extremidade padrão, nem descoberta, nem ouvinte: nada aqui aceita uma conexão. Quem controla o ponto de extremidade controla o que é renderizado, portanto, direcione o módulo apenas para um motor em que você confia, em uma rede em que você confia.

**Erros.** Falhas de transporte, conexões recusadas e dados desatualizados são relatados como frases simples na linha de status e no log (`[stale] desvio de estado no ciclo N: a simulação relata X, o módulo registrou Y`), nunca como exceções brutas na interface do usuário. A flag `--verbose` do próprio Godot ativa o registro em nível de motor; nada do que o módulo registra contém um segredo, pois nunca o armazena.

Política completa e informações de contato para relatórios: [SECURITY.md](SECURITY.md).

## Licença

MIT © mcp-tool-shop. Consulte [LICENSE](LICENSE) e [CHANGELOG.md](CHANGELOG.md).

---

<p align="center">Built by <a href="https://mcp-tool-shop.github.io/">MCP Tool Shop</a></p>
