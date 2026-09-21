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

`ai-rpg-stage` crea un mondo che qualcos'altro decide. Si connette a un
processo in esecuzione [`ai-rpg-engine`](https://github.com/mcp-tool-shop-org/ai-rpg-engine) tramite
JSON-RPC, invia ciò che il giocatore sta cercando di fare e visualizza ciò che viene restituito. Non contiene regole. Non fa avanzare il tempo. Quando non è d'accordo con la simulazione, la
simulazione ha ragione e la scena lo dichiara ad alta voce.

Questa limitazione è il prodotto. Una simulazione deterministica il cui client può fare delle ipotesi è una simulazione con due verità, e la seconda si disallinea silenziosamente. Tutto qui è organizzato in modo che la scena non possa diventare la seconda verità.

**Stato:** `0.x`, ancora nessuna versione con tag; `main` è la versione supportata. Godot **4.7**.

## Cosa visualizza

La telecamera di gioco è **2:1 dimetrica**: un porto continuo su un Godot
`TileMapLayer` (isometrico, con diamanti rivolti verso il basso, 256×128 celle), ordinato in Y, con
personaggi HD di [Sprite Foundry](https://github.com/mcp-tool-shop-org/sprite-foundry) (8 direzioni, albedo + normale, perno del piede) posizionati su aree di contatto.
Gli edifici sono delle piastre che passano attraverso una griglia di proiezione e vengono suddivise in strisce di 128 pixel, in modo che l'ordinamento in Y abbia un elemento disegnabile per ogni diamante. Le torce sono `PointLight2D` che
illuminano le mappe normali dei personaggi. L'HUD è una targa, non un pannello che occupa spazio.

L'occupazione nel motore è ancora un **ID di zona**. Un diamante sotto il cursore è una
vista di una zona, mai una seconda simulazione spaziale. Il contratto che entrambe le parti rispettano è
[Visual Clients](https://mcp-tool-shop-org.github.io/ai-rpg-engine/handbook/66-visual-clients/)
nel manuale del motore.

L'arte della città si trova in [`assets/dimetric/`](assets/dimetric/README.md). Ogni piastra
è stata renderizzata tramite una telecamera ortografica di Blender con X 60° / Z 45° e deve passare
`assets/dimetric/andon/iso_andon.py` prima che la scena la carichi. La griglia rifiuta
la proiezione errata, l'assenza di alfa, gli sfondi pre-renderizzati e qualsiasi cosa che non si trovi sulla griglia delle tessere. Nulla sotto `assets/iso/` viene caricato; quella cartella è inutilizzabile.

## Cosa c'è qui

| | |
|---|---|
| `client/` | Le parti che comunicano con il motore e collegano il suo vocabolario all'albero delle scene: client di rete, bus di eventi, coda di tick, unione della scena, caricatore di pacchetti Foundry |
| `stage/` | Il mondo renderizzato: il porto dimetrico (`stage/iso/`), l'illuminazione, il mixer e la voce, l'HUD a forma di targa, la sessione che li gestisce |
| `assets/dimetric/` | Il kit della città: ANDON, script della telecamera, tessere del terreno, strutture, oggetti di scena, `MANIFEST.json` |
| `assets/characters/` | Pacchetti HD di Foundry forniti (abitanti della città) |
| `fixtures/` | Un mondo generato e la sua verità a livello di codice, salvati come coppia in modo che l'unione tra loro possa essere verificata |
| `tools/` | Il runner di test senza interfaccia grafica, lo strumento di screenshot, il launcher del gioco, l'ambiente di test separato |
| `tests/` | Undici suite di test, ognuna con un controllo che la fa fallire |

## Come eseguirlo

Richiede Godot **4.7.x** su `PATH` come `godot`. Il motore è un checkout parallelo
(`../ai-rpg-engine` o `AI_RPG_ENGINE_DIR`), compilato con `npm run build`.

**Play Salt Road** (avvia l'ambiente di test con il porto caricato, attende la
porta, apre la scena, interrompe la simulazione quando la finestra si chiude):

```bash
node tools/play.mjs
```

Opzioni: `--seed <n>` (predefinito 71), `--port <n>` (predefinito 47820),
`--shock <district:metric:delta@round>` o `--no-shock`, `--engine <dir>`,
`--forge <dir>`, `--headless` (avvia solo la simulazione e stampa la porta).

| Chiave | Fa |
|---|---|
| clic su un diamante | si sposta lì; un diamante in una zona adiacente invia `move` |
| `1`–`9` | attraversa quella porta |
| `Space` | aspetta un turno |
| `I` | mostra il log testuale |
| `J` | attiva/disattiva gli effetti visivi della telecamera |
| `M` | silenzia |
| `Esc` | esci |

**Esegui la suite** (senza interfaccia grafica, senza finestra; le suite che necessitano di una simulazione attiva vengono saltate
con una motivazione specifica quando non è presente alcun motore):

```bash
./verify.sh
```

`verify.sh` importa il progetto, esegue ogni `tests/test_*.gd`, ri-applica ogni
piastra in fase di esecuzione in `MANIFEST.json` e costruisce il sito quando `site/` esiste.
La stessa operazione eseguita manualmente:

```bash
godot --headless --path . --import
godot --headless --path . --script res://tools/headless.gd
godot --headless --path . --script res://tools/headless.gd -- --only=iso_world
```

Il runner stampa `PASS:` / `FAIL:` righe e una riga `verdict=` ed esce
con un codice di errore in caso di fallimento, in caso di un test che non ha affermato nulla e in caso di un filtro `--only=`
che non ha trovato corrispondenze. Un filtro è **una** suite; un elenco separato da virgole non trova corrispondenze e un'esecuzione vuota è un fallimento qui, non un successo.

## Collegamento

La scena si connette **in uscita** tramite TCP a un processo secondario il cui nome è specificato dall'operatore
(`--attach=host:port` sulla riga di comando di Godot; `play.mjs` lo passa).
L'handshake richiede `capabilities.hashes` (latenza per tick) e
`capabilities.audio` (il payload `felt`: steli di zona, stringhe di sovrapposizione, la frase pronunciata, il trauma della telecamera). In caso di mancata corrispondenza dell'hash, la scena lo segnala sulla riga di stato
e nel log, smette di fidarsi di sé stessa e si ricrea. Non modifica mai la simulazione.

Un processo secondario avviato con `--content` ha comunque bisogno di `--manifest`; il launcher passa
`fixtures/salt-road.manifest.json`.

## L'unione e il motivo per cui ha un elemento modificato

La simulazione comunica tramite ID di zona. La scena è un albero di nodi.
`client/scene_join.gd` trasforma uno nell'altro e `fixtures/` contiene due
scene: l'esportazione reale e una con un singolo ID di zona modificato. Il test
riconcilia entrambe. Quella reale deve corrispondere in entrambe le direzioni; quella modificata deve
fallire in entrambe le direzioni, indicando che l'ID reale manca dalla scena e l'ID modificato è assente nel codice. Senza il secondo elemento, il primo dimostra solo che due elenchi sono risultati corrispondenti il giorno in cui sono stati generati.

La scena esportata contiene anche `metadata/entry_gate*` sulle zone con griglia. La scena
non la legge mai per prendere decisioni. Le griglie sono regole del motore: la scena invia il
movimento e visualizza il rifiuto che riceve, inclusa la motivazione fornita dalla persona. `client/scene_join.gd` non offre alcun modo per valutare una griglia, intenzionalmente.

Gli elementi vengono prodotti da [World Forge](https://github.com/mcp-tool-shop-org/world-forge)
e salvati qui, quindi questo repository non ha bisogno di una catena di strumenti JavaScript per essere eseguito o compilato:

```bash
npx tsx dogfood/export-stage-fixture.ts --world=coverage --out=<this-repo>/fixtures --doctor
```

Il generatore rifiuta di scrivere un elemento con zero zone, ID di zona duplicati, un
conteggio delle griglie che non corrisponde al mondo creato o una zona per la quale la scena non contiene un nodo.

## Modello di fiducia e di minaccia

**Dati elaborati.** Questa fase legge la scena, gli elementi grafici e le texture presenti in questo repository, nonché i messaggi JSON-RPC provenienti dall'unico endpoint dell'engine a cui è collegata. Scrive solo nella directory dei dati utente di Godot (cache dell'editor, registri).

**Dati non elaborati.** Nessun file al di fuori del progetto e della directory utente di Godot. Nessuna credenziale viene letta, memorizzata o inviata; il protocollo di comunicazione non è autenticato per impostazione predefinita e presuppone un endpoint locale affidabile. **Non vengono raccolti né inviati dati di telemetria**, né dalla fase né da qualsiasi componente che essa includa. Nessun codice viene scaricato o eseguito in fase di esecuzione.

**Autorizzazioni.** Una singola connessione TCP in uscita verso l'host e la porta specificati dall'operatore. Non è presente alcun endpoint predefinito, né viene eseguita alcuna ricerca o utilizzato alcun listener: nulla qui accetta una connessione. Chi controlla l'endpoint controlla ciò che viene renderizzato, quindi indirizzare la fase solo verso un engine di cui ci si fida, su una rete di cui ci si fida.

**Errori.** I problemi di comunicazione, le connessioni rifiutate e i dati obsoleti vengono segnalati come semplici frasi nella riga di stato e nel registro (`[obsoleto] deriva dello stato al tick N: la simulazione riporta X, la fase ha registrato Y`), mai come eccezioni non elaborate nell'interfaccia utente. Il flag `--verbose` di Godot attiva la registrazione a livello di engine; nulla di ciò che la fase registra contiene informazioni sensibili perché non le memorizza mai.

Politica completa e informazioni di contatto per la segnalazione: [SECURITY.md](SECURITY.md).

## Licenza

MIT © mcp-tool-shop. Consultare [LICENSE](LICENSE) e [CHANGELOG.md](CHANGELOG.md).

---

<p align="center">Built by <a href="https://mcp-tool-shop.github.io/">MCP Tool Shop</a></p>
