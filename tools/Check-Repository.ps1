$ErrorActionPreference = 'Stop'

# Validate the files that would actually enter a commit.  Developers are
# expected to have ignored build output and an imported game beside the source,
# so rejecting every physical file under the folder would make the check fail
# precisely on a normal development machine.
$repository = Split-Path -Parent $PSScriptRoot
$forbiddenTestInstall = 'D:\Games\Theme Park'
$gitDirectory = Join-Path $repository '.git'
if (Test-Path -LiteralPath $gitDirectory) {
    $relativeFiles = @(& git -C $repository ls-files --cached --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) {
        throw 'Git could not enumerate the public repository surface.'
    }
} else {
    $relativeFiles = Get-ChildItem -LiteralPath $repository -Recurse -File |
        Where-Object {
            $_.FullName -notlike "$repository\build\*" -and
            $_.FullName -notlike "$repository\.vs\*" -and
            $_.FullName -notlike "$repository\data\*"
        } |
        ForEach-Object { $_.FullName.Substring($repository.Length + 1) }
}

$relativeFiles = @($relativeFiles | ForEach-Object { $_ -replace '/', '\' })

# A hard-coded developer test path is proof that a clean user install could
# not reproduce the behavior. The distribution guide may name it once while
# documenting this rule; executable code and release tooling may never do so.
$testPathReferences = @($relativeFiles | Where-Object {
    $_ -notin @('docs\DISTRIBUTION.md', 'tools\Check-Repository.ps1') -and
    (Get-Content -LiteralPath (Join-Path $repository $_) -Raw -ErrorAction SilentlyContinue) `
        -match [regex]::Escape($forbiddenTestInstall)
})
if ($testPathReferences) {
    throw "Developer test-install path leaked into public files:`n$($testPathReferences -join "`n")"
}

# These are generated, private, or playable original-game files.  None belongs
# in source control. Documentation screenshots are permitted, but files that
# the original executable can consume are not.
$forbiddenRoots = @('build\', '.vs\', 'data\', 'music\', 'reshade-cache\')
$forbiddenFiles = @(
    'ThemePark2Native.exe',
    'music-manifest.json',
    'preview.gif',
    'ReShade.log'
)
$violations = @($relativeFiles | Where-Object {
    $path = $_
    ($forbiddenFiles -contains $path) -or
    ($forbiddenRoots | Where-Object { $path.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) })
})
if ($violations) {
    throw "Generated or private runtime content would be published:`n$($violations -join "`n")"
}

$originalAssetNames = @(
    'MAIN.EXE', 'INTRO.EXE', 'MMENU-0.DAT', 'MPALETTE.DAT',
    'MUSIC0-0.DAT', 'SNDS0-0.DAT'
)
$assets = @($relativeFiles | Where-Object {
    $originalAssetNames -contains [System.IO.Path]::GetFileName($_)
})
if ($assets) {
    throw "Original game files would be published:`n$($assets -join "`n")"
}

$symbols = @($relativeFiles | Where-Object { [System.IO.Path]::GetExtension($_) -ieq '.pdb' })
if ($symbols) {
    throw "Build symbols would be published:`n$($symbols -join "`n")"
}

# The threshold is inclusive: a 300-line file must be split. License text and
# compressed third-party source are data, not authored code, and are unaffected.
$codeExtensions = @('.cpp', '.h', '.hpp', '.ps1', '.fx', '.fxh')
$oversized = foreach ($relativePath in $relativeFiles) {
    if ($codeExtensions -notcontains [System.IO.Path]::GetExtension($relativePath)) {
        continue
    }
    $fullPath = Join-Path $repository $relativePath
    $lineCount = (Get-Content -LiteralPath $fullPath).Count
    if ($lineCount -ge 300) {
        [pscustomobject]@{ Path = $relativePath; Lines = $lineCount }
    }
}
if ($oversized) {
    $details = $oversized | Format-Table -AutoSize | Out-String
    throw "Code reached the 300-line split threshold:`n$details"
}

Write-Host 'Repository boundary and source-size checks passed.' -ForegroundColor Green
