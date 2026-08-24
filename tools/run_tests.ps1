<#
.SYNOPSIS
    Compact headless runner for tests/ (Pirate Harbour Tavern).

.DESCRIPTION
    Wraps `godot --headless res://tests/<name>.tscn` per test, enforces a
    wall-clock timeout so a hanging test cannot hang the caller, and reduces
    each run's raw Godot output to one compact result line.

    Does not modify, read the source of, or depend on the internal structure
    of any test file. It only launches the existing .tscn scenes and parses
    their printed output.

    Known caveats this script exists to work around (see docs/TEST_MAP.md):
      - tests/item_system_tests.gd only calls get_tree().quit() when its own
        `quit_when_finished` export is true, which no .tscn sets. Run exactly
        as its own header documents, it will not exit on its own. This
        script's timeout kills it regardless, so it always terminates, but it
        will show as TIMEOUT rather than PASS/FAIL unless investigated.
      - The `RESULT` summary line format is not consistent across the suite
        (at least 5 distinct phrasings exist). This script does not trust any
        single phrasing; see "Result classification" below.
      - Several tests measure multiple simulated minutes of world time using
        real elapsed delta. -FixedFps decouples simulated time from wall time
        (matches the `--fixed-fps 60` invocation several tests already
        document in their own header comments) so those finish quickly
        instead of taking as long as the simulated duration.

.PARAMETER Test
    One or more test names (the .tscn basename, e.g. "item_system_tests").
    Accepts bare names, "tests/<name>.tscn", or "res://tests/<name>.tscn".
    For more than one test, comma-separate them (PowerShell array syntax):
    -Test name_one,name_two -- space-separated values after -Test are not
    reliably bound to the array by PowerShell's parameter binder.

.PARAMETER All
    Run every *.tscn found in tests/.

.PARAMETER List
    Print the available test names and exit. No tests are run.

.PARAMETER TimeoutSeconds
    Per-test wall-clock timeout. The test's process is force-killed if it has
    not exited by then. Default 90.

.PARAMETER FixedFps
    Value passed as `--fixed-fps <N>` to decouple simulated time from real
    time. 0 disables the flag entirely. Default 60.

.PARAMETER ShowOutput
    After the summary table, dump each test's full captured output. Off by
    default to keep console output compact; full logs are always written to
    disk regardless (see the "Full logs" line in the report).

.PARAMETER GodotPath
    Godot executable to invoke. Default "godot" (resolved via PATH).

.EXAMPLE
    tools\run_tests.ps1 -Test item_system_tests

.EXAMPLE
    tools\run_tests.ps1 -Test group_framework_test,group_keg_loop_test -TimeoutSeconds 120

.EXAMPLE
    tools\run_tests.ps1 -All

.EXAMPLE
    tools\run_tests.ps1 -List

.NOTES
    Result classification (per test), most to least confident:
      PASS        - at least one check counted, zero failed, exit code 0
                    (or no exit code signal available), summary and per-line
                    counts agree where both exist.
      FAIL        - a failure was counted (by summary or by line count), or
                    the process exited non-zero despite reporting 0 failed.
      SUSPECT     - the process exited cleanly but zero checks were counted
                    at all. This is the "script error mid-run silently skips
                    every assertion" failure mode CLAUDE.md warns about - it
                    is deliberately never reported as PASS.
      NO_RESULT   - no PASS/FAIL/RESULT-shaped text was found anywhere in the
                    output. Likely a crash before the test printed anything.
      TIMEOUT     - the process did not exit within -TimeoutSeconds and was
                    killed.
      NOT_FOUND   - tests/<name>.tscn does not exist.
      GODOT_NOT_FOUND - the Godot executable could not be launched.

    This script never treats "0 failed" as PASS unless at least one check
    was actually counted.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string[]]$Test = @(),

    [switch]$All,
    [switch]$List,
    [int]$TimeoutSeconds = 90,
    [int]$FixedFps = 60,
    [switch]$ShowOutput,
    [string]$GodotPath = "godot"
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$testsDir = Join-Path $repoRoot "tests"

if (-not (Test-Path $testsDir)) {
    Write-Host "tests/ not found under $repoRoot - run this from the repository, or check tools/ has not moved."
    exit 2
}

$allNames = Get-ChildItem -Path $testsDir -Filter "*.tscn" |
    ForEach-Object { $_.BaseName } | Sort-Object

if ($List) {
    $allNames | ForEach-Object { Write-Host $_ }
    exit 0
}

