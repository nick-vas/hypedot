# `deck`: the Steam Deck check in one command. Valve's Deck Verified review asks for a supported resolution (1280x800, or
# 1280x720), text no smaller than 9 px at 1280x800 (12 recommended) and playable performance in the default settings
# (docs/console-cert.md). This runs, at 1280x800 and one after another:
#   textsize  the textsize runner with its resolutions forced to 1280x800 (textsize.json's sizes still apply)
#   layout    the layout runner on the steam_deck profile, off-screen check only
#   shot      shot at 1280x800 (with -Locale/-Pseudo: their text checks too), to look at
#   bench     bench at 1280x800 on the first -Scene (default the main scene), with -BudgetMs, default 33.3 (30 fps)
# -Scene names the scenes for all four (bench measures the first); without it, textsize and layout take their JSON's
# scenes or the main scene, and shot and bench the main scene. Every part runs even when an earlier one failed; the verdict fails (deck-failed) when any did, and deck.parts[] says
# which, with each part's own code. bench measures this machine at the Deck's resolution, not a Deck's speed.

$script:DeckResolution = '1280x800'
$script:DeckBudgetMs = 33.3

# The Deck's displays at their default frame limit, the only data Steam's store page shows for a game since November 2026 (the average frame
# rate and a histogram, from players who opted in): 90 Hz on the OLED model, 60 Hz on the LCD one (docs/steam.md).
$script:DeckDisplays = [ordered]@{ 'Steam Deck OLED' = 90; 'Steam Deck LCD' = 60 }

# What a frame cap does on each Deck display with VSync: a game that cannot present every refresh falls to the next divisor of the refresh
# rate for that frame (Valve: 75 fps on a 90 Hz display presents as 90 90 45, and a game with an internal limit of 60 "will bounce between
# 90 and 45"). A cap at or above the refresh rate, or one that divides it, paces evenly; any other is uneven on that display, and the
# store's histogram shows it as two columns. Returns one message per display the cap is uneven on; none for no cap (0).
function Get-DeckPacingWarnings([int]$MaxFps) {
    if ($MaxFps -le 0) { return @() }
    @(foreach ($name in $script:DeckDisplays.Keys) {
        $hz = $script:DeckDisplays[$name]
        if ($MaxFps -ge $hz -or $hz % $MaxFps -eq 0) { continue }
        $divisors = @(1..4 | ForEach-Object { $hz / $_ } | Where-Object { $_ -eq [math]::Floor($_) })
        $above = @($divisors | Where-Object { $_ -gt $MaxFps } | Select-Object -Last 1)[0]
        $below = @($divisors | Where-Object { $_ -lt $MaxFps } | Select-Object -First 1)[0]
        "a frame cap of $MaxFps (application/run/max_fps) does not divide the ${name}'s $hz Hz: with VSync its frames alternate between $above and $below fps, which Steam's store page shows in the game's frame-rate histogram; cap at a divisor of the display's rate ($(@($divisors | Where-Object { $_ -ge 30 }) -join ', ')) or leave the pacing to VSync"
    })
}

# The project's frame cap (application/run/max_fps in project.godot; 0 is none). A cap set in code (Engine.max_fps) is not read.
function Get-ProjectMaxFps([string]$ProjectDir) {
    $file = Join-Path $ProjectDir 'project.godot'
    if (-not (Test-Path -LiteralPath $file)) { return 0 }
    $m = [regex]::Match([System.IO.File]::ReadAllText($file), '(?m)^run/max_fps=(?<v>\d+)\s*$')
    return $(if ($m.Success) { [int]$m.Groups['v'].Value } else { 0 })
}

# Runs one part with stops caught: returns { part, ok, code, message } plus what the part adds ($Body returns a dictionary
# of extra fields, or nothing; an "ok" of false among them fails the part as tests-failed).
function Invoke-DeckPart([string]$Name, [scriptblock]$Body) {
    $entry = [ordered]@{ part = $Name; ok = $true; code = $null; message = $null }
    Start-LogGroup "Steam Deck: $Name"
    $script:CatchStops = $true
    try {
        $extra = & $Body
        if ($extra -is [System.Collections.IDictionary]) { foreach ($key in @($extra.Keys)) { $entry[$key] = $extra[$key] } }
        if (-not $entry.ok) { $entry.code = 'tests-failed' }
    } catch {
        $entry.ok = $false
        $entry.code = if ($_.Exception.Data.Contains('HyperdotCode')) { $_.Exception.Data['HyperdotCode'] } else { 'unexpected-error' }
        $entry.message = $_.Exception.Message
    } finally {
        $script:CatchStops = $false
        $script:TextSizeOverride = @{}
        $script:LayoutOverride = @{}
        Stop-LogGroup
    }
    Write-CiLog "Steam Deck ${Name}: $(if ($entry.ok) { 'OK' } else { "FAILED ($($entry.code))$(if ($entry.message) { ": $($entry.message)" })" })"
    return $entry
}

