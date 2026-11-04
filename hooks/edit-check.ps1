#Requires -Version 7.6
# PostToolUse hook (Edit and Write): after Claude edits a .gd, .tscn or .tres file, loads that one file in headless Godot
# (ci/godot/tools/editcheck.gd) and tells Claude at once when it does not compile, does not instantiate or names something
# that is not there, instead of at the end of the turn. A file that loads says nothing. It costs the engine's start-up,
# about 0.2 s whatever the project's size, and never blocks: the tool has already run, so the note is added as context.
# It stays quiet (exit 0, no output) when it cannot check: no Godot found, the game not imported yet (no .godot folder),
# a file under addons/, a C# file, or a Godot that takes too long. Godot is $env:GODOT_BIN, or one of the kit's installs
# under ~/.hyperdot (the one matching project.godot's version, else the newest). Set HYPERDOT_EDIT_CHECK=off to disable it.
# It parses and loads; it does not run the game's tests. The Stop hook (stop-gate.ps1) still decides when "done" is true.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

function Exit-Quiet { exit 0 }
function Write-Note([string]$Text) {
    $out = [ordered]@{ hookSpecificOutput = [ordered]@{ hookEventName = 'PostToolUse'; additionalContext = $Text } }
    [Console]::Out.WriteLine((ConvertTo-Json -InputObject $out -Compress -Depth 4))
    exit 0
}

# The Godot binaries the kit installed, newest first, the one for the project's version (project.godot's "4.7") ahead of the rest.
function Find-InstalledGodot([string]$ProjectGodotFile) {
    $toolsDir = if ($env:GODOT_TOOLS_DIR) { $env:GODOT_TOOLS_DIR } else { Join-Path $HOME '.hyperdot' }
    if (-not (Test-Path -LiteralPath $toolsDir -PathType Container)) { return $null }
    $features = ''
    if ((Get-Content -LiteralPath $ProjectGodotFile -Raw) -match 'config/features=PackedStringArray\("(?<v>\d+\.\d+)"') { $features = $Matches.v }
    $bins = @(Get-ChildItem -LiteralPath $toolsDir -Recurse -Depth 3 -File -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match '^Godot_v\d.*(_linux\.(x86_64|arm64)|_win64_console\.exe)$' -or ($_.Name -eq 'Godot' -and $_.FullName -match 'Godot[^/\\]*\.app[/\\]Contents[/\\]MacOS')
    } | Sort-Object LastWriteTimeUtc -Descending)
    $match = @($bins | Where-Object { $features -and $_.FullName -match "[/\\]Godot_v$([regex]::Escape($features))[.\-]" })
    if ($match.Count -gt 0) { return $match[0].FullName }
    if ($bins.Count -gt 0) { return $bins[0].FullName }
    return $null
}

try {
    if ($env:HYPERDOT_EDIT_CHECK -eq 'off') { Exit-Quiet }
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $raw = [Console]::In.ReadToEnd()
    if (-not $raw -or -not $raw.Trim()) { Exit-Quiet }
    $hookInput = $raw | ConvertFrom-Json -AsHashtable
    if ($hookInput -isnot [System.Collections.IDictionary] -or $hookInput['tool_input'] -isnot [System.Collections.IDictionary]) { Exit-Quiet }
    $file = $hookInput['tool_input']['file_path']
    if (-not $file -or $file -isnot [string] -or $file -notmatch '\.(gd|tscn|tres)$') { Exit-Quiet }
    if (-not [System.IO.Path]::IsPathRooted($file) -and $hookInput['cwd']) { $file = Join-Path $hookInput['cwd'] $file }
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { Exit-Quiet }   # a failed or deleted write

    # The game the file belongs to: the nearest folder above it with project.godot, unless a .gdignore'd folder comes first
    # (the kit placed inside a game is not the game's own code).
    $file = (Get-Item -LiteralPath $file).FullName
    $dir = (Get-Item -LiteralPath $file).Directory
    $projectDir = $null
    while ($dir) {
        if (Test-Path -LiteralPath (Join-Path $dir.FullName '.gdignore')) { break }
        if (Test-Path -LiteralPath (Join-Path $dir.FullName 'project.godot')) { $projectDir = $dir.FullName; break }
        $dir = $dir.Parent
    }
    if (-not $projectDir) { Exit-Quiet }
    $rel = [System.IO.Path]::GetRelativePath($projectDir, $file) -replace '\\', '/'
    if ($rel -match '^(addons|\.godot|test-results|TestResults)/') { Exit-Quiet }
    # No import cache yet: the first load would import everything (seconds), and the Stop hook's test run does that anyway.
    if (-not (Test-Path -LiteralPath (Join-Path $projectDir '.godot') -PathType Container)) { Exit-Quiet }

    $godot = if ($env:GODOT_BIN -and (Test-Path -LiteralPath $env:GODOT_BIN -PathType Leaf)) { $env:GODOT_BIN } else { Find-InstalledGodot (Join-Path $projectDir 'project.godot') }
    if (-not $godot) { Exit-Quiet }
    $tool = Join-Path $PSScriptRoot '../ci/godot/tools/editcheck.gd'
    if (-not (Test-Path -LiteralPath $tool)) { Exit-Quiet }
    $tool = (Get-Item -LiteralPath $tool).FullName

    $info = [System.Diagnostics.ProcessStartInfo]::new($godot)
    foreach ($arg in '--headless', '--path', $projectDir, '-s', $tool, '--', "res://$rel") { $info.ArgumentList.Add($arg) }
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.UseShellExecute = $false
    $process = [System.Diagnostics.Process]::Start($info)
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(20000)) {
        $process.Kill($true)
        Exit-Quiet
    }
    $process.WaitForExit()   # flush the output readers
    $lines = @(("$($stdout.Result)`n$($stderr.Result)") -split "`r?`n" | ForEach-Object { $_.TrimEnd() } | Where-Object { $_ })

    # The engine prints a missing reference or a broken script as an ERROR line, and a scene with a missing script still
    # exits 0, so the lines count as much as the exit code. Stack frames of the checking tool itself say nothing.
    $errors = @($lines | Where-Object { $_ -match '^(SCRIPT ERROR|SHADER ERROR|ERROR|@@editcheck)' -or $_ -match '^\s+at: ' })
    if ($errors.Count -eq 0) { Exit-Quiet }   # the engine failed without saying why (a crash on start-up): not a verdict on this file
    $shown = @($errors | Select-Object -First 8 | ForEach-Object { $_.Trim() -replace '^@@editcheck ', '' })
    Write-Note ("Hyperdot checked res://$rel after your edit and Godot reports a problem:`n" + ($shown -join "`n") +
        "`nFix it before building on it. (To turn this check off: HYPERDOT_EDIT_CHECK=off.)")
} catch {
    Exit-Quiet   # a hook that cannot check must not disturb the turn
}