if (-not $All -and $Test.Count -eq 0) {
    Write-Host "Usage:"
    Write-Host "  tools\run_tests.ps1 -Test <name>[,<name> ...]  [-TimeoutSeconds N] [-FixedFps N] [-ShowOutput]"
    Write-Host "  tools\run_tests.ps1 -All                        [-TimeoutSeconds N] [-FixedFps N] [-ShowOutput]"
    Write-Host "  tools\run_tests.ps1 -List"
    Write-Host "(comma-separate multiple -Test names, e.g. -Test foo_test,bar_test)"
    Write-Host ""
    Write-Host "See docs/TEST_MAP.md for which test(s) are relevant to a given system."
    exit 2
}

function Normalize-TestName {
    param([string]$Raw)
    $n = $Raw.Trim()
    $n = $n -replace '^res://tests/', ''
    $n = $n -replace '^tests/', ''
    $n = $n -replace '\.tscn$', ''
    $n = $n -replace '\.gd$', ''
    return $n
}

$namesToRun = @()
if ($All) {
    $namesToRun = $allNames
} else {
    $namesToRun = $Test | ForEach-Object { Normalize-TestName $_ }
}

$logDir = Join-Path $env:TEMP "pht_test_runs"
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$runStamp = Get-Date -Format "yyyyMMdd-HHmmss"

$results = @()

foreach ($name in $namesToRun) {

    $result = [ordered]@{
        Name     = $name
        Status   = "UNKNOWN"
        Passed   = $null
        Failed   = $null
        ExitCode = $null
        Seconds  = $null
        LogPath  = $null
        Note     = ""
    }

    $scenePath = Join-Path $testsDir "$name.tscn"
    if (-not (Test-Path $scenePath)) {
        $result.Status = "NOT_FOUND"
        $result.Note = "No tests/$name.tscn"
        $results += [pscustomobject]$result
        continue
    }

    $outFile = Join-Path $logDir "$name-$runStamp.out.log"
    $errFile = Join-Path $logDir "$name-$runStamp.err.log"
    $result.LogPath = $outFile

    $argList = @("--headless", "--path", $repoRoot)
    if ($FixedFps -gt 0) {
        $argList += @("--fixed-fps", "$FixedFps")
    }
    $argList += "res://tests/$name.tscn"

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $proc = $null
    try {
        $proc = Start-Process -FilePath $GodotPath -ArgumentList $argList `
            -NoNewWindow -PassThru `
            -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    } catch {
        $stopwatch.Stop()
        $result.Status = "GODOT_NOT_FOUND"
        $result.Note = $_.Exception.Message
        $results += [pscustomobject]$result
        continue
    }

    # Forces the process handle to be created with exit-code access rights.
    # Without this, Process.ExitCode is unreliable after Start-Process -PassThru.
    $proc.Handle | Out-Null

    $exited = $proc.WaitForExit($TimeoutSeconds * 1000)
    $stopwatch.Stop()
    $result.Seconds = [math]::Round($stopwatch.Elapsed.TotalSeconds, 1)

    if (-not $exited) {
        try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
        $result.Status = "TIMEOUT"
        $result.Note = "Killed after ${TimeoutSeconds}s (no exit)"
        $results += [pscustomobject]$result
        continue
    }

    $result.ExitCode = $proc.ExitCode

    $stdOut = ""
    if (Test-Path $outFile) { $stdOut = Get-Content -Path $outFile -Raw -ErrorAction SilentlyContinue }
    $stdErr = ""
    if (Test-Path $errFile) { $stdErr = Get-Content -Path $errFile -Raw -ErrorAction SilentlyContinue }
    if ($null -eq $stdOut) { $stdOut = "" }
    if ($null -eq $stdErr) { $stdErr = "" }
    $combined = $stdOut + "`n" + $stdErr

    # Per-check line tags: covers "  PASS  label", "  [PASS] label", "[FAIL] scenario: msg" etc.
    $derivedPass = ([regex]::Matches($combined, '(?m)^\s*\[?PASS\]?\b')).Count
    $derivedFail = ([regex]::Matches($combined, '(?m)^\s*\[?FAIL\]?\b')).Count

    # Explicit summary numbers, several known phrasings in this suite.
    $summaryPass = $null
    $summaryFail = $null
    $m = [regex]::Match($combined, '(?i)(\d+)\s+passed,\s*(\d+)\s+failed')
    if ($m.Success) {
        $summaryPass = [int]$m.Groups[1].Value
        $summaryFail = [int]$m.Groups[2].Value
    } else {
        $mp = [regex]::Matches($combined, '(?i)passed:\s*(\d+)')
        $mf = [regex]::Matches($combined, '(?i)failed:\s*(\d+)')
        if ($mp.Count -gt 0) { $summaryPass = [int]$mp[$mp.Count - 1].Groups[1].Value }
        if ($mf.Count -gt 0) { $summaryFail = [int]$mf[$mf.Count - 1].Groups[1].Value }
    }

    $mismatchNote = ""
    $effectivePass = $derivedPass
    $effectiveFail = $derivedFail
    if (($null -ne $summaryPass) -or ($null -ne $summaryFail)) {
        $sp = 0; if ($null -ne $summaryPass) { $sp = $summaryPass }
        $sf = 0; if ($null -ne $summaryFail) { $sf = $summaryFail }
        if (($sp -ne $derivedPass) -or ($sf -ne $derivedFail)) {
            $mismatchNote = "summary=$sp/$sf vs line-tags=$derivedPass/$derivedFail"
        }
        # The test's own declared summary is authoritative when present.
        $effectivePass = $sp
        $effectiveFail = $sf
    }

    $result.Passed = $effectivePass
    $result.Failed = $effectiveFail

    $hasAnyResultShape = (($derivedPass + $derivedFail) -gt 0) -or
                         ($null -ne $summaryPass) -or ($null -ne $summaryFail) -or
                         ($combined -match '(?i)RESULT')

    if (-not $hasAnyResultShape) {
        $result.Status = "NO_RESULT"
        $lines = $combined -split "`r?`n" | Where-Object { $_.Trim() -ne "" }
        $tail = ($lines | Select-Object -Last 6) -join "  |  "
        $result.Note = "No PASS/FAIL/RESULT text found. exit=$($result.ExitCode). tail: $tail"
    }
    elseif (($effectivePass + $effectiveFail) -eq 0) {
        $result.Status = "SUSPECT"
        $result.Note = "0 checks counted despite RESULT-shaped output - possible silent skip. exit=$($result.ExitCode)."
    }
    elseif ($effectiveFail -gt 0) {
        $result.Status = "FAIL"
        $result.Note = $mismatchNote
    }
    elseif ($result.ExitCode -ne 0) {
        $result.Status = "FAIL"
        $note = "0 failures reported but exit code $($result.ExitCode)"
        if ($mismatchNote -ne "") { $note = "$note; $mismatchNote" }
        $result.Note = $note
    }
    else {
        $result.Status = "PASS"
        $result.Note = $mismatchNote
    }

    $results += [pscustomobject]$result
}

