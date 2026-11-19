# Exercise the publication gate with an unsigned PE built on this runner.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
$source = Join-Path $env:RUNNER_TEMP 'signature_fixture.rs'
$binary = Join-Path $env:RUNNER_TEMP 'signature_fixture.exe'
Set-Content $source 'fn main() {}'
rustc $source -o $binary
if ((Get-AuthenticodeSignature $binary).Status -ne 'NotSigned') { throw 'Expected an unsigned fixture.' }
try {
    & "$PSScriptRoot/verify-windows-signature.ps1" -Path $binary -Thumbprint ('A' * 40)
} catch {
    if ($_.Exception.Message -notmatch 'status: NotSigned') { throw }
    Write-Host 'Unsigned installer rejected by the publication gate.'
    return
}
throw 'Publication gate accepted the unsigned installer.'
