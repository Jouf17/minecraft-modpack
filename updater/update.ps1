$ErrorActionPreference = "Stop"

# Force TLS 1.2 pour les telechargements HTTPS sur Windows PowerShell 5.1.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$PackageRoot = Split-Path -Parent $PSScriptRoot
$ConfigPath = Join-Path $PSScriptRoot "config.json"

function Write-Step {
    param([Parameter(Mandatory = $true)][string] $Message)

    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([Parameter(Mandatory = $true)][string] $Message)

    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Fail {
    param([Parameter(Mandatory = $true)][string] $Message)

    Write-Host "[ERREUR] $Message" -ForegroundColor Red
}

function Read-Config {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "Fichier de configuration introuvable : $ConfigPath"
    }

    return Get-Content -Raw -LiteralPath $ConfigPath | ConvertFrom-Json
}

function Find-PrismLauncher {
    $CandidatePaths = @(
        (Join-Path $env:LOCALAPPDATA "Programs\PrismLauncher\prismlauncher.exe"),
        "C:\Program Files\PrismLauncher\prismlauncher.exe",
        "C:\Program Files (x86)\PrismLauncher\prismlauncher.exe",
        (Join-Path $env:USERPROFILE "PrismLauncher\prismlauncher.exe")
    )

    foreach ($Path in $CandidatePaths) {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            return $Path
        }
    }

    $RunningPrism = Get-Process -Name "prismlauncher" -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($null -ne $RunningPrism -and -not [string]::IsNullOrWhiteSpace($RunningPrism.Path)) {
        return $RunningPrism.Path
    }

    return $null
}

function Download-File {
    param(
        [Parameter(Mandatory = $true)][string] $Url,
        [Parameter(Mandatory = $true)][string] $Destination
    )

    $TempDestination = "$Destination.tmp"

    if (Test-Path -LiteralPath $TempDestination -PathType Leaf) {
        Remove-Item -LiteralPath $TempDestination -Force
    }

    try {
        $Curl = Get-Command "curl.exe" -ErrorAction SilentlyContinue

        if ($null -ne $Curl) {
            & $Curl.Source -L --fail --silent --show-error --output $TempDestination $Url

            if ($LASTEXITCODE -ne 0) {
                throw "curl.exe a retourne le code $LASTEXITCODE"
            }
        }
        else {
            Invoke-WebRequest -Uri $Url -OutFile $TempDestination -MaximumRedirection 10
        }

        Move-Item -LiteralPath $TempDestination -Destination $Destination -Force
    }
    catch {
        if (Test-Path -LiteralPath $TempDestination -PathType Leaf) {
            Remove-Item -LiteralPath $TempDestination -Force
        }

        throw $_
    }
}

function Read-RemoteJson {
    param([Parameter(Mandatory = $true)][string] $Url)

    $NoCacheUrl = $Url

    if ($NoCacheUrl.Contains("?")) {
        $NoCacheUrl = "${NoCacheUrl}&cacheBust=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
    }
    else {
        $NoCacheUrl = "${NoCacheUrl}?cacheBust=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
    }

    return Invoke-RestMethod -Uri $NoCacheUrl -Headers @{
        "Cache-Control" = "no-cache"
        "Pragma" = "no-cache"
        "User-Agent" = "CustomUniverse-Updater"
    }
}

function Install-PrismLauncher {
    Write-Step "Installation de Prism Launcher"

    $Release = Invoke-RestMethod -Uri "https://api.github.com/repos/PrismLauncher/PrismLauncher/releases/latest" -Headers @{
        "User-Agent" = "CustomUniverse-Updater"
    }

    $Asset = $Release.assets |
        Where-Object { $_.name -match "Windows" -and $_.name -match "Setup" -and $_.name -match "\.exe$" } |
        Select-Object -First 1

    if ($null -eq $Asset) {
        throw "Impossible de trouver l'installateur Windows de Prism Launcher sur GitHub."
    }

    $InstallerPath = Join-Path $env:TEMP $Asset.name

    Write-Host "Telechargement de Prism Launcher..."
    Download-File -Url $Asset.browser_download_url -Destination $InstallerPath

    Write-Host "L'installateur Prism va s'ouvrir. Termine l'installation, puis reviens ici."
    $Process = Start-Process -FilePath $InstallerPath -Wait -PassThru

    if ($Process.ExitCode -ne 0) {
        Write-Host "L'installateur s'est ferme avec le code $($Process.ExitCode). Verification de Prism quand meme..."
    }
}

function Get-PrismInstancesRoots {
    $Roots = @(
        (Join-Path $env:APPDATA "PrismLauncher\instances"),
        (Join-Path $env:LOCALAPPDATA "PrismLauncher\instances"),
        (Join-Path $env:APPDATA ".minecraft\instances")
    )

    return $Roots | Select-Object -Unique
}

