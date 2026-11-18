$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$installDir = Join-Path $env:LOCALAPPDATA 'Machine Party 模组管理器'
$installed = Start-Process dist/bootstrap.exe -ArgumentList '/S' -Wait -PassThru
if ($installed.ExitCode -ne 0) { throw "Bootstrap installer exited $($installed.ExitCode)" }
$binary = Join-Path $installDir 'machine-party-mod-manager.exe'
$env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = '--remote-debugging-port=9222'
Start-Process $binary
node scripts/test-upgrade.mjs
