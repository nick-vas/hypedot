#!/usr/bin/env pwsh
# Self-test of the flows runner's rotation steps on tests/flows-fixture. The good flows hold "jump", resize the window to
# portrait and back (the scene sees one size_changed per resize, the action still held, its layout in the new shape, and
# the release afterwards), rotate during a loading screen, and check that the next flow starts at the project's window
# size with nothing held. The broken flows fail with the reason each one gives: a bad size, an unknown or numeric hold,
# a release of an action not held, an action step on a held action, a flow that ends with an action held, and a loading
# screen that picks its layout before the rotation. A flow fails on its own end line or on an error of its own between its markers; the errors
# Godot's C# bindings log ("Handle is not initialized.") are warnings that name the flow that was running (fake logs, no Godot), and the flows
# run with a throwaway user:// folder. Needs Godot (GODOT_BIN, or the kit installs it); -NoGodot runs the log checks only.
param([switch]$NoGodot)
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$kit = Join-Path $root 'ci/godot/hyperdot.ps1'
$fixture = Join-Path $PSScriptRoot 'flows-fixture'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}
# Runs the flows whose path contains $Filter; returns ok and every case from the JUnit file (the JSON keeps the first 10).
function Invoke-Flows([string]$Filter) {
    $results = Join-Path ([IO.Path]::GetTempPath()) "flows-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    $json = pwsh -NoProfile -NonInteractive -File $kit test -Json -Project $fixture -Runners flows -Filter $Filter -Results $results 2>$null | Out-String | ConvertFrom-Json
    $junit = Join-Path $results 'flows/flows.junit.xml'
    $cases = @(if (Test-Path -LiteralPath $junit) {
        foreach ($case in ([xml](Get-Content -LiteralPath $junit -Raw)).SelectNodes('//testcase')) {
            $failure = $case.SelectSingleNode('failure')
            [pscustomobject]@{ Name = $case.GetAttribute('name'); Message = $(if ($failure) { $failure.InnerText } else { '' }) }
        } })
    $log = Join-Path $results 'flows/flows.log'
    $logText = if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Raw } else { '' }
    Remove-Item -Recurse -Force $results -ErrorAction SilentlyContinue
    return [pscustomobject]@{ Ok = [bool]$json.ok; Cases = $cases; LogText = $logText }
}
function Get-Message($Result, [string]$File) {
    $found = @($Result.Cases | Where-Object { $_.Name -like "*/$File" })
    if ($found.Count -eq 0) { return '<no case>' }
    return $found[0].Message
}

