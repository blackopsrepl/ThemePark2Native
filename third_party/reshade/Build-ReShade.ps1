$ErrorActionPreference = 'Stop'

# This is a maintainer recipe, not an end-user installer dependency. It keeps
# the binary in the release reproducible using the project's Windows toolchain.
$commit = '4a50d1eddace85734871d91792ff214f13f66c01'
$expectedHash = '76A4D595D450E0BEB46C2A3B53C4A95D7AB1812172FE17A37373F535E27A3165'
$repository = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$source = Join-Path $repository 'build\references\reshade-6.7.3'
$patch = Join-Path $PSScriptRoot 'themepark-invisible-overlay.patch'

if (-not (Test-Path -LiteralPath (Join-Path $source '.git'))) {
    New-Item -ItemType Directory -Path (Split-Path $source) -Force | Out-Null
    & git clone --recurse-submodules https://github.com/crosire/reshade.git $source
    if ($LASTEXITCODE -ne 0) { throw 'Could not clone the official ReShade source.' }
}

& git -C $source fetch origin $commit
if ($LASTEXITCODE -ne 0) { throw 'Could not fetch the pinned ReShade commit.' }
& git -C $source diff --quiet
if ($LASTEXITCODE -ne 0) {
    throw 'The ReShade worktree has local edits; preserve or revert them first.'
}
& git -C $source checkout --detach $commit
if ($LASTEXITCODE -ne 0) { throw 'Could not select the pinned ReShade commit.' }
& git -C $source submodule update --init --recursive
if ($LASTEXITCODE -ne 0) { throw 'Could not initialize ReShade submodules.' }
& git -C $source apply $patch
if ($LASTEXITCODE -ne 0) { throw 'Could not apply the Theme Park patch.' }

$msbuild = 'C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe'
if (-not (Test-Path -LiteralPath $msbuild)) { throw 'Visual Studio 2022 Community is required.' }
& $msbuild (Join-Path $source 'ReShade.sln') /m /p:Configuration=Release /p:Platform=64-bit
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$built = Join-Path $source 'bin\x64\Release\ReShade64.dll'
$actualHash = (Get-FileHash -LiteralPath $built -Algorithm SHA256).Hash
if ($actualHash -ne $expectedHash) {
    throw "ReShade built successfully but hash differs: $actualHash"
}
Copy-Item -LiteralPath $built -Destination (Join-Path $repository 'dxgi.dll') -Force
Write-Host 'Reproducible ReShade artifact updated.' -ForegroundColor Green
