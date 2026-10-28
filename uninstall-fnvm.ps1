# uninstall-fnvm.ps1 - Desinstalador de fnvm/fnpm (Fabian Node Version Manager)
# ----------------------------------------------------------------------------
# Deshace lo que hizo install-fnvm.ps1, pidiendo confirmacion en cada paso:
#   1. Saca la carga de fnvm del $PROFILE de PowerShell.
#   2. Borra el junction (solo el enlace; las versiones no se tocan).
#   3. Saca el junction del PATH de usuario.
#   4. Borra la config (%USERPROFILE%\.fnvm\).
#   5. Las versiones de Node (nodesDir) NO se borran salvo que lo pidas explicitamente.
#
# No borra esta carpeta (los scripts de fnvm): eso lo haces vos si queres.
#
# Uso:
#   .\uninstall-fnvm.ps1                    # pregunta en cada paso
#   .\uninstall-fnvm.ps1 -DryRun            # muestra lo que haria, sin tocar nada
#   .\uninstall-fnvm.ps1 -Yes               # si a todo (pero conserva las versiones)
#   .\uninstall-fnvm.ps1 -Yes -RemoveVersions   # si a todo, incluido borrar las versiones

param(
    [switch]$DryRun,
    [switch]$Yes,
    [switch]$RemoveVersions
)

$ErrorActionPreference = "Stop"
$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$fnvmScript = Join-Path $scriptDir "fnvm.ps1"

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Skip($msg) { Write-Host "    -- $msg" -ForegroundColor DarkGray }
function Write-Warn($msg) { Write-Host "    $msg" -ForegroundColor Yellow }
function Write-Dry($msg)  { Write-Host "    [dry-run] haria: $msg" -ForegroundColor Magenta }

if (-not (Test-Path $fnvmScript)) {
    Write-Host "ERROR: no encontre fnvm.ps1 junto a este desinstalador ($fnvmScript)." -ForegroundColor Red
    exit 1
}

# Carga las funciones y las rutas efectivas (config.json / variables / defaults).
. $fnvmScript

function Ask([string]$Question) {
    if ($Yes) { return $true }
    return (Confirm-Fnvm $Question)
}

$title = if ($DryRun) { "Desinstalador fnvm / fnpm (DRY-RUN: no se toca nada)" } else { "Desinstalador fnvm / fnpm" }
Write-Host "`n== $title ==`n" -ForegroundColor White
Write-Host "  nodeLink  $($script:FnvmNodeLink)   ($($script:FnvmNodeLinkSource))" -ForegroundColor DarkGray
Write-Host "  nodesDir  $($script:FnvmNodesRoot)   ($($script:FnvmNodesRootSource))" -ForegroundColor DarkGray
Write-Host "  config    $($script:FnvmConfigFile)" -ForegroundColor DarkGray
Write-Host ""

# --- 1. $PROFILE ---
Write-Step "Carga de fnvm en el `$PROFILE ($PROFILE)"
$profileLines = if (Test-Path $PROFILE) { @(Get-Content $PROFILE) } else { @() }
$isFnvmLine = { param($l) ($l -match 'fnvm\.ps1') -or ($l -match '^\s*#\s*Carga fnvm/fnpm') }
$toRemove = @($profileLines | Where-Object { & $isFnvmLine $_ })
if ($toRemove.Count -eq 0) {
    Write-Skip "el profile no carga fnvm"
} elseif ($DryRun) {
    $toRemove | ForEach-Object { Write-Dry "sacar la linea: $_" }
} elseif (Ask "Saco la carga de fnvm del profile?") {
    $keep = @($profileLines | Where-Object { -not (& $isFnvmLine $_) })
    # saca lineas en blanco sobrantes al final
    while ($keep.Count -gt 0 -and -not $keep[-1].Trim()) { $keep = @($keep[0..($keep.Count - 2)]) }
    Set-Content -Path $PROFILE -Value $keep -Encoding UTF8
    Write-Ok "profile actualizado ($($toRemove.Count) linea(s) quitada(s))"
} else {
    Write-Skip "se deja como esta"
}

# --- 2. Junction ---
Write-Step "Junction $($script:FnvmNodeLink)"
$linkItem = Get-Item $script:FnvmNodeLink -ErrorAction SilentlyContinue
if (-not $linkItem) {
    Write-Skip "no existe"
} elseif ($linkItem.LinkType -ne 'Junction') {
    Write-Warn "es una carpeta real, no un junction: no la toco."
} elseif ($DryRun) {
    Write-Dry "borrar el junction (-> $($linkItem.Target | Select-Object -First 1)); las versiones no se tocan"
} elseif (Ask "Borro el junction? (solo el enlace, las versiones quedan)") {
    cmd /c rmdir "$($script:FnvmNodeLink)" | Out-Null
    if (Test-Path $script:FnvmNodeLink) { Write-Warn "no se pudo borrar el junction" } else { Write-Ok "junction borrado" }
} else {
    Write-Skip "se deja como esta"
}

