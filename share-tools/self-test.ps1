$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\config.ps1"
. "$PSScriptRoot\common.ps1"

Assert-GitAvailable
Assert-Configuration
$tempBase = if ($env:TEMP) { $env:TEMP } else { [System.IO.Path]::GetTempPath() }
$root = Join-Path $tempBase ('share-tools-selftest-' + [Guid]::NewGuid().ToString('N'))
$canonical = Join-Path $root 'canonical'
$out = Join-Path $root 'out'
New-Item -ItemType Directory -Path (Join-Path $canonical 'control\policies') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $canonical 'control\schemas') -Force | Out-Null
New-Item -ItemType Directory -Path $out -Force | Out-Null

$originalPublicRepoUrl = $PublicRepoUrl
$originalPublicBranch = $PublicBranch
$originalMaxFileBytes = $MaxPublicFileBytes

function Expect-Block {
    param([Parameter(Mandatory=$true)][scriptblock]$Action,[Parameter(Mandatory=$true)][string]$Name)
    $blocked = $false
    try { & $Action }
    catch { $blocked = $true }
    if (-not $blocked) { throw "Expected block did not occur: $Name" }
}

try {
    Write-Host '[TEST 0A] non-git probe must return false without throwing (WinPS 5.1 regression)'
    $nonGit = Join-Path $root 'plain-folder'
    New-Item -ItemType Directory -Path $nonGit -Force | Out-Null
    if (Test-GitWorkingTree -Path $nonGit) { throw 'non-git probe unexpectedly returned true' }

    Write-Host '[TEST 0B] nullable provenance for non-git local preview'
    $nullablePreview = Join-Path $root 'nullable-preview'
    New-Item -ItemType Directory -Path $nullablePreview -Force | Out-Null
    Write-PublicReadme -DestinationRoot $nullablePreview -SourceHead $null -SourceLayout '0.2.1-lite' -SourceMode 'local-non-git-preview' -SourceDirty $null
    $previewText = Get-Content -LiteralPath (Join-Path $nullablePreview 'README.md') -Raw
    if ($previewText -notmatch 'non-git local preview' -or $previewText -notmatch 'none; local source is not a Git working tree') { throw 'nullable preview provenance rendering failed' }

    # Build a complete synthetic canonical profile.
    $metaObj = @{ layout='0.2.1-lite'; schema_version=2; tooling_closure='0.2.1'; canonical_role='private-skill-library' }
    Write-Utf8NoBomText -Path (Join-Path $canonical '.supply-chain-version.json') -Text (($metaObj | ConvertTo-Json) + "`n")
    Write-Utf8NoBomText -Path (Join-Path $canonical 'Skill_Supply_Chain_v0.2.md') -Text "# test`n"
    foreach ($name in @('admission-policy.md','deployment-policy.md','eval-policy.md','rights-policy.md','risk-policy.md','routing-policy.md','source-isolation-policy.md')) {
        Write-Utf8NoBomText -Path (Join-Path $canonical "control\policies\$name") -Text "policy`n"
    }
    foreach ($name in @('decision-record.example.json','evidence-record.example.json','revision-record.example.json')) {
        Write-Utf8NoBomText -Path (Join-Path $canonical "control\schemas\$name") -Text "{}`n"
    }

    Write-Host '[TEST 1] metadata canonical gate'
    $meta = Assert-CanonicalLayout -CanonicalRoot $canonical
    if ($meta.layout -ne '0.2.1-lite' -or $meta.identity_source -ne 'metadata-file') { throw 'metadata canonical test failed' }

    Write-Host '[TEST 2] structural fallback gate'
    Remove-Item -LiteralPath (Join-Path $canonical '.supply-chain-version.json') -Force
    $fallback = Assert-CanonicalLayout -CanonicalRoot $canonical
    if ($fallback.identity_source -ne 'structural-compatibility') { throw 'structural fallback test failed' }

    Write-Host '[TEST 3] invalid explicit metadata blocks'
    Write-Utf8NoBomText -Path (Join-Path $canonical '.supply-chain-version.json') -Text '{"layout":"0.1","schema_version":1,"canonical_role":"wrong"}'
    Expect-Block -Name 'invalid explicit metadata' -Action { Assert-CanonicalLayout -CanonicalRoot $canonical | Out-Null }
    Remove-Item -LiteralPath (Join-Path $canonical '.supply-chain-version.json') -Force

    Write-Host '[TEST 4] allowlist safe copy + required count'
    $copied = @(Copy-FrameworkAllowlist -SourceRoot $canonical -DestinationRoot $out -AllowList $AllowListPath -DenyList $DenyListPath)
    if ($copied.Count -ne 3) { throw "allowlist copy test failed: $($copied.Count)" }

    Write-Host '[TEST 5] required-missing blocks'
    $schemas = Join-Path $canonical 'control\schemas'
    Rename-Item -LiteralPath $schemas -NewName 'schemas.off'
    Expect-Block -Name 'required missing' -Action {
        $tmp = Join-Path $root 'missing-test'; New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        Copy-FrameworkAllowlist -SourceRoot $canonical -DestinationRoot $tmp -AllowList $AllowListPath -DenyList $DenyListPath | Out-Null
    }
    Rename-Item -LiteralPath (Join-Path $canonical 'control\schemas.off') -NewName 'schemas'

    Write-Host '[TEST 6] traversal/overlap allowlist blocks'
    $badAllow = Join-Path $root 'bad-allow.txt'
    Write-Utf8NoBomText -Path $badAllow -Text "required:../records`n"
    Expect-Block -Name 'path traversal' -Action { Read-ExportRules -Path $badAllow | Out-Null }
    Write-Utf8NoBomText -Path $badAllow -Text "required:control`noptional:control/policies`n"
    Expect-Block -Name 'overlap' -Action { Read-ExportRules -Path $badAllow | Out-Null }

    Write-Host '[TEST 7] deny-list blocks forbidden final path'
    $denyRoot = Join-Path $root 'deny-test'
    New-Item -ItemType Directory -Path (Join-Path $denyRoot 'records') -Force | Out-Null
    Write-Utf8NoBomText -Path (Join-Path $denyRoot 'records\x.json') -Text "{}`n"
    Expect-Block -Name 'deny records' -Action { Test-FinalDeniedPaths -Root $denyRoot -DenyList $DenyListPath }

    Write-Host '[TEST 8] secret scanner blocks synthetic token'
    $secretRoot = Join-Path $root 'secret-test'; New-Item -ItemType Directory -Path $secretRoot -Force | Out-Null
    $syntheticSecret = 'PIXIV_REFRESH_TOKEN=' + ('A' * 32)
    Write-Utf8NoBomText -Path (Join-Path $secretRoot 'x.txt') -Text $syntheticSecret
    Expect-Block -Name 'secret token' -Action { Test-PublicSnapshotSecrets -Root $secretRoot }

    Write-Host '[TEST 9] extension and size gates'
    $shapeRoot = Join-Path $root 'shape-test'; New-Item -ItemType Directory -Path $shapeRoot -Force | Out-Null
    Write-Utf8NoBomText -Path (Join-Path $shapeRoot 'x.exe') -Text 'x'
    Expect-Block -Name 'unsupported extension' -Action { Test-PublicSnapshotShape -Root $shapeRoot }
    Remove-Item -LiteralPath (Join-Path $shapeRoot 'x.exe') -Force
    $MaxPublicFileBytes = 64
    Write-Utf8NoBomText -Path (Join-Path $shapeRoot 'x.txt') -Text ('x' * 65)
    Expect-Block -Name 'file size' -Action { Test-PublicSnapshotShape -Root $shapeRoot }
    $MaxPublicFileBytes = $originalMaxFileBytes

    Write-Host '[TEST 10] UTF-8 no-BOM writer'
    $utf = Join-Path $root 'utf8.txt'; Write-Utf8NoBomText -Path $utf -Text 'abc'
    $bytes = [System.IO.File]::ReadAllBytes($utf)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw 'UTF-8 writer emitted BOM' }

    Write-Host '[TEST 11] package completeness'
    foreach ($f in $PublicToolFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $f) -PathType Leaf)) { throw "PublicToolFiles missing package file: $f" }
    }

    Write-Host '[TEST 12] local Git force-with-lease and post-push verification'
    Assert-GitIdentity
    $bare = Join-Path $root 'public.git'
    Invoke-Git init --bare $bare
    $PublicRepoUrl = $bare
    $PublicBranch = 'main'

    $snap1 = Join-Path $root 'snap1'; New-Item -ItemType Directory -Path $snap1 -Force | Out-Null
    Write-Utf8NoBomText -Path (Join-Path $snap1 'README.md') -Text "one`n"
    Write-PublicGitAttributes -DestinationRoot $snap1
    Write-Sha256Manifest -Root $snap1
    $none = Get-RemoteHead -RepoUrl $PublicRepoUrl -Branch $PublicBranch
    if ($none) { throw 'bare remote unexpectedly had main' }
    Initialize-FreshGitSnapshot -SnapshotRoot $snap1 -CommitMessage 'one'
    $c1 = Get-GitHead -RepoRoot $snap1
    Push-FreshSnapshotWithLease -SnapshotRoot $snap1 -ExpectedRemoteHead $null
    Assert-RemoteHeadEquals -RepoUrl $PublicRepoUrl -Branch $PublicBranch -ExpectedHead $c1

    $other = Join-Path $root 'other'
    Invoke-Git clone --branch main $bare $other
    Write-Utf8NoBomText -Path (Join-Path $other 'README.md') -Text "other`n"
    Invoke-Git -C $other add -A
    Invoke-Git -C $other commit -m 'other'
    Invoke-Git -C $other push origin "HEAD:refs/heads/main"
    $cOther = Get-GitHead -RepoRoot $other
    if ($cOther -eq $c1) { throw 'competing commit was not created' }

    $snap2 = Join-Path $root 'snap2'; New-Item -ItemType Directory -Path $snap2 -Force | Out-Null
    Write-Utf8NoBomText -Path (Join-Path $snap2 'README.md') -Text "two`n"
    Write-PublicGitAttributes -DestinationRoot $snap2
    Write-Sha256Manifest -Root $snap2
    Initialize-FreshGitSnapshot -SnapshotRoot $snap2 -CommitMessage 'two'
    Expect-Block -Name 'stale force-with-lease' -Action { Push-FreshSnapshotWithLease -SnapshotRoot $snap2 -ExpectedRemoteHead $c1 }
    Assert-RemoteHeadEquals -RepoUrl $PublicRepoUrl -Branch $PublicBranch -ExpectedHead $cOther

    Write-Host '[PASS] 14 share-tools self-test cases passed (2 WinPS regressions + 12 numbered groups). No network was used.'
}
finally {
    $PublicRepoUrl = $originalPublicRepoUrl
    $PublicBranch = $originalPublicBranch
    $MaxPublicFileBytes = $originalMaxFileBytes
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
