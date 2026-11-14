#requires -Version 7.0
param([Parameter(Mandatory)][string]$InstallerPath)

$ErrorActionPreference = 'Stop'
if (-not $IsWindows -or $env:GITHUB_ACTIONS -ne 'true' -or -not $env:RUNNER_TEMP) {
    throw 'Run this installation test only on a disposable Windows GitHub Actions runner.'
}

$installer = (Resolve-Path -LiteralPath $InstallerPath).ProviderPath
$expectedVersion = (Get-Content -LiteralPath (Join-Path $PSScriptRoot '../package.json') -Raw | ConvertFrom-Json).version
$legacyKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Caffeine'
$currentKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Hot Coffee'
$settingsDirectory = Join-Path $env:APPDATA 'com.cnlutong.caffeine'
foreach ($path in @($legacyKey, $currentKey, $settingsDirectory)) {
    if (Test-Path -LiteralPath $path) {
        throw "The runner already has application data at $path. Refusing to replace it."
    }
}

$stage = Join-Path $env:RUNNER_TEMP ('hot-coffee-upgrade-' + [guid]::NewGuid().ToString('N'))
$legacyDirectory = Join-Path $stage 'legacy'
$currentDirectory = Join-Path $stage 'current'
$legacyInstaller = Join-Path $stage 'Caffeine_2.0.1_windows_x86_64_setup.exe'
$settingsPath = Join-Path $settingsDirectory 'settings.json'
$startMenu = [Environment]::GetFolderPath('Programs')
$legacyShortcut = Join-Path $startMenu 'Caffeine.lnk'
$currentShortcut = Join-Path $startMenu 'Hot Coffee.lnk'
New-Item -ItemType Directory -Path $stage -Force | Out-Null

function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Run-Checked([string]$FilePath, [string[]]$ProcessArguments) {
    $process = Start-Process -FilePath $FilePath -ArgumentList $ProcessArguments -PassThru
    if (-not $process.WaitForExit(180000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw "Timed out running $FilePath."
    }
    $process.Refresh()
    Assert ($process.ExitCode -eq 0) "$FilePath exited with $($process.ExitCode)."
}

try {
    # An immutable, published fixture from this project; validate its known release digest.
    Invoke-WebRequest -Uri 'https://github.com/cnlutong/Hot-Coffee/releases/download/v2.0.1/Caffeine_2.0.1_windows_x86_64_setup.exe' -OutFile $legacyInstaller
    $digest = (Get-FileHash -LiteralPath $legacyInstaller -Algorithm SHA256).Hash.ToLowerInvariant()
    Assert ($digest -eq 'afb65a7898a5cf2587a7c5fb080ec7552ab7c291641c897e575117d1d8cd9082') 'The legacy installer digest differs from the published fixture.'

    # /D must be the final NSIS argument; its remaining text is the installation path.
    Run-Checked $legacyInstaller @('/S', "/D=$legacyDirectory")
    Assert (Test-Path -LiteralPath (Join-Path $legacyDirectory 'caffeine.exe')) 'The legacy app was not installed.'
    Assert ((Get-ItemProperty -LiteralPath $legacyKey).Publisher -eq 'cnlutong') 'Unexpected legacy publisher.'
    Assert (Test-Path -LiteralPath $legacyShortcut) 'The legacy Start menu shortcut was not created.'

    New-Item -ItemType Directory -Path $settingsDirectory -Force | Out-Null
    $preferences = '{"language":"zh","lastActiveMode":"display"}'
    [IO.File]::WriteAllText($settingsPath, $preferences)

    Run-Checked $installer @('/S', "/D=$currentDirectory")
    $currentExe = Join-Path $currentDirectory 'hot-coffee.exe'
    Assert (Test-Path -LiteralPath $currentExe) 'Hot Coffee was not installed.'
    Assert (-not (Test-Path -LiteralPath (Join-Path $legacyDirectory 'caffeine.exe'))) 'The legacy executable remains after migration.'
    Assert (-not (Test-Path -LiteralPath $legacyKey)) 'The legacy uninstall entry remains after migration.'
    Assert (-not (Test-Path -LiteralPath $legacyShortcut)) 'The legacy Start menu shortcut remains after migration.'
    Assert (Test-Path -LiteralPath $currentShortcut) 'The Hot Coffee Start menu shortcut was not created.'
    $installed = Get-ItemProperty -LiteralPath $currentKey
    Assert ($installed.DisplayName -eq 'Hot Coffee') 'The installed display name is incorrect.'
    Assert ($installed.DisplayVersion -eq $expectedVersion) 'The installed product version is incorrect.'
    Assert ((Get-Content -LiteralPath $settingsPath -Raw) -eq $preferences) 'Preferences changed during the rename upgrade.'
    Run-Checked $currentExe @('--self-test')
    Assert ((Get-Content -LiteralPath $settingsPath -Raw) -eq $preferences) 'The native self-test changed saved preferences.'

    Write-Host 'PASS: published Caffeine 2.0.1 -> Hot Coffee; installer, executable, registry, shortcuts, retained preferences, and installed native power self-test.'
}
finally {
    # The guard above ensures this disposable runner had no pre-existing app or settings.
    foreach ($directory in @($currentDirectory, $legacyDirectory)) {
        $uninstaller = Join-Path $directory 'uninstall.exe'
        if (Test-Path -LiteralPath $uninstaller) {
            $cleanup = Start-Process -FilePath $uninstaller -ArgumentList '/S', '/UPDATE' -PassThru
            if (-not $cleanup.WaitForExit(60000)) {
                Stop-Process -Id $cleanup.Id -Force -ErrorAction SilentlyContinue
            }
        }
    }
    Remove-Item -LiteralPath $settingsDirectory -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
}
