<p align="center">
  <a href="README.ja.md">日本語</a> | <a href="README.zh.md">中文</a> | <a href="README.es.md">Español</a> | <a href="README.fr.md">Français</a> | <a href="README.hi.md">हिन्दी</a> | <a href="README.md">English</a> | <a href="README.pt-BR.md">Português (BR)</a>
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

`ai-rpg-stage` crea un mondo che qualcos'altro determina. Si collega a un
processo [`ai-rpg-engine`](https://github.com/mcp-tool-shop-org/ai-rpg-engine) in esecuzione su
JSON-RPC, invia ciò che il giocatore sta cercando di fare e visualizza il risultato. Non ha regole. Non fa avanzare il tempo. Quando non è d'accordo con la simulazione, la
simulazione ha ragione e la scena lo dichiara ad alta voce.

Questa limitazione è il prodotto. Una simulazione deterministica il cui client è autorizzato
a indovinare è una simulazione con due verità, e la seconda si disallinea
silenziosamente. Tutto qui è organizzato in modo che la scena non possa diventare la seconda verità.

**Stato:** il mondo simulato è giocabile. `main` è la linea supportata. Godot **4.7**.

## Cosa visualizza

La telecamera di gioco è **2:1 dimetrica**: un mondo continuo su un Godot
`TileMapLayer` (isometrico, con diamanti rivolti verso il basso, 256×128 celle), ordinato in Y, con
personaggi HD di [Sprite Foundry](https://github.com/mcp-tool-shop-org/sprite-foundry) (8 direzioni, albedo + normale, perno del piede) posizionati su aree di contatto.
Gli edifici sono delle piastre che passano attraverso una griglia di proiezione e vengono suddivise in strisce di 128 pixel, in modo che l'ordinamento in Y abbia un elemento disegnabile per ogni diamante. Le torce sono `PointLight2D` che
illuminano le mappe normali dei personaggi. L'HUD è una targa, non un pannello che occupa
lo spazio.

L'occupazione nel motore è ancora un **ID di zona**. Un diamante sotto il cursore è una
vista di una zona, mai una seconda simulazione spaziale. Il contratto che entrambe le parti rispettano è
[Visual Clients](https://mcp-tool-shop-org.github.io/ai-rpg-engine/handbook/66-visual-clients/)
nel manuale del motore.

Chi si trova dove è **definito a monte**, non improvvisato qui.
[World Forge](https://github.com/mcp-tool-shop-org/world-forge) scrive un
blocco `presentation` su `fixtures/pack.json`: una riga di occupazione per ogni
abitante (personaggio, zona, cella, direzione e il motivo per cui quella cella è stata scelta)
più la cella di ancoraggio di ogni zona 3×3. Il mondo simulato preferisce quel blocco quando
il pacchetto lo contiene, torna a `fixtures/harbour-occupancy.json` quando non lo fa e deriva una cella d'angolo solo quando nessuno dei due esiste. Il blocco è additivo
e viene letto direttamente dall'elemento configurato; non viene mai chiesto al motore di
interpretarlo.

L'arte della città si trova sotto [`assets/dimetric/`](assets/dimetric/README.md). Ogni piastra
è stata renderizzata tramite una telecamera ortografica di Blender con X 60° / Z 45° e deve passare
`assets/dimetric/andon/iso_andon.py` prima che la scena la carichi. La griglia rifiuta
la proiezione errata, l'assenza di alfa, gli sfondi pre-renderizzati e qualsiasi cosa che non si trovi sulla griglia delle tessere. Nulla sotto `assets/iso/` viene caricato; quella cartella è inutilizzabile.

## Cosa c'è qui

| | |
|---|---|
| `client/` | Le parti che comunicano con il motore e collegano il suo vocabolario all'albero della scena: client di rete, verificatore di digest canonici, bus di eventi, coda di tick, unione della scena, manifesto degli eventi, caricatore di pacchetti Foundry |
| `stage/` | Il mondo renderizzato: il mondo dimetrico (`stage/iso/`), l'illuminazione, il mixer e la voce, l'HUD a forma di targa, la sessione che li gestisce |
| `assets/dimetric/` | Il kit della città: ANDON, script della telecamera, tessere del terreno, strutture, oggetti di scena, `MANIFEST.json` |
| `assets/characters/` | Pacchetti Foundry HD forniti (abitanti della città) |
| `fixtures/` | Un mondo generato e la sua rappresentazione interna, memorizzati come coppia in modo che la connessione tra loro possa essere verificata |
| `tools/` | L'esecutore di test headless, lo strumento di screenshot, il lanciatore di gioco, l'ambiente di test |
| `tests/` | Diciassette suite di test, ognuna con un controllo che le fa fallire |

## Esecuzione

Richiede Godot **4.7.x** su `PATH` come `godot`. Il motore è un checkout fratello
(`../ai-rpg-engine` o `AI_RPG_ENGINE_DIR`), compilato con `npm run build`.

**Esegui Salt Road** (avvia l'ambiente di test con il mondo caricato, attende la
porta, apre la scena, chiude la simulazione quando la finestra si chiude):

```bash
node tools/play.mjs
```

Opzioni: `--seed <n>` (predefinito 71), `--port <n>` (predefinito 47820, o `0` per una porta effimera),
`--shock <district:metric:delta@round>` o `--no-shock`, `--engine <dir>`,
`--forge <dir>`, `--unresolved-ai-profile <fail|warn>` (predefinito `fail`;
`--release` seleziona `warn` e inoltra `--sidecar-stderr=<log>` a Godot),
`--godot <bin>` (percorso dell'eseguibile di Godot, predefinito `GODOT_BIN` o `godot`),
`--headless` (avvia solo la simulazione, stampa la porta e attende),
`--stage-headless` (avvia Godot con `--headless` e stdin chiuso insieme
alla simulazione) e `--quit-after-sync <path>` (passa `--quit-after-sync=<path>` a
Godot in modo che `Playable` scriva un riepilogo di sincronizzazione JSON dopo l'attacco e lo snapshot di base, si disconnette ed esce con codice `0`). Si noti che una scena di Godot esportata per la pubblicazione non avvia mai direttamente la simulazione (si collega solo tramite `--attach`):
`fail` rispetto a `warn` deriva da `tools/play.mjs` (`--release`), `tools/sidecar_harness.gd`
(`OS.is_debug_build()`) o un `--unresolved-ai-profile fail` esplicito di CI.

| Chiave | Fa |
|---|---|
| clicca su un diamante | si sposta lì; un diamante in una zona adiacente invia `move` |
| `1`–`9` | attraversa quella porta |
| `Space` | aspetta un turno |
| `I` | mostra il log testuale |
| `J` | attiva/disattiva gli effetti visivi della telecamera |
| `M` | silenzia |
| `Esc` | esci |

**Esegui la suite** (headless, senza finestra; le suite che necessitano di una simulazione attiva vengono saltate
con una motivazione specifica quando non è presente alcun motore):

```bash
./verify.sh
```

`verify.sh` importa il progetto, esegue ogni `tests/test_*.gd`, ri-applica ogni
elemento grafico in `MANIFEST.json` e crea il sito quando `site/` esiste.
La stessa operazione eseguita manualmente:

```bash
godot --headless --path . --import
godot --headless --path . --script res://tools/headless.gd
godot --headless --path . --script res://tools/headless.gd -- --only=iso_world
```

L'esecutore stampa `PASS:` / `FAIL:` righe e una riga `verdict=` ed esce
con un codice di errore in caso di fallimento, in caso di un test che non ha affermato nulla e in caso di un filtro `--only=`
che non ha trovato corrispondenze. Un filtro è **un** nome di suite; un elenco separato da virgole non trova corrispondenze e un'esecuzione vuota è un fallimento qui, non un successo.

**Trigger CI e filtri di percorso.** Le azioni GitHub avviano le esecuzioni sui percorsi di progetto monitorati (`project.godot`, `client/**`, `stage/**`, `tools/**`, `tests/**`,
`fixtures/**`, `entities/**`, `transitions/**`, `assets/**`, `.github/workflows/**`,
`.github/upstream-pins.env`, `atlas/**`) e saltano i lavori `pull_request` dai
rami dello stesso repository perché i test corrispondenti `push` sono stati eseguiti durante il commit.
Poiché `on.push.paths` ispeziona solo l'intervallo modificato (`before..after`) mentre
`on.pull_request.paths` ispeziona l'intera differenza della PR (`base...head`), una PR dello stesso repository con commit monitorati precedenti lascia il suo SHA finale senza un'esecuzione `headless`
dopo uno dei seguenti eventi: (1) un commit successivo che contiene solo modifiche non monitorate (`README.md`,
`CHANGELOG.md`, `site/**`, documentazione) o (2) un commit che contiene solo modifiche al messaggio di commit o modifiche non monitorate
`--amend` forza-push: le modifiche monitorate sono già state eseguite durante il push, vengono eseguite di nuovo durante il merge in `main` (`main^..main`) o possono essere eseguite tramite `workflow_dispatch`. Su
`main`, la concorrenza dei lavori mantiene un lavoro in esecuzione più al massimo un lavoro in attesa
(`cancel-in-progress: false`), quindi due merge rapidi vengono eseguiti mentre un terzo merge
prima che il primo termini sostituisce il secondo in coda, il cui albero è incluso.

## Collegamento

La scena si connette in modalità **outbound** tramite TCP a un processo secondario il cui nome è specificato dall'operatore (`--attach=host:port` sulla riga di comando di Godot; `play.mjs` lo passa). La fase di handshake richiede `capabilities.hashes` (hash per ogni tick), `capabilities.canonicalHashes` (specifica del digest v2 per la verifica incrociata tra linguaggi) e `capabilities.audio` (il payload `felt`: elementi della zona, elementi sovrapposti, la frase pronunciata, il trauma della telecamera). Se `digest_spec_version` non è supportato o manca, l'attacco fallisce e viene visualizzato un errore di caricamento. Fino a quando non viene ricevuto l'iniziale e definitivo `snapshot`, l'HUD visualizza uno stato `syncing` e rifiuta gli input di gioco (`submitAction`, `advance` e i controlli di navigazione dell'HUD). Dopo ogni invio di gioco, la scena ricalcola il digest dello stato canonico sulla base della sua copia modificata e lo confronta con l'`canonicalHash` del motore. In caso di discrepanza, registra l'offset del primo byte dell'immagine preliminare diverso, richiede uno snapshot completo e definitivo, sostituisce la sua copia e verifica immediatamente il digest dello snapshot; le risincronizzazioni consecutive sono limitate a 3, dopodiché il gioco si interrompe e viene visualizzato un errore. Non modifica mai la simulazione. Solo gli eventi `world.zone.entered` che contengono un `actorId` di livello superiore corrispondente all'`playerId` risolto della sessione spostano il nodo del giocatore, aggiornano `_player_zone` ed emettono le frasi di arrivo nella stanza.

Un processo secondario avviato con `--content` ha comunque bisogno di `--manifest`; il launcher passa `fixtures/salt-road.manifest.json`.

## La connessione e il motivo per cui utilizza un elemento modificato

La simulazione comunica tramite ID di zona. La scena è un albero di nodi. `client/scene_join.gd` trasforma un nodo nell'altro e `fixtures/` contiene due scene: l'esportazione reale e una con un singolo ID di zona modificato. Il test riconcilia entrambe. Quella reale deve corrispondere in entrambe le direzioni; quella modificata deve fallire in entrambe le direzioni, indicando che l'ID reale manca dalla scena e che l'ID modificato è assente dal flusso di dati. Senza il secondo elemento, il primo dimostra solo che due elenchi sono risultati corrispondenti nel giorno in cui sono stati generati.

La scena esportata contiene anche `metadata/entry_gate*` nelle zone protette. La scena non la legge mai per prendere decisioni. Le protezioni sono regole del motore: la scena invia lo spostamento e visualizza il rifiuto che riceve, inclusa la motivazione fornita dalla persona. `client/scene_join.gd` non offre alcun modo per valutare una protezione, intenzionalmente.

Gli elementi di test sono prodotti da [World Forge](https://github.com/mcp-tool-shop-org/world-forge) e vengono inseriti qui, quindi questo repository non necessita di una toolchain JavaScript per essere eseguito o compilato:

```bash
npx tsx dogfood/export-stage-fixture.ts --world=coverage --out=<this-repo>/fixtures --doctor
```

Il generatore rifiuta di scrivere un elemento di test con zero zone, ID di zona duplicati, un conteggio di protezioni che non corrisponde al mondo definito o una zona per la quale la scena non contiene un nodo.

## Modello di fiducia e di minaccia

**Dati interessati.** La scena legge la scena, gli elementi di test e le immagini in questo repository, nonché i messaggi JSON-RPC dall'unico endpoint del motore a cui è stata indirizzata. Scrive solo nella directory dei dati utente di Godot (cache dell'editor, log).

**Dati non interessati.** Nessun file al di fuori del progetto e della directory utente di Godot. Nessuna credenziale viene letta, archiviata o inviata; il protocollo di comunicazione non è autenticato per progettazione e presuppone un endpoint locale affidabile. **Non vengono raccolti né inviati dati di telemetria**, né dalla scena né da qualsiasi elemento che essa include. Nessun codice viene scaricato o eseguito in fase di esecuzione.

**Autorizzazioni.** Una singola connessione TCP in uscita all'host e alla porta specificati dall'operatore. Non esiste un endpoint predefinito, né una funzione di rilevamento, né un listener: nulla qui accetta una connessione. Chi controlla l'endpoint controlla ciò che viene visualizzato, quindi indirizza la scena solo a un motore di cui ti fidi, su una rete di cui ti fidi.

**Errori.** I guasti del trasporto, le connessioni rifiutate, le discrepanze nella versione della fase di handshake, l'obsolescenza e i limiti di sincronizzazione interrotti vengono segnalati come frasi semplici nella riga di stato e nel log (`[stale] state drift at tick N: expected X, mirror Y, first
differing pre-image offset K (resync 1/3)`), mai come eccezioni non elaborate nell'interfaccia utente. L'opzione `--verbose` di Godot attiva la registrazione a livello di motore; nulla di ciò che la scena registra contiene un segreto perché non ne contiene mai uno.

Politica completa e informazioni di contatto per la segnalazione: [SECURITY.md](SECURITY.md).

## Licenza

MIT © mcp-tool-shop. Consulta [LICENSE](LICENSE) e [CHANGELOG.md](CHANGELOG.md).

---

<p align="center">Built by <a href="https://mcp-tool-shop.github.io/">MCP Tool Shop</a></p>
