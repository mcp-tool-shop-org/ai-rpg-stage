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
proceso en ejecución [`ai-rpg-engine`](https://github.com/mcp-tool-shop-org/ai-rpg-engine) a través de
JSON-RPC, envía lo que el jugador intenta hacer y dibuja lo que se devuelve. No
tiene reglas. No avanza el tiempo. Cuando no está de acuerdo con la simulación,
la simulación tiene razón y el escenario lo dice en voz alta.

Esa restricción es el producto. Una simulación determinista cuyo cliente puede
adivinar es una simulación con dos verdades, y la segunda se desincroniza
silenciosamente. Todo aquí está organizado de tal manera que el escenario no puede
convertirse en la segunda verdad.

**Estado:** `0.x`, aún no hay una versión etiquetada; `main` es la versión compatible. Godot **4.7**.

## Lo que dibuja

La cámara del juego es **2:1 dimétrica**: un puerto continuo en un Godot
`TileMapLayer` (isométrico, diamante hacia abajo, 256×128 celdas), ordenado en Y, con
personajes HD de [Sprite Foundry](https://github.com/mcp-tool-shop-org/sprite-foundry)
(8 direcciones, albedo + normal, pivote de pie) que se encuentran sobre manchas
de contacto. Los edificios son placas que pasan por una puerta de proyección y se
cortan en franjas de 128 píxeles, de modo que el orden en Y tiene un elemento
dibujable por diamante. Las antorchas son `PointLight2D` que iluminan los mapas de normales
de los personajes. La interfaz de usuario (HUD) es una placa, no un panel que
ocupa espacio.

La ocupación en el motor sigue siendo un **ID de zona**. Un diamante debajo del
cursor es una vista de una zona, nunca una segunda simulación espacial. El
contrato que ambas partes cumplen es [Clientes visuales](https://mcp-tool-shop-org.github.io/ai-rpg-engine/handbook/66-visual-clients/)
en el manual del motor.

El arte de la ciudad se encuentra en [`assets/dimetric/`](assets/dimetric/README.md). Cada placa
se renderizó a través de una cámara ortográfica de Blender en X 60° / Z 45° y debe
pasar `assets/dimetric/andon/iso_andon.py` antes de que el escenario la cargue. La puerta rechaza
la proyección incorrecta, la falta de alfa, los fondos precalculados y cualquier
cosa que no esté en la cuadrícula de mosaicos. Nada debajo de `assets/iso/` se carga; esa
carpeta está inactiva.

## Lo que hay aquí

| | |
|---|---|
| `client/` | Las partes que se comunican con el motor y vinculan su vocabulario al árbol de
escenas: cliente de red, bus de eventos, cola de ticks, unión de escenas,
cargador de paquetes de Foundry. |
| `stage/` | El mundo renderizado: el puerto dimétrico (`stage/iso/`), el sistema de iluminación, el
mezclador y la voz, la interfaz de usuario (HUD) en forma de placa, la sesión
que los controla. |
| `assets/dimetric/` | El kit de la ciudad: ANDON, script de cámara, mosaicos de suelo, estructuras,
accesorios, `MANIFEST.json`. |
| `assets/characters/` | Paquetes HD de Foundry (habitantes de la ciudad) |
| `fixtures/` | Un mundo generado y su verdad en forma de código, comprometidos como un par para
que se pueda verificar la unión entre ellos. |
| `tools/` | El ejecutor de pruebas sin cabeza, la herramienta de captura de pantalla, el
lanzador del juego, el sistema auxiliar. |
| `tests/` | Once conjuntos de pruebas, cada uno con un control que hace que falle. |

## Ejecutándolo

Requiere Godot **4.7.x** en `PATH` como `godot`. El motor es una copia del repositorio
(`../ai-rpg-engine` u `AI_RPG_ENGINE_DIR`), compilado con `npm run build`.

**Jugar Salt Road** (inicia el sistema auxiliar con el puerto cargado, espera
al puerto, abre el escenario, apaga la simulación cuando se cierra la ventana):

```bash
node tools/play.mjs
```

Opciones: `--seed <n>` (predeterminado 71), `--port <n>` (predeterminado 47820),
`--shock <district:metric:delta@round>` o `--no-shock`, `--engine <dir>`,
`--forge <dir>`, `--headless` (inicia solo la simulación e imprime el puerto).

| Clave. | Hace. |
|---|---|
| hace clic en un diamante. | camina hasta allí; un diamante en una zona vecina envía `move`. |
| `1`–`9` | camina a través de esa puerta. |
| `Space` | espera una ronda. |
| `I` | muestra el registro de prosa. |
| `J` | efecto de cámara activado/desactivado. |
| `M` | silencio. |
| `Esc` | salir. |

**Ejecutar la suite** (sin cabeza, sin ventana; las suites que necesitan una
simulación activa se omiten con una razón específica cuando no hay un motor
presente):

```bash
./verify.sh
```

`verify.sh` importa el proyecto, ejecuta cada `tests/test_*.gd`, vuelve a aplicar cada
placa en tiempo de ejecución en `MANIFEST.json` y construye el sitio cuando `site/` existe.
Lo mismo manualmente:

```bash
godot --headless --path . --import
godot --headless --path . --script res://tools/headless.gd
godot --headless --path . --script res://tools/headless.gd -- --only=iso_world
```

El ejecutor imprime `PASS:` / `FAIL:` líneas y una línea `verdict=` y sale
con un código de error distinto de cero en caso de cualquier error, en una prueba
que no afirmó nada y en un filtro `--only=` que no coincidió con nada. Un filtro es
**un** nombre de suite; una lista separada por comas no coincide, y una ejecución
vacía es un fallo aquí, no un éxito.

## Adjuntando

El escenario se conecta **de forma saliente** a través de TCP a un sistema auxiliar
cuyo nombre especifica el operador (`--attach=host:port` en la línea de comandos de Godot; `play.mjs` lo
pasa). El protocolo de enlace solicita `capabilities.hashes` (latencia por tick) y
`capabilities.audio` (la carga útil `felt`: orígenes de zona, elementos superpuestos, la línea
pronunciada, el trauma de la cámara). En caso de una discrepancia de hash, el
escenario lo informa en la línea de estado y en el registro, deja de confiar en
sí mismo y vuelve a tomar una instantánea. Nunca aplica parches a la simulación.

Un sistema auxiliar iniciado con `--content` aún necesita `--manifest`; el lanzador pasa
`fixtures/salt-road.manifest.json`.

## La unión y por qué tiene un elemento modificado

La simulación habla en ID de zona. El escenario es un árbol de nodos.
`client/scene_join.gd` convierte uno en el otro, y `fixtures/` contiene dos
escenas: la exportación real y una con un solo ID de zona modificado. La prueba
reconcilia ambas. La real debe coincidir en ambas direcciones; la modificada debe
fallar en ambas direcciones, indicando que el ID real falta en la escena y el ID
modificado está ausente en el código. Sin el segundo elemento, el primero solo
prueba que dos listas coincidieron el día en que se generaron.

La escena exportada también contiene `metadata/entry_gate*` en las zonas con puerta. El escenario
nunca lo lee para decidir nada. Las puertas son reglas del motor: el escenario
envía el movimiento y renderiza la negativa que recibe, incluido el motivo que
una persona dio para ello. `client/scene_join.gd` no ofrece ninguna forma de evaluar una puerta, a
propósito.

Los elementos se producen con [World Forge](https://github.com/mcp-tool-shop-org/world-forge)
y se comprometen aquí, por lo que este repositorio no necesita una cadena de
herramientas de JavaScript para ejecutarse o construirse:

```bash
npx tsx dogfood/export-stage-fixture.ts --world=coverage --out=<this-repo>/fixtures --doctor
```

El generador se niega a escribir un elemento con cero zonas, ID de zona
duplicados, un recuento de puertas que no coincide con el mundo diseñado o una
zona para la que la escena no tiene un nodo.

## Modelo de confianza y amenaza

**Datos accedidos.** La etapa lee la escena, los objetos y las texturas de este repositorio, así como los mensajes JSON-RPC del único punto final del motor al que se dirige. Solo escribe en el directorio de datos de usuario de Godot (caché del editor, registros).

**Datos no accedidos.** No se accede a ningún archivo fuera del proyecto y del directorio de usuario de Godot. No se leen, almacenan ni envían credenciales; el protocolo de comunicación no está autenticado por diseño y asume un punto final local de confianza. **No se recopilan ni se envían datos de telemetría**, ni por la etapa ni por nada que incluya. No se descarga ni se ejecuta ningún código en tiempo de ejecución.

**Permisos.** Una única conexión TCP saliente al host y al puerto que especifique el operador. No hay ningún punto final predeterminado, ni descubrimiento, ni ningún receptor: nada aquí acepta una conexión. Quien controle el punto final controla lo que se renderiza, por lo que dirija la etapa solo a un motor en el que confíe y en una red en la que confíe.

**Errores.** Los fallos de transporte, las conexiones rechazadas y los datos obsoletos se informan como frases sencillas en la línea de estado y en el registro (`[obsoleto] desviación de estado en el ciclo N: la simulación informa X, la etapa registró Y`), nunca como excepciones sin procesar en la interfaz de usuario. La bandera `--verbose` de Godot activa el registro a nivel de motor; nada de lo que registra la etapa contiene un secreto, ya que nunca lo almacena.

Política completa e información de contacto para informar: [SECURITY.md](SECURITY.md).

## Licencia

MIT © mcp-tool-shop. Consulte [LICENSE](LICENSE) y [CHANGELOG.md](CHANGELOG.md).

---

<p align="center">Built by <a href="https://mcp-tool-shop.github.io/">MCP Tool Shop</a></p>
