# The `juice` runner: plays the game headless with a bot for a while and checks that every gameplay event got its feedback in
# time. The game prints one line per event and per feedback, with its game time in milliseconds:
#   [juice] event brick_hit 1234.5
#   [juice] feedback flash 1240.1
# and juice.json in the project says what must follow what:
#   { "frames": 1800, "args": ["--autoplay"], "rules": [ { "event": "brick_hit", "feedback": ["flash", "sfx"], "withinMs": 100 } ] }
# The run uses --fixed-fps 60, so game time advances the same on every machine and the bot's run is reproducible.

function Get-JuiceConfig([string]$ProjectDir) {
    $file = Join-Path $ProjectDir 'juice.json'
    if (-not (Test-Path -LiteralPath $file)) { return $null }
    try { $config = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable }
    catch { Stop-GodotCi "juice.json is not valid JSON: $($_.Exception.Message)" 'invalid-arguments' }
    if (-not $config.Contains('rules') -or @($config.rules).Count -eq 0) { Stop-GodotCi 'juice.json needs "rules": [ { "event", "feedback", "withinMs" } ]' 'invalid-arguments' }
    foreach ($rule in $config.rules) {
        if (-not $rule.Contains('event') -or -not $rule.Contains('feedback')) { Stop-GodotCi 'Each juice.json rule needs "event" and "feedback"' 'invalid-arguments' }
    }
    # Godot's --quit-after 0 means never quit: the run would hang until the time limit.
    if ($config.Contains('frames') -and ("$($config.frames)" -notmatch '^\d+$' -or [long]$config.frames -le 0)) {
        Stop-GodotCi "juice.json ""frames"" must be a whole number above 0, not $($config.frames | ConvertTo-Json -Depth 10 -Compress)" 'invalid-arguments'
    }
    return $config
}

# One JUnit case per rule (and per feedback it requires): failed when an event had no such feedback within the window, or when
# the event never happened (the bot never reached it, so nothing was checked).
function Test-JuiceLog([string[]]$Lines, $Config, [int]$Frames) {
    $events = @{}; $feedback = @{}
    foreach ($line in $Lines) {
        if ($line -match '^\s*\[juice\]\s+(?<kind>event|feedback)\s+(?<name>\S+)\s+(?<ms>-?\d+(?:\.\d+)?)\s*$') {
            $table = if ($Matches.kind -eq 'event') { $events } else { $feedback }
            if (-not $table.ContainsKey($Matches.name)) { $table[$Matches.name] = [System.Collections.Generic.List[double]]::new() }
            $table[$Matches.name].Add([double]::Parse($Matches.ms, [cultureinfo]::InvariantCulture))
        }
    }
    # At --fixed-fps 60 the run ends at a known game time; an event too close to the end had no chance to be answered.
    $endMs = $Frames * 1000.0 / 60
    $cases = [System.Collections.Generic.List[object]]::new()
    foreach ($rule in $Config.rules) {
        $within = if ($rule.Contains('withinMs')) { [double]$rule.withinMs } else { 100 }
        $times = @($events.ContainsKey($rule.event) ? @($events[$rule.event]) : @() | Where-Object { $_ + $within -lt $endMs })
        foreach ($name in @($rule.feedback)) {
            $caseName = "$($rule.event) -> $name within $within ms"
            if ($times.Count -eq 0) {
                $cases.Add(@{ Name = $caseName; Failure = "No '$($rule.event)' event in $Frames frames, so its feedback was never checked; does the bot reach it (juice.json ""args"", ""frames"")?" })
                continue
            }
            $answers = $feedback.ContainsKey($name) ? @($feedback[$name]) : @()
            $missed = @($times | Where-Object { $t = $_; -not ($answers | Where-Object { $_ -ge $t -and $_ -le $t + $within }) })
            $failure = if ($missed.Count -gt 0) {
                "$($missed.Count) of $($times.Count) '$($rule.event)' events had no '$name' within $within ms (first at $([math]::Round($missed[0], 1)) ms)"
            } else { '' }
            $cases.Add(@{ Name = $caseName; Failure = $failure })
        }
    }
    return $cases
}

# What the run itself adds to the rule cases: a failure, or a warning. A Godot that crashed (exit 128 and up, or a negative
# Windows code) after every rule had been judged is a crash in its shutdown (observed: exit 134, `FATAL: Condition
# "csharp_lang && !csharp_lang->script_bindings.is_empty()"` in the mono teardown, followed by hundreds of "Leaked unsafe
# reference" lines), nothing the change under test did: a warning with the FATAL line. A crash with a rule not judged, or an
# engine error before the crash, still fails, and so does any other nonzero exit.
function Get-JuiceRunVerdict([int]$Code, [string[]]$Lines, [object[]]$Cases) {
    $fatal = [array]::FindIndex($Lines, [Predicate[string]]{ param($l) $l -match 'FATAL:' })
    $before = if ($fatal -ge 0) { @($Lines[0..([Math]::Max(0, $fatal - 1))]) } else { @($Lines) }
    $errors = @(Select-GodotErrors $before)
    $crashed = $Code -ge 128 -or $Code -lt 0
    $judgedAll = @($Cases | Where-Object { $_.Failure }).Count -eq 0
    if ($Code -eq 0) { return [pscustomobject]@{ Failure = ($errors -join "`n"); Warning = '' } }
    if ($crashed -and $judgedAll -and $errors.Count -eq 0) {
        $line = if ($fatal -ge 0) { $Lines[$fatal].Trim() } else { 'no FATAL line in the log' }
        return [pscustomobject]@{ Failure = ''; Warning = "Godot crashed at shutdown (exit $Code) after every rule was judged: $line" }
    }
    return [pscustomobject]@{ Failure = "Godot exited with $Code"; Warning = '' }
}

function Invoke-JuiceRunner($Info, [string]$ResultsDir, [string[]]$GameArgs) {
    $config = Get-JuiceConfig $Info.ProjectDir
    if (-not $config) { Stop-GodotCi "juice runner: no juice.json in $($Info.ProjectDir)" 'invalid-arguments' }
    $frames = if ($config.Contains('frames')) { [int]$config.frames } else { 1800 }
    $gameArgs = @(@($config.Contains('args') ? $config.args : @()) + @($GameArgs) | Where-Object { $_ })
    $log = Join-Path $ResultsDir 'juice.log'
    Start-LogGroup "Juice ($frames frames$(if ($gameArgs) { ', ' + ($gameArgs -join ' ') }))"
    $engine = @('--headless', '--path', $Info.ProjectDir, '--fixed-fps', '60', '--quit-after', "$frames")
    $code = Invoke-Logged $env:GODOT_BIN ($engine + $(if ($gameArgs) { @('--') + $gameArgs })) $log
    Stop-LogGroup
    $cases = @(Test-JuiceLog @(Get-Content -LiteralPath $log) $config $frames)
    $verdict = Get-JuiceRunVerdict $code @(Get-Content -LiteralPath $log) $cases
    $runFailure = $verdict.Failure
    if ($verdict.Warning) { Write-CiLog "WARN: $($verdict.Warning)" }
    $cases = @(@{ Name = 'run'; Failure = $runFailure }) + $cases
    Write-JUnitCases (Join-Path $ResultsDir 'juice.junit.xml') 'juice' $cases
    return ($runFailure ? 1 : 0)
}
