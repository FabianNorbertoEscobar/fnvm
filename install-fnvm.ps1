# install-fnvm.ps1 - Instalador de fnvm/fnpm (Fabian Node Version Manager)
# ------------------------------------------------------------------------
# Deja fnvm/fnpm funcionando en una maquina nueva. Es idempotente: se puede
# correr varias veces sin romper nada.
#
# Que hace:
#   1. Valida las rutas (discos locales, junction en NTFS, sin carpetas anidadas).
#   2. Guarda las rutas en %USERPROFILE%\.fnvm\config.json (solo si no son las default).
#   3. Crea la carpeta de versiones y, si esta vacia, descarga la ultima LTS.
#   4. Crea el junction (hace backup si en esa ruta habia una carpeta real).
#   5. Agrega el dot-source de fnvm.ps1 al $PROFILE de PowerShell.
#   6. Verifica, y si el junction no esta en el PATH ofrece agregarlo (pregunta).
#
# Uso:
#   .\install-fnvm.ps1                                    # defaults: C:\Programas\node y C:\Programas\nodes
#   .\install-fnvm.ps1 -ProgramasRoot "D:\Programas"      # D:\Programas\node y D:\Programas\nodes
#   .\install-fnvm.ps1 -NodeLink "C:\tools\node" -NodesDir "D:\node-versions"
#   .\install-fnvm.ps1 -NoPathUpdate                      # no ofrece tocar el PATH, solo avisa
#
# Para cambiar las rutas DESPUES de instalado, usar: fnvm config set nodesDir|nodeLink <ruta>

param(
    [string]$ProgramasRoot,
    [string]$NodeLink,
    [string]$NodesDir,
    [switch]$NoPathUpdate
)

$ErrorActionPreference = "Stop"
$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$fnvmScript = Join-Path $scriptDir "fnvm.ps1"

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "    $msg" -ForegroundColor Yellow }

Write-Host "`n== Instalador fnvm / fnpm ==`n" -ForegroundColor White

if (-not (Test-Path $fnvmScript)) {
    Write-Host "ERROR: no encontre fnvm.ps1 junto a este instalador ($fnvmScript)." -ForegroundColor Red
    Write-Host "Copia la carpeta fnvm completa y corre el instalador desde adentro." -ForegroundColor Red
    exit 1
}

# Carga las funciones de fnvm y las rutas actuales (config.json existente o defaults).
. $fnvmScript

# --- Rutas objetivo: parametros > config existente > defaults ---
$targetLink = $script:FnvmNodeLink
$targetDir  = $script:FnvmNodesRoot
if ($ProgramasRoot) {
    $targetLink = ConvertTo-FnvmPath (Join-Path $ProgramasRoot "node")
    $targetDir  = ConvertTo-FnvmPath (Join-Path $ProgramasRoot "nodes")
}
if ($NodeLink) { $targetLink = ConvertTo-FnvmPath $NodeLink }
if ($NodesDir) { $targetDir  = ConvertTo-FnvmPath $NodesDir }