# --- Report ---------------------------------------------------------------

Write-Host ""
Write-Host ("{0,-32} {1,-9} {2,7} {3,7} {4,6} {5,7}  {6}" -f "TEST", "STATUS", "PASSED", "FAILED", "EXIT", "TIME(s)", "NOTE")
foreach ($r in $results) {
    $p = "-"; if ($null -ne $r.Passed) { $p = $r.Passed }
    $f = "-"; if ($null -ne $r.Failed) { $f = $r.Failed }
    $e = "-"; if ($null -ne $r.ExitCode) { $e = $r.ExitCode }
    $t = "-"; if ($null -ne $r.Seconds) { $t = $r.Seconds }
    Write-Host ("{0,-32} {1,-9} {2,7} {3,7} {4,6} {5,7}  {6}" -f $r.Name, $r.Status, $p, $f, $e, $t, $r.Note)
}

$total = @($results).Count
$passCount = @($results | Where-Object { $_.Status -eq "PASS" }).Count
$failCount = @($results | Where-Object { $_.Status -eq "FAIL" }).Count
$otherCount = $total - $passCount - $failCount

Write-Host ""
Write-Host "TOTAL: $total run | PASS: $passCount | FAIL: $failCount | OTHER (SUSPECT/TIMEOUT/NO_RESULT/NOT_FOUND/GODOT_NOT_FOUND): $otherCount"
Write-Host "Full per-test logs: $logDir (not committed; safe to delete any time)"

if ($ShowOutput) {
    foreach ($r in $results) {
        if ($r.LogPath -and (Test-Path $r.LogPath)) {
            Write-Host ""
            Write-Host "===== $($r.Name) : stdout ====="
            Get-Content $r.LogPath
        }
    }
}

if ($failCount -gt 0 -or $otherCount -gt 0) { exit 1 } else { exit 0 }
