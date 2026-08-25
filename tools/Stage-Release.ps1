param(
    [Parameter(Mandatory = $true)]
    [string]$Destination,

    [string]$Executable
)

$ErrorActionPreference = 'Stop'

# This script is the single definition of a playable public release.  Both a
# freshly downloaded archive and the developer's installed copy are assembled
# from this same list, which prevents the importer in one from quietly drifting
# away from the other.
$repository = Split-Path -Parent $PSScriptRoot
$destinationPath = [System.IO.Path]::GetFullPath($Destination)
if (-not $Executable) {
    $Executable = Join-Path $repository 'build\x64\Release\ThemePark2Native.exe'
}
if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
    throw "The release executable does not exist: $Executable"
}

New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null

function Copy-VerifiedFile {
    param([string]$Source, [string]$Destination)
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "A required release file is missing: $Source"
    }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    $sourceHash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
    $destinationHash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
    if ($sourceHash -ne $destinationHash) {
        throw "Release staging changed or omitted a file: $Destination"
    }
}

function Assert-DirectoryParity {
    param([string]$Source, [string]$Destination)
    foreach ($sourceFile in Get-ChildItem -LiteralPath $Source -Recurse -File) {
        $relative = $sourceFile.FullName.Substring($Source.Length).TrimStart('\')
        $copy = Join-Path $Destination $relative
        if (-not (Test-Path -LiteralPath $copy -PathType Leaf)) {
            throw "Release staging omitted a file: $relative"
        }
        $sourceHash = (Get-FileHash -LiteralPath $sourceFile.FullName -Algorithm SHA256).Hash
        $copyHash = (Get-FileHash -LiteralPath $copy -Algorithm SHA256).Hash
        if ($sourceHash -ne $copyHash) {
            throw "Release staging produced a mismatched file: $relative"
        }
    }
}

# Files imported by the owner (data, music, saves, and generated manifests) are
# intentionally absent.  Copying into an existing installation never removes
# or rewrites them.
$rootFiles = @(
    @{ Source = $Executable; Name = 'ThemePark2Native.exe' },
    @{ Source = (Join-Path $repository 'dxgi.dll'); Name = 'dxgi.dll' },
    @{ Source = (Join-Path $repository 'ReShade.ini'); Name = 'ReShade.ini' },
    @{ Source = (Join-Path $repository 'ThemePark-CRT.ini'); Name = 'ThemePark-CRT.ini' },
    @{ Source = (Join-Path $repository 'ThemePark-Widescreen.ini'); Name = 'ThemePark-Widescreen.ini' },
    @{ Source = (Join-Path $repository 'README.md'); Name = 'README.md' },
    @{ Source = (Join-Path $repository 'LICENSE'); Name = 'LICENSE' }
)
foreach ($file in $rootFiles) {
    Copy-VerifiedFile $file.Source (Join-Path $destinationPath $file.Name)
}

# ReShade loads these files by relative path beside the executable.
$shaderSource = Join-Path $repository 'reshade-shaders'
$shaderDestination = Join-Path $destinationPath 'reshade-shaders'
New-Item -ItemType Directory -Path $shaderDestination -Force | Out-Null
Copy-Item -Path (Join-Path $shaderSource '*') -Destination $shaderDestination -Recurse -Force
Assert-DirectoryParity $shaderSource $shaderDestination

# The installed README links to the controls guide and the same two gameplay
# screenshots shown on the repository front page.  Stage only those user-facing
# documents; contributor and reverse-engineering notes remain in the source
# repository.
$docsDestination = Join-Path $destinationPath 'docs'
$imageDestination = Join-Path $docsDestination 'images'
New-Item -ItemType Directory -Path $imageDestination -Force | Out-Null
Copy-VerifiedFile (Join-Path $repository 'docs\CONTROLS.md') (Join-Path $docsDestination 'CONTROLS.md')
$releaseImages = @('gameplay.jpg', 'high-resolution.jpg')
foreach ($name in $releaseImages) {
    Copy-VerifiedFile (Join-Path $repository "docs\images\$name") (Join-Path $imageDestination $name)
}

# Only end-user importer tools belong in the release.  Contributor checks and
# symbol-inspection utilities remain in the source repository.
$toolFiles = @('7z.exe', '7z.dll', 'Import-ThemePark.ps1')
$toolDestination = Join-Path $destinationPath 'tools'
New-Item -ItemType Directory -Path $toolDestination -Force | Out-Null
foreach ($name in $toolFiles) {
    Copy-VerifiedFile (Join-Path $PSScriptRoot $name) (Join-Path $toolDestination $name)
}

# Existing developer/test installations may still contain the experimental
# executable patcher from the widescreen branch.  It is not part of the stable
# release and could otherwise mislead a user into modifying freshly imported
# game data.  Remove only this explicitly named obsolete helper; imported game
# files and every other user-owned file remain untouched.
$obsoletePatcher = Join-Path $toolDestination 'Patch-ThemePark.ps1'
if (Test-Path -LiteralPath $obsoletePatcher -PathType Leaf) {
    Remove-Item -LiteralPath $obsoletePatcher -Force
}

Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'licenses') -Destination $toolDestination -Recurse -Force
Assert-DirectoryParity (Join-Path $PSScriptRoot 'licenses') (Join-Path $toolDestination 'licenses')

# GPLv2 requires the exact corresponding DOSBox Pure source to accompany the
# binary.  The archive includes this project's MSVC/FLAC integration changes.
$sourceDestination = Join-Path $toolDestination 'source'
New-Item -ItemType Directory -Path $sourceDestination -Force | Out-Null
$sourceArchive = Join-Path $repository 'third_party\dosbox-pure\dosbox-pure-msvc-source.tar.gz'
Copy-VerifiedFile $sourceArchive (Join-Path $sourceDestination 'dosbox-pure-msvc-source.tar.gz')

# This filename came from an earlier, incomplete runtime assembly.  Remove only
# this known obsolete archive after its corresponding replacement is present.
$obsoleteArchives = @(
    'dosbox-pure-1.0-preview6-source.tar.gz',
    'dosbox-pure-msvc-flac-source.tar.gz'
)
foreach ($name in $obsoleteArchives) {
    $obsoleteArchive = Join-Path $sourceDestination $name
    if (Test-Path -LiteralPath $obsoleteArchive -PathType Leaf) {
        Remove-Item -LiteralPath $obsoleteArchive -Force
    }
}

Write-Host "Complete release staged at $destinationPath" -ForegroundColor Green
