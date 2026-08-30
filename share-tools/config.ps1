# share-tools v0.2.1 Framework-Aware v2.3 configuration
$ToolsetVersion = "2.3.1-workspace-layout"

$PrivateRepoUrl  = "https://github.com/dddb2333-glitch/myskills_private.git"
$PublicRepoUrl   = "https://github.com/dddb2333-glitch/my-skills.git"
$PrivateRepoSlug = "dddb2333-glitch/myskills_private"
$PublicRepoSlug  = "dddb2333-glitch/my-skills"
$PrivateBranch   = "main"
$PublicBranch    = "main"

function Find-SkillTempWorkspaceRoot {
    $cursor = Get-Item -LiteralPath $PSScriptRoot
    while ($null -ne $cursor) {
        $hasCanonical = Test-Path -LiteralPath (Join-Path $cursor.FullName 'myskills-private') -PathType Container
        $hasWorking = Test-Path -LiteralPath (Join-Path $cursor.FullName 'skill-packs') -PathType Container
        if ($hasCanonical -and $hasWorking) { return $cursor.FullName }
        $cursor = $cursor.Parent
    }

    $legacyRoot = 'F:\SkillTemp'
    if (Test-Path -LiteralPath (Join-Path $legacyRoot 'myskills-private') -PathType Container) {
        return $legacyRoot
    }

    throw "Unable to discover SkillTemp workspace root from: $PSScriptRoot"
}

$WorkspaceRoot      = Find-SkillTempWorkspaceRoot
$WorkRoot           = Join-Path $WorkspaceRoot 'work\share-tools\remote'
$PreviewRoot        = Join-Path $WorkspaceRoot 'work\share-tools\preview'
$LocalCanonicalRoot = Join-Path $WorkspaceRoot 'myskills-private'

$AllowListPath   = Join-Path $PSScriptRoot "public-framework-allowlist.txt"
$DenyListPath    = Join-Path $PSScriptRoot "public-deny.txt"

$ExpectedLayoutPrefix = "0.2.1"
$ExpectedSchemaVersion = 2
$ExpectedCanonicalRole = "private-skill-library"

# Structural fallback proves compatibility with the current public Framework shape,
# not the exact historical version. Explicit metadata, when present, is authoritative.
$StructuralCompatibilityAnchors = @(
    "Skill_Supply_Chain_v0.2.md",
    "control\policies\admission-policy.md",
    "control\policies\deployment-policy.md",
    "control\policies\eval-policy.md",
    "control\policies\rights-policy.md",
    "control\policies\risk-policy.md",
    "control\policies\routing-policy.md",
    "control\policies\source-isolation-policy.md",
    "control\schemas\decision-record.example.json",
    "control\schemas\evidence-record.example.json",
    "control\schemas\revision-record.example.json"
)

$MaxPublicFileBytes = 5MB
$MaxPublicTotalBytes = 20MB
$MaxPublicFileCount = 1000
$AllowedPublicExtensions = @('.md','.json','.ps1','.cmd','.bat','.txt','.yml','.yaml')
$AllowedPublicExtensionlessNames = @('.gitattributes')

# Complete distributable toolset copied into PUBLIC/share-tools.
$PublicToolFiles = @(
    "README.md",
    "AUDIT_REPORT.md",
    "TROUBLESHOOT_PRIVATE_REMOTE.md",
    "PACKAGE_VALIDATION.json",
    "SHA256SUMS.txt",
    "config.ps1",
    "common.ps1",
    "public-framework-allowlist.txt",
    "public-deny.txt",
    "check-private-canonical.ps1",
    "preview-public-framework.ps1",
    "publish-private-to-public.ps1",
    "publish-framework.ps1",
    "clear-public-keep-tools.ps1",
    "ensure-private-source.ps1",
    "self-test.ps1",
    "00_CHECK_PRIVATE_CANONICAL.cmd",
    "00A_CHECK_LOCAL_CANONICAL.cmd",
    "01_PREVIEW_PUBLIC_FRAMEWORK.cmd",
    "01A_PREVIEW_LOCAL_FRAMEWORK.cmd",
    "02_PUBLISH_PRIVATE_TO_PUBLIC.cmd",
    "03_CLEAR_PUBLIC_KEEP_TOOLS.cmd",
    "04_ENSURE_PRIVATE_REPO.cmd",
    "05_SELF_TEST.cmd",
    "Install-ShareTools.ps1",
    "INSTALL_SHARE_TOOLS.cmd",
    "PUBLISH_FRAMEWORK.bat"
)
