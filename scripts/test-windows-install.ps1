param([Parameter(Mandatory)][string]$Installer)
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
# This acceptance test owns a disposable runner's current-user installation.
$newDir = Join-Path $env:LOCALAPPDATA 'MachinePartyModManager'
$oldDir = Join-Path $env:LOCALAPPDATA 'Machine Party 模组管理器'
$config = Join-Path $env:APPDATA 'community.machineparty.modmanager'
if ((Test-Path $newDir) -or (Test-Path $oldDir) -or (Test-Path $config)) {
    throw 'Windows installer acceptance requires a fresh user profile.'
}
function Run-Installer($Path) {
    $result = Start-Process -FilePath $Path -ArgumentList '/S' -Wait -PassThru
    if ($result.ExitCode -ne 0) { throw "Installer failed with exit code $($result.ExitCode)" }
}
$old = Join-Path $env:RUNNER_TEMP 'previous-setup.exe'
Invoke-WebRequest 'https://github.com/JamesGZM/machine-party-mod-manager/releases/download/v0.1.2-1/setup.exe' -OutFile $old
if ((Get-FileHash $old).Hash -ne '18e26c91d806e5da5831343a3e98714858960795f0e7066c1664a16b397babc6') {
    throw 'Previous prerelease checksum mismatch.'
}
Run-Installer $old
if (!(Test-Path "$oldDir/machine-party-mod-manager.exe")) { throw 'Previous installation missing.' }
New-Item "$config/backups/test-copy" -ItemType Directory -Force | Out-Null
Set-Content "$config/backups/test-copy/test.txt" 'restore evidence'
Set-Content "$config/installations.json" '{}'
Run-Installer $Installer
if ((Test-Path "$oldDir/machine-party-mod-manager.exe") -or !(Test-Path "$newDir/machine-party-mod-manager.exe")) {
    throw 'Upgrade left an unexpected binary layout.'
}
if ((Get-Content "$config/backups/test-copy/test.txt") -ne 'restore evidence' -or (Get-Content "$config/installations.json") -ne '{}') {
    throw 'Upgrade lost configuration or backups.'
}
$entries = @(Get-ItemProperty HKCU:/Software/Microsoft/Windows/CurrentVersion/Uninstall/* | Where-Object { $_.DisplayName -in @('MachinePartyModManager','Machine Party 模组管理器') })
if ($entries.Count -ne 1 -or $entries[0].DisplayName -ne 'MachinePartyModManager') { throw 'Unexpected uninstall registrations.' }
$shell = New-Object -ComObject WScript.Shell
$desktop = [Environment]::GetFolderPath('Desktop')
$link = $shell.CreateShortcut((Join-Path $desktop 'MachinePartyModManager.lnk'))
if ($link.TargetPath -ne "$newDir\machine-party-mod-manager.exe") { throw 'Desktop shortcut target mismatch.' }
Run-Installer "$newDir/uninstall.exe"
Run-Installer $Installer
if (!(Test-Path "$newDir/machine-party-mod-manager.exe")) { throw 'Fresh installation failed.' }

$fixture = Join-Path $env:RUNNER_TEMP 'Steam 測試副本'
New-Item $fixture -ItemType Directory -Force | Out-Null
New-Item "$fixture/Machine Party.exe" -ItemType File | Out-Null
$pck = [IO.File]::Create("$fixture/Machine Party.pck")
try { $pck.SetLength(256MB) } finally { $pck.Dispose() }
$inventory = @{ $fixture = @{ 'DarkJadeStone/MachineParty-Overtime' = 'v1.7' } }
$inventory | ConvertTo-Json | Set-Content "$config/installations.json"
$env:PREVIEW_FIXTURE = $fixture
$env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = '--remote-debugging-port=9222'
$manager = Start-Process "$newDir/machine-party-mod-manager.exe" -PassThru
try { node scripts/test-preview-ui.mjs }
finally { Stop-Process -Id $manager.Id -ErrorAction SilentlyContinue }
