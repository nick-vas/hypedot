# The git tree of the working folder as it is now, tracked and untracked files alike (what .gitignore leaves in), without
# touching the repository's own index: the run history stamps each test run with it, and the Stop hook (hooks/stop-gate.ps1)
# lets a session finish when the tree in front of it is one that passed a full test run, whatever the file times say (a
# checkout, a pull or a merge change times, not the code). Needs only git; $null outside a repository or when git fails.
# The index is copied first so git's stat cache makes `add -A` quick; the copy is the only thing written to.
function Get-WorkingTreeId([string]$Dir) {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
    $top = @(& git -C $Dir rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or $top.Count -eq 0) { return $null }
    $topDir = "$($top[0])".Trim()
    $index = @(& git -C $topDir rev-parse --path-format=absolute --git-path index 2>$null)
    $copy = Join-Path ([System.IO.Path]::GetTempPath()) "hyperdot-index-$([guid]::NewGuid().ToString('N'))"
    $before = $env:GIT_INDEX_FILE
    try {
        if ($LASTEXITCODE -eq 0 -and $index.Count -gt 0 -and (Test-Path -LiteralPath "$($index[0])")) { Copy-Item -LiteralPath "$($index[0])" -Destination $copy }
        $env:GIT_INDEX_FILE = $copy
        & git -C $topDir add -A 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { return $null }
        $tree = @(& git -C $topDir write-tree 2>$null)
        if ($LASTEXITCODE -ne 0 -or $tree.Count -eq 0) { return $null }
        return "$($tree[0])".Trim()
    } catch {
        return $null
    } finally {
        if ($null -eq $before) { Remove-Item Env:GIT_INDEX_FILE -ErrorAction SilentlyContinue } else { $env:GIT_INDEX_FILE = $before }
        Remove-Item -LiteralPath $copy -Force -ErrorAction SilentlyContinue
    }
}
