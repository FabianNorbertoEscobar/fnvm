# fnvm / fnpm - Fabian Node Version Manager (para Windows)
# ---------------------------------------------------------------
# Modelo: <nodeLink> es un JUNCTION que apunta a una de las versiones reales en
# <nodesDir>\node-vXX.XX.X-win-x64. El PATH apunta siempre a <nodeLink>, asi que
# cambiar de version = reapuntar el junction (instantaneo, global).
#
# Rutas (por default C:\Programas\node y C:\Programas\nodes). Prioridad:
#   1. variables de entorno FNVM_NODE_LINK / FNVM_NODES_DIR (override puntual)
#   2. archivo de config  %USERPROFILE%\.fnvm\config.json  (o FNVM_CONFIG)
#   3. defaults
#
# Ver README.md para la documentacion completa. 'fnvm help' lista los comandos.

$script:FnvmVersion         = "1.1.0"
$script:FnvmDefaultNodeLink = "C:\Programas\node"
$script:FnvmDefaultNodesDir = "C:\Programas\nodes"
$script:FnvmConfigFile      = if ($env:FNVM_CONFIG) { $env:FNVM_CONFIG } else { Join-Path $env:USERPROFILE ".fnvm\config.json" }

# =====================================================================
# Configuracion
# =====================================================================

