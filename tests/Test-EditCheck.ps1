#!/usr/bin/env pwsh
# Self-test of the plugin's edit hook (hooks/edit-check.ps1) and ci/godot/tools/editcheck.gd on a copy of examples/gdscript:
# a script with a syntax error, one that names an undeclared identifier, a scene that points to a script that is not there
# and a working script, scene and resource; the Write form with a relative path; and every case where the hook must say
# nothing (another file type, addons/, no .godot folder, no Godot, a missing file, HYPERDOT_EDIT_CHECK=off, empty or
# damaged hook input, a .gdignore'd folder). The hook finds Godot the way a player's machine does, in the kit's install
# folder, because the first `test` run installs it there. Needs Godot.
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$hook = Join-Path $root 'hooks/edit-check.ps1'
$example = Join-Path $root 'examples/gdscript'
$kit = Join-Path $root 'ci/godot/hyperdot.ps1'
$temp = Join-Path ([System.IO.Path]::GetTempPath()) "edit-check-$PID"
$pwsh = (Get-Process -Id $PID).Path
$failures = @()

function Copy-Game([string]$Name) {
    $game = Join-Path $temp $Name
    New-Item -ItemType Directory -Force $game | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $example -Force | Where-Object { $_.Name -notin '.godot', 'test-results' }) {
        Copy-Item -LiteralPath $item.FullName -Destination $game -Recurse
    }
    return $game
}

# Runs the hook with the given stdin text; returns its output text and exit code.
function Invoke-Hook([string]$StdIn, [hashtable]$Env = @{}) {
    $info = [System.Diagnostics.ProcessStartInfo]::new($pwsh)
    foreach ($arg in '-NoProfile', '-NonInteractive', '-File', $hook) { $info.ArgumentList.Add($arg) }
    $info.RedirectStandardInput = $true; $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
    $info.UseShellExecute = $false
    foreach ($key in $Env.Keys) { if ($null -eq $Env[$key]) { $info.Environment.Remove($key) | Out-Null } else { $info.Environment[$key] = $Env[$key] } }
    $process = [System.Diagnostics.Process]::Start($info)
    $out = $process.StandardOutput.ReadToEndAsync(); $err = $process.StandardError.ReadToEndAsync()
    $process.StandardInput.Write($StdIn); $process.StandardInput.Close()
    $process.WaitForExit()
    return [pscustomobject]@{ Out = "$($out.Result)".Trim(); Err = "$($err.Result)".Trim(); Code = $process.ExitCode }
}

function New-EditInput([string]$Cwd, [string]$File, [string]$Tool = 'Edit') {
    return ConvertTo-Json -Compress -Depth 4 -InputObject ([ordered]@{ cwd = $Cwd; hook_event_name = 'PostToolUse'; tool_name = $Tool; tool_input = [ordered]@{ file_path = $File } })
}

function Assert-Silent($Result, [string]$What) {
    if ($Result.Code -ne 0 -or $Result.Out -or $Result.Err) { $script:failures += "$What should say nothing and exit 0: exit $($Result.Code), out '$($Result.Out)', err '$($Result.Err)'" }
}

