param([string]$RuntimeDirectory)

$ErrorActionPreference = 'Stop'

# The third-party source is stored compressed so the public repository remains
# navigable and our authored files retain the 300-line ceiling.  It is expanded
# into the ignored build tree and compiled by the *same* MSVC project as the
# native host.  This creates one EXE; it does not build or ship a second module.
$sourceArchive = Join-Path $PSScriptRoot 'third_party\dosbox-pure\dosbox-pure-msvc-source.tar.gz'
$generatedRoot = Join-Path $PSScriptRoot 'build\generated\dosbox-pure'
$sourceMarker = Join-Path $generatedRoot 'dosbox_pure_libretro.cpp'
if (-not (Test-Path -LiteralPath $sourceMarker -PathType Leaf)) {
    if (-not (Test-Path -LiteralPath $sourceArchive -PathType Leaf)) {
        throw "Embedded DOS engine source archive is missing: $sourceArchive"
    }
    New-Item -ItemType Directory -Path $generatedRoot -Force | Out-Null
    & tar.exe -xzf $sourceArchive -C $generatedRoot
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $sourceMarker)) {
        throw 'Windows could not expand the embedded DOS engine source.'
    }
}

# Visual Studio owns compilation. This wrapper supplies the one supported
# public configuration. Passing -RuntimeDirectory assembles the *complete*
# playable distribution there, rather than copying an executable that lacks
# the first-run importer or its redistributable tools.
$vsRoot = 'C:\Program Files\Microsoft Visual Studio\2022\Community'
$msbuild = Join-Path $vsRoot 'MSBuild\Current\Bin\MSBuild.exe'
if (-not (Test-Path -LiteralPath $msbuild)) {
    throw "Visual Studio 2022 Community MSBuild was not found at $msbuild"
}
& $msbuild (Join-Path $PSScriptRoot 'ThemePark2Native.sln') /m /p:Configuration=Release /p:Platform=x64
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
if ($RuntimeDirectory) {
    & (Join-Path $PSScriptRoot 'tools\Stage-Release.ps1') `
        -Destination $RuntimeDirectory `
        -Executable (Join-Path $PSScriptRoot 'build\x64\Release\ThemePark2Native.exe')
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}