function Find-ExistingInstance {
    param(
        [Parameter(Mandatory = $true)] $Config
    )

    foreach ($Root in Get-PrismInstancesRoots) {
        foreach ($Name in $Config.preferredInstanceNames) {
            $InstancePath = Join-Path $Root $Name
            $PackPath = Join-Path $InstancePath "mmc-pack.json"
            $CfgPath = Join-Path $InstancePath "instance.cfg"

            if ((Test-Path -LiteralPath $PackPath -PathType Leaf) -or (Test-Path -LiteralPath $CfgPath -PathType Leaf)) {
                return [pscustomobject]@{
                    Name = $Name
                    Path = $InstancePath
                    Root = $Root
                }
            }
        }
    }

    return $null
}

function Get-InstanceNameFromCfg {
    param([Parameter(Mandatory = $true)][string] $InstanceCfgPath)

    $NameLine = Get-Content -LiteralPath $InstanceCfgPath |
        Where-Object { $_ -match "^name=" } |
        Select-Object -First 1

    if ($NameLine) {
        return $NameLine.Substring(5).Trim()
    }

    return $null
}

function Import-PrismInstance {
    param(
        [Parameter(Mandatory = $true)] $Config,
        [bool] $ReplaceExisting = $false
    )

    Write-Step "Import de l'instance"

    $ArchivePath = Join-Path $PackageRoot $Config.instanceArchive

    if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
        throw "Archive d'instance introuvable : $ArchivePath`nLe fichier doit etre place dans le dossier du launcher, par exemple : <dossier du pack>\$($Config.instanceArchive)"
    }

    $InstancesRoot = Join-Path $env:APPDATA "PrismLauncher\instances"
    New-Item -ItemType Directory -Path $InstancesRoot -Force | Out-Null

    $TempRoot = Join-Path $env:TEMP ("CustomUniverse-instance-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null

    try {
        Expand-Archive -LiteralPath $ArchivePath -DestinationPath $TempRoot -Force

        $InstanceCfg = Get-ChildItem -Path $TempRoot -Recurse -Filter "instance.cfg" -File |
            Select-Object -First 1

        if ($null -eq $InstanceCfg) {
            throw "L'archive ne contient pas de fichier instance.cfg Prism valide."
        }

        $SourceInstancePath = Split-Path -Parent $InstanceCfg.FullName
        $InstanceName = Get-InstanceNameFromCfg -InstanceCfgPath $InstanceCfg.FullName

        if ([string]::IsNullOrWhiteSpace($InstanceName)) {
            $InstanceName = $Config.preferredInstanceNames[0]
        }

        $DestinationInstancePath = Join-Path $InstancesRoot $InstanceName

        if (Test-Path -LiteralPath $DestinationInstancePath -PathType Container) {
            if ($ReplaceExisting) {
                $ResolvedInstancesRoot = (Resolve-Path -LiteralPath $InstancesRoot).Path
                $ResolvedDestination = (Resolve-Path -LiteralPath $DestinationInstancePath).Path

                if (-not $ResolvedDestination.StartsWith($ResolvedInstancesRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                    throw "Refus de supprimer une instance hors du dossier Prism : $ResolvedDestination"
                }

                Write-Host "Instance existante remplacee : $InstanceName"
                Remove-Item -LiteralPath $DestinationInstancePath -Recurse -Force
                Copy-Item -LiteralPath $SourceInstancePath -Destination $DestinationInstancePath -Recurse
                Write-Ok "Instance importee : $InstanceName"
            }
            else {
                Write-Ok "Instance deja presente : $InstanceName"
            }
        }
        else {
            Copy-Item -LiteralPath $SourceInstancePath -Destination $DestinationInstancePath -Recurse
            Write-Ok "Instance importee : $InstanceName"
        }

        return [pscustomobject]@{
            Name = $InstanceName
            Path = $DestinationInstancePath
            Root = $InstancesRoot
        }
    }
    finally {
        if (Test-Path -LiteralPath $TempRoot -PathType Container) {
            Remove-Item -LiteralPath $TempRoot -Recurse -Force
        }
    }
}

function Get-ModsPath {
    param([Parameter(Mandatory = $true)] $Instance)

    $ModsPath = Join-Path $Instance.Path ".minecraft\mods"
    New-Item -ItemType Directory -Path $ModsPath -Force | Out-Null
    Write-Host "Dossier mods : $ModsPath"
    return $ModsPath
}

function Update-Mods {
    param(
        [Parameter(Mandatory = $true)] $Config,
        [Parameter(Mandatory = $true)][string] $ModsPath
    )

    Write-Step "Mise a jour des mods"

    $Manifest = Read-RemoteJson -Url $Config.manifestUrl

    if ($null -eq $Manifest.mods -or $Manifest.mods.Count -eq 0) {
        throw "Le manifest ne contient aucun mod : $($Config.manifestUrl)"
    }

    Write-Ok "Manifest version $($Manifest.version) charge"
    Write-Host "Mods attendus : $((@($Manifest.mods) | ForEach-Object { $_.name }) -join ', ')"

    $ExpectedModNames = @($Manifest.mods | ForEach-Object { $_.name })

    foreach ($Pattern in $Config.homeModPatterns) {
        $InstalledHomeMods = Get-ChildItem -Path $ModsPath -Filter $Pattern -File -ErrorAction SilentlyContinue

        foreach ($InstalledMod in $InstalledHomeMods) {
            if ($Config.removeMissingHomeMods -and $InstalledMod.Name -notin $ExpectedModNames) {
                Remove-Item -LiteralPath $InstalledMod.FullName -Force
                Write-Host "Ancienne version supprimee : $($InstalledMod.Name)"
            }
        }
    }

    foreach ($Mod in $Manifest.mods) {
        if ([string]::IsNullOrWhiteSpace($Mod.name) -or [string]::IsNullOrWhiteSpace($Mod.url)) {
            throw "Entree invalide dans le manifest : chaque mod doit avoir name et url."
        }

        $Destination = Join-Path $ModsPath $Mod.name
        $ShouldDownload = -not (Test-Path -LiteralPath $Destination -PathType Leaf)

        if (-not $ShouldDownload -and -not [string]::IsNullOrWhiteSpace($Mod.sha256)) {
            $CurrentHash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLowerInvariant()
            $ExpectedHash = ([string]$Mod.sha256).ToLowerInvariant()
            $ShouldDownload = $CurrentHash -ne $ExpectedHash
        }

        if (-not $ShouldDownload) {
            Write-Host "Deja a jour : $($Mod.name)"
            continue
        }

        Write-Host "Telechargement : $($Mod.name)"

        try {
            Download-File -Url $Mod.url -Destination $Destination
        }
        catch {
            if (Test-Path -LiteralPath $Destination -PathType Leaf) {
                Remove-Item -LiteralPath $Destination -Force
            }

            throw "Impossible de telecharger $($Mod.name) depuis $($Mod.url)`nDetail : $($_.Exception.Message)"
        }

        if (-not [string]::IsNullOrWhiteSpace($Mod.sha256)) {
            $DownloadedHash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLowerInvariant()

            if ($DownloadedHash -ne ([string]$Mod.sha256).ToLowerInvariant()) {
                Remove-Item -LiteralPath $Destination -Force
                throw "Le fichier telecharge ne correspond pas au hash attendu : $($Mod.name)"
            }
        }

        Write-Ok "Installe : $($Mod.name)"
    }

    foreach ($ExpectedModName in $ExpectedModNames) {
        $ExpectedPath = Join-Path $ModsPath $ExpectedModName

        if (-not (Test-Path -LiteralPath $ExpectedPath -PathType Leaf)) {
            throw "Mod attendu introuvable apres mise a jour : $ExpectedModName"
        }
    }

    $InstalledHomeModNames = foreach ($Pattern in $Config.homeModPatterns) {
        Get-ChildItem -Path $ModsPath -Filter $Pattern -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }
    }

    Write-Host "Mods maison presents : $((@($InstalledHomeModNames) | Sort-Object -Unique) -join ', ')"
}

