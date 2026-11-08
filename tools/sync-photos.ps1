param(
    [Parameter(Mandatory = $true)][string]$PhotoDirectory,
    [Parameter(Mandatory = $true)][string]$TvAddress,
    [Parameter(Mandatory = $true)][string]$ExpectedModel,
    [Parameter(Mandatory = $true)][string]$ExpectedDevice,
    [switch]$Preview
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$python = Join-Path $repo 'tools\venv\Scripts\python.exe'
$prepare = Join-Path $repo 'tools\wallpaper_prep.py'
$themeTool = Join-Path $repo 'tools\theme.ps1'
$adbCommand = Get-Command adb -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
$adb = if ($adbCommand) { $adbCommand.Source } else { $null }
$remoteTheme = '/sdcard/Android/data/com.gathin.tvhome/files'
$allowedExtensions = @('.jpg', '.jpeg', '.png', '.webp', '.heic', '.heif')

function Invoke-Adb([string[]]$Arguments) {
    $ErrorActionPreference = 'Continue'
    $result = @(& $adb @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "ADB: $($result -join ' ')" }
    return $result
}

function Get-PhotoLimit([string]$LauncherInfo) {
    if ($LauncherInfo -match '(?m)^\s*versionName=3\.4-local1000\.1\s*$') { return 1000 }
    return 100
}

try {
    if (-not $adb) { throw 'ADB was not found in PATH. Install Android platform-tools first.' }
    foreach ($path in @($python, $prepare, $themeTool, $adb)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Required file not found: $path. Set up the repository Python environment first."
        }
    }
    $ip = $null
    if (-not [System.Net.IPAddress]::TryParse($TvAddress, [ref]$ip) -or $ip.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        throw 'Indirizzo TV non valido: usa un indirizzo IPv4.'
    }
    $serial = "${TvAddress}:5555"
    Write-Host "Controllo la connessione con la TV ($serial)..."
    $ErrorActionPreference = 'Continue'
    try {
        $connectOutput = @(& $adb connect $serial 2>&1)
        $state = @(& $adb -s $serial get-state 2>&1)
        $stateExit = $LASTEXITCODE
    } finally { $ErrorActionPreference = 'Stop' }
    if ($stateExit -ne 0 -or (($state -join '').Trim() -ne 'device')) {
        throw "TV non raggiungibile o PC non autorizzato. Accendi la TV, attiva Debug USB, accetta l'eventuale richiesta sullo schermo e riprova. Risposta: $($connectOutput -join ' ')"
    }
    $model = ((Invoke-Adb -Arguments @('-s', $serial, 'shell', 'getprop', 'ro.product.model')) -join '').Trim()
    $device = ((Invoke-Adb -Arguments @('-s', $serial, 'shell', 'getprop', 'ro.product.device')) -join '').Trim()
    if ($model -ne $ExpectedModel -or $device -ne $ExpectedDevice) {
        throw 'The connected device does not match the expected model and device. No photos were sent.'
    }
    if (-not (Test-Path -LiteralPath $PhotoDirectory -PathType Container)) {
        throw "Cartella foto non accessibile: $PhotoDirectory. Nessuna foto e stata inviata."
    }
    $source = @(Get-ChildItem -LiteralPath $PhotoDirectory -File | Where-Object { $allowedExtensions -contains $_.Extension.ToLowerInvariant() })
    if ($source.Count -eq 0) { throw 'La cartella non contiene foto supportate. Le foto sulla TV non sono state cambiate.' }
    if ($source.Count -gt 1000) { throw "Trovate $($source.Count) foto: il limite e 1000. Selezionane fino a 1000 e riprova." }
    if ($source.Count -gt 100) {
        $launcherInfo = (Invoke-Adb -Arguments @('-s', $serial, 'shell', 'dumpsys', 'package', 'com.gathin.tvhome')) -join "`n"
        if ((Get-PhotoLimit $launcherInfo) -lt $source.Count) {
            throw 'La TV ha ancora un launcher che supporta solo 100 foto, oppure la versione non e verificabile. Installa prima il launcher aggiornato; nessuna foto e stata inviata.'
        }
    }
    & $python -c 'import PIL' 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Pillow non e disponibile nell ambiente Python del progetto.' }
    if (@($source | Where-Object { $_.Extension -match '^\.hei[cf]$' }).Count -gt 0) {
        & $python -c 'import pillow_heif' 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Sono presenti file HEIC/HEIF: installa pillow-heif nell ambiente Python del progetto prima di riprovare.' }
    }
    $runId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
    $runDir = Join-Path $repo "work\photo-sync\$runId"
    $stagedTheme = Join-Path $runDir 'new-theme'
    $previousTheme = Join-Path $runDir 'previous-theme'
    New-Item -ItemType Directory -Force -Path $stagedTheme, $previousTheme | Out-Null

    # The current TV configuration is the source of truth; avoid resetting the user's theme preferences.
    $configLines = Invoke-Adb -Arguments @('-s', $serial, 'shell', 'cat', "$remoteTheme/config.json")
    $configText = $configLines -join "`n"
    $config = $configText | ConvertFrom-Json
    if ($null -eq $config -or $config -is [array]) { throw 'La configurazione attuale del tema non e valida. Nessuna foto e stata inviata.' }
    [System.IO.File]::WriteAllText((Join-Path $stagedTheme 'config.json'), $configText, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText((Join-Path $previousTheme 'config.json'), $configText, [System.Text.UTF8Encoding]::new($false))

    Write-Host "Preparo copie delle $($source.Count) foto; i file originali non vengono modificati..."
    # The upstream preparation tool refuses a destination under its source folder. Copy the
    # selected top-level images to a separate per-run source inside this package first.
    $temporarySource = Join-Path $runDir 'source-photos'
    New-Item -ItemType Directory -Path $temporarySource | Out-Null
    try {
        foreach ($photo in $source) { Copy-Item -LiteralPath $photo.FullName -Destination $temporarySource }
        & $python -I $prepare $temporarySource (Join-Path $stagedTheme 'wallpapers') --brightness 0.8 --gradient 0.15 --max-kb 300
        if ($LASTEXITCODE -ne 0) { throw 'Preparazione delle foto non riuscita. Nessuna foto e stata inviata.' }
    } finally {
        $resolvedRun = (Resolve-Path -LiteralPath $runDir).Path
        $resolvedSource = (Resolve-Path -LiteralPath $temporarySource).Path
        $expectedSource = Join-Path $resolvedRun 'source-photos'
        if ($resolvedSource -ne $expectedSource -or -not $resolvedSource.StartsWith($resolvedRun + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'Impossibile verificare la cartella temporanea: nessun file temporaneo eliminato.'
        }
        Remove-Item -LiteralPath $resolvedSource -Recurse -Force
    }
    $prepared = @(Get-ChildItem -LiteralPath (Join-Path $stagedTheme 'wallpapers') -File -Filter '*.jpg')
    if ($prepared.Count -ne $source.Count) { throw "Preparazione incompleta ($($prepared.Count) di $($source.Count)). Le foto sulla TV non sono state cambiate." }
    if (@($prepared | Where-Object { $_.Length -le 0 -or $_.Length -gt 10MB }).Count -gt 0) { throw 'Una foto preparata supera i limiti del launcher o e vuota. Nessuna foto e stata inviata.' }
    $total = ($prepared | Measure-Object -Property Length -Sum).Sum
    $largest = ($prepared | Measure-Object -Property Length -Maximum).Maximum
    $df = @(Invoke-Adb -Arguments @('-s', $serial, 'shell', 'df', '-k', '/sdcard'))
    $columns = ($df[-1].Trim() -split '\s+')
    $availableKb = 0L
    if ($columns.Count -lt 4 -or -not [long]::TryParse($columns[3], [ref]$availableKb)) { throw 'Impossibile verificare lo spazio libero sulla TV. Nessuna foto e stata inviata.' }
    if (($availableKb * 1024) -lt ($total + 3 * $largest)) { throw 'Spazio insufficiente per trasferire le foto e i file temporanei. Nessuna foto e stata inviata.' }
    Write-Host ("Foto pronte: {0}, dimensione totale: {1:N2} MiB." -f $prepared.Count, ($total / 1MB))
    if ($Preview) {
        Write-Host 'Anteprima completata: nessuna modifica inviata alla TV.'
        exit 0
    }

    # Preserve the actual TV collection so an interrupted theme update can be retried or rolled back.
    $remoteCountText = (Invoke-Adb -Arguments @('-s', $serial, 'shell', "ls $remoteTheme/wallpapers | wc -l") | Out-String).Trim()
    $remoteCount = 0
    if (-not [int]::TryParse($remoteCountText, [ref]$remoteCount) -or $remoteCount -le 0) {
        throw 'Impossibile verificare le foto gia presenti sulla TV. Nessuna modifica inviata.'
    }
    Write-Host 'Salvo una copia locale delle immagini attualmente sulla TV...'
    Invoke-Adb -Arguments @('-s', $serial, 'pull', "$remoteTheme/wallpapers", $previousTheme) | Out-Null
    $previous = @(Get-ChildItem -LiteralPath (Join-Path $previousTheme 'wallpapers') -File)
    if ($previous.Count -ne $remoteCount) { throw 'Backup della raccolta attuale incompleto. Nessuna modifica inviata.' }
    $env:TV_ADB_BINARY = $adb
    $env:TV_HOST = $TvAddress
    $env:TV_PORT = '5555'
    Push-Location $repo
    try {
        Write-Host 'Trasferimento in corso; possono servire alcuni minuti...'
        try {
            & $themeTool -TvHost $TvAddress $stagedTheme
            if ($LASTEXITCODE -ne 0) { throw "Trasferimento non riuscito (codice $LASTEXITCODE)." }
        } catch {
            Write-Warning "Aggiornamento interrotto. Provo a ripristinare le foto precedenti dalla copia locale: $previousTheme"
            try {
                & $themeTool -TvHost $TvAddress $previousTheme
                if ($LASTEXITCODE -ne 0) { throw 'Ripristino non riuscito.' }
                Write-Warning 'La raccolta precedente e stata ripristinata.'
            } catch { Write-Warning "Ripristino automatico non confermato. Conserva la cartella $previousTheme e chiedi assistenza." }
            throw 'Aggiornamento delle foto non completato.'
        }
    } finally { Pop-Location }
    $afterText = (Invoke-Adb -Arguments @('-s', $serial, 'shell', "ls $remoteTheme/wallpapers | wc -l") | Out-String).Trim()
    $afterCount = 0
    if (-not [int]::TryParse($afterText, [ref]$afterCount) -or $afterCount -ne $prepared.Count) {
        throw "Trasferimento terminato, ma il numero di foto sulla TV non coincide. Backup precedente: $previousTheme"
    }
    Write-Host "Completato: $afterCount foto sulla TV. Video e altri file non sono stati trasferiti."
    Write-Host "Backup della raccolta precedente: $previousTheme"
} catch {
    [Console]::Error.WriteLine("Errore: " + $_.Exception.Message)
    exit 1
}
