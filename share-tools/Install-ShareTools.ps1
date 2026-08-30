param(
    [string]$Target = 'F:\SkillTemp\tools\share-tools',
    [switch]$NoBackup
)
$ErrorActionPreference = 'Stop'

function Get-Full([string]$Path) { return [System.IO.Path]::GetFullPath($Path).TrimEnd('\') }
function Is-Within([string]$Child,[string]$Parent) {
    $c = Get-Full $Child
    $p = Get-Full $Parent
    return $c.StartsWith($p + '\', [System.StringComparison]::OrdinalIgnoreCase)
}
function Assert-PackageIntegrity([string]$PackageRoot) {
    $sumPath = Join-Path $PackageRoot 'SHA256SUMS.txt'
    if (-not (Test-Path -LiteralPath $sumPath -PathType Leaf)) { throw "Missing package checksum manifest: $sumPath" }
    $expected = @{}
    foreach ($line in Get-Content -LiteralPath $sumPath) {
        $t = $line.TrimEnd()
        if (-not $t) { continue }
        if ($t -notmatch '^([0-9a-fA-F]{64})  (.+)$') { throw "Invalid checksum line: $t" }
        $hash = $Matches[1].ToLowerInvariant()
        $rel = $Matches[2].Replace('/','\')
        if ([System.IO.Path]::IsPathRooted($rel) -or $rel -match '(^|\\)\.\.(\\|$)') { throw "Unsafe checksum path: $rel" }
        $key = $rel.ToLowerInvariant()
        if ($expected.ContainsKey($key)) { throw "Duplicate checksum entry: $rel" }
        $expected[$key] = [pscustomobject]@{ Rel=$rel; Hash=$hash }
    }
    if ($expected.Count -eq 0) { throw 'Checksum manifest is empty.' }
    foreach ($entry in $expected.Values) {
        $p = Join-Path $PackageRoot $entry.Rel
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "Package file missing: $($entry.Rel)" }
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLowerInvariant()
        if ($actual -ne $entry.Hash) { throw "Package checksum mismatch: $($entry.Rel)" }
    }
    $actualFiles = @(Get-ChildItem -LiteralPath $PackageRoot -Recurse -Force -File | ForEach-Object {
        $_.FullName.Substring($PackageRoot.Length).TrimStart([char[]]'\/').Replace('/','\')
    })
    foreach ($rel in $actualFiles) {
        if ($rel -ieq 'SHA256SUMS.txt') { continue }
        if (-not $expected.ContainsKey($rel.ToLowerInvariant())) { throw "Unexpected/unhashed package file: $rel" }
    }
}

$sourceOriginal = (Resolve-Path $PSScriptRoot).Path
Assert-PackageIntegrity -PackageRoot $sourceOriginal
$targetFull = Get-Full $Target
$source = Get-Full $sourceOriginal

if ($source -ieq $targetFull) {
    Write-Host '[PASS] Package is already located at the target path and passed checksum verification.'
    exit 0
}
if (Is-Within -Child $targetFull -Parent $source) { throw 'Target cannot be inside the package source directory.' }

$stage = $null
$incoming = $null
$backup = $null
$installSucceeded = $false
try {
    # If the installer itself is inside the target tree, stage first so moving the old target
    # does not invalidate the source path mid-install.
    if (Is-Within -Child $source -Parent $targetFull) {
        $stage = Join-Path ([System.IO.Path]::GetTempPath()) ('share-tools-install-stage-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $stage -Force | Out-Null
        foreach ($item in Get-ChildItem -LiteralPath $source -Force) {
            Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $stage $item.Name) -Recurse -Force
        }
        Assert-PackageIntegrity -PackageRoot $stage
        $source = $stage
    }

    $parent = Split-Path -Parent $targetFull
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

    # Build and verify the incoming tree before touching the existing installation.
    $incoming = Join-Path $parent ('.share-tools-incoming-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $incoming -Force | Out-Null
    foreach ($item in Get-ChildItem -LiteralPath $source -Force) {
        Copy-Item -LiteralPath $item.FullName -Destination (Join-Path $incoming $item.Name) -Recurse -Force
    }
    Assert-PackageIntegrity -PackageRoot $incoming

    if (Test-Path -LiteralPath $targetFull) {
        if (-not $NoBackup) {
            $backupRoot = Join-Path $parent 'archive'
            New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
            $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            $backup = Join-Path $backupRoot ("share-tools-backup-$stamp-" + [Guid]::NewGuid().ToString('N').Substring(0,8))
            Move-Item -LiteralPath $targetFull -Destination $backup
            Write-Host "Backup: $backup"
        }
        else {
            Remove-Item -LiteralPath $targetFull -Recurse -Force
        }
    }

    try {
        Move-Item -LiteralPath $incoming -Destination $targetFull
        $incoming = $null
        Assert-PackageIntegrity -PackageRoot $targetFull
        $installSucceeded = $true
    }
    catch {
        if (Test-Path -LiteralPath $targetFull) { Remove-Item -LiteralPath $targetFull -Recurse -Force -ErrorAction SilentlyContinue }
        if ($backup -and (Test-Path -LiteralPath $backup)) {
            Move-Item -LiteralPath $backup -Destination $targetFull
            Write-Warning 'Install failed; previous share-tools installation was restored from backup.'
            $backup = $null
        }
        throw
    }

    Write-Host "[DONE] Installed and checksum-verified share-tools to: $targetFull"
    Write-Host 'Recommended next step: run 05_SELF_TEST.cmd, then 00_CHECK_PRIVATE_CANONICAL.cmd.'
}
finally {
    if ($incoming -and (Test-Path -LiteralPath $incoming)) { Remove-Item -LiteralPath $incoming -Recurse -Force -ErrorAction SilentlyContinue }
    if ($stage -and (Test-Path -LiteralPath $stage)) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
}
