# Windows regression test using disposable stand-ins for the game.
$ErrorActionPreference = "Stop"
$base = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
$game = Join-Path $base "game copy"
$launch = Join-Path $game "mods\broadcast-8p-freecam\launchers"
$hash = [Security.Cryptography.SHA256]::Create()
$key = [BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($game.ToUpperInvariant()))).Replace("-", "")
$hash.Dispose()
$session = Join-Path $env:LOCALAPPDATA "MachinePartyBroadcast\sessions\$key"
$exe = Join-Path $game "Machine Party.exe"
$other = Join-Path $base "other\Machine Party.exe"
$owned = @()
try {
    [void][IO.Directory]::CreateDirectory($session)
    [void][IO.Directory]::CreateDirectory((Split-Path $other))
    [void][IO.Directory]::CreateDirectory($launch)
    Copy-Item "$PSScriptRoot/../../apps/desktop/src-tauri/assets/recipes/broadcast/localtest.ps1" $launch
    $fixture = Join-Path $base "fixture.rs"
    'fn main() { std::thread::sleep(std::time::Duration::from_secs(120)); }' |
        Set-Content -LiteralPath $fixture -Encoding Ascii
    & rustc $fixture -o $exe
    if ($LASTEXITCODE -ne 0) { throw "Could not build the test fixture" }
    Copy-Item $exe $other
    $normal = Start-Process $exe -PassThru
    $owned += $normal
    $foreign = Start-Process $other -PassThru
    $owned += $foreign
    # Simulate a recycled PID and a process from another copy with a matching timestamp.
    foreach ($proc in $owned) {
        $stamp = $proc.StartTime.ToUniversalTime().Ticks
        if ($proc.Id -eq $normal.Id) { $stamp-- }
        [IO.File]::WriteAllText((Join-Path $session "$($proc.Id)-$stamp.pid"), "")
    }
    & "$launch/localtest.ps1" -Players 1
    $records = @(Get-ChildItem $session -Filter "*.pid")
    if ($records.Count -ne 2) { throw "Expected host and one client" }
    foreach ($record in $records) {
        $processId = [int]($record.Name.Split('-')[0])
        $child = Get-Process -Id $processId
        if ($child.MainModule.FileName -ne $exe) { throw "Wrong game copy" }
        $owned += $child
    }
    & "$launch/localtest.ps1" -Stop
    & "$launch/localtest.ps1" -Stop
    if ($normal.HasExited -or $foreign.HasExited) { throw "An unrelated process was stopped" }
    if (-not $owned[2].HasExited -or -not $owned[3].HasExited) { throw "Test process still running" }
} finally {
    foreach ($proc in $owned) {
        if (-not $proc.HasExited) { $proc.Kill(); $proc.WaitForExit() }
        $proc.Dispose()
    }
    Remove-Item -LiteralPath $session -Recurse -Force
    Remove-Item -LiteralPath $base -Recurse -Force
}