# A runner's result (Write-TestSummary's) as a deck part's fields.
function ConvertTo-DeckRunnerPart($Result) {
    $failures = @($Result.Failures | ForEach-Object { [ordered]@{ name = $_.Name; message = $_.Message } })
    return [ordered]@{
        ok = [bool]$Result.Ok; total = $Result.Total; failed = $Result.Failed; failures = $failures
        warnings = @($Result.Warnings | Where-Object { $_ } | ForEach-Object { [ordered]@{ rule = $_.rule; file = $_.file; message = $_.message } })
        message = $(if (-not $Result.Ok) { "$($Result.Failed) failing: $(@($failures | Select-Object -First 3 | ForEach-Object { "$($_.name): $($_.message)" }) -join '; ')" })
    }
}

function Invoke-Deck {
    param($Info, [string[]]$Scene, [double]$Seconds, [double]$Warmup, [int]$Frames, [double]$BudgetMs, [double]$MaxDrawCalls,
        [double]$MaxLoadMs, [string[]]$GameArgs, [string[]]$Locale, [switch]$Pseudo, [switch]$GpuValidation, [string]$ResultsDir)
    $budget = if ($BudgetMs -gt 0) { $BudgetMs } else { $script:DeckBudgetMs }
    $scenes = @($Scene | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    New-Item -ItemType Directory -Force $ResultsDir | Out-Null
    $parts = [System.Collections.Generic.List[object]]::new()
    $parts.Add((Invoke-DeckPart 'textsize' {
        $script:TextSizeOverride = @{ resolutions = @($script:DeckResolution) }
        if ($scenes) { $script:TextSizeOverride['scenes'] = $scenes }
        ConvertTo-DeckRunnerPart (Invoke-TestRunner -Runner textsize -Info $Info -ResultsDir (Join-Path $ResultsDir 'textsize') -Filter '' -Coverage $false -Frames $Frames -GameArgs $GameArgs)
    }))
    $parts.Add((Invoke-DeckPart 'layout' {
        $script:LayoutOverride = @{ profiles = @('steam_deck'); checks = @('off-screen') }
        if ($scenes) { $script:LayoutOverride['scenes'] = $scenes }
        ConvertTo-DeckRunnerPart (Invoke-TestRunner -Runner layout -Info $Info -ResultsDir (Join-Path $ResultsDir 'layout') -Filter '' -Coverage $false -Frames $Frames -GameArgs $GameArgs)
    }))
    $parts.Add((Invoke-DeckPart 'shot' {
        $dir = Join-Path $ResultsDir 'screenshots'
        Invoke-Shot -Info $Info -Scene $scenes -Frames $Frames -Resolution $script:DeckResolution -GameArgs $GameArgs -Locale $Locale -Pseudo:$Pseudo `
            -GpuValidation:$GpuValidation -OutputDir $dir
        [ordered]@{ folder = $dir }
    }))
    $parts.Add((Invoke-DeckPart 'bench' {
        Invoke-Bench -Info $Info -Scene $(if ($scenes) { $scenes[0] } else { '' }) -Seconds $Seconds -Warmup $Warmup -Resolution $script:DeckResolution `
            -BudgetMs $budget -MaxDrawCalls $MaxDrawCalls -MaxLoadMs $MaxLoadMs -Label 'steam deck' -GameArgs $GameArgs -GpuValidation:$GpuValidation `
            -ResultsDir (Join-Path $ResultsDir 'bench')
        $result = Get-Content -LiteralPath (Join-Path $ResultsDir 'bench/bench.json') -Raw | ConvertFrom-Json
        [ordered]@{ p99Ms = $result.frameMs.p99; fpsAvg = $result.fps.avg }
    }))
    $failed = @($parts | Where-Object { -not $_.ok })
    # Not a part and never a failure: how the project's frame cap paces on the Deck's two displays.
    $maxFps = Get-ProjectMaxFps $Info.ProjectDir
    $pacing = @(Get-DeckPacingWarnings $maxFps)
    foreach ($warning in $pacing) { Write-CiLog "WARN: $warning" }
    Set-JsonField deck ([ordered]@{ resolution = $script:DeckResolution; budgetMs = $budget; ok = ($failed.Count -eq 0); parts = $parts.ToArray()
        framePacing = [ordered]@{ maxFps = $maxFps; displays = $script:DeckDisplays; warnings = $pacing } })
    if ($failed.Count -gt 0) {
        Stop-GodotCi "Steam Deck check failed: $(@($failed | ForEach-Object { "$($_.part) ($($_.code))" }) -join ', ') (see deck.parts)" 'deck-failed'
    }
    Write-CiLog "Steam Deck check passed at $($script:DeckResolution): text size, layout, screenshots, and p99 within $budget ms"
}
