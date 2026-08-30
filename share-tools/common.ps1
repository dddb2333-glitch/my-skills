$ErrorActionPreference = 'Stop'

function Write-Utf8NoBomText {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [AllowEmptyString()][string]$Text = ''
    )
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $enc = New-Object System.Text.UTF8Encoding -ArgumentList $false
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

function Write-Utf8NoBomLines {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string[]]$Lines
    )
    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $enc = New-Object System.Text.UTF8Encoding -ArgumentList $false
    [System.IO.File]::WriteAllLines($Path, $Lines, $enc)
}

function Invoke-NativeCapture {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [string[]]$ArgumentList = @()
    )
    # Windows PowerShell 5.1 can promote native stderr to NativeCommandError when
    # $ErrorActionPreference='Stop'. Query/probe commands are expected to fail
    # sometimes, so run them under Continue and return an explicit exit code.
    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $FilePath @ArgumentList 2>$null)
        $exitCode = $LASTEXITCODE
    }
    catch {
        $output = @()
        $exitCode = 1
    }
    finally {
        $ErrorActionPreference = $oldPreference
    }
    return [pscustomobject]@{
        ExitCode = [int]$exitCode
        Output   = @($output)
    }
}

function Invoke-Git {
    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & git @args
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldPreference
    }
    if ($exitCode -ne 0) {
        throw "git failed (exit $exitCode): git $($args -join ' ')"
    }
}

function Assert-GitAvailable {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'Git is not available in PATH.'
    }
    $probe = Invoke-NativeCapture -FilePath 'git' -ArgumentList @('--version')
    if ($probe.ExitCode -ne 0) { throw 'Git is not usable.' }
}

function Get-GitConfigValue {
    param(
        [Parameter(Mandatory=$true)][ValidateSet('global','system')][string]$Scope,
        [Parameter(Mandatory=$true)][string]$Name
    )
    $r = Invoke-NativeCapture -FilePath 'git' -ArgumentList @('config',"--$Scope",'--get',$Name)
    if ($r.ExitCode -ne 0 -or $r.Output.Count -eq 0) { return $null }
    return (($r.Output -join "`n").Trim())
}

function Assert-GitIdentity {
    $name = Get-GitConfigValue -Scope global -Name 'user.name'
    $mail = Get-GitConfigValue -Scope global -Name 'user.email'
    if (-not $name) { $name = Get-GitConfigValue -Scope system -Name 'user.name' }
    if (-not $mail) { $mail = Get-GitConfigValue -Scope system -Name 'user.email' }
    if (-not $name) { throw 'Fresh-snapshot commits require Git user.name in global or system config.' }
    if (-not $mail) { throw 'Fresh-snapshot commits require Git user.email in global or system config.' }
}

function Normalize-RepoIdentity {
    param([Parameter(Mandatory=$true)][string]$RepoUrl)
    $v = $RepoUrl.Trim().TrimEnd('/')
    $v = $v -replace '(?i)\.git$',''
    return $v.ToLowerInvariant()
}

function Assert-Configuration {
    if (-not $PrivateRepoUrl -or -not $PublicRepoUrl) { throw 'Repository URLs must not be empty.' }
    if ((Normalize-RepoIdentity $PrivateRepoUrl) -eq (Normalize-RepoIdentity $PublicRepoUrl)) {
        throw 'PRIVATE and PUBLIC repository URLs resolve to the same repository. Publishing is blocked.'
    }
    if (-not $PrivateBranch -or -not $PublicBranch) { throw 'Branch names must not be empty.' }
    if (-not (Test-Path -LiteralPath $AllowListPath -PathType Leaf)) { throw "Missing allowlist: $AllowListPath" }
    if (-not (Test-Path -LiteralPath $DenyListPath -PathType Leaf)) { throw "Missing deny list: $DenyListPath" }
}

