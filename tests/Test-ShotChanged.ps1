#!/usr/bin/env pwsh
# Self-test of shot -MaxChangedPercent on a copy of tests/colorvision-fixture: the same scene again passes, the scene with one
# swatch repainted fails with shot-changed, -MaxChangedPercent without -Baseline is refused, and scenes that share a name in
# different folders get a picture each. Needs Godot (GODOT_BIN, or the kit installs it) and a display (Xvfb :99, DISPLAY=:99).
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$kit = Join-Path $root 'ci/godot/hyperdot.ps1'
$failures = @()
$temp = Join-Path ([System.IO.Path]::GetTempPath()) "shotchanged-$([guid]::NewGuid().ToString('n').Substring(0, 8))"
$project = Join-Path $temp 'game'
New-Item -ItemType Directory -Force $project | Out-Null
Copy-Item -Path (Join-Path $PSScriptRoot 'colorvision-fixture/*') -Destination $project -Recurse
function Invoke-KitShot([string[]]$More) {
    $err = Join-Path $temp 'stderr.txt'
    $json = & pwsh -NoProfile -NonInteractive -File $kit shot -Project $project -Scene res://swatches.tscn -Resolution 640x360 -Frames 5 -Json @More 2>$err
    try { return ($json | Out-String | ConvertFrom-Json) }
    catch { throw "shot $($More -join ' ') printed no JSON: $((Get-Content -LiteralPath $err -Raw) -replace '\s+$', '')" }
}
$before = Join-Path $temp 'before'; $after = Join-Path $temp 'after'
$first = Invoke-KitShot @('-Output', $before)
if (-not $first.ok) { $failures += "baseline screenshots failed: $($first.error.code) $($first.error.message)" }
$same = Invoke-KitShot @('-Output', $after, '-Baseline', $before, '-MaxChangedPercent', '0.5')
if (-not $same.ok) { $failures += "an unchanged scene should pass: $($same.error.code) $($same.error.message)" }
$scene = Join-Path $project 'swatches.tscn'
(Get-Content -LiteralPath $scene -Raw) -replace 'color = Color\(0\.784314, 0\.27451, 0\.0627451, 1\)', 'color = Color(0.1, 0.2, 0.9, 1)' | Set-Content -LiteralPath $scene -NoNewline
$changed = Invoke-KitShot @('-Output', (Join-Path $temp 'changed'), '-Baseline', $before, '-MaxChangedPercent', '0.5')
if ($changed.ok -or $changed.error.code -ne 'shot-changed') { $failures += "a repainted swatch should fail with shot-changed: $($changed | ConvertTo-Json -Depth 5 -Compress)" }
elseif (@($changed.shots)[0].compare.changedPercent -le 0.5) { $failures += "the repainted swatch should change more than 0.5%: $(@($changed.shots)[0].compare.changedPercent)" }
$loose = Invoke-KitShot @('-Output', (Join-Path $temp 'loose'), '-Baseline', $before, '-MaxChangedPercent', '100')
if (-not $loose.ok) { $failures += "100% allowed should pass: $($loose.error.code)" }
$alone = Invoke-KitShot @('-Output', (Join-Path $temp 'alone'), '-MaxChangedPercent', '1')
if ($alone.ok -or $alone.error.code -ne 'invalid-arguments') { $failures += "-MaxChangedPercent without -Baseline should be refused: $($alone.error.code)" }
# A project that renders at its base size (stretch aspect keep): a wider window gives the base size, and shot says so; -RequireResolution fails.
$keep = Join-Path $temp 'keep'
Copy-Item -LiteralPath $project -Destination $keep -Recurse
$display = @('', '[display]', '', 'window/size/viewport_width=640', 'window/size/viewport_height=360', 'window/stretch/mode="canvas_items"', 'window/stretch/aspect="keep"') -join "`n"
Add-Content -LiteralPath (Join-Path $keep 'project.godot') -Value $display
$keepErr = Join-Path $temp 'keep.stderr.txt'
$keepJson = & pwsh -NoProfile -NonInteractive -File $kit shot -Project $keep -Scene res://swatches.tscn -Resolution 960x360 -Frames 5 -Output (Join-Path $temp 'keep-out') -Json 2>$keepErr | Out-String | ConvertFrom-Json
$keepShot = @($keepJson.shots)[0]
if (-not $keepJson.ok -or $keepShot.requested -ne '960x360' -or $keepShot.sizeMatches -or $keepShot.width -ne 640) { $failures += "a window wider than the base aspect with stretch keep should report a 640 picture that does not match 960x360: $($keepJson | ConvertTo-Json -Depth 5 -Compress)" }
if ((Get-Content -LiteralPath $keepErr -Raw) -notmatch 'stretch is mode canvas_items, aspect keep') { $failures += 'the size warning should name the stretch setting' }
$strict = & pwsh -NoProfile -NonInteractive -File $kit shot -Project $keep -Scene res://swatches.tscn -Resolution 960x360 -Frames 5 -Output (Join-Path $temp 'keep-strict') -RequireResolution -Json 2>$null | Out-String | ConvertFrom-Json
if ($strict.ok -or $strict.error.code -ne 'shot-size') { $failures += "-RequireResolution should fail with shot-size: $($strict | ConvertTo-Json -Depth 5 -Compress)" }
elseif ($strict.error.message -notmatch 'stretch is mode \w+, aspect keep' -or $strict.error.message -notmatch 'not shown at 960x360') { $failures += "the shot-size error should name the stretch setting and say the layout is not shown: $($strict.error.message)" }
$match = & pwsh -NoProfile -NonInteractive -File $kit shot -Project $keep -Scene res://swatches.tscn -Resolution 640x360 -Frames 5 -Output (Join-Path $temp 'keep-match') -RequireResolution -Json 2>$null | Out-String | ConvertFrom-Json
if (-not $match.ok -or -not @($match.shots)[0].sizeMatches) { $failures += "a picture of the size asked for passes -RequireResolution: $($match | ConvertTo-Json -Depth 5 -Compress)" }
# Two scenes with the same name in different folders get a picture each, not one written over the other.
foreach ($folder in 'a', 'b') {
    New-Item -ItemType Directory -Force (Join-Path $project $folder) | Out-Null
    Copy-Item -LiteralPath $scene -Destination (Join-Path $project "$folder/swatches.tscn")
}
$twinErr = Join-Path $temp 'twins.stderr.txt'
$twinJson = & pwsh -NoProfile -NonInteractive -File $kit shot -Project $project -Scene 'res://swatches.tscn,res://a/swatches.tscn,res://b/swatches.tscn' -Resolution 640x360 -Frames 5 -Output (Join-Path $temp 'twins') -Json 2>$twinErr
$twins = $twinJson | Out-String | ConvertFrom-Json
$twinFiles = @(@($twins.shots) | ForEach-Object { Split-Path -Leaf $_.file })
if (-not $twins.ok -or ($twinFiles -join ',') -ne 'swatches.png,a_swatches.png,b_swatches.png') { $failures += "scenes with the same name should get their own pictures: $($twinFiles -join ', ')" }
Remove-Item -Recurse -Force $temp
if ($failures) { $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }; exit 1 }
Write-Host "shot -MaxChangedPercent passes an unchanged scene, fails a repainted one with shot-changed ($(@($changed.shots)[0].compare.changedPercent)% changed), and needs -Baseline"
exit 0