# The runner reads Godot's log (fake ones here, no Godot): a flow fails on its own end line, or on an error of its own printed between its markers.
# Godot's C# bindings log "Handle is not initialized." (godotengine/godot#124587) around whatever flow is running: those are warnings that name
# the flow, not failures. The issue it answers: 56 flows ended ok and the summary still said 53 passed, 3 failed.
foreach ($lib in 'Common', 'Report', 'Runners', 'Setup') { . (Join-Path $root "ci/godot/lib/$lib.ps1") }
$fakeLog = Join-Path ([IO.Path]::GetTempPath()) "flows-fake-$([guid]::NewGuid().ToString('N').Substring(0, 8)).log"
function Read-FakeLog([string[]]$Lines, [bool]$Separate = $true) {
    Set-Content -LiteralPath $fakeLog -Value $Lines
    $engine = [System.Collections.Generic.List[object]]::new()
    $cases = @(if ($Separate) { ConvertFrom-ValidateLog $fakeLog 'flow' $engine } else { ConvertFrom-ValidateLog $fakeLog 'flow' })
    return [pscustomobject]@{ Cases = $cases; Engine = $engine; Failed = @($cases | Where-Object { $_.Failure }) }
}
try {
    $handle = 'ERROR: System.InvalidOperationException: Handle is not initialized.'
    $lines = @(foreach ($n in 1..56) {
        "@@flow begin res://test/flows/f$n.flow.json"
        if ($n -in 10, 40) { $handle; '   at Godot.NativeInterop.NativeFuncs.SwapGCHandleForType()' }
        "@@flow end res://test/flows/f$n.flow.json ok"
        if ($n -eq 56) { $handle }
    }) + '@@flow done 56'
    $r = Read-FakeLog $lines
    Assert-True ($r.Cases.Count -eq 56 -and $r.Failed.Count -eq 0) "56 flows that ended ok and 3 engine errors: 0 failed flows ($($r.Failed.Count) failed of $($r.Cases.Count))"
    Assert-True ($r.Engine.Count -eq 3 -and $r.Engine[0].where -eq 'res://test/flows/f10.flow.json' -and $r.Engine[1].where -eq 'res://test/flows/f40.flow.json' -and $null -eq $r.Engine[2].where -and $r.Engine[0].text -like '*Handle is not initialized*') 'the 3 engine errors are listed with the flow that was running (the last after every flow)'
    $r = Read-FakeLog $lines $false
    Assert-True ($r.Failed.Count -ge 2) "without the list (the other callers) an error between a flow's markers still fails it"

    # Godot crashing in its shutdown (exit 134, the mono teardown's FATAL and its "Leaked unsafe reference" lines, which come after the "done" line)
    # after every flow ended ok is a warning; a crash before the "done" line, a failed flow, or any other nonzero exit still fails.
    $fatal = 'FATAL: Condition "csharp_lang && !csharp_lang->script_bindings.is_empty()" is true.'
    $leak = 'ERROR: Leaked unsafe reference to object 1234'
    $teardown = $lines + @($fatal) + @(1..40 | ForEach-Object { $leak })
    $r = Read-FakeLog $teardown
    $verdict = Get-RunnerExitVerdict 134 $fakeLog 'flow' $r.Cases $r.Engine 'flow'
    Assert-True ($r.Cases.Count -eq 56 -and $r.Failed.Count -eq 0 -and -not $verdict.Failure) "exit 134 after the done line: no failed flow, no failure ($($r.Failed.Count) failed, '$($verdict.Failure)')"
    Assert-True ($verdict.Warning -like '*crashed at shutdown (exit 134) after every flow was judged: FATAL: Condition*' -and @($r.Engine | Where-Object { $_.text -like '*crashed at shutdown*' }).Count -eq 1) 'the crash is one warning with the FATAL line, listed with the engine errors'
    Assert-True (@($r.Engine | Where-Object { $_.text -like '*Leaked unsafe reference*' }).Count -eq 0) 'the errors after the done line are not read as errors of the project'
    $r = Read-FakeLog $lines
    Assert-True ((Get-RunnerExitVerdict 1 $fakeLog 'flow' $r.Cases $r.Engine 'flow').Failure -eq 'Godot exited with 1') 'an ordinary nonzero exit still fails'
    $r = Read-FakeLog ($lines[0..20] + @($fatal))
    Assert-True ((Get-RunnerExitVerdict 134 $fakeLog 'flow' $r.Cases $r.Engine 'flow').Failure -eq 'Godot exited with 134') 'a crash before the done line still fails'
    $r = Read-FakeLog (@('@@flow begin res://z.flow.json', '@@flow end res://z.flow.json step 1: no node', '@@flow done 1', $fatal))
    Assert-True ((Get-RunnerExitVerdict 134 $fakeLog 'flow' $r.Cases $r.Engine 'flow').Failure -eq 'Godot exited with 134' -and $r.Failed.Count -eq 1) 'a crash after a failed flow still fails'
    Assert-True ((Test-GodotCrashCode 134) -and (Test-GodotCrashCode -1073741819) -and -not (Test-GodotCrashCode 1) -and -not (Test-GodotCrashCode 0)) 'a crash code is 128 and up, or a negative Windows code'

    # An error of its own, between one flow's markers, fails that flow by name, and only that one.
    $own = "SCRIPT ERROR: Invalid call. Nonexistent function 'jump' in base 'Nil'."
    $r = Read-FakeLog @('@@flow begin res://a.flow.json', '@@flow end res://a.flow.json ok', '@@flow begin res://b.flow.json', $own, '@@flow end res://b.flow.json ok', '@@flow begin res://c.flow.json', $handle, '@@flow end res://c.flow.json ok')
    Assert-True ($r.Failed.Count -eq 1 -and $r.Failed[0].Name -eq 'res://b.flow.json' -and $r.Failed[0].Failure -like '*Nonexistent function*' -and $r.Engine.Count -eq 1) "an error of its own fails its flow by name, the engine's does not: $(@($r.Failed | ForEach-Object { $_.Name }) -join ', ')"
    # A flow's own end line decides too: anything but ok fails it, and says the step.
    $r = Read-FakeLog @('@@flow begin res://d.flow.json', '@@flow end res://d.flow.json step 2 ({"press":"Play"}): no node Play')
    Assert-True ($r.Failed.Count -eq 1 -and $r.Failed[0].Failure -like 'step 2 *no node Play*') "a flow that did not end ok fails with its step: $(@($r.Failed | ForEach-Object { $_.Failure }) -join ' | ')"
    # The first line may name nothing and the managed trace under it the bindings: that is the engine's. A trace that names only the game's code is the game's.
    $r = Read-FakeLog @('@@flow begin res://e.flow.json', 'ERROR: System.Exception: collected', '   at Godot.Bridge.ScriptManagerBridge.CreateManagedForGodotObjectBinding()', '@@flow end res://e.flow.json ok')
    Assert-True ($r.Failed.Count -eq 0 -and $r.Engine.Count -eq 1) "an error whose stack trace names ScriptManagerBridge is the engine's"
    $r = Read-FakeLog @('@@flow begin res://f.flow.json', 'ERROR: System.NullReferenceException: Object reference not set to an instance of an object.', '   at Game.Player._Ready() in /game/Player.cs:line 3', '@@flow end res://f.flow.json ok')
    Assert-True ($r.Failed.Count -eq 1 -and $r.Engine.Count -eq 0) "an error whose stack trace names only the game's code stays the flow's"
    # The warnings reach findings.json (runnerResults[].warnings).
    $results = Join-Path ([IO.Path]::GetTempPath()) "flows-find-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    New-Item -ItemType Directory -Force $results | Out-Null
    Write-EngineErrorFindings ([System.Collections.Generic.List[object]]@([ordered]@{ where = 'res://c.flow.json'; text = $handle })) 'flows' $results
    $found = @(Get-Content -LiteralPath (Join-Path $results 'findings.json') -Raw | ConvertFrom-Json)
    Assert-True ($found.Count -eq 1 -and $found[0].rule -eq 'engine-internal-error' -and $found[0].severity -eq 'warning' -and $found[0].file -eq 'res://c.flow.json') 'the engine error is a warning in findings.json, with its flow'
    Remove-Item -LiteralPath $results -Recurse -Force
} finally {
    Remove-Item -LiteralPath $fakeLog -Force -ErrorAction SilentlyContinue
}
if ($NoGodot) {
    if ($failures.Count) { Write-Host "$($failures.Count) check(s) failed" -ForegroundColor Red; exit 1 }
    Write-Host 'flows: engine errors are warnings; a flow fails on its own end line or error (fake logs)'
    exit 0
}

