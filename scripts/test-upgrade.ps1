$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$installDir = Join-Path $env:LOCALAPPDATA 'Machine Party 模组管理器'
$installed = Start-Process dist/bootstrap.exe -ArgumentList '/S' -Wait -PassThru
if ($installed.ExitCode -ne 0) { throw "Bootstrap installer exited $($installed.ExitCode)" }
$binary = Join-Path $installDir 'machine-party-mod-manager.exe'
# The installer may relaunch through Explorer with a fresh environment.
$policy = 'HKCU:\Software\Policies\Microsoft\Edge\WebView2\AdditionalBrowserArguments'
New-Item $policy -Force | Out-Null
New-ItemProperty $policy -Name 'machine-party-mod-manager.exe' -Value '--remote-debugging-port=9222' -PropertyType String -Force | Out-Null
if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
Write-Host "Bootstrap file version $((Get-Item $binary).VersionInfo.ProductVersion)"
Start-Process $binary
try {
    node scripts/test-upgrade.mjs
} finally {
    Write-Host "Installed file version $((Get-Item $binary).VersionInfo.ProductVersion)"
    Get-Process -Name 'machine-party-mod-manager','explorer','setup','msedgewebview2' -ErrorAction SilentlyContinue | Select-Object Name,Id,SessionId,MainWindowTitle | Format-Table
    Remove-ItemProperty $policy -Name 'machine-party-mod-manager.exe'
}