# --- 3. PATH de usuario ---
Write-Step "PATH de usuario"
$key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
$raw = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
$parts = @($raw -split ';' | Where-Object { $_ })
$matching = @($parts | Where-Object { (ConvertTo-FnvmPath ([Environment]::ExpandEnvironmentVariables($_))) -ieq $script:FnvmNodeLink })
if ($matching.Count -eq 0) {
    Write-Skip "$($script:FnvmNodeLink) no esta en el PATH de usuario"
} elseif ($DryRun) {
    Write-Dry "sacar $($script:FnvmNodeLink) del PATH de usuario"
} elseif (Ask "Saco $($script:FnvmNodeLink) del PATH de usuario?") {
    $kind = [Microsoft.Win32.RegistryValueKind]::ExpandString
    try { $kind = $key.GetValueKind('Path') } catch { }
    $keepParts = @($parts | Where-Object { (ConvertTo-FnvmPath ([Environment]::ExpandEnvironmentVariables($_))) -ine $script:FnvmNodeLink })
    $key.SetValue('Path', ($keepParts -join ';'), $kind)
    [Environment]::SetEnvironmentVariable('FNVM_PATH_REFRESH', '1', 'User')
    [Environment]::SetEnvironmentVariable('FNVM_PATH_REFRESH', $null, 'User')
    Write-Ok "PATH de usuario actualizado (las consolas nuevas ya no lo ven)"
} else {
    Write-Skip "se deja como esta"
}
$key.Close()
$machine = [Environment]::GetEnvironmentVariable('Path', 'Machine') -split ';' | Where-Object { $_ -and ((ConvertTo-FnvmPath $_) -ieq $script:FnvmNodeLink) }
if ($machine) { Write-Warn "ojo: tambien esta en el PATH de sistema; sacarlo requiere admin." }

# --- 4. Config ---
$cfgDir = Split-Path $script:FnvmConfigFile -Parent
Write-Step "Config ($cfgDir)"
if (-not (Test-Path $cfgDir)) {
    Write-Skip "no existe (se usaban los defaults)"
} elseif ($DryRun) {
    Write-Dry "borrar $cfgDir"
} elseif (Ask "Borro la config de fnvm?") {
    Remove-Item $cfgDir -Recurse -Force
    Write-Ok "config borrada"
} else {
    Write-Skip "se deja como esta"
}

# --- 5. Versiones de Node ---
Write-Step "Versiones de Node en $($script:FnvmNodesRoot)"
$versions = @(Get-FnvmVersions)
if ($versions.Count -eq 0) {
    Write-Skip "no hay versiones"
} else {
    $list = ($versions | ForEach-Object { $_.Version }) -join ', '
    if ($DryRun) {
        if ($RemoveVersions) { Write-Dry "borrar $($versions.Count) version(es): $list" }
        else { Write-Skip "se conservan $($versions.Count) version(es): $list (para borrarlas: -RemoveVersions)" }
    } else {
        $doRemove = $false
        if ($RemoveVersions -and $Yes) { $doRemove = $true }
        elseif (-not $Yes) {
            Write-Warn "hay $($versions.Count) version(es): $list"
            $doRemove = Confirm-Fnvm "Las BORRO? (no se puede deshacer; por default se conservan)"
        }
        if (-not $doRemove) {
            Write-Skip "se conservan"
        } else {
            $busy = @(Get-FnvmBusyProcesses -Paths @($script:FnvmNodesRoot))
            if ($busy.Count -gt 0) {
                Write-Warn "hay procesos node corriendo desde ahi (PID: $(($busy | ForEach-Object { $_.Id }) -join ', ')). Cerralos y volve a correr. No se borro nada."
            } else {
                foreach ($v in $versions) { Remove-Item $v.Path -Recurse -Force }
                if (-not (Get-ChildItem $script:FnvmNodesRoot -Force | Select-Object -First 1)) { Remove-Item $script:FnvmNodesRoot -Force }
                Write-Ok "versiones borradas"
            }
        }
    }
}

Write-Host ""
if ($DryRun) {
    Write-Host "== Dry-run terminado: no se cambio nada ==" -ForegroundColor Green
} else {
    Write-Host "== Listo ==" -ForegroundColor Green
    Write-Host "Abri una consola NUEVA: en esta, 'fnvm' sigue cargado hasta que la cierres." -ForegroundColor White
    Write-Host "Los scripts siguen en $scriptDir; borralos a mano si ya no los queres." -ForegroundColor DarkGray
}