$good = Invoke-Flows 'flows/good/'
Assert-True ($good.Ok) "the rotation flows pass: $(@($good.Cases | Where-Object Message | ForEach-Object { "$($_.Name): $($_.Message)" }) -join ' | ')"
Assert-True ($good.Cases.Count -eq 3) "three good flows ran: $($good.Cases.Count)"

# Flows share one process: what one leaves (a paused tree, a time scale, a node in the root window) is cleaned before the next.
$leak = Invoke-Flows 'flows/leak/'
Assert-True ($leak.Ok -and $leak.Cases.Count -eq 2) "a flow that leaves the tree paused, the time scale at 3 and a node in the root does not reach the next flow: $(@($leak.Cases | Where-Object Message | ForEach-Object { "$($_.Name): $($_.Message)" }) -join ' | ')"

# An autoload that has hyperdot_reset_flow_state() is reset between flows, so the run does not depend on their order (a relic one flow added
# is gone when the next starts, and the note says what was found).
$autoload = Invoke-Flows 'flows/autoload/'
Assert-True ($autoload.Ok -and $autoload.Cases.Count -eq 2) "a relic an autoload holds after one flow is gone for the next: $(@($autoload.Cases | Where-Object Message | ForEach-Object { "$($_.Name): $($_.Message)" }) -join ' | ')"
Assert-True ($autoload.LogText -match 'StateBoxCs: 1 coin\(s\) left by the last flow') 'an autoload that names its method HyperdotResetFlowState (as a C# one must) is reset too'
Assert-True ($autoload.LogText -match '@@flow note res://test/flows/autoload/a_adds_a_relic\.flow\.json StateBox: 1 relic\(s\) left by the last flow') 'the note names the autoload and what it found'