# Normaliza una ruta: acepta barras '/', saca comillas y la barra final.
function ConvertTo-FnvmPath {
    param([string]$Path)
    if (-not $Path) { return $null }
    $p = ($Path.Trim().Trim('"')) -replace '/', '\'
    if ($p.Length -gt 3) { $p = $p.TrimEnd('\') }
    return $p
}

function Read-FnvmConfigFile {
    if (-not (Test-Path $script:FnvmConfigFile)) { return $null }
    try {
        return (Get-Content $script:FnvmConfigFile -Raw | ConvertFrom-Json)
    } catch {
        Write-Host "fnvm: $($script:FnvmConfigFile) no es un JSON valido, se ignora (se usan defaults)." -ForegroundColor Yellow
        return $null
    }
}

# Resuelve las rutas efectivas (env > config.json > default) y recuerda de donde salio cada una.
function Initialize-FnvmPaths {
    $cfg = Read-FnvmConfigFile

    if ($env:FNVM_NODE_LINK)         { $link = $env:FNVM_NODE_LINK; $linkSrc = 'variable FNVM_NODE_LINK' }
    elseif ($cfg -and $cfg.nodeLink) { $link = $cfg.nodeLink;       $linkSrc = 'config.json' }
    else                             { $link = $script:FnvmDefaultNodeLink; $linkSrc = 'default' }

    if ($env:FNVM_NODES_DIR)         { $dir = $env:FNVM_NODES_DIR;  $dirSrc = 'variable FNVM_NODES_DIR' }
    elseif ($cfg -and $cfg.nodesDir) { $dir = $cfg.nodesDir;        $dirSrc = 'config.json' }
    else                             { $dir = $script:FnvmDefaultNodesDir; $dirSrc = 'default' }

    $script:FnvmNodeLink        = ConvertTo-FnvmPath $link
    $script:FnvmNodesRoot       = ConvertTo-FnvmPath $dir
    $script:FnvmNodeLinkSource  = $linkSrc
    $script:FnvmNodesRootSource = $dirSrc
}

function Save-FnvmConfig {
    param([string]$NodeLink, [string]$NodesDir)
    $dir = Split-Path $script:FnvmConfigFile -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $obj = [ordered]@{ nodeLink = $NodeLink; nodesDir = $NodesDir }
    ($obj | ConvertTo-Json) | Set-Content -Path $script:FnvmConfigFile -Encoding UTF8
}

# Actualiza una sola clave del config.json, conservando la otra (o su default).
function Update-FnvmConfig {
    param([string]$Key, [string]$Value)
    $cfg  = Read-FnvmConfigFile
    $link = if ($cfg -and $cfg.nodeLink) { $cfg.nodeLink } else { $script:FnvmDefaultNodeLink }
    $dir  = if ($cfg -and $cfg.nodesDir) { $cfg.nodesDir } else { $script:FnvmDefaultNodesDir }
    if ($Key -eq 'nodeLink') { $link = $Value } else { $dir = $Value }
    Save-FnvmConfig -NodeLink $link -NodesDir $dir
}

# =====================================================================
# Validacion de rutas
# =====================================================================
# Reglas: rutas absolutas en un disco LOCAL FIJO (no red, no UNC, no pendrive),
# el junction en un disco NTFS, y ninguna carpeta adentro de la otra.
# Pueden estar en discos distintos (ej. junction en C:, versiones en D:).
function Test-FnvmPaths {
    param([string]$NodeLink, [string]$NodesDir)
    $errors = New-Object System.Collections.Generic.List[string]

    foreach ($pair in @(@('nodeLink', $NodeLink), @('nodesDir', $NodesDir))) {
        $name = $pair[0]; $p = $pair[1]
        if (-not $p) { $errors.Add("${name}: esta vacio."); continue }
        if ($p.StartsWith('\\')) { $errors.Add("${name} ($p): es una ruta de red (UNC). Tiene que estar en un disco local."); continue }
        if ($p -notmatch '^[A-Za-z]:\\') { $errors.Add("${name} ($p): tiene que ser una ruta absoluta (ej. C:\Programas\node)."); continue }
        $drive = New-Object System.IO.DriveInfo($p.Substring(0, 1))
        if (-not $drive.IsReady) { $errors.Add("${name} ($p): el disco $($drive.Name) no existe o no esta disponible."); continue }
        if ($drive.DriveType -ne [System.IO.DriveType]::Fixed) {
            $errors.Add("${name} ($p): el disco $($drive.Name) es de tipo '$($drive.DriveType)'. Tiene que ser un disco local fijo (no red ni removible).")
            continue
        }
        if ($name -eq 'nodeLink' -and $drive.DriveFormat -ne 'NTFS') {
            $errors.Add("nodeLink ($p): el disco $($drive.Name) es $($drive.DriveFormat). Los junctions necesitan NTFS.")
        }
    }

    if ($NodeLink -and $NodesDir) {
        $a = $NodeLink.TrimEnd('\') + '\'
        $b = $NodesDir.TrimEnd('\') + '\'
        if ($a -ieq $b) {
            $errors.Add("nodeLink y nodesDir no pueden ser la misma carpeta.")
        } elseif ($b.StartsWith($a, [StringComparison]::OrdinalIgnoreCase)) {
            $errors.Add("nodesDir ($NodesDir) no puede estar adentro de nodeLink ($NodeLink): el junction se apuntaria a si mismo.")
        } elseif ($a.StartsWith($b, [StringComparison]::OrdinalIgnoreCase)) {
            $errors.Add("nodeLink ($NodeLink) no puede estar adentro de nodesDir ($NodesDir): se mezclaria con las versiones.")
        }
    }
    return ,$errors
}

# Valida y, si hay problemas, los muestra. Devuelve $true si esta todo OK.
function Assert-FnvmPaths {
    param([string]$NodeLink = $script:FnvmNodeLink, [string]$NodesDir = $script:FnvmNodesRoot)
    $errs = Test-FnvmPaths -NodeLink $NodeLink -NodesDir $NodesDir
    if ($errs.Count -eq 0) { return $true }
    Write-Host "Las rutas de fnvm no cumplen las reglas:" -ForegroundColor Red
    $errs | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host "No se toco nada. Revisa con 'fnvm config'." -ForegroundColor DarkGray
    return $false
}

# =====================================================================
# Helpers generales
# =====================================================================

function Confirm-Fnvm {
    param([string]$Question)
    $ans = Read-Host "$Question (s/N)"
    return ($ans -match '^(s|si|y|yes)$')
}

function Get-FnvmVersions {
    if (-not (Test-Path $script:FnvmNodesRoot)) { return @() }
    Get-ChildItem $script:FnvmNodesRoot -Directory |
        Where-Object { $_.Name -match '^node-v(\d+\.\d+\.\d+)' } |
        ForEach-Object {
            [pscustomobject]@{
                Version = ($_.Name -replace '^node-v','' -replace '-win-x64$','')
                Path    = $_.FullName
                Name    = $_.Name
            }
        } | Sort-Object { [version]$_.Version }
}

function Get-FnvmActiveTarget {
    $item = Get-Item $script:FnvmNodeLink -ErrorAction SilentlyContinue
    if ($item -and $item.Target) { return ($item.Target | Select-Object -First 1) }
    return $null
}

# Crea (o reapunta) el junction. Falla si en $Link hay una carpeta real.
function Set-FnvmJunction {
    param([string]$Link, [string]$Target)
    $item = Get-Item $Link -ErrorAction SilentlyContinue
    if ($item) {
        if ($item.LinkType -ne 'Junction') { throw "$Link es una carpeta real, no un junction. fnvm no la pisa." }
        cmd /c rmdir "$Link" | Out-Null
    }
    $parent = Split-Path $Link -Parent
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    cmd /c mklink /J "$Link" "$Target" | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $Link)) { throw "No se pudo crear el junction $Link -> $Target." }
}

# Procesos node.exe que corren desde alguna de las rutas indicadas (bloquean mover/borrar).
function Get-FnvmBusyProcesses {
    param([string[]]$Paths)
    Get-Process node -ErrorAction SilentlyContinue | Where-Object {
        $pp = $_.Path
        $pp -and ($Paths | Where-Object { $_ -and $pp.StartsWith(($_.TrimEnd('\') + '\'), [StringComparison]::OrdinalIgnoreCase) })
    }
}

function Test-FnvmInPath {
    param([string]$Dir)
    $all = @([Environment]::GetEnvironmentVariable('Path', 'User'), [Environment]::GetEnvironmentVariable('Path', 'Machine')) -join ';'
    $target = ConvertTo-FnvmPath $Dir
    foreach ($p in ($all -split ';')) {
        if ($p -and ((ConvertTo-FnvmPath $p) -ieq $target)) { return $true }
    }
    return $false
}

# Reemplaza $Old por $New en el PATH de USUARIO (o agrega $New), previa confirmacion.
# Escribe directo en el registro para conservar el tipo (REG_EXPAND_SZ) y no romper
# entradas con %VARIABLES%. El PATH de sistema (Machine) requiere admin: solo avisa.
function Update-FnvmUserPath {
    param([string]$Old, [string]$New)
    $userParts    = @(([Environment]::GetEnvironmentVariable('Path', 'User'))    -split ';' | Where-Object { $_ })
    $machineParts = @(([Environment]::GetEnvironmentVariable('Path', 'Machine')) -split ';' | Where-Object { $_ })
    $oldInUser    = $Old -and @($userParts    | Where-Object { (ConvertTo-FnvmPath $_) -ieq $Old }).Count -gt 0
    $oldInMachine = $Old -and @($machineParts | Where-Object { (ConvertTo-FnvmPath $_) -ieq $Old }).Count -gt 0
    $newInPath    = Test-FnvmInPath $New

    if ($newInPath -and -not $oldInUser) {
        Write-Host "PATH: $New ya esta en el PATH." -ForegroundColor Green
    } else {
        if ($oldInUser) { Write-Host "PATH: hay que reemplazar $Old por $New en el PATH de usuario." -ForegroundColor Cyan }
        else            { Write-Host "PATH: hay que agregar $New al PATH de usuario." -ForegroundColor Cyan }

        if (Confirm-Fnvm "Actualizo el PATH de usuario?") {
            $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
            $raw = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            $kind = [Microsoft.Win32.RegistryValueKind]::ExpandString
            try { $kind = $key.GetValueKind('Path') } catch { }
            $parts = @($raw -split ';' | Where-Object { $_ })
            $parts = @($parts | ForEach-Object { if ((ConvertTo-FnvmPath $_) -ieq $Old) { $New } else { $_ } })
            if (@($parts | Where-Object { (ConvertTo-FnvmPath $_) -ieq $New }).Count -eq 0) { $parts += $New }
            $key.SetValue('Path', ($parts -join ';'), $kind)
            $key.Close()
            # avisa a Windows del cambio (asi lo toman las consolas nuevas)
            [Environment]::SetEnvironmentVariable('FNVM_PATH_REFRESH', '1', 'User')
            [Environment]::SetEnvironmentVariable('FNVM_PATH_REFRESH', $null, 'User')
            # y a la sesion actual
            $sess = @($env:Path -split ';' | Where-Object { $_ } | ForEach-Object { if ((ConvertTo-FnvmPath $_) -ieq $Old) { $New } else { $_ } })
            if (@($sess | Where-Object { (ConvertTo-FnvmPath $_) -ieq $New }).Count -eq 0) { $sess += $New }
            $env:Path = $sess -join ';'
            Write-Host "PATH de usuario actualizado. Las consolas que ya estaban abiertas no lo ven: abri una nueva." -ForegroundColor Green
        } else {
            Write-Host "No toque el PATH. Hacelo a mano (Configuracion > Variables de entorno de tu usuario):" -ForegroundColor Yellow
            if ($oldInUser) { Write-Host "  reemplaza $Old por $New" -ForegroundColor Yellow }
            else            { Write-Host "  agrega $New" -ForegroundColor Yellow }
        }
    }
    if ($oldInMachine) {
        Write-Host "Ojo: $Old esta en el PATH de sistema. Sacarlo requiere admin; mientras tanto no molesta (esa ruta ya no tiene node)." -ForegroundColor Yellow
    }
}

# =====================================================================
# fnvm config
# =====================================================================

function Show-FnvmConfig {
    Write-Host "fnvm v$($script:FnvmVersion) - configuracion" -ForegroundColor Cyan
    Write-Host ""
    $cfgNote = if (Test-Path $script:FnvmConfigFile) { "" } else { "   (no existe: se usan los defaults)" }
    Write-Host ("  archivo    {0}{1}" -f $script:FnvmConfigFile, $cfgNote)
    Write-Host ("  nodeLink   {0}   ({1})" -f $script:FnvmNodeLink,  $script:FnvmNodeLinkSource)
    Write-Host ("  nodesDir   {0}   ({1})" -f $script:FnvmNodesRoot, $script:FnvmNodesRootSource)
    Write-Host ""

    $item = Get-Item $script:FnvmNodeLink -ErrorAction SilentlyContinue
    if (-not $item) {
        Write-Host "  junction   no existe todavia (se crea con 'fnvm use <version>')" -ForegroundColor Yellow
    } elseif ($item.LinkType -ne 'Junction') {
        Write-Host "  junction   PROBLEMA: $($script:FnvmNodeLink) es una carpeta real, no un junction" -ForegroundColor Red
    } else {
        $t = $item.Target | Select-Object -First 1
        $inside = ($t.TrimEnd('\') + '\').StartsWith($script:FnvmNodesRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)
        if (-not (Test-Path $t))  { Write-Host "  junction   PROBLEMA: apunta a $t, que no existe" -ForegroundColor Red }
        elseif (-not $inside)     { Write-Host "  junction   -> $t   (ojo: esta FUERA de nodesDir)" -ForegroundColor Yellow }
        else                      { Write-Host "  junction   -> $t" -ForegroundColor Green }
    }

    $n = @(Get-FnvmVersions).Count
    Write-Host "  versiones  $n en nodesDir"

    if (Test-FnvmInPath $script:FnvmNodeLink) {
        Write-Host "  PATH       nodeLink esta en el PATH" -ForegroundColor Green
    } else {
        Write-Host "  PATH       nodeLink NO esta en el PATH ('node' no se va a reconocer en consola)" -ForegroundColor Yellow
    }

    $errs = Test-FnvmPaths -NodeLink $script:FnvmNodeLink -NodesDir $script:FnvmNodesRoot
    if ($errs.Count -eq 0) {
        Write-Host "  reglas     OK (discos locales, junction en NTFS, sin carpetas anidadas)" -ForegroundColor Green
    } else {
        Write-Host "  reglas     PROBLEMAS:" -ForegroundColor Red
        $errs | ForEach-Object { Write-Host "               - $_" -ForegroundColor Red }
    }
    Write-Host ""
    Write-Host "  Para cambiar:  fnvm config set nodesDir <ruta>   |   fnvm config set nodeLink <ruta>" -ForegroundColor DarkGray
}

# Cambia la carpeta de versiones: mueve las versiones y reapunta el junction.
function Set-FnvmNodesDir {
    param([string]$NewDir)
    $new = ConvertTo-FnvmPath $NewDir
    $old = $script:FnvmNodesRoot
    if ($new -ieq $old) { Write-Host "nodesDir ya es $new. No hay nada que cambiar." -ForegroundColor Yellow; return }
    if ($env:FNVM_NODES_DIR) {
        Write-Host "La variable FNVM_NODES_DIR esta definida y pisa config.json. Sacala primero:" -ForegroundColor Red
        Write-Host "  Remove-Item Env:\FNVM_NODES_DIR   (y del entorno de usuario si la definiste ahi)" -ForegroundColor DarkGray
        return
    }
    if (-not (Assert-FnvmPaths -NodeLink $script:FnvmNodeLink -NodesDir $new)) { return }

    $versions     = @(Get-FnvmVersions)
    $activeTarget = Get-FnvmActiveTarget
    $activeName   = if ($activeTarget) { Split-Path $activeTarget.TrimEnd('\') -Leaf } else { $null }
    $activeInOld  = $activeTarget -and ($activeTarget.TrimEnd('\') + '\').StartsWith($old.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)
    $crossVolume  = $old.Substring(0, 1) -ine $new.Substring(0, 1)

    Write-Host "Cambiar nodesDir" -ForegroundColor Cyan
    Write-Host "  de  $old"
    Write-Host "  a   $new"
    if ($versions.Count -gt 0) {
        Write-Host "  se MUEVEN $($versions.Count) version(es): $(($versions | ForEach-Object { $_.Version }) -join ', ')"
        if ($crossVolume) { Write-Host "  (son discos distintos: se copian y despues se borran del origen; puede tardar)" -ForegroundColor DarkGray }
    } else {
        Write-Host "  no hay versiones para mover"
    }
    if ($activeInOld) { Write-Host "  el junction se reapunta a $new\$activeName" }
    if (-not (Confirm-Fnvm "Continuar?")) { Write-Host "Cancelado. No se toco nada." -ForegroundColor Yellow; return }

    if ($versions.Count -gt 0) {
        $busy = @(Get-FnvmBusyProcesses -Paths @($old, $script:FnvmNodeLink))
        if ($busy.Count -gt 0) {
            Write-Host "Hay procesos node corriendo desde esas versiones (PID: $(($busy | ForEach-Object { $_.Id }) -join ', '))." -ForegroundColor Red
            Write-Host "Cerralos y volve a intentar. No se toco nada." -ForegroundColor Red
            return
        }
    }

    if (-not (Test-Path $new)) { New-Item -ItemType Directory -Path $new -Force | Out-Null }

    # La version activa se mueve ultima, asi el junction sigue sano si algo falla antes.
    $ordered = @($versions | Where-Object { $_.Name -ne $activeName }) + @($versions | Where-Object { $_.Name -eq $activeName })
    foreach ($v in $ordered) {
        $dest = Join-Path $new $v.Name
        if (Test-Path $dest) {
            Write-Host "  $($v.Name) ya existe en el destino: se usa esa y se deja la original en $old" -ForegroundColor Yellow
            continue
        }
        Write-Host "  moviendo $($v.Name) ..." -ForegroundColor DarkGray
        try {
            if ($crossVolume) {
                Copy-Item $v.Path $dest -Recurse -Force -ErrorAction Stop
                Remove-Item $v.Path -Recurse -Force -ErrorAction Stop
            } else {
                Move-Item $v.Path $dest -ErrorAction Stop
            }
        } catch {
            Write-Host "Fallo moviendo $($v.Name): $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "La configuracion NO se cambio. Las versiones ya movidas quedaron en $new; revisalas." -ForegroundColor Red
            return
        }
    }

    Update-FnvmConfig -Key 'nodesDir' -Value $new
    Initialize-FnvmPaths

    if ($activeInOld -and $activeName) {
        $newTarget = Join-Path $script:FnvmNodesRoot $activeName
        try { Set-FnvmJunction -Link $script:FnvmNodeLink -Target $newTarget }
        catch { Write-Host "No pude reapuntar el junction: $($_.Exception.Message). Corre 'fnvm use <version>'." -ForegroundColor Red }
    }

    if ((Test-Path $old) -and -not (Get-ChildItem $old -Force | Select-Object -First 1)) {
        Remove-Item $old -Force -ErrorAction SilentlyContinue
    }
    Write-Host "Listo: nodesDir = $($script:FnvmNodesRoot)" -ForegroundColor Green
}

# Cambia la ruta del junction: crea el nuevo, borra el viejo y ofrece actualizar el PATH.
function Set-FnvmNodeLink {
    param([string]$NewLink)
    $new = ConvertTo-FnvmPath $NewLink
    $old = $script:FnvmNodeLink
    if ($new -ieq $old) { Write-Host "nodeLink ya es $new. No hay nada que cambiar." -ForegroundColor Yellow; return }
    if ($env:FNVM_NODE_LINK) {
        Write-Host "La variable FNVM_NODE_LINK esta definida y pisa config.json. Sacala primero:" -ForegroundColor Red
        Write-Host "  Remove-Item Env:\FNVM_NODE_LINK   (y del entorno de usuario si la definiste ahi)" -ForegroundColor DarkGray
        return
    }
    if (-not (Assert-FnvmPaths -NodeLink $new -NodesDir $script:FnvmNodesRoot)) { return }
    if (Test-Path $new) {
        Write-Host "Ya existe algo en $new. Borralo o elegi otra ruta (fnvm no pisa carpetas existentes)." -ForegroundColor Red
        return
    }

    $target = Get-FnvmActiveTarget
    if (-not $target -or -not (Test-Path $target)) {
        $top = Get-FnvmVersions | Select-Object -Last 1
        $target = if ($top) { $top.Path } else { $null }
    }
    $oldItem       = Get-Item $old -ErrorAction SilentlyContinue
    $oldIsJunction = $oldItem -and $oldItem.LinkType -eq 'Junction'

    Write-Host "Cambiar nodeLink" -ForegroundColor Cyan
    Write-Host "  de  $old"
    Write-Host "  a   $new"
    if ($target) { Write-Host "  el junction nuevo apunta a $target" }
    else         { Write-Host "  no hay versiones instaladas: el junction se crea con el primer 'fnvm use'" }
    if ($oldIsJunction) { Write-Host "  se borra el junction viejo (solo el enlace; las versiones no se tocan)" }
    elseif ($oldItem)   { Write-Host "  en $old hay una carpeta real: no se toca" -ForegroundColor Yellow }
    if (-not (Confirm-Fnvm "Continuar?")) { Write-Host "Cancelado. No se toco nada." -ForegroundColor Yellow; return }

    if ($target) {
        try { Set-FnvmJunction -Link $new -Target $target }
        catch { Write-Host "No pude crear el junction nuevo: $($_.Exception.Message). No se toco nada." -ForegroundColor Red; return }
    }
    if ($oldIsJunction) { cmd /c rmdir "$old" | Out-Null }

    Update-FnvmConfig -Key 'nodeLink' -Value $new
    Initialize-FnvmPaths
    Write-Host "Listo: nodeLink = $($script:FnvmNodeLink)" -ForegroundColor Green

    Update-FnvmUserPath -Old $old -New $new
}

# =====================================================================
# Deteccion de version del proyecto / indice remoto
# =====================================================================

# Orden: .nvmrc -> package.json (engines.node). Devuelve Version y Source, o $null.
function Get-FnvmProjectVersion {
    $cwd = (Get-Location).Path

    $nvmrc = Join-Path $cwd '.nvmrc'
    if (Test-Path $nvmrc) {
        $raw = (Get-Content $nvmrc -Raw).Trim()
        if ($raw) {
            # aliases de nvm (lts/*, node, stable) no se soportan: solo numeros
            $clean = $raw -replace '^v',''
            if ($clean -match '^\d') {
                return [pscustomobject]@{ Version = $clean; Source = '.nvmrc' }
            }
            return [pscustomobject]@{ Version = $null; Source = '.nvmrc'; Raw = $raw }
        }
    }

    $pkg = Join-Path $cwd 'package.json'
    if (Test-Path $pkg) {
        try {
            $json = Get-Content $pkg -Raw | ConvertFrom-Json
            $eng = $json.engines.node
            if ($eng) {
                # engines declara un rango (">=18", "^18.0.0", "18.x"...). Lo que importa
                # es la major; matcheamos por ella para agarrar la version real instalada.
                $m = [regex]::Match($eng, '(\d+)')
                if ($m.Success) {
                    return [pscustomobject]@{ Version = $m.Groups[1].Value; Source = "package.json (engines.node: $eng)" }
                }
            }
        } catch { }
    }
    return $null
}

# Resuelve '22', '22.11.0' o 'lts' a una version exacta (sin la 'v') segun el indice oficial.
function Resolve-FnvmRemoteVersion {
    param([string]$Requested)
    try {
        $idx = Invoke-RestMethod -Uri "https://nodejs.org/dist/index.json" -TimeoutSec 20 -UseBasicParsing
    } catch {
        Write-Host "No pude consultar el indice de versiones de Node: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
    $idx = $idx | Where-Object { $_.files -contains 'win-x64-zip' }

    if ($Requested -match '^lts$') {
        $v = ($idx | Where-Object { $_.lts } | Select-Object -First 1).version
        return ($v -replace '^v','')
    }
    $clean = $Requested -replace '^v',''
    $exact = $idx | Where-Object { ($_.version -replace '^v','') -eq $clean } | Select-Object -First 1
    if ($exact) { return ($exact.version -replace '^v','') }
    $cands = $idx | Where-Object { ($_.version -replace '^v','') -like "$clean.*" }
    if ($cands) {
        $top = $cands | Sort-Object { [version]($_.version -replace '^v','') } -Descending | Select-Object -First 1
        return ($top.version -replace '^v','')
    }
    return $null
}

# =====================================================================
# Comandos
# =====================================================================

function fnvm {
    # Se usa $args crudo (no param nombrado) para que '-v' no lo capture el parser
    # de PowerShell como si fuera un parametro.
    $Command = if ($args.Count -ge 1) { [string]$args[0] } else { "" }
    $Version = if ($args.Count -ge 2) { [string]$args[1] } else { "" }
    $Arg3    = if ($args.Count -ge 3) { [string]$args[2] } else { "" }
    $Arg4    = if ($args.Count -ge 4) { ($args[3..($args.Count - 1)] -join ' ') } else { "" }

    switch -Regex ($Command) {
        '^(-v|--version|version)$' {
            Write-Host "fnvm v$($script:FnvmVersion)" -ForegroundColor Cyan
            return
        }
        '^current$' {
            $node = Join-Path $script:FnvmNodeLink 'node.exe'
            if (Test-Path $node) {
                $v = & $node -v
                $target = Get-FnvmActiveTarget
                Write-Host "node $v" -ForegroundColor Green -NoNewline
                if ($target) { Write-Host "  ($target)" -ForegroundColor DarkGray } else { Write-Host "" }
            } else {
                Write-Host "No hay node activo en $($script:FnvmNodeLink)" -ForegroundColor Red
            }
            return
        }
        '^which$' {
            $target = Get-FnvmActiveTarget
            if ($target) {
                Write-Output (Join-Path $target.TrimEnd('\') 'node.exe')
            } else {
                $node = Join-Path $script:FnvmNodeLink 'node.exe'
                if (Test-Path $node) { Write-Output $node }
                else { Write-Host "No hay node activo en $($script:FnvmNodeLink)" -ForegroundColor Red }
            }
            return
        }
        '^(list|ls)$' {
            $target = Get-FnvmActiveTarget
            $root = $script:FnvmNodesRoot
            Write-Host "Versiones de Node disponibles en ${root}:`n"
            foreach ($v in Get-FnvmVersions) {
                $active = if ($target -and $target.TrimEnd('\') -ieq $v.Path.TrimEnd('\')) { "* " } else { "  " }
                $color  = if ($active -eq "* ") { "Green" } else { "Gray" }
                Write-Host ("{0}{1}" -f $active, $v.Version) -ForegroundColor $color
            }
            Write-Host "`n(* = version activa)" -ForegroundColor DarkGray
            return
        }
        '^config$' {
            if (-not $Version) { Show-FnvmConfig; return }
            if ($Version -ieq 'set') {
                if (-not $Arg3 -or -not $Arg4) {
                    Write-Host "Uso: fnvm config set nodesDir <ruta>   |   fnvm config set nodeLink <ruta>" -ForegroundColor Yellow
                    return
                }
                if ($Arg3 -ieq 'nodesDir')     { Set-FnvmNodesDir -NewDir $Arg4 }
                elseif ($Arg3 -ieq 'nodeLink') { Set-FnvmNodeLink -NewLink $Arg4 }
                else { Write-Host "Clave desconocida '$Arg3'. Validas: nodeLink, nodesDir." -ForegroundColor Red }
                return
            }
            Write-Host "Uso: fnvm config   |   fnvm config set nodesDir <ruta>   |   fnvm config set nodeLink <ruta>" -ForegroundColor Yellow
            return
        }
        '^(install|i)$' {
            if (-not $Version) {
                Write-Host "Uso: fnvm install <version>  (alias: fnvm i)" -ForegroundColor Yellow
                Write-Host "  fnvm i 22.11.0   version exacta" -ForegroundColor DarkGray
                Write-Host "  fnvm i 22        la ultima 22.x del indice oficial" -ForegroundColor DarkGray
                Write-Host "  fnvm i lts       la ultima LTS" -ForegroundColor DarkGray
                return
            }
            if (-not (Assert-FnvmPaths)) { return }
            $resolved = Resolve-FnvmRemoteVersion -Requested $Version
            if (-not $resolved) {
                Write-Host "No encontre ninguna version de Node (win-x64) que matchee '$Version'." -ForegroundColor Red
                return
            }
            $folderName = "node-v$resolved-win-x64"
            $dest = Join-Path $script:FnvmNodesRoot $folderName
            if (Test-Path $dest) {
                Write-Host "La version $resolved ya esta en $dest" -ForegroundColor Yellow
                Write-Host "Activala con: fnvm use $resolved" -ForegroundColor DarkGray
                return
            }
            if (-not (Test-Path $script:FnvmNodesRoot)) { New-Item -ItemType Directory -Path $script:FnvmNodesRoot -Force | Out-Null }

            $url = "https://nodejs.org/dist/v$resolved/$folderName.zip"
            $zip = Join-Path $env:TEMP "$folderName.zip"
            Write-Host "Descargando Node v$resolved ..." -ForegroundColor Cyan
            Write-Host "  $url" -ForegroundColor DarkGray
            try {
                Invoke-WebRequest -Uri $url -OutFile $zip -TimeoutSec 300 -UseBasicParsing
            } catch {
                Write-Host "Fallo la descarga: $($_.Exception.Message)" -ForegroundColor Red
                return
            }
            Write-Host "Descomprimiendo en $($script:FnvmNodesRoot) ..." -ForegroundColor Cyan
            try {
                Expand-Archive -Path $zip -DestinationPath $script:FnvmNodesRoot -Force
            } catch {
                Write-Host "Fallo la descompresion: $($_.Exception.Message)" -ForegroundColor Red
                Remove-Item $zip -Force -ErrorAction SilentlyContinue
                return
            }
            Remove-Item $zip -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path $dest)) {
                Write-Host "El zip se descomprimio pero no encontre $dest." -ForegroundColor Red
                return
            }
            # quita la marca de internet (Zone.Identifier) de los launchers
            Get-ChildItem $dest -File -Filter *.ps1 -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue
            Write-Host "Node v$resolved instalado en $dest" -ForegroundColor Green
            Write-Host "Activalo con: fnvm use $resolved" -ForegroundColor DarkGray
            return
        }
        '^use$' {
            if (-not $Version) {
                $proj = Get-FnvmProjectVersion
                if (-not $proj) {
                    Write-Host "No encontre .nvmrc ni engines.node (package.json) en esta carpeta." -ForegroundColor Yellow
                    Write-Host "Uso: fnvm use <version>   (ej: fnvm use 18, fnvm use 18.20.8)" -ForegroundColor DarkGray
                    return
                }
                if (-not $proj.Version) {
                    Write-Host "El .nvmrc dice '$($proj.Raw)', que es un alias de nvm no soportado." -ForegroundColor Yellow
                    Write-Host "Indica una version numerica: fnvm use <version>" -ForegroundColor DarkGray
                    return
                }
                Write-Host "Detectado en $($proj.Source) -> $($proj.Version)" -ForegroundColor Cyan
                $Version = $proj.Version
            }
            $all = @(Get-FnvmVersions)
            $found = @($all | Where-Object { $_.Version -eq $Version })
            if ($found.Count -eq 0) { $found = @($all | Where-Object { $_.Version -like "$Version*" }) }
            if ($found.Count -eq 0) {
                Write-Host "No tenes instalada ninguna version que matchee '$Version'." -ForegroundColor Red
                Write-Host "Instalala con: fnvm install $Version   (o: fnvm i $Version)" -ForegroundColor Cyan
                Write-Host "Versiones que ya tenes:" -ForegroundColor DarkGray
                $all | ForEach-Object { Write-Host "  $($_.Version)" -ForegroundColor DarkGray }
                return
            }
            if ($found.Count -gt 1) {
                Write-Host "Hay varias versiones que matchean '$Version'. Se mas especifico:" -ForegroundColor Yellow
                $found | ForEach-Object { Write-Host "  $($_.Version)" -ForegroundColor Yellow }
                return
            }
            $sel = $found[0]
            if (-not (Assert-FnvmPaths)) { return }
            try {
                Set-FnvmJunction -Link $script:FnvmNodeLink -Target $sel.Path
            } catch {
                Write-Host "ATENCION: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "Si $($script:FnvmNodeLink) es una carpeta real, renombrala (ej. node_backup) y volve a correr." -ForegroundColor Red
                return
            }
            Get-ChildItem $sel.Path -File -Filter *.ps1 -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue
            $v = & (Join-Path $script:FnvmNodeLink 'node.exe') -v
            Write-Host "Node activo -> $v  ($($sel.Name))" -ForegroundColor Green
            return
        }
        '^(help|--help|-h|)$' {
            Write-Host "fnvm v$($script:FnvmVersion) - Fabian Node Version Manager" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "  fnvm -v | version      version de la herramienta fnvm"
            Write-Host "  fnvm current           version de Node activa"
            Write-Host "  fnvm which             ruta real del node.exe activo"
            Write-Host "  fnvm list | ls         lista las versiones instaladas (marca la activa con *)"
            Write-Host "  fnvm help              esta ayuda"
            Write-Host ""
            Write-Host "  fnvm install | i <ver> descarga una version a nodesDir :" -ForegroundColor Gray
            Write-Host "     fnvm i 22.11.0         version exacta"
            Write-Host "     fnvm i 22              la ultima 22.x del indice oficial"
            Write-Host "     fnvm i lts             la ultima LTS"
            Write-Host ""
            Write-Host "  fnvm use <version>     activa una version YA instalada :" -ForegroundColor Gray
            Write-Host "     fnvm use 18.20.8       version exacta"
            Write-Host "     fnvm use 18            la major 18 que tengas (si hay varias, pide precision)"
            Write-Host "                            (si no la tenes instalada, te sugiere: fnvm i)"
            Write-Host "  fnvm use               detecta del proyecto (.nvmrc, o engines.node del package.json)"
            Write-Host ""
            Write-Host "  fnvm config            muestra las rutas en uso y si cumplen las reglas" -ForegroundColor Gray
            Write-Host "     fnvm config set nodesDir <ruta>   mueve las versiones a otra carpeta"
            Write-Host "     fnvm config set nodeLink <ruta>   mueve el junction (y ofrece actualizar el PATH)"
            Write-Host ""
            Write-Host "  fnpm <args>            npm con el Node activo (fnpm i, fnpm install, fnpm run ...)"
        }
        default {
            Write-Host "Comando desconocido: '$Command'" -ForegroundColor Yellow
            Write-Host "Escribi 'fnvm help' para ver los comandos disponibles." -ForegroundColor DarkGray
        }
    }
}

function fnpm {
    # Invoca npm a traves de node + npm-cli.js (mas confiable que la capa npm.cmd).
    $node = Join-Path $script:FnvmNodeLink 'node.exe'
    $cli  = Join-Path $script:FnvmNodeLink 'node_modules\npm\bin\npm-cli.js'
    if ((Test-Path $node) -and (Test-Path $cli)) {
        & $node $cli @args
        return
    }
    $npm = Join-Path $script:FnvmNodeLink 'npm.cmd'
    if (Test-Path $npm) { & $npm @args; return }
    Write-Host "No encontre npm en $($script:FnvmNodeLink)" -ForegroundColor Red
}

# Resolver rutas al cargar (rapido: sin validaciones ni accesos de red).
Initialize-FnvmPaths