# Si fnvm ya esta instalado con OTRAS rutas, no las pisamos: eso es un cambio de config.
$currentLinkItem = Get-Item $script:FnvmNodeLink -ErrorAction SilentlyContinue
$alreadyInstalled = $currentLinkItem -and $currentLinkItem.LinkType -eq 'Junction'
if ($alreadyInstalled -and (($targetLink -ine $script:FnvmNodeLink) -or ($targetDir -ine $script:FnvmNodesRoot))) {
    Write-Host "fnvm ya esta instalado con estas rutas:" -ForegroundColor Yellow
    Write-Host "  nodeLink  $($script:FnvmNodeLink)"
    Write-Host "  nodesDir  $($script:FnvmNodesRoot)"
    Write-Host "Para cambiarlas (moviendo versiones y junction) usa:" -ForegroundColor Yellow
    if ($targetDir  -ine $script:FnvmNodesRoot) { Write-Host "  fnvm config set nodesDir `"$targetDir`"" -ForegroundColor DarkGray }
    if ($targetLink -ine $script:FnvmNodeLink)  { Write-Host "  fnvm config set nodeLink `"$targetLink`"" -ForegroundColor DarkGray }
    exit 1
}

# --- 1. Validacion ---
Write-Step "Validando rutas"
Write-Host "    nodeLink  $targetLink" -ForegroundColor DarkGray
Write-Host "    nodesDir  $targetDir" -ForegroundColor DarkGray
$errs = Test-FnvmPaths -NodeLink $targetLink -NodesDir $targetDir
if ($errs.Count -gt 0) {
    Write-Host "    Las rutas no cumplen las reglas (no se toco nada):" -ForegroundColor Red
    $errs | ForEach-Object { Write-Host "      - $_" -ForegroundColor Red }
    exit 1
}
Write-Ok "rutas validas"

# --- 2. config.json (solo si no son las default) ---
Write-Step "Configuracion"
$isDefault = ($targetLink -ieq $script:FnvmDefaultNodeLink) -and ($targetDir -ieq $script:FnvmDefaultNodesDir)
if ($isDefault -and -not (Test-Path $script:FnvmConfigFile)) {
    Write-Ok "se usan las rutas default (no hace falta config.json)"
} else {
    Save-FnvmConfig -NodeLink $targetLink -NodesDir $targetDir
    Write-Ok "rutas guardadas en $($script:FnvmConfigFile)"
}
Initialize-FnvmPaths

# --- 3. Carpeta de versiones y LTS ---
Write-Step "Verificando $($script:FnvmNodesRoot)"
if (-not (Test-Path $script:FnvmNodesRoot)) {
    New-Item -ItemType Directory -Path $script:FnvmNodesRoot -Force | Out-Null
    Write-Ok "carpeta creada"
}
$versions = @(Get-FnvmVersions)
if ($versions.Count -eq 0) {
    Write-Warn "no hay ninguna version. Descargando la ultima LTS..."
    $lts = Resolve-FnvmRemoteVersion -Requested 'lts'
    if (-not $lts) { Write-Host "ERROR: no pude resolver la ultima LTS." -ForegroundColor Red; exit 1 }
    $folder = "node-v$lts-win-x64"
    $url = "https://nodejs.org/dist/v$lts/$folder.zip"
    $zip = Join-Path $env:TEMP "$folder.zip"
    Write-Host "    bajando $url" -ForegroundColor DarkGray
    Invoke-WebRequest -Uri $url -OutFile $zip -TimeoutSec 300 -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath $script:FnvmNodesRoot -Force
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    Get-ChildItem (Join-Path $script:FnvmNodesRoot $folder) -File -Filter *.ps1 -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue
    Write-Ok "LTS $lts instalada"
    $versions = @(Get-FnvmVersions)
} else {
    Write-Ok "$($versions.Count) version(es) encontrada(s)"
}
$highest = $versions | Select-Object -Last 1

# --- 4. Junction ---
Write-Step "Configurando el junction $($script:FnvmNodeLink)"
$linkItem = Get-Item $script:FnvmNodeLink -ErrorAction SilentlyContinue
if ($linkItem -and $linkItem.LinkType -eq 'Junction') {
    Write-Ok "ya es un junction -> $($linkItem.Target | Select-Object -First 1)"
} else {
    if ($linkItem) {
        $backup = "$($script:FnvmNodeLink)_backup"
        if (Test-Path $backup) { $backup = "$($script:FnvmNodeLink)_backup_" + (Get-Date -Format "yyyyMMddHHmmss") }
        Write-Warn "$($script:FnvmNodeLink) es una carpeta real. Respaldando en $backup ..."
        Rename-Item $script:FnvmNodeLink (Split-Path $backup -Leaf)
    }
    Set-FnvmJunction -Link $script:FnvmNodeLink -Target $highest.Path
    Write-Ok "junction creado -> $($highest.Name)"
}

# --- 5. $PROFILE ---
Write-Step "Configurando el `$PROFILE de PowerShell"
$profileDir = Split-Path $PROFILE -Parent
if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }
if (-not (Test-Path $PROFILE))    { New-Item -ItemType File -Path $PROFILE -Force | Out-Null }
if (Select-String -Path $PROFILE -SimpleMatch $fnvmScript -Quiet) {
    Write-Ok "el profile ya carga fnvm"
} else {
    Add-Content -Path $PROFILE -Value "`n# Carga fnvm/fnpm (Fabian Node Version Manager)`n. `"$fnvmScript`""
    Write-Ok "agregado el dot-source al profile ($PROFILE)"
}

# --- 6. Verificacion y PATH ---
Write-Step "Verificando"
$nodeExe = Join-Path $script:FnvmNodeLink 'node.exe'
try {
    $v = & $nodeExe -v
    Write-Ok "node activo: $v"
} catch {
    Write-Warn "no pude ejecutar $nodeExe : $($_.Exception.Message)"
}

if (Test-FnvmInPath $script:FnvmNodeLink) {
    Write-Ok "$($script:FnvmNodeLink) esta en el PATH"
} elseif ($NoPathUpdate) {
    Write-Warn "$($script:FnvmNodeLink) NO esta en el PATH: agregalo a mano al PATH de tu usuario."
    Write-Warn "(fnvm/fnpm igual funcionan, pero 'node' y 'npm' a secas no se van a reconocer)"
} else {
    Update-FnvmUserPath -Old '' -New $script:FnvmNodeLink
}

Write-Host "`n== Listo ==" -ForegroundColor Green
Write-Host "Abri una consola NUEVA (o corre '. `$PROFILE') y proba:" -ForegroundColor White
Write-Host "  fnvm config    # rutas en uso y estado" -ForegroundColor DarkGray
Write-Host "  fnvm current   # node activo" -ForegroundColor DarkGray
Write-Host "  fnvm help      # todos los comandos" -ForegroundColor DarkGray