# The flows run with a throwaway user:// folder (Linux and Windows), not the one where whoever ran them last keeps saved settings; it is gone afterwards.
$userdir = Invoke-Flows 'flows/userdir/'
$printed = [regex]::Match($userdir.LogText, '\[userdir\] (?<dir>.+)').Groups['dir'].Value.Trim()
Assert-True ($userdir.Ok -and $printed) "the user-dir flow ran and the scene printed where user:// is: $printed"
if (-not $IsMacOS) {
    $throwaway = [regex]::Match($printed, '^.*hyperdot-user-[0-9a-f]{8}').Value
    Assert-True ($throwaway -ne '') "user:// is inside a throwaway folder during a flows run: $printed"
    Assert-True ($throwaway -ne '' -and -not (Test-Path -LiteralPath $throwaway)) "the throwaway folder is removed afterwards: $throwaway"
}

$broken = Invoke-Flows 'flows/broken/'
Assert-True (-not $broken.Ok) 'the broken flows fail the run'
$size = 'resize needs \[width, height\] in pixels, whole numbers from 1 to 16384, got '
$want = [ordered]@{
    'resize_zero.flow.json'              = "step 1 .*: $size\[0"
    'resize_fraction.flow.json'          = "step 1 .*: $size\[720\.5"
    'resize_huge.flow.json'              = "step 1 .*: $size\[720(\.0)?,20000"
    'resize_three.flow.json'             = "step 1 .*: $size\[720(\.0)?,1280(\.0)?,1"
    'resize_word.flow.json'              = "step 1 .*: $size`"portrait`""
    'hold_unknown.flow.json'             = 'step 1 .*: no input action fly \(see Project Settings > Input Map\)'
    'hold_frames.flow.json'              = 'step 1 .*: hold needs an input action name \(to hold for N frames, use \{ "action": "name", "hold": N \}\)'
    'hold_twice.flow.json'               = 'step 2 .*: jump is already held'
    'release_not_held.flow.json'         = 'step 1 .*: jump is not held \(hold it first with \{ "hold": "jump" \}\)'
    'release_unknown.flow.json'          = 'step 1 .*: no input action fly'
    'action_while_held.flow.json'        = 'step 2 .*: jump is held by a hold step; release it first'
    'held_at_end.flow.json'              = '^the flow ended with jump still held \(add \{ "release": "jump" \}\)'
    'layout_picked_too_early.flow.json'  = 'step 4 .*loaded_layout is landscape, expected equals portrait'
}
foreach ($file in $want.Keys) {
    $message = Get-Message $broken $file
    Assert-True ($message -match $want[$file]) "$file fails with its reason: $message"
}
Assert-True ($broken.Cases.Count -eq $want.Count) "every broken flow ran: $($broken.Cases.Count) of $($want.Count)"

if ($failures.Count) { Write-Host "$($failures.Count) check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'flows rotate the window with an action held, start each flow at the project size, and name every bad step'
exit 0
