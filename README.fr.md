<p align="center">
  <a href="README.ja.md">日本語</a> | <a href="README.zh.md">中文</a> | <a href="README.es.md">Español</a> | <a href="README.md">English</a> | <a href="README.hi.md">हिन्दी</a> | <a href="README.it.md">Italiano</a> | <a href="README.pt-BR.md">Português (BR)</a>
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

`ai-rpg-stage` crée un monde dont un autre élément décide. Il s’attache à un
programme en cours d’exécution [`ai-rpg-engine`](https://github.com/mcp-tool-shop-org/ai-rpg-engine) sur
JSON-RPC, soumet ce que le joueur essaie de faire et affiche ce qui en ressort. Il
n’a aucune règle. Il ne fait avancer aucune horloge. Lorsqu’il est en désaccord avec la simulation,
la simulation a raison et la scène l’indique à voix haute.

Cette contrainte est le produit. Une simulation déterministe dont le client est autorisé
à deviner est une simulation qui a deux vérités, et la seconde se désynchronise
discrètement. Tout ici est organisé de telle sorte que la scène ne puisse pas devenir la deuxième vérité.

**État :** le port ressenti est jouable. `main` est la ligne prise en charge. Godot **4.7**.

## Ce qu’il affiche

La caméra de jeu est **dimétrique 2:1** : un port continu sur un Godot
`TileMapLayer` (isométrique, diamant vers le bas, 256 x 128 cellules), trié selon l’axe Y, avec
des personnages HD [Sprite Foundry](https://github.com/mcp-tool-shop-org/sprite-foundry)
(8 directions, albedo + normal, pivot du pied) se tenant sur des zones de contact.
Les bâtiments sont des plaques qui passent une grille de projection et sont découpées en bandes de 128 pixels, de sorte que le tri selon l’axe Y ait un élément affichable par diamant. Les torches sont des `PointLight2D` qui
illuminent les cartes de normales des personnages. L’interface utilisateur est une plaque, et non un panneau qui prend de la place.

L’occupation dans le moteur est toujours un **ID de zone**. Un diamant sous le curseur est une
vue d’une zone, et non une deuxième simulation spatiale. Le contrat que les deux parties respectent est
[Visual Clients](https://mcp-tool-shop-org.github.io/ai-rpg-engine/handbook/66-visual-clients/)
dans le manuel du moteur.

Qui se tient où est **défini en amont**, et non improvisé ici.
[World Forge](https://github.com/mcp-tool-shop-org/world-forge) écrit un
bloc `presentation` sur `fixtures/pack.json` : une ligne d’occupation par habitant nommé
(personnage, zone, cellule, orientation et la raison pour laquelle cette cellule a été choisie)
plus la cellule d’ancrage de chaque zone 3 x 3. Le port préfère ce bloc lorsque
le paquet le transporte, revient à `fixtures/harbour-occupancy.json` lorsqu’il ne le fait
pas, et dérive une cellule d’angle uniquement lorsque ni l’un ni l’autre n’existe. Le bloc est additif
et est lu directement à partir de l’élément validé ; on ne demande jamais au moteur de
le comprendre.

L’art de la ville se trouve sous [`assets/dimetric/`](assets/dimetric/README.md). Chaque plaque
a été rendue à l’aide d’une caméra orthographique Blender à X 60° / Z 45° et doit passer
`assets/dimetric/andon/iso_andon.py` avant que la scène ne la charge. La grille refuse
la mauvaise projection, le manque d’alpha, les arrière-plans précalculés et tout ce qui ne se trouve pas sur la grille de tuiles. Rien sous `assets/iso/` n’est chargé ; ce dossier est inactif.

## Ce qui se trouve ici

| | |
|---|---|
| `client/` | Les parties qui communiquent avec le moteur et lient son vocabulaire à l’arborescence de la scène : client réseau, vérificateur de hachage canonique, bus d’événements, file d’attente de ticks, jointure de scène, manifeste d’événements, chargeur de paquet Foundry |
| `stage/` | Le monde rendu : le port dimétrique (`stage/iso/`), le système d’éclairage, le mélangeur et la voix, l’interface utilisateur en plaque, la session qui les alimente |
| `assets/dimetric/` | La trousse de la ville : ANDON, script de caméra, tuiles de sol, structures, accessoires, `MANIFEST.json` |
| `assets/characters/` | Paquets Foundry HD fournis (habitants de la ville) |
| `fixtures/` | Un monde généré et sa vérité du côté filaire, validés en tant que paire afin que la jonction entre eux puisse être vérifiée |
| `tools/` | L’exécuteur de test sans interface, l’outil de capture d’écran, le lanceur de jeu, le système d’exécution secondaire |
| `tests/` | Dix-sept suites de tests, chacune avec un contrôle qui la fait échouer |

## Pour l’exécuter

Nécessite Godot **4.7.x** sur `PATH` en tant que `godot`. Le moteur est une copie de la branche
(`../ai-rpg-engine` ou `AI_RPG_ENGINE_DIR`), compilée avec `npm run build`.

**Jouer à Salt Road** (démarre le système d’exécution secondaire avec le port chargé, attend le
port, ouvre la scène, arrête la simulation lorsque la fenêtre se ferme) :

```bash
node tools/play.mjs
```

Options : `--seed <n>` (par défaut 71), `--port <n>` (par défaut 47820, ou `0` pour une utilisation temporaire),
`--shock <district:metric:delta@round>` ou `--no-shock`, `--engine <dir>`,
`--forge <dir>`, `--unresolved-ai-profile <fail|warn>` (par défaut `fail` ;
`--release` sélectionne `warn` et transmet `--sidecar-stderr=<log>` à Godot),
`--godot <bin>` (chemin d’exécution de Godot, par défaut `GODOT_BIN` ou `godot`),
`--headless` (démarre uniquement la simulation, affiche le port et attend),
`--stage-headless` (lance Godot avec `--headless` et stdin fermé en même temps que
la simulation) et `--quit-after-sync <path>` (transmet `--quit-after-sync=<path>` à
Godot afin que `Playable` écrive un résumé de synchronisation JSON après la connexion et la capture d’instantané de référence, se déconnecte et quitte avec le code `0`). Notez qu’une scène Godot exportée pour la publication ne lance jamais directement la simulation (elle se connecte uniquement via `--attach`) :
`fail` par rapport à `warn` provient de `tools/play.mjs` (`--release`), `tools/sidecar_harness.gd`
(`OS.is_debug_build()`) ou du `--unresolved-ai-profile fail` explicite de CI.

| Clé | Fait |
|---|---|
| clique sur un diamant | se déplace là ; un diamant dans une zone voisine soumet `move` |
| `1`–`9` | traverse cette porte |
| `Space` | attend un tour |
| `I` | affiche le journal textuel |
| `J` | active/désactive les effets visuels de la caméra |
| `M` | muet |
| `Esc` | quitter |

**Exécuter la suite** (sans interface, pas de fenêtre ; les suites qui ont besoin d’une simulation active sautent
avec une raison nommée lorsqu’aucun moteur n’est présent) :

```bash
./verify.sh
```

`verify.sh` importe le projet, exécute chaque `tests/test_*.gd`, réapplique chaque
plaque d’exécution dans `MANIFEST.json` et crée le site lorsque `site/` existe.
La même chose manuellement :

```bash
godot --headless --path . --import
godot --headless --path . --script res://tools/headless.gd
godot --headless --path . --script res://tools/headless.gd -- --only=iso_world
```

L’exécuteur affiche `PASS:` / `FAIL:` lignes et une ligne `verdict=` et quitte
avec un code d’erreur en cas d’échec, sur un test qui n’a rien affirmé et sur un filtre `--only=`
qui n’a rien trouvé. Un filtre est **un** nom de suite ; une liste séparée par des virgules ne correspond à rien, et une exécution vide est un échec ici, et non une réussite.

**Déclencheurs CI et filtres de chemin.** GitHub Actions filtre (conditionne) les exécutions selon les chemins de projet surveillés (`project.godot`, `client/**`, `stage/**`, `tools/**`, `tests/**`, `fixtures/**`, `entities/**`, `transitions/**`, `assets/**`, `.github/workflows/**`, `.github/upstream-pins.env`, `atlas/**`) et ignore `pull_request` tâches provenant des branches du même dépôt, car l’exécution `push` correspondante teste ce commit.
Étant donné que `on.push.paths` n’examine que la plage envoyée (`before..after`), tandis que `on.pull_request.paths` examine l’ensemble des différences de la demande de fusion (`base...head`), une demande de fusion du même dépôt avec des commits surveillés antérieurs laisse son dernier SHA sans exécution `headless` après soit (1) un commit de suivi ne modifiant que des fichiers non surveillés (`README.md`, `CHANGELOG.md`, `site/**`, docs), soit (2) une poussée forcée `--amend` ne modifiant que le message de commit ou que des fichiers non surveillés. Les modifications surveillées ont déjà été exécutées lors de la poussée, elles sont exécutées à nouveau lors de la fusion vers `main` (`main^..main`), ou peuvent être exécutées via `workflow_dispatch`. Sur `main`, la concurrence des tâches maintient une tâche en cours d’exécution et au maximum une tâche en attente (`cancel-in-progress: false`), de sorte que deux fusions rapides s’exécutent toutes les deux, tandis qu’une troisième fusion avant la fin de la première remplace la deuxième tâche en attente, dont elle inclut l’arborescence.

## Connexion

La scène se connecte en **sortant** via TCP à un processus auxiliaire dont le nom est défini par l’opérateur (`--attach=host:port` sur la ligne de commande de Godot ; `play.mjs` le transmet). La séquence d’établissement de la connexion demande `capabilities.hashes` (hachages par image), `capabilities.canonicalHashes` (spécification du hachage v2, vérification de la correspondance entre les différentes versions), et `capabilities.audio` (la charge utile `felt` : éléments de zone, éléments de superposition, la ligne prononcée, traumatisme de la caméra). Si `digest_spec_version` n’est pas pris en charge ou est manquant, l’attachement échoue et une erreur de chargement visible est affichée. Jusqu’à ce que l’autorité initiale `snapshot` soit établie, l’interface utilisateur affiche un état `syncing` et refuse les entrées de jeu (`submitAction`, `advance` et les commandes de navigation de l’interface utilisateur). Après chaque envoi de jeu, la scène recalcule le hachage d’état canonique sur sa copie mise à jour et le compare avec le hachage `canonicalHash` du moteur. En cas de non-correspondance, elle enregistre le premier décalage d’octet de pré-image différent, demande un instantané complet et autoritaire, remplace sa copie et vérifie immédiatement le hachage de l’instantané ; les resynchronisations consécutives sont limitées à 3 avant que le jeu ne s’arrête et qu’une erreur visible ne soit affichée. Elle ne modifie jamais la simulation. Seuls les événements `world.zone.entered` contenant un `actorId` de niveau supérieur correspondant au `playerId` résolu de la session déplacent le nœud du joueur, mettent à jour `_player_zone` et émettent des lignes d’arrivée dans la pièce.

Un processus auxiliaire démarré avec `--content` a toujours besoin de `--manifest` ; le lanceur transmet `fixtures/salt-road.manifest.json`.

## La connexion et la raison pour laquelle elle utilise une configuration modifiée

La simulation utilise des identifiants de zone. La scène est un arbre de nœuds. `client/scene_join.gd` transforme l’un en l’autre, et `fixtures/` contient deux scènes : l’exportation réelle et une version avec un seul identifiant de zone modifié. Le test réconcilie les deux. La version réelle doit correspondre dans les deux sens ; la version modifiée doit échouer dans les deux sens, en indiquant que l’identifiant réel est manquant dans la scène et que l’identifiant modifié est absent du flux de données. Sans la deuxième configuration, la première prouve seulement que deux listes se sont trouvées en accord le jour de leur génération.

La scène exportée contient également `metadata/entry_gate*` sur les zones protégées. La scène ne la lit jamais pour prendre une décision. Les protections sont des règles du moteur : la scène soumet le mouvement et affiche le refus qu’elle reçoit, y compris la raison pour laquelle une personne l’a donné. `client/scene_join.gd` n’offre aucun moyen d’évaluer une protection, intentionnellement.

Les configurations sont produites par [World Forge](https://github.com/mcp-tool-shop-org/world-forge) et validées ici, de sorte que ce dépôt n’a pas besoin d’une chaîne d’outils JavaScript pour fonctionner ou être compilé :

```bash
npx tsx dogfood/export-stage-fixture.ts --world=coverage --out=<this-repo>/fixtures --doctor
```

Le générateur refuse d’écrire une configuration avec zéro zone, des identifiants de zone dupliqués, un nombre de protections qui ne correspond pas au monde défini ou une zone pour laquelle la scène ne contient aucun nœud.

## Modèle de confiance et de menace

**Données concernées.** La scène lit la scène, les configurations et les éléments dans ce dépôt, ainsi que les messages JSON-RPC provenant du seul point de terminaison du moteur auquel elle est connectée. Elle n’écrit que dans le répertoire des données utilisateur de Godot (cache de l’éditeur, journaux).

**Données non concernées.** Aucun fichier en dehors du projet et du répertoire utilisateur de Godot. Aucun identifiant n’est lu, stocké ou envoyé ; le protocole de communication n’est pas authentifié par conception et suppose un point de terminaison local de confiance. **Aucune télémétrie** n’est collectée ou envoyée, ni par la scène, ni par quoi que ce soit qu’elle inclut. Aucun code n’est téléchargé ou exécuté au moment de l’exécution.

**Autorisations.** Une seule connexion TCP sortante vers l’hôte et le port spécifiés par l’opérateur. Il n’y a pas de point de terminaison par défaut, pas de découverte et pas d’écoute : rien ici n’accepte une connexion. Celui qui contrôle le point de terminaison contrôle ce qui est rendu, alors pointez la scène uniquement vers un moteur auquel vous faites confiance, sur un réseau auquel vous faites confiance.

**Erreurs.** Les erreurs de transport, les connexions refusées, les incompatibilités de version de la séquence d’établissement de la connexion, l’obsolescence et les limites de synchronisation interrompues sont signalées sous forme de phrases simples sur la ligne d’état et dans le journal (`[stale] state drift at tick N: expected X, mirror Y, first
differing pre-image offset K (resync 1/3)`), jamais sous forme d’exceptions brutes dans l’interface utilisateur. Le drapeau `--verbose` de Godot active la journalisation au niveau du moteur ; rien de ce que la scène enregistre ne contient de secret, car elle n’en possède jamais un.

Politique complète et coordonnées pour les signalements : [SECURITY.md](SECURITY.md).

## Licence

MIT © mcp-tool-shop. Voir [LICENSE](LICENSE) et [CHANGELOG.md](CHANGELOG.md).

---

<p align="center">Built by <a href="https://mcp-tool-shop.github.io/">MCP Tool Shop</a></p>
