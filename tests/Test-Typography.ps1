#!/usr/bin/env pwsh
# What the typography skill says about Godot, held in the engine on tests/typography-fixture through the kit's gut runner. The
# script writes every Class.member the skill's godot.md quotes in backticks into the fixture's test/api.txt; test/
# test_typography.gd checks each against ClassDB and measures the numbers the skill states (line pitch, tracking in pixels,
# tabular and proportional figures, uppercase, feature names). Then a made-up name is added to api.txt and must fail by name,
# so a check that stopped looking is noticed. A second project holds a label with real marks (curly apostrophe, ellipsis, no-break space) and two flows:
# one asserts the same characters and passes, one asserts the straight, three-dot version and fails, as the ui-flows skill says.
# Needs Godot (GODOT_BIN, or the kit installs it).
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$kit = Join-Path $root 'ci/godot/hyperdot.ps1'
$failures = [System.Collections.Generic.List[string]]::new()
function Assert-True([bool]$Condition, [string]$What) {
    if ($Condition) { Write-Host "ok     $What" } else { Write-Host "FAILED $What" -ForegroundColor Red; $failures.Add($What) }
}

# A backticked Class.member of an engine class the skill quotes (godot.md and punctuation.md); its own scripts and files are not the engine's.
$text = (@('godot.md', 'punctuation.md') | ForEach-Object { Get-Content -LiteralPath (Join-Path $root ".agents/skills/typography/$_") -Raw }) -join "`n"
$classes = 'FontFile|FontVariation|LabelSettings|Label|Control|ThemeDB|Font|TextServer'
$names = [System.Collections.Generic.SortedSet[string]]::new()
foreach ($m in [regex]::Matches($text, '`([^`\r\n]+)`')) {
    $token = $m.Groups[1].Value
    if ($token -cmatch "^($classes)\.[A-Za-z_][A-Za-z0-9_]*(\(\))?$") { [void]$names.Add($token) }
}
Assert-True ($names.Count -ge 20) "the skill's side files quote at least 20 engine names: $($names.Count)"

$game = Join-Path ([IO.Path]::GetTempPath()) "typography-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
Copy-Item -Recurse -LiteralPath (Join-Path $PSScriptRoot 'typography-fixture') $game
$api = Join-Path $game 'test/api.txt'
[IO.File]::WriteAllText($api, (($names -join "`n") + "`n"))

function Invoke-Typography([string]$Tag) {
    $results = Join-Path $game "r-$Tag"
    $json = pwsh -NoProfile -NonInteractive -File $kit test -Json -Quiet -Project $game -Runners gut -Results $results 2>$null | ConvertFrom-Json
    $runner = @($json.runnerResults | Where-Object runner -eq 'gut')[0]
    $log = Get-Content -LiteralPath (Join-Path $results 'gut/gut.log') -Raw
    return [pscustomobject]@{ Ok = [bool]$json.ok; Total = $runner.total; Failed = @($runner.failures).Count; Log = $log }
}

try {
    $good = Invoke-Typography 'good'
    Assert-True ($good.Ok) "the typography fixture passes: $($good.Failed) failed of $($good.Total)$(if (-not $good.Ok) { "`n" + $good.Log })"
    Assert-True ($good.Total -ge 6) "at least 6 tests ran: $($good.Total)"
    Assert-True ($good.Log -match '\d+ names checked') 'the names were counted'

    [IO.File]::AppendAllText($api, "FontVariation.no_such_thing`nLabelSettings.no_such_setting`n")
    $bad = Invoke-Typography 'bad'
    Assert-True (-not $bad.Ok) 'made-up names fail the run'
    foreach ($made in 'FontVariation.no_such_thing', 'LabelSettings.no_such_setting') {
        Assert-True ($bad.Log.Contains("missing from the engine: $made")) "the report names $made"
    }
}
finally {
    Remove-Item -Recurse -Force -LiteralPath $game -ErrorAction SilentlyContinue
}

# The ui-flows claim: a text assertion compares exact characters.
$flowGame = Join-Path ([IO.Path]::GetTempPath()) "typography-flows-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
try {
    New-Item -ItemType Directory -Force (Join-Path $flowGame 'test/flows/good'), (Join-Path $flowGame 'test/flows/bad') | Out-Null
    $nbsp = [string][char]0x00A0
    [IO.File]::WriteAllText((Join-Path $flowGame 'project.godot'), "config_version=5`n`n[application]`n`nconfig/name=`"typography-flows`"`nrun/main_scene=`"res://text.tscn`"`nconfig/features=PackedStringArray(`"4.7`")`n")
    [IO.File]::WriteAllText((Join-Path $flowGame 'text.tscn'), "[gd_scene format=3]`n`n[node name=`"Root`" type=`"Control`"]`n`n[node name=`"Label`" type=`"Label`" parent=`".`"]`ntext = `"Don$([char]0x2019)t stop$([char]0x2026)${nbsp}now`"`n")
    $flow = { param($Equals) (@{ scene = 'res://text.tscn'; steps = @(@{ wait = 2 }, @{ assert = @{ node = 'Label'; prop = 'text'; equals = $Equals } }) } | ConvertTo-Json -Depth 6) }
    [IO.File]::WriteAllText((Join-Path $flowGame 'test/flows/good/real_marks.flow.json'), (& $flow "Don$([char]0x2019)t stop$([char]0x2026)${nbsp}now"))
    [IO.File]::WriteAllText((Join-Path $flowGame 'test/flows/bad/straight_marks.flow.json'), (& $flow "Don't stop... now"))
    foreach ($case in @(@{ Dir = 'good'; Pass = $true }, @{ Dir = 'bad'; Pass = $false })) {
        $json = pwsh -NoProfile -NonInteractive -File $kit test -Json -Quiet -Project $flowGame -Runners flows -Filter "flows/$($case.Dir)/" -Results (Join-Path $flowGame "r-$($case.Dir)") 2>$null | Out-String | ConvertFrom-Json
        if ($case.Pass) { Assert-True ([bool]$json.ok) 'a flow asserting the real marks (curly apostrophe, ellipsis character, no-break space) passes' }
        else { Assert-True (-not [bool]$json.ok) 'a flow asserting the straight, three-dot, ordinary-space version fails' }
    }
}
finally {
    Remove-Item -Recurse -Force -LiteralPath $flowGame -ErrorAction SilentlyContinue
}

if ($failures.Count) { Write-Host "$($failures.Count) check(s) failed" -ForegroundColor Red; exit 1 }
Write-Host 'the Godot names the typography skill quotes exist, and line pitch, tracking, figures, uppercase and feature names behave as it says'
exit 0
