# fnvm / fnpm — Fabian Node Version Manager

Un gestor de versiones de Node liviano para **Windows + PowerShell**, sin dependencias
externas. Pensado para quien usa los Node portables (zip oficial) y los quiere alternar
sin instalar nada en el sistema.

En vez de reinstalar Node, mantiene todas las versiones en una carpeta y usa un
**junction** para marcar cuál está activa. Cambiar de versión es instantáneo y global para
todas las consolas.

---

## ¿Cuándo usarlo? (y cuándo no)

fnvm es la alternativa para máquinas **sin permisos de administrador**, donde no se puede
instalar [nvm-windows](https://github.com/coreybutler/nvm-windows). Todo lo que hace queda
dentro de tu usuario: Node portables, un *junction*, tu `$PROFILE`, un archivo de config en
tu perfil y (si lo confirmás) tu PATH de usuario. Nada requiere admin.

| Situación | Recomendación |
|-----------|---------------|
| Tenés permisos de admin y podés instalar programas | Usá **nvm-windows** (el estándar) |
| No tenés permisos de admin / no podés instalar nvm | Usá **fnvm** |

> No los mezcles: si ya usás nvm-windows, no instales fnvm (los dos quieren controlar
> qué `node` está en el PATH).

---

## Cómo funciona (el modelo)

Con las rutas default:

```
C:\Programas\
├── node            -> JUNCTION a una versión de nodes\ (la versión ACTIVA)   = nodeLink
└── nodes\                                                                    = nodesDir
    ├── node-v18.20.8-win-x64
    ├── node-v20.20.2-win-x64
    ├── node-v22.21.0-win-x64
    └── ...
```

- **`nodeLink`** (`C:\Programas\node`) **no es una carpeta real**: es un *junction*
  (enlace de directorio) que apunta a una de las versiones de `nodesDir`.
- **`nodesDir`** (`C:\Programas\nodes`) tiene las versiones reales, una carpeta por versión.
- El `PATH` apunta siempre a `nodeLink`, así que `node` y `npm` andan en cualquier consola.
- `fnvm use` reapunta el junction: cambiás de versión sin copiar archivos ni tocar el PATH.
  El cambio es **global** (todas las consolas nuevas) y persiste hasta el próximo `use`.

Las dos rutas son **configurables e independientes** (ver [Configuración](#configuración)).

---

## Instalación (máquina nueva)

1. Cloná/copiá esta carpeta `fnvm/` completa a donde quieras.
2. Desde PowerShell, parado en la carpeta, corré el instalador:

   ```powershell
   .\install-fnvm.ps1                                     # rutas default (C:\Programas\...)
   .\install-fnvm.ps1 -ProgramasRoot "D:\Programas"       # D:\Programas\node y D:\Programas\nodes
   .\install-fnvm.ps1 -NodeLink "C:\tools\node" -NodesDir "D:\node-versions"   # separadas
   ```

El instalador es **idempotente** (se puede correr varias veces) y hace:

1. **Valida las rutas** contra las [reglas](#reglas-de-las-rutas). Si alguna falla, corta
   sin tocar nada.
2. Si las rutas no son las default, las guarda en el [archivo de config](#configuración).
3. Crea `nodesDir` y, si no hay ninguna versión, **descarga la última LTS** de nodejs.org.
4. Crea el junction `nodeLink` (hace backup si en esa ruta había una carpeta real).
5. Agrega el `dot-source` de `fnvm.ps1` a tu `$PROFILE` de PowerShell.
6. Verifica que Node responda y, si `nodeLink` no está en el PATH, **te pregunta** si lo
   agrega al PATH de tu usuario. Con `-NoPathUpdate` no pregunta: solo avisa.

Si fnvm **ya está instalado** con otras rutas, el instalador no las pisa: te indica el
`fnvm config set ...` para cambiarlas.

Después, abrí una **consola nueva** (o `. $PROFILE`) y probá `fnvm config`.

### Requisitos previos

- Windows + Windows PowerShell 5.1 (o PowerShell 7).
- Execution policy `RemoteSigned` (la recomendada; **no** hace falta `Unrestricted`). Si
  tu política bloquea el profile: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.
- Acceso de red a `nodejs.org` para `fnvm install`.

---

## Comandos

### Resumen

| Comando | Qué hace |
|---------|----------|
| `fnvm -v` / `fnvm version` | versión de la **herramienta** fnvm |
| `fnvm current` | versión de **Node activa** |
| `fnvm which` | ruta real del `node.exe` activo (resuelve el junction). Capturable: `$p = fnvm which` |
| `fnvm list` / `fnvm ls` | versiones instaladas, marca la activa con `*` |
| `fnvm install <ver>` / `fnvm i <ver>` | **descarga** una versión a `nodesDir` |
| `fnvm use <ver>` | **activa** una versión ya instalada |
| `fnvm use` | detecta la versión del proyecto y la activa (`.nvmrc` → `engines.node`) |
| `fnvm config` | muestra las rutas en uso, de dónde salen y si cumplen las reglas |
| `fnvm config set nodesDir <ruta>` | cambia la carpeta de versiones (las mueve) |
| `fnvm config set nodeLink <ruta>` | cambia la ruta del junction (y ofrece actualizar el PATH) |
| `fnvm help` / `fnvm` | ayuda |
| `fnpm <args>` | npm con el Node activo |

### fnvm install / i

Descarga desde el índice oficial de Node y descomprime en `nodesDir`. Quita la marca de
internet de los launchers automáticamente. No vuelve a bajar una versión que ya tenés.

| Ejemplo | Resultado |
|---------|-----------|
| `fnvm i 22.11.0` | versión exacta |
| `fnvm i 22` | la última `22.x` del índice oficial |
| `fnvm i lts` | la última LTS |

> Ojo: `fnvm i` instala **Node**; `fnpm i` instala **paquetes npm**. No se pisan.

### fnvm use

Activa una versión **ya instalada** (reapunta el junction).

| Ejemplo | Resultado |
|---------|-----------|
| `fnvm use 18.20.8` | versión exacta |
| `fnvm use 18` | la major `18.x` que tengas instalada |
| `fnvm use 24` | si hay varias (24.10 y 24.18), **pide precisión** |
| `fnvm use <no instalada>` | avisa y **sugiere `fnvm i`** |
| `fnvm use` (sin arg) | detecta del proyecto: `.nvmrc`, y si no hay, `engines.node` del `package.json` |

Con `.nvmrc` toma la versión tal cual; con `engines.node` toma la **major** del rango
(ej. `^20.0.0` → matchea tu `20.x` instalada). Los alias de nvm (`lts/*`) no están
soportados en `use`: avisa y pide versión numérica.

### fnpm

Passthrough completo a `npm` con el Node activo:

```powershell
fnpm -v
fnpm i
fnpm install express
fnpm run build
```

Internamente invoca `node + npm-cli.js` (más confiable que la capa `npm.cmd`).

---

## Configuración

### Dónde se guarda

En **`%USERPROFILE%\.fnvm\config.json`** (fuera de esta carpeta, a propósito: la config es
de cada máquina y no tiene que viajar en git).

```json
{
  "nodeLink": "C:\\Programas\\node",
  "nodesDir": "D:\\node-versions"
}
```

- Si el archivo **no existe**, se usan los defaults (`C:\Programas\node` y
  `C:\Programas\nodes`). El instalador solo lo crea si elegiste otras rutas.
- En JSON las barras invertidas van dobles (`\\`). También se aceptan barras normales
  (`"D:/node-versions"`).
- **No hace falta editarlo a mano**: usá `fnvm config set`, que además mueve lo necesario.

### Prioridad (de dónde sale cada ruta)

1. Variables de entorno **`FNVM_NODE_LINK`** / **`FNVM_NODES_DIR`**: override puntual (ej.
   para una prueba en una sola consola). Mientras estén definidas, `fnvm config set` se
   niega a cambiar esa clave, para no dejar la config y la realidad desfasadas.
2. **`config.json`**.
3. **Defaults**.

`fnvm config` muestra la ruta efectiva y entre paréntesis de dónde salió
(`default`, `config.json` o `variable ...`).

> Avanzado: `FNVM_CONFIG` permite usar otro archivo de config (útil para pruebas).

### Ver la configuración: `fnvm config`

```
fnvm v1.1.0 - configuracion

  archivo    C:\Users\yo\.fnvm\config.json   (no existe: se usan los defaults)
  nodeLink   C:\Programas\node   (default)
  nodesDir   C:\Programas\nodes   (default)

  junction   -> C:\Programas\nodes\node-v22.21.0-win-x64
  versiones  9 en nodesDir
  PATH       nodeLink esta en el PATH
  reglas     OK (discos locales, junction en NTFS, sin carpetas anidadas)

  Para cambiar:  fnvm config set nodesDir <ruta>   |   fnvm config set nodeLink <ruta>
```

Si algo está mal (junction roto o fuera de `nodesDir`, `nodeLink` fuera del PATH, rutas que
no cumplen las reglas), lo marca en amarillo/rojo.

### Cambiar la carpeta de versiones: `fnvm config set nodesDir <ruta>`

```powershell
fnvm config set nodesDir D:\node-versions
```

1. Valida la ruta nueva contra las reglas.
2. Muestra el plan (qué versiones se mueven, a dónde se reapunta el junction) y **pide
   confirmación**.
3. Si hay procesos `node` corriendo desde esas versiones, frena (bloquearían el movimiento).
4. Mueve las versiones. En el mismo disco es instantáneo; entre discos distintos copia y
   después borra el origen (puede tardar). La versión activa se mueve **última**, así el
   junction sigue sano si algo falla antes.
5. Guarda la config y reapunta el junction a la versión activa en la carpeta nueva.
6. Si la carpeta vieja quedó vacía, la borra.

> Si en la carpeta nueva **ya existe** una versión con el mismo nombre, se usa la del
> destino y la original **no se mueve** (queda en la carpeta vieja, que entonces no se
> borra). El comando lo avisa al correr; revisá y borrá la que sobre a mano.

### Cambiar la ruta del junction: `fnvm config set nodeLink <ruta>`

```powershell
fnvm config set nodeLink C:\tools\node
```

1. Valida la ruta nueva. Si ya existe algo ahí, frena (no pisa carpetas existentes).
2. Muestra el plan y **pide confirmación**.
3. Crea el junction nuevo apuntando a la versión activa y borra el viejo (solo el enlace,
   las versiones no se tocan).
4. Guarda la config.
5. **Te pregunta si actualiza el PATH de tu usuario** (reemplaza la ruta vieja por la nueva).
   Si decís que no, te dice qué cambiar a mano. Las consolas ya abiertas no ven el cambio:
   abrí una nueva.

> Si la ruta vieja estaba en el PATH **de sistema** (no el de usuario), fnvm no la puede
> sacar (requiere admin). Avisa; no molesta, porque esa ruta ya no tiene `node`.

### Reglas de las rutas

Se validan en el instalador, en `fnvm config set`, en `fnvm use` e `fnvm install` (antes
de tocar nada) y se reportan en `fnvm config`. Al abrir la consola **no** se valida nada,
para no hacerla más lenta.

| Regla | Por qué |
|-------|---------|
| Rutas **absolutas** (`C:\...`) | evita depender del directorio actual |
| En un **disco local fijo** (no unidad de red, no UNC `\\servidor\...`, no pendrive) | un junction no puede apuntar a una carpeta de red |
| `nodeLink` en un disco **NTFS** | los junctions solo existen en NTFS |
| **Ninguna carpeta adentro de la otra** (ni la misma) | `nodesDir` adentro del junction se apuntaría a sí mismo; el junction adentro de `nodesDir` se mezclaría con las versiones |

Las dos rutas **sí pueden estar en discos distintos** (ej. junction en `C:`, versiones en
`D:`), siempre que ambos sean discos locales.

---

## Actualizar fnvm

No hace falta reinstalar. El `$PROFILE` carga `fnvm.ps1` desde esta carpeta, así que
alcanza con actualizar los archivos y recargar:

```powershell
git pull            # o reemplazá los archivos de la carpeta a mano
. $PROFILE          # o abrí una consola nueva
fnvm -v             # confirma la versión nueva
```

La config (`%USERPROFILE%\.fnvm\config.json`), el junction y las versiones de Node no se
tocan al actualizar.

> Si **movés esta carpeta** a otro lugar, el `$PROFILE` queda apuntando a la ruta vieja.
> Volvé a correr `.\install-fnvm.ps1` desde la ubicación nueva (agrega la línea correcta) y
> sacá la vieja del `$PROFILE` a mano.

---

## Desinstalar

```powershell
.\uninstall-fnvm.ps1 -DryRun            # muestra lo que haría, sin tocar nada
.\uninstall-fnvm.ps1                    # pregunta en cada paso
.\uninstall-fnvm.ps1 -Yes               # sí a todo, pero CONSERVA las versiones de Node
.\uninstall-fnvm.ps1 -Yes -RemoveVersions   # sí a todo, incluido borrar las versiones
```

Deshace lo que hizo el instalador, pidiendo confirmación en cada paso:

1. Saca la carga de fnvm del `$PROFILE` (solo esas líneas; el resto del profile queda igual).
2. Borra el junction (solo el enlace; las versiones no se tocan).
3. Saca `nodeLink` del PATH de usuario. Si además está en el PATH **de sistema**, avisa:
   sacarlo de ahí requiere admin.
4. Borra la config (`%USERPROFILE%\.fnvm\`).
5. Las **versiones de Node no se borran por default** (para no perder descargas por
   accidente). Sin `-Yes` te pregunta; con `-Yes` solo se borran si además pasás
   `-RemoveVersions`. Si hay procesos `node` corriendo desde ahí, frena.

No borra esta carpeta con los scripts: eso lo hacés vos si querés. Después, abrí una
consola nueva (en la actual `fnvm` sigue cargado hasta que la cierres).

---

## Mantenimiento

- La versión de fnvm está en `$script:FnvmVersion` (tope de `fnvm.ps1`).
- Toda la lógica vive en `fnvm.ps1`. El `$PROFILE` solo hace `. dot-source` de ese archivo.
- Las rutas default están en `$script:FnvmDefaultNodeLink` / `$script:FnvmDefaultNodesDir`.
- Los scripts son ASCII a propósito (sin tildes): Windows PowerShell 5.1 lee los `.ps1`
  sin BOM como ANSI y los caracteres acentuados se romperían.

---

## Troubleshooting

### "npm.ps1 no está firmado digitalmente"

Los Node bajados como `.zip` traen la marca "venido de internet" (`Zone.Identifier`), y
con `RemoteSigned` eso bloquea los `.ps1`. **No** pongas `Unrestricted`. Quitá la marca
(reemplazá la ruta por tu `nodesDir`):

```powershell
Get-ChildItem "C:\Programas\nodes" -Directory | ForEach-Object {
    Get-ChildItem $_.FullName -File -Filter *.ps1 | Unblock-File
}
```

`fnvm use` e `fnvm install` ya hacen este `Unblock-File` automáticamente sobre la versión
que tocan, así que en el uso normal no deberías verlo.

### `node` no se reconoce en consola

`nodeLink` no está en el PATH. Corré `fnvm config` para confirmarlo, y agregalo al PATH de
tu usuario (o volvé a correr el instalador, que te ofrece hacerlo). Abrí una consola nueva.

### "archivo en uso por otro proceso" al cambiar o mover una versión

Hay un proceso `node.exe` corriendo sobre esa versión. Cerralo (`Get-Process node`) y
reintentá.

### Cambié `config.json` a mano y algo no anda

`fnvm config` te dice qué está mal. Lo más común: cambiaste `nodeLink` y el junction
sigue en la ruta vieja, o cambiaste `nodesDir` sin mover las versiones. Volvé el archivo a
como estaba y usá `fnvm config set`, que hace la mudanza completa.

---

## Archivos de esta carpeta

| Archivo | Qué es |
|---------|--------|
| `fnvm.ps1` | el script con las funciones `fnvm` y `fnpm` |
| `install-fnvm.ps1` | instalador idempotente para máquina nueva |
| `uninstall-fnvm.ps1` | desinstalador (con `-DryRun`, confirma cada paso, conserva las versiones por default) |
| `README.md` | este documento |
