param(
    [Parameter(Position = 0)][ValidateRange(1, 8)][int]$Players = 8,
    [ValidateRange(1, 240)][int]$MaxFps = 30,
    [ValidateSet("360","540","720","1080","1440","2k")][string]$DirectorRender = "540",
    [ValidateSet("360","540","720")][string]$ClientRender = "360",
    [switch]$Stop
)
$ErrorActionPreference = "Stop"
$gameDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\..\.."))
$exe = Join-Path $gameDir "Machine Party.exe"
# Keep mutable session records outside the fingerprinted mod installation.
$hash = [Security.Cryptography.SHA256]::Create()
try {
    $key = [BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($gameDir.ToUpperInvariant()))).Replace("-", "")
} finally { $hash.Dispose() }
$session = Join-Path $env:LOCALAPPDATA "MachinePartyBroadcast\sessions\$key"
[void][IO.Directory]::CreateDirectory($session)

function Stop-RecordedPlayers {
    foreach ($record in Get-ChildItem -LiteralPath $session -Filter "*.pid") {
        if ($record.Name -notmatch '^(\d+)-(\d+)\.pid$') { continue }
        $processId = [int]$Matches[1]
        $started = [long]$Matches[2]
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($process) {
            try {
                # Hold the handle across identity checks and termination, even if the PID exits.
                $null = $process.Handle
                if ($process.StartTime.ToUniversalTime().Ticks -eq $started -and
                    $process.MainModule.FileName -eq $exe) {
                    $process.Kill()
                    if (-not $process.WaitForExit(5000)) { throw "Timed out stopping PID $processId" }
                }
            } catch {
                if (-not $process.HasExited) { throw }
            } finally { $process.Dispose() }
        }
        Remove-Item -LiteralPath $record.FullName
    }
}

try {
    $lock = [IO.File]::Open((Join-Path $session "lock"), 'OpenOrCreate', 'ReadWrite', 'None')
} catch [IO.IOException] {
    throw "Another local test operation is in progress or its lock is unavailable."
}
$launched = @()
try {
    Stop-RecordedPlayers
    if ($Stop) { return }
    if (-not [IO.File]::Exists($exe)) { throw "Game executable missing: $exe" }
    Add-Type -AssemblyName System.Windows.Forms
    if (-not ("BroadcastTestWindow" -as [type])) {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class BroadcastTestWindow {
    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int w, int h, uint flags);
}
"@
    }
    $screen = [Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $count = $Players + 1
    $width = [int][Math]::Max(320, [Math]::Floor($screen.Width / 4))
    $height = [int][Math]::Max(240, [Math]::Floor($screen.Height / [Math]::Ceiling($count / 4)))
    for ($slot = 1; $slot -le $count; $slot++) {
        $role = "join"
        $render = $ClientRender
        if ($slot -eq 1) { $role = "host"; $render = $DirectorRender }
        $x = $screen.X + (($slot - 1) % 4) * $width
        $y = $screen.Y + [int][Math]::Floor(($slot - 1) / 4) * $height
        $arguments = @("-localtest", $slot, $role, "-startgame", $count, "--windowed",
            "--resolution", "$($width - 8)x$($height - 8)", "--position", "$x,$y",
            "-broadcast-max-fps", $MaxFps, "--max-fps", $MaxFps, "-broadcast-render", $render)
        $process = Start-Process -FilePath $exe -WorkingDirectory $gameDir -ArgumentList $arguments -PassThru
        try {
            $record = "{0}-{1}.pid" -f $process.Id, $process.StartTime.ToUniversalTime().Ticks
            [IO.File]::WriteAllText((Join-Path $session $record), "")
            $launched += [PSCustomObject]@{ Process = $process; X = $x; Y = $y }
        } catch {
            if (-not $process.HasExited) { $process.Kill() }
            $process.Dispose()
            throw
        }
        if ($slot -lt $count) {
            if ($slot -eq 1) { Start-Sleep -Seconds 3 } else { Start-Sleep -Milliseconds 800 }
        }
    }
} catch {
    Stop-RecordedPlayers
    throw
} finally { $lock.Dispose() }

# The game resets its window size during bootstrap. Reapply the grid during startup.
try {
    for ($i = 0; $i -lt 40; $i++) {
        foreach ($slotWindow in $launched) {
            $process = $slotWindow.Process
            if ($process.HasExited) { continue }
            $process.Refresh()
            $window = $process.MainWindowHandle
            if ($window -ne [IntPtr]::Zero) {
                [void][BroadcastTestWindow]::SetWindowPos($window, [IntPtr]::Zero, $slotWindow.X,
                    $slotWindow.Y, $width - 8, $height - 8, 0x14)
            }
        }
        Start-Sleep -Milliseconds 500
    }
} finally {
    foreach ($slotWindow in $launched) { $slotWindow.Process.Dispose() }
}
