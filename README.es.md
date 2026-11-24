<p align="center">
  <a href="README.ja.md">日本語</a> | <a href="README.zh.md">中文</a> | <a href="README.md">English</a> | <a href="README.fr.md">Français</a> | <a href="README.hi.md">हिन्दी</a> | <a href="README.it.md">Italiano</a> | <a href="README.pt-BR.md">Português (BR)</a>
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

`ai-rpg-stage` representa un mundo que otra entidad decide. Se conecta a un
proceso en ejecución [`ai-rpg-engine`](https://github.com/mcp-tool-shop-org/ai-rpg-engine) sobre
JSON-RPC, envía lo que el jugador intenta hacer y muestra lo que se devuelve. No
tiene reglas. No avanza el tiempo. Cuando no está de acuerdo con la simulación,
la simulación tiene la razón y el escenario lo dice en voz alta.

Esa restricción es el producto. Una simulación determinista cuyo cliente puede
adivinar es una simulación con dos verdades, y la segunda se desincroniza
silenciosamente. Todo aquí está organizado de tal manera que el escenario no puede convertirse en la segunda verdad.

**Estado:** `0.2.0`: el puerto simulado es jugable. `main` es la línea compatible. Godot **4.7**.

## Lo que muestra

La cámara de juego es **2:1 dimétrica**: un puerto continuo en un Godot
`TileMapLayer` (isométrico, diamante hacia abajo, 256×128 celdas), ordenado en Y, con
personajes HD de [Sprite Foundry](https://github.com/mcp-tool-shop-org/sprite-foundry) (8 direcciones, albedo + normal, pivote de pie) que se encuentran sobre manchas de contacto.
Los edificios son placas que pasan por una puerta de proyección y se dividen en franjas de 128 píxeles, de modo que el orden en Y tiene un elemento dibujable por diamante. Las antorchas son `PointLight2D` que
iluminan los mapas de normales de los personajes. La interfaz de usuario (HUD) es una placa, no un panel que ocupa espacio.

La ocupación en el motor sigue siendo un **ID de zona**. Un diamante debajo del cursor es una
vista de una zona, nunca una segunda simulación espacial. El acuerdo que ambas partes mantienen es
[Clientes visuales](https://mcp-tool-shop-org.github.io/ai-rpg-engine/handbook/66-visual-clients/)
en el manual del motor.

Quién está dónde se **define previamente**, no se improvisa aquí.
[World Forge](https://github.com/mcp-tool-shop-org/world-forge) escribe un
bloque `presentation` en `fixtures/pack.json`: una fila de ocupación por habitante nombrado (personaje, zona, celda, orientación y la razón por la que se eligió esa celda)
más la celda de anclaje de cada zona de 3×3. El puerto prefiere ese bloque cuando
el paquete lo lleva, vuelve a `fixtures/harbour-occupancy.json` cuando no lo hace y deriva una celda de esquina solo cuando ninguno de los dos existe. El bloque es aditivo
y se lee directamente del elemento comprometido; nunca se le pide al motor que lo
entienda.

El arte de la ciudad se encuentra en [`assets/dimetric/`](assets/dimetric/README.md). Cada placa
se renderizó a través de una cámara ortográfica de Blender en X 60° / Z 45° y debe pasar
`assets/dimetric/andon/iso_andon.py` antes de que el escenario la cargue. La puerta rechaza
la proyección incorrecta, la falta de alfa, los fondos precalculados y cualquier cosa que no esté en la cuadrícula de mosaicos. Nada debajo de `assets/iso/` se carga; esa carpeta está inactiva.

## Lo que hay aquí

| | |
|---|---|
| `client/` | Las partes que se comunican con el motor y vinculan su vocabulario al árbol de la escena: cliente de red, verificador de resumen canónico, bus de eventos, cola de ticks, unión de escena, manifiesto de eventos, cargador de paquetes de Foundry. |
| `stage/` | El mundo renderizado: el puerto dimétrico (`stage/iso/`), el sistema de iluminación, el mezclador y la voz simulados, la interfaz de usuario (HUD) en forma de placa, la sesión que los controla. |
| `assets/dimetric/` | El kit de la ciudad: ANDON, script de cámara, mosaicos de suelo, estructuras, accesorios, `MANIFEST.json`. |
| `assets/characters/` | Paquetes HD de Foundry (habitantes de la ciudad). |
| `fixtures/` | Un mundo generado y su verdad en forma de código, comprometidos como un par para que se pueda verificar la unión entre ellos. |
| `tools/` | El ejecutor de pruebas sin cabeza, la herramienta de captura de pantalla, el lanzador de juegos, el sistema de pruebas secundario. |
| `tests/` | Diecisiete conjuntos de pruebas, cada uno con un control que hace que falle. |

## Ejecutándolo

Requiere Godot **4.7.x** en `PATH` como `godot`. El motor es una copia del código fuente (`../ai-rpg-engine` u `AI_RPG_ENGINE_DIR`), compilado con `npm run build`.

**Jugar Salt Road** (inicia el sistema de pruebas secundario con el puerto cargado, espera a que se abra el puerto, abre el escenario, cierra la simulación cuando se cierra la ventana):

```bash
node tools/play.mjs
```

Opciones: `--seed <n>` (predeterminado 71), `--port <n>` (predeterminado 47820, o `0` para efímero),
`--shock <district:metric:delta@round>` o `--no-shock`, `--engine <dir>`,
`--forge <dir>`, `--unresolved-ai-profile <fail|warn>` (predeterminado `fail`;
`--release` selecciona `warn` y reenvía `--sidecar-stderr=<log>` a Godot),
`--godot <bin>` (ruta del ejecutable de Godot, predeterminado `GODOT_BIN` o `godot`),
`--headless` (inicia solo la simulación, imprime el puerto y espera),
`--stage-headless` (inicia Godot con `--headless` y la entrada estándar cerrada junto con
la simulación) y `--quit-after-sync <path>` (pasa `--quit-after-sync=<path>` a
Godot para que `Playable` escriba un resumen de sincronización JSON después de la conexión y la instantánea de referencia, se desconecta y sale con código `0`). Tenga en cuenta que un escenario de Godot exportado para su lanzamiento nunca inicia la simulación directamente (solo se conecta a través de `--attach`):
`fail` frente a `warn` proviene de `tools/play.mjs` (`--release`), `tools/sidecar_harness.gd`
(`OS.is_debug_build()`) o el `--unresolved-ai-profile fail` explícito de CI.

| Clave. | Hace. |
|---|---|
| hace clic en un diamante. | camina hasta allí; un diamante en una zona vecina envía `move`. |
| `1`–`9` | camina por esa puerta. |
| `Space` | espera una ronda. |
| `I` | muestra el registro de prosa. |
| `J` | efecto de cámara activado/desactivado. |
| `M` | silencio. |
| `Esc` | salir. |

**Ejecutar la suite** (sin cabeza, sin ventana; las suites que necesitan una simulación activa se omiten
con una razón específica cuando no hay un motor presente).

```bash
./verify.sh
```

`verify.sh` importa el proyecto, ejecuta cada `tests/test_*.gd`, vuelve a aplicar cada
placa de tiempo de ejecución en `MANIFEST.json` y construye el sitio cuando `site/` existe.
Lo mismo manualmente:

```bash
godot --headless --path . --import
godot --headless --path . --script res://tools/headless.gd
godot --headless --path . --script res://tools/headless.gd -- --only=iso_world
```

El ejecutor imprime `PASS:` / `FAIL:` líneas y una línea `verdict=` y sale
con un código de error en caso de cualquier fallo, en una prueba que no afirmó nada y en un filtro `--only=`
que no coincidió con nada. Un filtro es **un** nombre de suite; una lista separada por comas no coincide con nada, y una ejecución vacía es un fallo aquí, no un éxito.

**Activadores de CI y filtros de ruta.** Las acciones de GitHub activan las ejecuciones en las rutas de proyecto observadas (`project.godot`, `client/**`, `stage/**`, `tools/**`, `tests/**`,
`fixtures/**`, `entities/**`, `transitions/**`, `assets/**`, `.github/workflows/**`,
`.github/upstream-pins.env`, `atlas/**`) y omite los trabajos `pull_request` de
ramas del mismo repositorio porque la ejecución `push` que coincide prueba los commits.
Debido a que `on.push.paths` inspecciona solo el rango de cambios (`before..after`) mientras que
`on.pull_request.paths` inspecciona todo el cambio de la solicitud de fusión (`base...head`), una solicitud de fusión del mismo repositorio con commits observados anteriores deja su SHA final sin una ejecución `headless`
después de cualquiera de los siguientes: (1) un commit de seguimiento que solo contiene cambios no observados (`README.md`,
`CHANGELOG.md`, `site/**`, documentación) o (2) un commit que solo contiene cambios en el mensaje del commit o cambios no observados
`--amend` fuerza-push; los cambios observados ya se ejecutaron al realizar el push, se vuelven a ejecutar al fusionarse en `main` (`main^..main`) o se pueden ejecutar a través de `workflow_dispatch`. En
`main`, la concurrencia de trabajos mantiene un trabajo en ejecución más, como máximo, un trabajo pendiente (`cancel-in-progress: false`), por lo que dos fusiones rápidas se ejecutan mientras que una tercera fusión antes de que finalice la primera reemplaza a la segunda en cola, cuyo código se incluye.

## Adjuntando

La etapa se conecta a un proceso secundario a través de TCP, al que el operador le asigna un nombre (`--attach=host:port` en la línea de comandos de Godot; `play.mjs` se lo pasa). El protocolo de enlace solicita `capabilities.hashes` (hashes por fotograma), `capabilities.canonicalHashes` (especificación del resumen v2 para la verificación entre idiomas) y `capabilities.audio` (la carga útil `felt`: elementos de la zona, elementos superpuestos, la línea hablada, el trauma de la cámara). Si `digest_spec_version` no es compatible o falta, se produce un error visible al intentar adjuntarlo. Hasta que se reciba la primera `snapshot` autoritativa, la interfaz de usuario muestra un estado `syncing` y rechaza las entradas de juego (`submitAction`, `advance` y los controles de navegación de la interfaz de usuario). Después de cada envío de juego, la etapa recalcula el resumen del estado canónico en su espejo modificado y lo compara con el `canonicalHash` del motor. Si hay una discrepancia, registra el primer desplazamiento de byte de la preimagen diferente, solicita una instantánea autoritativa completa, reemplaza su espejo y verifica el resumen de la instantánea inmediatamente; las resincronizaciones consecutivas se limitan a 3 antes de que el juego se detenga con un error visible. Nunca modifica la simulación. Solo los eventos `world.zone.entered` que contienen un `actorId` de nivel superior que coincida con el `playerId` resuelto de la sesión mueven el nodo del jugador, actualizan `_player_zone` y emiten líneas de llegada a la sala.

Un proceso secundario iniciado con `--content` aún necesita `--manifest`; el iniciador pasa `fixtures/salt-road.manifest.json`.

## La conexión y por qué tiene una configuración modificada

La simulación se comunica mediante identificadores de zona. La etapa es un árbol de nodos. `client/scene_join.gd` transforma uno en el otro, y `fixtures/` contiene dos escenas: la exportación real y una con un único identificador de zona modificado. La prueba reconcilia ambas. La real debe coincidir en ambas direcciones; la modificada debe fallar en ambas direcciones, indicando que el identificador real falta en la escena y el identificador modificado está ausente en la conexión. Sin la segunda configuración, la primera solo prueba que dos listas coincidieron el día en que se generaron.

La escena exportada también contiene `metadata/entry_gate*` en las zonas restringidas. La etapa nunca la lee para tomar ninguna decisión. Las restricciones son reglas del motor: la etapa envía el movimiento y renderiza el rechazo que recibe, incluido el motivo que dio la persona. `client/scene_join.gd` no ofrece ninguna forma de evaluar una restricción, a propósito.

Las configuraciones son producidas por [World Forge](https://github.com/mcp-tool-shop-org/world-forge) y se incluyen aquí, por lo que este repositorio no necesita ninguna herramienta JavaScript para ejecutarse o compilarse:

```bash
npx tsx dogfood/export-stage-fixture.ts --world=coverage --out=<this-repo>/fixtures --doctor
```

El generador se niega a escribir una configuración con cero zonas, identificadores de zona duplicados, un recuento de restricciones que no coincida con el mundo diseñado o una zona para la que la escena no contenga ningún nodo.

## Modelo de confianza y amenazas

**Datos accedidos.** La etapa lee la escena, las configuraciones y las plantillas en este repositorio, y los mensajes JSON-RPC del único punto final del motor al que se apunta. Solo escribe en el directorio de datos de usuario de Godot (caché del editor, registros).

**Datos no accedidos.** Ningún archivo fuera del proyecto y del directorio de usuario de Godot. No se leen, almacenan ni envían credenciales; el protocolo de conexión no está autenticado por diseño y asume un punto final local de confianza. No se recopila ni se envía **ningún dato de telemetría**, ni por la etapa ni por nada que incluya. No se descarga ni se ejecuta ningún código en tiempo de ejecución.

**Permisos.** Una conexión TCP saliente al host y al puerto que el operador proporciona. No hay ningún punto final predeterminado, ni descubrimiento ni ningún receptor: nada aquí acepta una conexión. Quien controle el punto final controla lo que se renderiza, por lo que apunte la etapa solo a un motor en el que confíe, en una red en la que confíe.

**Errores.** Los fallos de transporte, las conexiones rechazadas, las discrepancias en la versión del protocolo de enlace, la antigüedad y los límites de sincronización interrumpidos se informan como frases sencillas en la línea de estado y en el registro (`[stale] state drift at tick N: expected X, mirror Y, first
differing pre-image offset K (resync 1/3)`), nunca como excepciones sin procesar en la interfaz de usuario. La bandera `--verbose` de Godot activa el registro a nivel de motor; nada de lo que registra la etapa contiene un secreto porque nunca lo almacena.

Política completa y contacto para informes: [SECURITY.md](SECURITY.md).

## Licencia

MIT © mcp-tool-shop. Consulte [LICENSE](LICENSE) y [CHANGELOG.md](CHANGELOG.md).

---

<p align="center">Built by <a href="https://mcp-tool-shop.github.io/">MCP Tool Shop</a></p>