function Reset-Directory {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Test-GitWorkingTree {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    $r = Invoke-NativeCapture -FilePath 'git' -ArgumentList @('-C',$Path,'rev-parse','--is-inside-work-tree')
    if ($r.ExitCode -ne 0) { return $false }
    return (($r.Output -join "`n").Trim() -eq 'true')
}

function Get-GitStatusPorcelain {
    param([Parameter(Mandatory=$true)][string]$RepoRoot)
    $r = Invoke-NativeCapture -FilePath 'git' -ArgumentList @('-C',$RepoRoot,'status','--porcelain')
    if ($r.ExitCode -ne 0) { throw "Could not read Git status: $RepoRoot" }
    return @($r.Output)
}

function Normalize-RelativePath {
    param([Parameter(Mandatory=$true)][string]$Path)
    $p = $Path.Trim().Replace('/', '\')
    if (-not $p) { throw 'Empty relative path is not allowed.' }
    if ([System.IO.Path]::IsPathRooted($p)) { throw "Absolute path is not allowed in export rules: $Path" }
    $parts = @($p -split '\\' | Where-Object { $_ -ne '' -and $_ -ne '.' })
    if ($parts -contains '..') { throw "Path traversal is not allowed in export rules: $Path" }
    if ($parts.Count -eq 0) { throw "Invalid relative path: $Path" }
    foreach ($part in $parts) {
        if ($part -match '[<>:"|?*]') { throw "Invalid Windows path character in export rule: $Path" }
        if ($part.EndsWith('.') -or $part.EndsWith(' ')) { throw "Trailing dot/space is not allowed in export rule: $Path" }
        if ($part -match '(?i)^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?$') {
            throw "Reserved Windows path segment in export rule: $Path"
        }
    }
    return ($parts -join '\')
}

function Read-ExportRules {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing export allowlist: $Path" }
    $rules = @()
    $seen = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        $t = $line.Trim()
        if (-not $t -or $t.StartsWith('#')) { continue }
        if ($t -notmatch '^(required|optional)\s*:(.+)$') { throw "Invalid export rule: $t" }
        $kind = $Matches[1].ToLowerInvariant()
        $rel = Normalize-RelativePath -Path $Matches[2]
        $key = $rel.Replace('\','/').ToLowerInvariant()
        if ($seen.ContainsKey($key)) { throw "Duplicate export rule: $rel" }
        foreach ($existing in @($seen.Keys)) {
            if ($key.StartsWith($existing + '/') -or $existing.StartsWith($key + '/')) {
                throw "Overlapping export rules are not allowed: '$rel' overlaps '$($seen[$existing])'."
            }
        }
        $seen[$key] = $rel
        $rules += [pscustomobject]@{ Kind=$kind; Path=$rel }
    }
    if ($rules.Count -eq 0) { throw "Export allowlist has no active rules: $Path" }
    return $rules
}

function Read-DenyRules {
    param([Parameter(Mandatory=$true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing deny list: $Path" }
    $rules = @()
    $seen = @{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        $t = $line.Trim()
        if (-not $t -or $t.StartsWith('#')) { continue }
        $rel = (Normalize-RelativePath -Path $t).Replace('\','/').ToLowerInvariant()
        if (-not $seen.ContainsKey($rel)) {
            $seen[$rel] = $true
            $rules += $rel
        }
    }
    if ($rules.Count -eq 0) { throw "Deny list has no active rules: $Path" }
    return $rules
}

function Test-IsDeniedRelativePath {
    param(
        [Parameter(Mandatory=$true)][string]$RelativePath,
        [Parameter(Mandatory=$true)][string[]]$DenyRules
    )
    $p = (Normalize-RelativePath -Path $RelativePath).Replace('\','/').ToLowerInvariant()
    foreach ($d in $DenyRules) {
        if ($p -eq $d -or $p.StartsWith($d + '/')) { return $true }
    }
    return $false
}

function Assert-CanonicalLayout {
    param([Parameter(Mandatory=$true)][string]$CanonicalRoot)
    if (-not (Test-Path -LiteralPath $CanonicalRoot -PathType Container)) {
        throw "Canonical root does not exist: $CanonicalRoot"
    }

    $versionPath = Join-Path $CanonicalRoot '.supply-chain-version.json'
    if (Test-Path -LiteralPath $versionPath -PathType Leaf) {
        try { $meta = Get-Content -LiteralPath $versionPath -Raw | ConvertFrom-Json }
        catch { throw "Invalid .supply-chain-version.json: $($_.Exception.Message)" }

        $layout = [string]$meta.layout
        $role = [string]$meta.canonical_role
        if (-not $layout) { throw 'Canonical metadata is missing layout.' }
        if (-not ($meta.PSObject.Properties.Name -contains 'schema_version')) { throw 'Canonical metadata is missing schema_version.' }
        $schema = [int]$meta.schema_version
        if (-not $role) { throw 'Canonical metadata is missing canonical_role.' }
        if (-not $layout.StartsWith($ExpectedLayoutPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Canonical layout mismatch. Expected prefix '$ExpectedLayoutPrefix', got '$layout'."
        }
        if ($schema -ne $ExpectedSchemaVersion) { throw "Canonical schema mismatch. Expected $ExpectedSchemaVersion, got $schema." }
        if ($role -ne $ExpectedCanonicalRole) { throw "Canonical role mismatch. Expected '$ExpectedCanonicalRole', got '$role'." }
        if (-not ($meta.PSObject.Properties.Name -contains 'identity_source')) {
            $meta | Add-Member -NotePropertyName identity_source -NotePropertyValue 'metadata-file'
        }
        if (-not ($meta.PSObject.Properties.Name -contains 'identity_confidence')) {
            $meta | Add-Member -NotePropertyName identity_confidence -NotePropertyValue 'declared-and-validated'
        }
        return $meta
    }

    $missing = @()
    foreach ($rel in $StructuralCompatibilityAnchors) {
        if (-not (Test-Path -LiteralPath (Join-Path $CanonicalRoot $rel))) { $missing += $rel }
    }
    if ($missing.Count -gt 0) {
        $top = @(Get-ChildItem -LiteralPath $CanonicalRoot -Force -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
        $topText = if ($top.Count -gt 0) { $top -join ', ' } else { '<empty>' }
        throw ("PRIVATE source is not compatible with the v0.2.1 Framework profile. " +
               "The optional .supply-chain-version.json marker is absent and structural anchors are missing: " +
               ($missing -join ', ') + '. Top-level items found: ' + $topText +
               '. This usually means PRIVATE/main has not been populated from the local canonical tree yet.')
    }

    Write-Warning 'Canonical marker is absent. Structural anchors prove v0.2.1 Framework compatibility, but not the exact historical layout version.'
    return [pscustomobject]@{
        layout = '0.2.1-compatible-structural'
        schema_version = $ExpectedSchemaVersion
        canonical_role = $ExpectedCanonicalRole
        identity_source = 'structural-compatibility'
        identity_confidence = 'compatible-not-version-proven'
    }
}

function Test-IsReparsePoint {
    param([Parameter(Mandatory=$true)][System.IO.FileSystemInfo]$Item)
    return (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Copy-PathExactSafe {
    param(
        [Parameter(Mandatory=$true)][string]$Source,
        [Parameter(Mandatory=$true)][string]$Destination
    )
    $item = Get-Item -LiteralPath $Source -Force -ErrorAction Stop
    if (Test-IsReparsePoint -Item $item) { throw "Reparse point/symlink is not allowed in public export source: $Source" }

    if ($item.PSIsContainer) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        foreach ($child in Get-ChildItem -LiteralPath $Source -Force) {
            Copy-PathExactSafe -Source $child.FullName -Destination (Join-Path $Destination $child.Name)
        }
    }
    else {
        $parent = Split-Path -Parent $Destination
        if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
    }
}

function Copy-FrameworkAllowlist {
    param(
        [Parameter(Mandatory=$true)][string]$SourceRoot,
        [Parameter(Mandatory=$true)][string]$DestinationRoot,
        [Parameter(Mandatory=$true)][string]$AllowList,
        [Parameter(Mandatory=$true)][string]$DenyList
    )
    $rules = @(Read-ExportRules -Path $AllowList)
    $deny = @(Read-DenyRules -Path $DenyList)
    $copied = @()
    $requiredExpected = @($rules | Where-Object { $_.Kind -eq 'required' }).Count
    $requiredCopied = 0
    if ($requiredExpected -eq 0) { throw 'Allowlist must contain at least one required Framework path.' }

    foreach ($rule in $rules) {
        if (Test-IsDeniedRelativePath -RelativePath $rule.Path -DenyRules $deny) {
            throw "Allowlist conflicts with deny-list: $($rule.Path)"
        }
        $src = Join-Path $SourceRoot $rule.Path
        if (-not (Test-Path -LiteralPath $src)) {
            if ($rule.Kind -eq 'required') { throw "[BLOCK] Missing REQUIRED Framework export: $($rule.Path)" }
            Write-Warning "Optional Framework export missing: $($rule.Path)"
            continue
        }
        $dst = Join-Path $DestinationRoot $rule.Path
        Copy-PathExactSafe -Source $src -Destination $dst
        $copied += $rule.Path
        if ($rule.Kind -eq 'required') { $requiredCopied++ }
    }
    if ($requiredCopied -ne $requiredExpected) {
        throw "Required Framework copy count mismatch. Expected $requiredExpected, copied $requiredCopied."
    }
    return $copied
}

function Copy-PublicShareTools {
    param(
        [Parameter(Mandatory=$true)][string]$DestinationRoot,
        [Parameter(Mandatory=$true)][string[]]$FileList
    )
    $dst = Join-Path $DestinationRoot 'share-tools'
    New-Item -ItemType Directory -Path $dst -Force | Out-Null
    $seen = @{}
    foreach ($name in $FileList) {
        $rel = Normalize-RelativePath -Path $name
        $key = $rel.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { throw "Duplicate PublicToolFiles entry: $name" }
        $seen[$key] = $true
        $src = Join-Path $PSScriptRoot $rel
        if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { throw "Package is incomplete; missing share-tool file: $name" }
        $target = Join-Path $dst $rel
        $targetParent = Split-Path -Parent $target
        if ($targetParent) { New-Item -ItemType Directory -Path $targetParent -Force | Out-Null }
        Copy-Item -LiteralPath $src -Destination $target -Force
    }
}

function Write-PublicReadme {
    param(
        [Parameter(Mandatory=$true)][string]$DestinationRoot,
        [Parameter(Mandatory=$true)][AllowNull()][AllowEmptyString()][string]$SourceHead,
        [Parameter(Mandatory=$true)][string]$SourceLayout,
        [Parameter(Mandatory=$true)][string]$SourceMode,
        [Parameter(Mandatory=$true)][AllowNull()][Nullable[bool]]$SourceDirty
    )
    $template = @'
# my-skills — Public Skill Supply Chain Framework

This repository is a **public Framework subset** exported from the private canonical Skill repository.

Public by design:

- `Skill_Supply_Chain_v0.2.md`
- `control/policies/`
- `control/schemas/`
- `share-tools/`

Not public by default: actual Skill source trees, local/adapted authoring trees, records, evidence, decisions, registry/catalog, pack locks, deployment state, quarantine, archives, or private exports.

Source mode: `{{SOURCE_MODE}}`
Source canonical layout: `{{SOURCE_LAYOUT}}`
Source canonical commit: `{{SOURCE_HEAD}}`
Source working tree dirty at export time: `{{SOURCE_DIRTY}}`

Public export is separate from Runtime Deployment and does not imply Skill admission, validation, stability, or deployability.
'@
    $headText = if ($null -eq $SourceHead -or -not $SourceHead) { '(none; local source is not a Git working tree)' } else { $SourceHead }
    $dirtyText = if ($null -eq $SourceDirty) { 'unknown (non-git local preview)' } else { ([string]$SourceDirty).ToLowerInvariant() }
    $text = $template.Replace('{{SOURCE_MODE}}',$SourceMode).Replace('{{SOURCE_LAYOUT}}',$SourceLayout).Replace('{{SOURCE_HEAD}}',$headText).Replace('{{SOURCE_DIRTY}}',$dirtyText)
    Write-Utf8NoBomText -Path (Join-Path $DestinationRoot 'README.md') -Text $text
}

function Write-PublicGitAttributes {
    param([Parameter(Mandatory=$true)][string]$DestinationRoot)
    # Preserve exact export bytes so PUBLIC_EXPORT_SHA256.txt remains meaningful
    # regardless of the caller's global core.autocrlf setting.
    Write-Utf8NoBomText -Path (Join-Path $DestinationRoot '.gitattributes') -Text "* -text`n"
}

function Test-FinalDeniedPaths {
    param(
        [Parameter(Mandatory=$true)][string]$Root,
        [Parameter(Mandatory=$true)][string]$DenyList
    )
    $deny = @(Read-DenyRules -Path $DenyList)
    foreach ($item in Get-ChildItem -LiteralPath $Root -Recurse -Force) {
        $rel = $item.FullName.Substring($Root.Length).TrimStart([char[]]'\/').Replace('\','/')
        if (-not $rel) { continue }
        if ($rel -eq 'share-tools' -or $rel.StartsWith('share-tools/')) { continue }
        if (Test-IsDeniedRelativePath -RelativePath $rel -DenyRules $deny) { throw "Denied path reached final PUBLIC snapshot: $rel" }
    }
}

function Test-PublicSnapshotShape {
    param([Parameter(Mandatory=$true)][string]$Root)
    $files = @(Get-ChildItem -LiteralPath $Root -Recurse -Force -File)
    if ($files.Count -gt $MaxPublicFileCount) { throw "Public snapshot file-count limit exceeded: $($files.Count) > $MaxPublicFileCount" }
    [int64]$total = 0
    foreach ($file in $files) {
        if ($file.Length -gt $MaxPublicFileBytes) { throw "Public file exceeds size limit: $($file.FullName) ($($file.Length) bytes)" }
        $total += $file.Length
        $name = $file.Name.ToLowerInvariant()
        $ext = [System.IO.Path]::GetExtension($name).ToLowerInvariant()
        if ($AllowedPublicExtensionlessNames -contains $name) { continue }
        if (-not ($AllowedPublicExtensions -contains $ext)) { throw "Public snapshot contains unsupported file type: $($file.FullName)" }
    }
    if ($total -gt $MaxPublicTotalBytes) { throw "Public snapshot total-size limit exceeded: $total > $MaxPublicTotalBytes bytes" }
}

function Test-PublicSnapshotSecrets {
    param([Parameter(Mandatory=$true)][string]$Root)
    $badExact = @('.env','.env.local','.env.production','.env.development','.npmrc','.pypirc','id_rsa','id_ed25519','credentials','credentials.json')
    $badExt = @('.pem','.key','.pfx','.p12','.jks','.keystore')
    $patterns = @(
        '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
        '(?i)github_pat_[A-Za-z0-9_]{20,}',
        '(?i)gh[pousr]_[A-Za-z0-9_]{20,}',
        '(?i)AKIA[0-9A-Z]{16}',
        'AIza[0-9A-Za-z_-]{35}',
        '(?i)sk-[A-Za-z0-9_-]{24,}',
        '(?i)(?:OPENAI_API_KEY|OPENROUTER_API_KEY|DEEPSEEK_API_KEY|OPENCODE_API_KEY|GOOGLE_API_KEY|GEMINI_API_KEY|GITHUB_TOKEN|GH_TOKEN|PIXIV_REFRESH_TOKEN|PIXIV_PHPSESSID)\s*[:=]\s*["'']?[^"''\s]{16,}',
        '(?i)PHPSESSID=[A-Za-z0-9_%.-]{20,}',
        '(?i)Authorization\s*:\s*Bearer\s+[A-Za-z0-9._~+\-/=]{20,}'
    )

    foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -Force -File) {
        $name = $file.Name.ToLowerInvariant()
        if ($badExact -contains $name) { throw "Blocked sensitive filename: $($file.FullName)" }
        foreach ($ext in $badExt) { if ($name.EndsWith($ext)) { throw "Blocked sensitive file type: $($file.FullName)" } }
        try { $text = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop }
        catch { throw "Could not scan public file as text: $($file.FullName)" }
        foreach ($pattern in $patterns) {
            if ($text -match $pattern) { throw "Blocked high-confidence secret/token pattern in: $($file.FullName)" }
        }
    }
}

function Get-RemoteHead {
    param(
        [Parameter(Mandatory=$true)][string]$RepoUrl,
        [Parameter(Mandatory=$true)][string]$Branch
    )
    $r = Invoke-NativeCapture -FilePath 'git' -ArgumentList @('ls-remote',$RepoUrl,"refs/heads/$Branch")
    if ($r.ExitCode -ne 0) { throw "Could not query remote HEAD: $RepoUrl $Branch" }
    if ($r.Output.Count -eq 0) { return $null }
    $line = [string]$r.Output[0]
    return (($line -split '\s+')[0]).Trim()
}

function Get-GitHead {
    param([Parameter(Mandatory=$true)][string]$RepoRoot)
    $r = Invoke-NativeCapture -FilePath 'git' -ArgumentList @('-C',$RepoRoot,'rev-parse','HEAD')
    if ($r.ExitCode -ne 0 -or $r.Output.Count -eq 0) { throw "Could not resolve Git HEAD: $RepoRoot" }
    return (($r.Output -join "`n").Trim())
}

function Clone-PrivateCanonical {
    param([Parameter(Mandatory=$true)][string]$Destination)
    if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Recurse -Force }
    $parent = Split-Path -Parent $Destination
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Invoke-Git clone --depth 1 --branch $PrivateBranch $PrivateRepoUrl $Destination
}

function Test-PrivateRepoVisibilityIfGhAvailable {
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Warning 'GitHub CLI is unavailable; PRIVATE repository visibility could not be independently verified.'
        return
    }
    $r = Invoke-NativeCapture -FilePath 'gh' -ArgumentList @('repo','view',$PrivateRepoSlug,'--json','visibility','--jq','.visibility')
    if ($r.ExitCode -ne 0 -or $r.Output.Count -eq 0) {
        Write-Warning 'GitHub CLI is present but repository visibility could not be queried; continuing because clone/source checks remain authoritative for this export.'
        return
    }
    $visibility = (($r.Output -join "`n").Trim())
    if ($visibility -ne 'PRIVATE') { throw "[BLOCK] Canonical source repository visibility is '$visibility', expected PRIVATE." }
    Write-Host '  PRIVATE visibility: verified'
}

function Write-PublicExportManifest {
    param(
        [Parameter(Mandatory=$true)][string]$DestinationRoot,
        [Parameter(Mandatory=$true)][AllowNull()][AllowEmptyString()][string]$SourceHead,
        [Parameter(Mandatory=$true)][object]$CanonicalMeta,
        [Parameter(Mandatory=$true)][string[]]$CopiedRules,
        [Parameter(Mandatory=$true)][string]$SourceMode,
        [Parameter(Mandatory=$true)][AllowNull()][Nullable[bool]]$SourceDirty
    )
    $allowHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $AllowListPath).Hash.ToLowerInvariant()
    $denyHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $DenyListPath).Hash.ToLowerInvariant()
    $obj = [ordered]@{
        schema_version = 2
        exporter = 'share-tools-v0.2.1-framework-aware-v2.3'
        toolset_version = $ToolsetVersion
        generated_utc = [DateTime]::UtcNow.ToString('o')
        private_source = $PrivateRepoUrl
        private_branch = $PrivateBranch
        source_mode = $SourceMode
        source_commit = $SourceHead
        source_worktree_dirty = $SourceDirty
        canonical_layout = [string]$CanonicalMeta.layout
        canonical_schema_version = [int]$CanonicalMeta.schema_version
        canonical_role = [string]$CanonicalMeta.canonical_role
        identity_source = [string]$CanonicalMeta.identity_source
        identity_confidence = [string]$CanonicalMeta.identity_confidence
        allowlist_sha256 = $allowHash
        denylist_sha256 = $denyHash
        exported_framework_paths = @($CopiedRules)
        public_repository = $PublicRepoUrl
        public_branch = $PublicBranch
    }
    $json = $obj | ConvertTo-Json -Depth 6
    Write-Utf8NoBomText -Path (Join-Path $DestinationRoot '.public-export-manifest.json') -Text ($json + "`n")
}

function Write-Sha256Manifest {
    param([Parameter(Mandatory=$true)][string]$Root)
    $outPath = Join-Path $Root 'PUBLIC_EXPORT_SHA256.txt'
    if (Test-Path -LiteralPath $outPath) { Remove-Item -LiteralPath $outPath -Force }
    $lines = @()
    foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -Force -File | Sort-Object FullName) {
        if ($file.FullName -eq $outPath) { continue }
        $rel = $file.FullName.Substring($Root.Length).TrimStart([char[]]'\/').Replace('\','/')
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToLowerInvariant()
        $lines += "$hash  $rel"
    }
    Write-Utf8NoBomLines -Path $outPath -Lines $lines
}

function Get-TreeFileCount {
    param([Parameter(Mandatory=$true)][string]$Root)
    $gitRoot = Join-Path $Root '.git'
    return @((Get-ChildItem -LiteralPath $Root -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object {
        -not $_.FullName.StartsWith($gitRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
    })).Count
}

function Initialize-FreshGitSnapshot {
    param(
        [Parameter(Mandatory=$true)][string]$SnapshotRoot,
        [Parameter(Mandatory=$true)][string]$CommitMessage
    )
    if (Test-Path -LiteralPath (Join-Path $SnapshotRoot '.git')) { throw "Snapshot already contains .git: $SnapshotRoot" }
    if ((Get-TreeFileCount -Root $SnapshotRoot) -eq 0) { throw 'Cannot create an empty PUBLIC snapshot.' }
    Push-Location $SnapshotRoot
    try {
        Invoke-Git init
        Invoke-Git config core.autocrlf false
        Invoke-Git checkout -b $PublicBranch
        Invoke-Git remote add origin $PublicRepoUrl
        Invoke-Git add -A
        Invoke-Git commit -m $CommitMessage
        $statusProbe = Invoke-NativeCapture -FilePath 'git' -ArgumentList @('status','--porcelain')
        if ($statusProbe.ExitCode -ne 0) { throw 'Could not verify fresh snapshot status.' }
        $dirty = @($statusProbe.Output)
        if ($dirty.Count -gt 0) { throw 'Fresh snapshot is not clean after commit.' }
    }
    finally { Pop-Location }
}

function Confirm-ExplicitAction {
    param(
        [Parameter(Mandatory=$true)][string]$ActionText,
        [Parameter(Mandatory=$true)][string]$Token,
        [switch]$Yes
    )
    if ($Yes) { return }
    Write-Host ''
    Write-Host "ABOUT TO MUTATE: $ActionText" -ForegroundColor Yellow
    $answer = Read-Host "Type $Token to continue"
    if ($answer -cne $Token) { throw 'Action cancelled by user.' }
}

function Confirm-Publish {
    param(
        [Parameter(Mandatory=$true)][string]$ActionText,
        [switch]$Yes
    )
    Confirm-ExplicitAction -ActionText $ActionText -Token 'PUBLISH' -Yes:$Yes
}

function Push-FreshSnapshotWithLease {
    param(
        [Parameter(Mandatory=$true)][string]$SnapshotRoot,
        [AllowNull()][string]$ExpectedRemoteHead
    )
    Push-Location $SnapshotRoot
    try {
        $refspec = "HEAD:refs/heads/$PublicBranch"
        if ($ExpectedRemoteHead) { $lease = "--force-with-lease=refs/heads/${PublicBranch}:$ExpectedRemoteHead" }
        else { $lease = "--force-with-lease=refs/heads/${PublicBranch}:" }
        $oldPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            & git push origin $lease $refspec
            $pushExit = $LASTEXITCODE
        }
        finally { $ErrorActionPreference = $oldPreference }
        if ($pushExit -ne 0) { throw 'Public push rejected/failed. Remote may have changed since preflight; inspect before retrying.' }
    }
    finally { Pop-Location }
}

function Assert-RemoteHeadEquals {
    param(
        [Parameter(Mandatory=$true)][string]$RepoUrl,
        [Parameter(Mandatory=$true)][string]$Branch,
        [Parameter(Mandatory=$true)][string]$ExpectedHead
    )
    $actual = Get-RemoteHead -RepoUrl $RepoUrl -Branch $Branch
    if (-not $actual -or $actual -ne $ExpectedHead) { throw "Post-push verification failed. Expected $ExpectedHead, got $actual" }
}