function Assert-Note($Result, [string]$What, [string[]]$Contains) {
    if ($Result.Code -ne 0) { $script:failures += "$What must not block: exit $($Result.Code)"; return }
    $doc = $null
    try { $doc = $Result.Out | ConvertFrom-Json } catch { Write-Verbose "not JSON: $($_.Exception.Message)" }
    if ($null -eq $doc -or -not $doc.PSObject.Properties['hookSpecificOutput']) { $script:failures += "$What printed no note: '$($Result.Out)' $($Result.Err)"; return }
    if ($doc.hookSpecificOutput.hookEventName -ne 'PostToolUse') { $script:failures += "$What names the wrong event: $($Result.Out)"; return }
    $text = "$($doc.hookSpecificOutput.additionalContext)"
    foreach ($needle in $Contains) { if ($text -notmatch [regex]::Escape($needle)) { $script:failures += "$What should mention '$needle': $text" } }
    if ($text -match 'editcheck\.gd') { $script:failures += "$What shows the checking tool's own stack frames: $text" }
    # The engine's words reach Claude as quoted data, without the machine's paths.
    if ($text -notmatch '(?s)quoted as data.*```text\n.*\n```') { $script:failures += "$What does not fence the engine's output as data: $text" }
    if ($text.Contains($temp) -or $text.Contains($temp.Replace('\', '/'))) { $script:failures += "$What shows the machine's path to the game: $text" }
    if (([regex]::Matches($text, '```')).Count -ne 2) { $script:failures += "$What has more than one fence: $text" }
}

try {
    $game = Copy-Game 'game'
    # The first run installs Godot into the kit's folder and imports the game (.godot); its own verdict does not matter here.
    & $pwsh -NoProfile -NonInteractive -File $kit test -Project $game -Runners none -Results (Join-Path $temp 'results') -Json 2>$null | Out-Null
    & $pwsh -NoProfile -NonInteractive -File $kit test -Project $game -Runners validate -Results (Join-Path $temp 'results') -Json 2>$null | Out-Null
    if (-not (Test-Path -LiteralPath (Join-Path $game '.godot') -PathType Container)) { throw 'the first test run left no .godot folder in the copy' }
    $noGodot = @{ GODOT_BIN = $null }   # the hook must find Godot itself

    Set-Content -LiteralPath (Join-Path $game 'broken_syntax.gd') -Value "extends Node`nfunc f(:`n"
    Set-Content -LiteralPath (Join-Path $game 'broken_name.gd') -Value "extends Node`nfunc f() -> int:`n`treturn undefined_thing`n"
    Set-Content -LiteralPath (Join-Path $game 'broken_ref.tscn') -Value "[gd_scene format=3]`n[ext_resource type=`"Script`" path=`"res://nope.gd`" id=`"1`"]`n[node name=`"X`" type=`"Node`"]`nscript = ExtResource(`"1`")`n"
    # A scene whose script writes a file in _init: the hook loads the scene and must not run that code.
    Set-Content -LiteralPath (Join-Path $game 'side_effect.gd') -Value "extends Node`nfunc _init() -> void:`n`tvar f := FileAccess.open(`"res://ran.txt`", FileAccess.WRITE)`n`tf.store_string(`"ran`")`n"
    Set-Content -LiteralPath (Join-Path $game 'side_effect.tscn') -Value "[gd_scene format=3]`n[ext_resource type=`"Script`" path=`"res://side_effect.gd`" id=`"1`"]`n[node name=`"X`" type=`"Node`"]`nscript = ExtResource(`"1`")`n"
    New-Item -ItemType Directory -Force (Join-Path $game 'addons/some_addon') | Out-Null
    Set-Content -LiteralPath (Join-Path $game 'addons/some_addon/broken.gd') -Value "extends Node`nfunc f(:`n"

    # Files that load: silence.
    foreach ($good in 'main.gd', 'main.tscn', 'score.gd') {
        Assert-Silent (Invoke-Hook (New-EditInput $game (Join-Path $game $good)) $noGodot) "a working $good"
    }
    # Broken files: a note with the file and the engine's words, exit 0, one JSON line.
    Assert-Note (Invoke-Hook (New-EditInput $game (Join-Path $game 'broken_syntax.gd')) $noGodot) 'a syntax error' @('res://broken_syntax.gd', 'Parse Error', 'broken_syntax.gd:2')
    Assert-Note (Invoke-Hook (New-EditInput $game (Join-Path $game 'broken_name.gd')) $noGodot) 'an undeclared identifier' @('res://broken_name.gd', 'undefined_thing')
    Assert-Note (Invoke-Hook (New-EditInput $game (Join-Path $game 'broken_ref.tscn')) $noGodot) 'a scene with a missing script' @('res://broken_ref.tscn', 'nope.gd')
    # Write, with a path relative to the working folder.
    Assert-Note (Invoke-Hook (New-EditInput $game 'broken_syntax.gd' 'Write') $noGodot) 'a relative path from Write' @('res://broken_syntax.gd')
    # The same editor-built Godot named by GODOT_BIN: found there too.
    $found = @(Get-ChildItem -LiteralPath (Join-Path $HOME '.hyperdot') -Recurse -Depth 3 -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^Godot_v\d.*(_linux\.(x86_64|arm64)|_win64_console\.exe)$' } | Select-Object -First 1)
    if ($found.Count -gt 0) {
        Assert-Note (Invoke-Hook (New-EditInput $game (Join-Path $game 'broken_syntax.gd')) @{ GODOT_BIN = $found[0].FullName }) 'GODOT_BIN' @('res://broken_syntax.gd')
    }

    Assert-Silent (Invoke-Hook (New-EditInput $game (Join-Path $game 'side_effect.tscn')) $noGodot) 'a scene with an _init side effect'
    if (Test-Path -LiteralPath (Join-Path $game 'ran.txt')) { $failures += 'the hook instantiated a scene and ran the project''s _init' }

    # Where it must stay quiet.
    Assert-Silent (Invoke-Hook (New-EditInput $game (Join-Path $game 'project.godot')) $noGodot) 'a file that is not a script, scene or resource'
    Assert-Silent (Invoke-Hook (New-EditInput $game (Join-Path $game 'addons/some_addon/broken.gd')) $noGodot) 'a file under addons/'
    Assert-Silent (Invoke-Hook (New-EditInput $game (Join-Path $game 'gone.gd')) $noGodot) 'a file that is not there'
    Assert-Silent (Invoke-Hook (New-EditInput $game (Join-Path $game 'broken_syntax.gd')) @{ GODOT_BIN = $null; HYPERDOT_EDIT_CHECK = 'off' }) 'HYPERDOT_EDIT_CHECK=off'
    Assert-Silent (Invoke-Hook (New-EditInput $game (Join-Path $game 'broken_syntax.gd')) @{ GODOT_BIN = $null; GODOT_TOOLS_DIR = (Join-Path $temp 'empty-tools') }) 'no Godot installed'
    Assert-Silent (Invoke-Hook '' $noGodot) 'empty hook input'
    Assert-Silent (Invoke-Hook '{ not json' $noGodot) 'damaged hook input'
    Assert-Silent (Invoke-Hook '{"tool_input":"x"}' $noGodot) 'a tool_input that is not an object'
    Assert-Silent (Invoke-Hook '{"tool_name":"Edit","tool_input":{}}' $noGodot) 'an edit with no file'

    # A game that was never imported has no .godot folder: the first load would import everything, so the hook waits.
    $fresh = Copy-Game 'fresh'
    Set-Content -LiteralPath (Join-Path $fresh 'broken_syntax.gd') -Value "extends Node`nfunc f(:`n"
    if (Test-Path -LiteralPath (Join-Path $fresh '.godot')) { Remove-Item -LiteralPath (Join-Path $fresh '.godot') -Recurse -Force }
    Assert-Silent (Invoke-Hook (New-EditInput $fresh (Join-Path $fresh 'broken_syntax.gd')) $noGodot) 'a game with no .godot folder'

    # A folder with .gdignore (the kit placed inside a game) is not the game's own code.
    $ignored = Join-Path $game 'kit'
    New-Item -ItemType Directory -Force $ignored | Out-Null
    New-Item -ItemType File -Force (Join-Path $ignored '.gdignore') | Out-Null
    Set-Content -LiteralPath (Join-Path $ignored 'broken.gd') -Value "extends Node`nfunc f(:`n"
    Assert-Silent (Invoke-Hook (New-EditInput $game (Join-Path $ignored 'broken.gd')) $noGodot) 'a file in a .gdignore folder'
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures) { $failures | ForEach-Object { Write-Host "FAIL $_" -ForegroundColor Red }; exit 1 }
Write-Host 'the edit hook reports a syntax error, an undeclared name and a missing script reference with the engine''s words, says nothing for a file that loads or one it cannot check, and never blocks'
exit 0
