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

`ai-rpg-stage` crea un mondo che qualcos'altro determina. Si connette a un processo in esecuzione [`ai-rpg-engine`](https://github.com/mcp-tool-shop-org/ai-rpg-engine) tramite JSON-RPC, invia ciò che il giocatore sta cercando di fare e visualizza ciò che viene restituito. Non contiene regole. Non fa avanzare il tempo. Quando non è d'accordo con la simulazione, la simulazione ha ragione e la scena lo dichiara ad alta voce.

Questa limitazione è il prodotto. Una simulazione deterministica il cui client è autorizzato a indovinare è una simulazione con due verità, e la seconda si disallinea silenziosamente. Tutto qui è organizzato in modo che la scena non possa diventare la seconda verità.

**Stato:** `0.2.0`: il mondo simulato è giocabile. `main` è la versione supportata. Godot **4.7**.

## Cosa visualizza

La telecamera di gioco è **2:1 dimetrica**: un mondo simulato continuo su Godot `TileMapLayer` (isometrico, con diamanti rivolti verso il basso, 256×128 celle), ordinato in base all'asse Y, con personaggi HD [Sprite Foundry](https://github.com/mcp-tool-shop-org/sprite-foundry) (8 direzioni, albedo + normale, punto di rotazione del piede) posizionati su aree di contatto. Gli edifici sono delle piastre che passano attraverso una griglia di proiezione e vengono suddivise in strisce di 128 pixel, in modo che l'ordinamento in base all'asse Y abbia un elemento disegnabile per ogni diamante. Le torce sono `PointLight2D` che illuminano le mappe normali dei personaggi. L'HUD è una placca, non un pannello che occupa spazio.

L'occupazione nel motore è ancora un **ID di zona**. Un diamante sotto il cursore è una vista di una zona, mai una seconda simulazione spaziale. Il contratto che entrambe le parti rispettano è [Visual Clients](https://mcp-tool-shop-org.github.io/ai-rpg-engine/handbook/66-visual-clients/) nel manuale del motore.