try {
    $Config = Read-Config

    Write-Step "Verification de Prism Launcher"
    $PrismPath = Find-PrismLauncher

    if ([string]::IsNullOrWhiteSpace($PrismPath)) {
        Install-PrismLauncher
        $PrismPath = Find-PrismLauncher
    }

    if ([string]::IsNullOrWhiteSpace($PrismPath)) {
        throw "Prism Launcher n'a pas ete trouve apres installation."
    }

    Write-Ok "Prism Launcher trouve"

    $ReplaceExistingInstance = $false

    if ($null -ne $Config.replaceExistingInstance) {
        $ReplaceExistingInstance = [bool]$Config.replaceExistingInstance
    }

    $Instance = Find-ExistingInstance -Config $Config

    if ($ReplaceExistingInstance) {
        $Instance = Import-PrismInstance -Config $Config -ReplaceExisting $true
    }
    elseif ($null -eq $Instance) {
        $Instance = Import-PrismInstance -Config $Config
    }
    else {
        Write-Ok "Instance deja presente : $($Instance.Name)"
    }

    $ModsPath = Get-ModsPath -Instance $Instance
    Update-Mods -Config $Config -ModsPath $ModsPath

    Write-Step "Lancement du jeu"

    $LaunchArguments = @("--launch", $Instance.Name)

    if ($Config.joinServerOnLaunch) {
        $LaunchArguments += @("--server", $Config.serverAddress)
    }

    Start-Process -FilePath $PrismPath -ArgumentList $LaunchArguments
    Write-Ok "Minecraft se lance"
}
catch {
    Write-Host ""
    Write-Fail $_.Exception.Message
    Write-Host ""
    Write-Host "La preparation a echoue. Tu peux fermer cette fenetre apres avoir lu le message." -ForegroundColor Yellow
    exit 1
}
