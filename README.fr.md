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

`ai-rpg-stage` crée un monde dont un autre élément décide. Il se connecte à un processus en cours [`ai-rpg-engine`](https://github.com/mcp-tool-shop-org/ai-rpg-engine) via JSON-RPC, soumet ce que le joueur essaie de faire, et affiche ce qui est renvoyé. Il ne contient aucune règle. Il ne fait progresser aucune horloge. Lorsque cela est en désaccord avec la simulation, la simulation a raison et la scène l’indique à voix haute.

Cette contrainte est le produit. Une simulation déterministe dont le client est autorisé à deviner est une simulation avec deux vérités, et la seconde se désynchronise silencieusement. Tout ici est organisé de telle sorte que la scène ne puisse pas devenir la deuxième vérité.

**État :** `0.x`, aucune version étiquetée pour le moment ; `main` est la branche prise en charge. Godot **4.7**.

## Ce qu’il affiche

La caméra du jeu est en **perspective dimétrique 2:1** : un port continu sur un Godot `TileMapLayer` (isométrique, en losange, 256 x 128 cellules), trié selon l’axe Y, avec des personnages HD [Sprite Foundry](https://github.com/mcp-tool-shop-org/sprite-foundry) (8 directions, albedo + normal, pivot du pied) se tenant sur des zones de contact. Les bâtiments sont des plaques qui passent une grille de projection et sont découpées en bandes de 128 pixels, de sorte que le tri selon l’axe Y n’ait qu’un élément à afficher par losange. Les torches sont des `PointLight2D` qui éclairent les cartes de normales des personnages. L’interface utilisateur est une plaque, et non un panneau qui prendrait de la place.

L’occupation dans le moteur est toujours un **ID de zone**. Un losange sous le curseur est une vue d’une zone, et non une deuxième simulation spatiale. Le contrat que les deux parties respectent est [Visual Clients](https://mcp-tool-shop-org.github.io/ai-rpg-engine/handbook/66-visual-clients/) dans le manuel du moteur.

L’art de la ville se trouve sous [`assets/dimetric/`](assets/dimetric/README.md). Chaque plaque a été rendue à travers une caméra orthographique de Blender à X 60° / Z 45° et doit passer `assets/dimetric/andon/iso_andon.py` avant que la scène ne la charge. La grille refuse la mauvaise projection, le manque d’alpha, les arrière-plans précalculés et tout ce qui ne se trouve pas sur la grille de tuiles. Rien sous `assets/iso/` n’est chargé ; ce dossier est inactif.

## Ce qui s’y trouve

| | |
|---|---|
| `client/` | Les parties qui communiquent avec le moteur et lient son vocabulaire à l’arborescence de la scène : client réseau, bus d’événements, file d’attente des cycles, jointure de scène, chargeur de packs Foundry. |
| `stage/` | Le monde rendu : le port dimétrique (`stage/iso/`), le système d’éclairage, le mélangeur et la voix, l’interface utilisateur en plaque, la session qui les contrôle. |
| `assets/dimetric/` | Le kit de la ville : ANDON, script de caméra, tuiles de sol, structures, accessoires, `MANIFEST.json`. |
| `assets/characters/` | Packs HD Foundry fournis (habitants de la ville). |
| `fixtures/` | Un monde généré et sa vérité côté fil, enregistrés par paires afin que la jointure entre eux puisse être vérifiée. |
| `tools/` | Le testeur sans interface graphique, l’outil de capture d’écran, le lanceur de jeu, le système annexe. |
| `tests/` | Onze suites de tests, chacune avec un contrôle qui la fait échouer. |

## Pour l’exécuter

Nécessite Godot **4.7.x** sur `PATH` en tant que `godot`. Le moteur est une copie de la branche (`../ai-rpg-engine` ou `AI_RPG_ENGINE_DIR`), compilée avec `npm run build`.

**Play Salt Road** (démarre le système annexe avec le port chargé, attend le port, ouvre la scène, arrête la simulation lorsque la fenêtre se ferme) :

```bash
node tools/play.mjs
```

Options : `--seed <n>` (par défaut 71), `--port <n>` (par défaut 47820), `--shock <district:metric:delta@round>` ou `--no-shock`, `--engine <dir>`, `--forge <dir>`, `--headless` (démarre uniquement la simulation et affiche le port).

| Clé. | Fait. |
|---|---|
| Clique sur un losange. | Se déplace vers cet endroit ; un losange dans une zone voisine soumet `move`. |
| `1`–`9` | Passe par cette porte. |
| `Space` | Attend un tour. |
| `I` | Affiche le journal narratif. |
| `J` | Active/désactive les effets visuels de la caméra. |
| `M` | Coupe le son. |
| `Esc` | Quitte. |

**Exécute la suite** (sans interface graphique, pas de fenêtre ; les suites qui ont besoin d’une simulation active sont ignorées avec une raison nommée lorsqu’aucun moteur n’est présent) :

```bash
./verify.sh
```

`verify.sh` importe le projet, exécute chaque `tests/test_*.gd`, réapplique chaque plaque d’exécution dans `MANIFEST.json` et construit le site lorsque `site/` existe. La même chose, manuellement :

```bash
godot --headless --path . --import
godot --headless --path . --script res://tools/headless.gd
godot --headless --path . --script res://tools/headless.gd -- --only=iso_world
```

Le testeur affiche `PASS:` / `FAIL:` lignes et une ligne `verdict=` et se termine avec un code de sortie différent de zéro en cas d’échec, sur un test qui n’a rien affirmé et sur un filtre `--only=` qui n’a rien trouvé. Un filtre est **un** nom de suite ; une liste séparée par des virgules ne correspond à rien, et une exécution vide est un échec ici, et non une réussite.

## Connexion

La scène se connecte **en sortie** via TCP à un système annexe dont le nom est spécifié par l’opérateur (`--attach=host:port` sur la ligne de commande de Godot ; `play.mjs` le transmet). Le processus de poignée de main demande `capabilities.hashes` (latence par cycle) et `capabilities.audio` (la charge utile `felt` : éléments de zone, éléments de superposition, la ligne parlée, traumatisme de la caméra). En cas de non-correspondance du hachage, la scène l’indique sur la ligne d’état et dans le journal, cesse de se faire confiance et effectue une nouvelle capture instantanée. Elle ne corrige jamais la simulation.

Un système annexe démarré avec `--content` a toujours besoin de `--manifest` ; le lanceur transmet `fixtures/salt-road.manifest.json`.

## La jointure, et pourquoi elle a un élément modifié

La simulation parle en ID de zone. La scène est un arbre de nœuds. `client/scene_join.gd` transforme l’un en l’autre, et `fixtures/` transporte deux scènes : l’exportation réelle et une où un seul ID de zone est modifié. Le test réconcilie les deux. La version réelle doit correspondre dans les deux sens ; la version modifiée doit échouer dans les deux sens, en indiquant que l’ID réel est manquant dans la scène et que l’ID modifié est absent du flux de données. Sans le deuxième élément, le premier ne prouve que deux listes se sont trouvées en accord le jour de leur génération.

La scène exportée contient également `metadata/entry_gate*` sur les zones validées. La scène ne la lit jamais pour prendre une décision. Les grilles sont des règles du moteur : la scène soumet le mouvement et affiche le refus qu’elle reçoit, y compris la raison pour laquelle une personne l’a donné. `client/scene_join.gd` n’offre aucun moyen d’évaluer une grille, intentionnellement.

Les éléments sont produits par [World Forge](https://github.com/mcp-tool-shop-org/world-forge) et enregistrés ici, de sorte que ce dépôt n’a pas besoin d’une chaîne d’outils JavaScript pour s’exécuter ou pour être compilé :

```bash
npx tsx dogfood/export-stage-fixture.ts --world=coverage --out=<this-repo>/fixtures --doctor
```

Le générateur refuse d’écrire un élément avec zéro zone, des ID de zone en double, un nombre de grilles qui ne correspond pas au monde créé ou une zone pour laquelle la scène ne contient pas de nœud.

## Modèle de confiance et de menace

**Données concernées.** Cette étape lit la scène, les éléments et les textures présents dans ce dépôt, ainsi que les messages JSON-RPC provenant du point de terminaison du moteur auquel elle est connectée. Elle n’écrit que dans le répertoire des données utilisateur de Godot (cache de l’éditeur, journaux).

**Données non concernées.** Aucun fichier en dehors du projet et du répertoire utilisateur de Godot. Aucun identifiant n’est lu, stocké ou envoyé ; le protocole de communication n’est pas authentifié par conception et suppose un point de terminaison local de confiance. **Aucune télémétrie** n’est collectée ou envoyée, ni par cette étape, ni par les éléments qu’elle inclut. Aucun code n’est téléchargé ou exécuté pendant l’exécution.

**Autorisations.** Une seule connexion TCP sortante vers l’hôte et le port spécifiés par l’opérateur. Il n’y a pas de point de terminaison par défaut, pas de découverte et pas d’écouteur : rien ici n’accepte de connexion. Celui qui contrôle le point de terminaison contrôle ce qui est rendu, il faut donc connecter cette étape uniquement à un moteur de confiance, sur un réseau de confiance.

**Erreurs.** Les erreurs de transport, les connexions refusées et les données obsolètes sont signalées sous forme de phrases simples dans la ligne d’état et dans le journal (`[obsolète] dérive de l’état au cycle N : la simulation indique X, l’étape a enregistré Y`), et non sous forme d’exceptions brutes dans l’interface utilisateur. Le drapeau `--verbose` de Godot active la journalisation au niveau du moteur ; rien de ce que l’étape enregistre ne contient de secret, car elle n’en contient jamais.

Politique complète et coordonnées pour les signalements : [SECURITY.md](SECURITY.md).

## Licence

MIT © mcp-tool-shop. Voir [LICENSE](LICENSE) et [CHANGELOG.md](CHANGELOG.md).

---

<p align="center">Built by <a href="https://mcp-tool-shop.github.io/">MCP Tool Shop</a></p>