Chi si trova dove è **definito a monte**, non improvvisato qui. [World Forge](https://github.com/mcp-tool-shop-org/world-forge) scrive un blocco `presentation` su `fixtures/pack.json`: una riga di occupazione per ogni abitante della città (personaggio, zona, cella, direzione e il motivo per cui quella cella è stata scelta) più la cella di ancoraggio di ogni zona 3×3. Il mondo simulato preferisce quel blocco quando il pacchetto lo contiene, torna a `fixtures/harbour-occupancy.json` quando non lo contiene e deriva una cella d'angolo solo quando nessuno dei due esiste. Il blocco è additivo e viene letto direttamente dalla struttura definita; non viene mai chiesto al motore di interpretarlo.

L'arte della città si trova in [`assets/dimetric/`](assets/dimetric/README.md). Ogni piastra è stata renderizzata tramite una telecamera ortografica di Blender con X 60° / Z 45° e deve superare `assets/dimetric/andon/iso_andon.py` prima che la scena la carichi. La griglia rifiuta la proiezione errata, l'assenza di alfa, gli sfondi pre-renderizzati e qualsiasi elemento che non si trovi sulla griglia delle celle. Nulla in `assets/iso/` viene caricato; tale cartella è inattiva.

## Cosa c'è qui

| | |
|---|---|
| `client/` | Le parti che comunicano con il motore e collegano il suo vocabolario all'albero delle scene: client di rete, bus di eventi, coda di tick, unione della scena, caricatore del pacchetto Foundry |
| `stage/` | Il mondo renderizzato: il mondo simulato dimetrico (`stage/iso/`), l'illuminazione, il mixer e la voce, l'HUD a placca, la sessione che li gestisce |
| `assets/dimetric/` | Il kit della città: ANDON, script della telecamera, piastrelle del terreno, strutture, oggetti di scena, `MANIFEST.json` |
| `assets/characters/` | Pacchetti Foundry HD forniti (abitanti della città) |
| `fixtures/` | Un mondo generato e la sua verità a livello di codice, salvati come coppia in modo che l'unione tra di essi possa essere verificata |
| `tools/` | Il runner di test headless, lo strumento di screenshot, il launcher del gioco, l'ambiente di test separato |
| `tests/` | Undici suite di test, ognuna con un controllo che la fa fallire |

## Esecuzione

Richiede Godot **4.7.x** su `PATH` come `godot`. Il motore è un checkout fratello (`../ai-rpg-engine` o `AI_RPG_ENGINE_DIR`), compilato con `npm run build`.

**Play Salt Road** (avvia l'ambiente di test con il mondo simulato caricato, attende la porta, apre la scena, arresta la simulazione quando la finestra si chiude):

```bash
node tools/play.mjs
```

Opzioni: `--seed <n>` (predefinito 71), `--port <n>` (predefinito 47820), `--shock <district:metric:delta@round>` o `--no-shock`, `--engine <dir>`, `--forge <dir>`, `--headless` (avvia solo la simulazione e stampa la porta).

| Chiave | Fa |
|---|---|
| clic su un diamante | si sposta lì; un diamante in una zona adiacente invia `move` |
| `1`–`9` | attraversa quella porta |
| `Space` | attende un turno |
| `I` | mostra il log testuale |
| `J` | attiva/disattiva gli effetti visivi della telecamera |
| `M` | silenzia |
| `Esc` | esci |

**Esegui la suite** (headless, senza finestra; le suite che necessitano di una simulazione attiva vengono saltate con una motivazione specifica quando non è presente alcun motore):

```bash
./verify.sh
```

`verify.sh` importa il progetto, esegue ogni `tests/test_*.gd`, ri-applica ogni piastra in fase di esecuzione in `MANIFEST.json` e costruisce il sito quando `site/` esiste. La stessa operazione eseguita manualmente:

```bash
godot --headless --path . --import
godot --headless --path . --script res://tools/headless.gd
godot --headless --path . --script res://tools/headless.gd -- --only=iso_world
```

Il runner stampa `PASS:` / `FAIL:` righe e una riga `verdict=` ed esce con un codice di errore diverso da zero in caso di errore, in caso di test che non ha affermato nulla e in caso di filtro `--only=` che non ha corrisposto a nulla. Un filtro è **un** nome di suite; un elenco separato da virgole non corrisponde a nulla e un'esecuzione vuota è un errore qui, non un successo.

## Collegamento

La scena si connette **in uscita** tramite TCP a un processo secondario il cui nome è specificato dall'operatore (`--attach=host:port` sulla riga di comando di Godot; `play.mjs` lo passa). L'handshake richiede `capabilities.hashes` (latenza per tick) e `capabilities.audio` (il payload `felt`: steli di zona, stringhe di sovrapposizione, la frase pronunciata, il trauma della telecamera). In caso di mancata corrispondenza dell'hash, la scena lo segnala sulla riga di stato e nel log, smette di fidarsi di sé stessa e esegue un nuovo snapshot. Non modifica mai la simulazione.

Un processo secondario avviato con `--content` ha comunque bisogno di `--manifest`; il launcher passa `fixtures/salt-road.manifest.json`.

## L'unione e il motivo per cui ha una struttura modificata

La simulazione comunica tramite ID di zona. La scena è un albero di nodi. `client/scene_join.gd` trasforma uno nell'altro e `fixtures/` contiene due scene: l'esportazione reale e una con un singolo ID di zona modificato. Il test le riconcilia. Quella reale deve corrispondere in entrambe le direzioni; quella modificata deve fallire in entrambe le direzioni, indicando che l'ID reale manca dalla scena e l'ID modificato è assente nel codice. Senza la seconda struttura, la prima dimostra solo che due elenchi sono risultati corrispondenti il giorno in cui sono stati generati.

La scena esportata contiene anche `metadata/entry_gate*` per le zone delimitate. La scena non utilizza mai queste informazioni per prendere decisioni. Le porte sono regole del motore: la scena invia il movimento e visualizza il rifiuto che riceve, inclusa la motivazione fornita dalla persona. `client/scene_join.gd` non offre alcun modo per valutare una porta, intenzionalmente.

Gli elementi grafici sono creati da [World Forge](https://github.com/mcp-tool-shop-org/world-forge) e vengono caricati qui, quindi questo repository non necessita di una catena di strumenti JavaScript per essere eseguito o compilato:

```bash
npx tsx dogfood/export-stage-fixture.ts --world=coverage --out=<this-repo>/fixtures --doctor
```

Il generatore si rifiuta di creare un elemento grafico con zero zone, ID di zona duplicati, un numero di porte che non corrisponde al mondo definito o una zona per la quale la scena non contiene un nodo.

## Modello di fiducia e di minaccia

**Dati utilizzati.** La scena legge la scena, gli elementi grafici e le texture in questo repository, nonché i messaggi JSON-RPC provenienti dall'unico endpoint del motore a cui è indirizzata. Scrive solo nella directory dei dati utente di Godot (cache dell'editor, registri).

**Dati non utilizzati.** Nessun file al di fuori del progetto e della directory utente di Godot. Nessuna credenziale viene letta, archiviata o inviata; il protocollo di comunicazione non è autenticato per impostazione predefinita e presuppone un endpoint locale affidabile. **Non vengono raccolti o inviati dati di telemetria**, né dalla scena né da qualsiasi componente che essa include. Nessun codice viene scaricato o eseguito in fase di esecuzione.

**Autorizzazioni.** Una singola connessione TCP in uscita all'host e alla porta specificati dall'operatore. Non esiste un endpoint predefinito, né un meccanismo di scoperta o un listener: nulla qui accetta una connessione. Chi controlla l'endpoint controlla ciò che viene visualizzato, quindi indirizza la scena solo a un motore di cui ti fidi, su una rete di cui ti fidi.

**Errori.** I guasti di trasmissione, le connessioni rifiutate e i dati obsoleti vengono segnalati come semplici frasi nella riga di stato e nel registro (`[obsoleto] deriva dello stato al tick N: la simulazione riporta X, la scena ha registrato Y`), mai come eccezioni non elaborate nell'interfaccia utente. Il flag `--verbose` di Godot attiva la registrazione a livello di motore; nulla di ciò che la scena registra contiene informazioni sensibili perché non le memorizza mai.

Politica completa e informazioni di contatto per la segnalazione: [SECURITY.md](SECURITY.md).

## Licenza

MIT © mcp-tool-shop. Consulta [LICENSE](LICENSE) e [CHANGELOG.md](CHANGELOG.md).

---

<p align="center">Built by <a href="https://mcp-tool-shop.github.io/">MCP Tool Shop</a></p>
