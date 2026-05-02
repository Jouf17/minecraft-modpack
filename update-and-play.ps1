$ErrorActionPreference = "Stop"

# Force TLS 1.2 pour les telechargements HTTPS sur Windows PowerShell 5.1.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Configuration du modpack.
$ManifestUrl = "https://raw.githubusercontent.com/Jouf17/minecraft-modpack/main/manifest.json"
$InstanceName = "1.20.1"
$ServerAddress = "82.165.57.177:25566"
$ModsPath = Join-Path $env:APPDATA "PrismLauncher\instances\$InstanceName\.minecraft\mods"

# Chemins Prism courants sous Windows.
$PrismCandidatePaths = @(
    "C:\Program Files\PrismLauncher\prismlauncher.exe",
    "C:\Program Files (x86)\PrismLauncher\prismlauncher.exe",
    (Join-Path $env:USERPROFILE "PrismLauncher\prismlauncher.exe"),
    (Join-Path $env:LOCALAPPDATA "Programs\PrismLauncher\prismlauncher.exe")
)

# Seuls ces mods maison sont geres. Les autres mods du joueur sont conserves.
$HomeModPatterns = @(
    "customships*.jar",
    "customuniverse*.jar"
)

function Write-Step {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Fail {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    Write-Host "[ERREUR] $Message" -ForegroundColor Red
}

function Find-PrismLauncher {
    foreach ($Path in $PrismCandidatePaths) {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            return $Path
        }
    }

    # Si Prism est deja ouvert, Windows expose souvent son chemin via la liste des processus.
    $RunningPrism = Get-Process -Name "prismlauncher" -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($null -ne $RunningPrism -and -not [string]::IsNullOrWhiteSpace($RunningPrism.Path)) {
        return $RunningPrism.Path
    }

    return $null
}

try {
    Write-Step "Verification de Prism Launcher"

    $PrismPath = Find-PrismLauncher

    if ([string]::IsNullOrWhiteSpace($PrismPath)) {
        throw "Prism Launcher est introuvable. Installe Prism Launcher ou ajoute son chemin dans `$PrismCandidatePaths dans update-and-play.ps1."
    }

    Write-Ok "Prism Launcher trouve : $PrismPath"

    Write-Step "Preparation du dossier mods"

    if (-not (Test-Path -LiteralPath $ModsPath -PathType Container)) {
        New-Item -ItemType Directory -Path $ModsPath -Force | Out-Null
        Write-Ok "Dossier mods cree : $ModsPath"
    }
    else {
        Write-Ok "Dossier mods trouve : $ModsPath"
    }

    Write-Step "Lecture du manifest"
    $Manifest = Invoke-RestMethod -Uri $ManifestUrl

    if ($null -eq $Manifest.mods -or $Manifest.mods.Count -eq 0) {
        throw "Le manifest ne contient aucun mod a telecharger : $ManifestUrl"
    }

    Write-Ok "Manifest version $($Manifest.version) charge"

    $ExpectedModNames = @($Manifest.mods | ForEach-Object { $_.name })

    Write-Step "Detection des mods maison a mettre a jour"

    foreach ($Pattern in $HomeModPatterns) {
        $InstalledHomeMods = Get-ChildItem -Path $ModsPath -Filter $Pattern -File -ErrorAction SilentlyContinue

        foreach ($InstalledMod in $InstalledHomeMods) {
            if ($InstalledMod.Name -notin $ExpectedModNames) {
                Remove-Item -LiteralPath $InstalledMod.FullName -Force
                Write-Host "Ancienne version supprimee : $($InstalledMod.Name)"
            }
            else {
                Write-Host "Deja a jour : $($InstalledMod.Name)"
            }
        }
    }

    Write-Step "Telechargement des mods manquants"

    foreach ($Mod in $Manifest.mods) {
        if ([string]::IsNullOrWhiteSpace($Mod.name) -or [string]::IsNullOrWhiteSpace($Mod.url)) {
            throw "Entree invalide dans manifest.json : chaque mod doit avoir un name et une url."
        }

        $Destination = Join-Path $ModsPath $Mod.name

        if (Test-Path -LiteralPath $Destination -PathType Leaf) {
            Write-Host "Ignore, deja installe : $($Mod.name)"
            continue
        }

        Write-Host "Telechargement : $($Mod.name)"

        try {
            Invoke-WebRequest -Uri $Mod.url -OutFile $Destination -MaximumRedirection 10
        }
        catch {
            if (Test-Path -LiteralPath $Destination -PathType Leaf) {
                Remove-Item -LiteralPath $Destination -Force
            }

            throw "Impossible de telecharger $($Mod.name). Verifie que cette URL existe et que la release GitHub est publique : $($Mod.url)`nDetail : $($_.Exception.Message)"
        }

        Write-Ok "Installe : $($Mod.name)"
    }

    Write-Step "Lancement de Minecraft"
    Write-Host "Instance Prism : $InstanceName"
    Write-Host "Serveur : $ServerAddress"

    Start-Process -FilePath $PrismPath -ArgumentList @("--launch", $InstanceName, "--server", $ServerAddress)
    Write-Ok "Prism Launcher a ete lance"
}
catch {
    Write-Host ""
    Write-Fail $_.Exception.Message
    Write-Host ""
    Write-Host "La mise a jour a echoue. Verifie le message ci-dessus, puis relance Jouer.bat." -ForegroundColor Yellow
    exit 1
}
