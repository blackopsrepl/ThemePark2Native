param(
    [Parameter(Mandatory = $true)]
    [string]$InstallDirectory,

    [string]$SourceImage,

    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path $PSScriptRoot 'Patch-ThemePark.ps1')

# Theme Park's PC CD keeps music and sound effects in DATA files rather than
# Red Book audio tracks.  Consequently ISO is a complete source for this game;
# BIN/CUE remains accepted so owners do not need to convert their own image.
$install = [IO.Path]::GetFullPath($InstallDirectory)
$tools = Join-Path $install 'tools'
$sevenZip = Join-Path $tools '7z.exe'
if (-not (Test-Path -LiteralPath $sevenZip -PathType Leaf)) {
    throw 'The bundled 7-Zip importer is missing.'
}

function Select-DiscImage {
    $dialog = New-Object Windows.Forms.OpenFileDialog
    $dialog.Title = 'Select your Theme Park PC CD image'
    $dialog.Filter = 'Theme Park disc image (*.iso;*.cue;*.zip)|*.iso;*.cue;*.zip|All files (*.*)|*.*'
    $dialog.CheckFileExists = $true
    $dialog.Multiselect = $false
    if ($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) {
        return $null
    }
    return $dialog.FileName
}

function Show-ImportMessage([string]$Text, [Windows.Forms.MessageBoxIcon]$Icon) {
    if ($Quiet) {
        Write-Host $Text
        return
    }
    [Windows.Forms.MessageBox]::Show(
        $Text,
        'Theme Park Native importer',
        [Windows.Forms.MessageBoxButtons]::OK,
        $Icon
    ) | Out-Null
}

function Repair-ThemeParkMouseFreeze([string]$MainExecutable) {
    # The retail game has a timing bug while changing between VGA and VESA.
    # Its mouse poll can jump into the wrong part of the transition and leave
    # the pointer frozen. This documented one-byte branch correction operates
    # only on the user's imported copy; the selected CD image is never changed.
    $bytes = [IO.File]::ReadAllBytes($MainExecutable)
    $old = [byte[]](0x0F, 0x84, 0x4D, 0x05)
    $fixed = [byte[]](0x0F, 0x84, 0x43, 0x05)
    $oldHits = @()
    $fixedHits = @()
    for ($offset = 0; $offset -le $bytes.Length - 4; $offset++) {
        if ($bytes[$offset] -eq $old[0] -and $bytes[$offset + 1] -eq $old[1] -and
            $bytes[$offset + 2] -eq $old[2] -and $bytes[$offset + 3] -eq $old[3]) {
            $oldHits += $offset
        }
        if ($bytes[$offset] -eq $fixed[0] -and $bytes[$offset + 1] -eq $fixed[1] -and
            $bytes[$offset + 2] -eq $fixed[2] -and $bytes[$offset + 3] -eq $fixed[3]) {
            $fixedHits += $offset
        }
    }
    if ($fixedHits.Count -eq 1 -and $oldHits.Count -eq 0) { return }
    if ($oldHits.Count -ne 1 -or $fixedHits.Count -ne 0) {
        throw 'MAIN.EXE is not the supported retail revision for the mouse-freeze repair.'
    }
    $bytes[$oldHits[0] + 2] = 0x43
    [IO.File]::WriteAllBytes($MainExecutable, $bytes)
}

if (-not $SourceImage) {
    $SourceImage = Select-DiscImage
}
if (-not $SourceImage) {
    exit 2
}
$image = [IO.Path]::GetFullPath($SourceImage)
if (-not (Test-Path -LiteralPath $image -PathType Leaf)) {
    Show-ImportMessage 'The selected disc image no longer exists.' Error
    exit 3
}

# Extract into a private staging folder first.  Nothing in data/ changes until
# the retail MAIN.EXE and representative audio/graphics files are verified.
$workRoot = Join-Path $install 'import-work'
$work = Join-Path $workRoot ([Guid]::NewGuid().ToString('N'))
$disc = Join-Path $work 'disc'
New-Item -ItemType Directory -Path $disc -Force | Out-Null
try {
    & $sevenZip x $image ("-o$disc") -y | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw '7-Zip could not read that image. For CUE images, keep every referenced BIN beside the CUE.'
    }

    # Some archival CUE tools expose the ISO data track as a nested file. If
    # the GAME directory is not immediately visible, extract the first ISO/BIN
    # payload once more before declaring the image unsupported.
    $game = Join-Path $disc 'GAME'
    if (-not (Test-Path -LiteralPath (Join-Path $game 'MAIN.EXE'))) {
        $nested = Get-ChildItem -LiteralPath $disc -File |
            Where-Object { $_.Extension -in '.iso', '.bin' } |
            Select-Object -First 1
        if ($nested) {
            & $sevenZip x $nested.FullName ("-o$disc") -y | Out-Null
        }
    }

    $required = @(
        'MAIN.EXE',
        'INTRO.EXE',
        'DATA\INTRO.DAT',
        'DATA\MUSIC0-0.DAT',
        'DATA\SNDS0-0.DAT'
    )
    $missing = @($required | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $game $_) -PathType Leaf)
    })
    if ($missing) {
        throw "This is not the supported 1994 Theme Park PC CD (`n$($missing -join "`n"))."
    }

    $data = Join-Path $install 'data'
    New-Item -ItemType Directory -Path $data -Force | Out-Null
    Copy-Item -Path (Join-Path $game '*') -Destination $data -Recurse -Force
    New-Item -ItemType Directory -Path (Join-Path $data 'SAVE') -Force | Out-Null
    Repair-ThemeParkMouseFreeze (Join-Path $data 'MAIN.EXE')
    Repair-ThemeParkWidescreen (Join-Path $data 'MAIN.EXE')

    # These are precisely the settings the DOS setup program would write for
    # DOSBox Pure's emulated SB16 and OPL hardware.  Keeping this as text makes
    # the choice reviewable and avoids ever showing the obsolete installer.
    @(
        'SOUNDFX = SB16 220 5 1',
        'MUSIC = ADLIB 388 0 0'
    ) | Set-Content -LiteralPath (Join-Path $data 'SNDSETUP.INF') -Encoding ascii

    $files = @(Get-ChildItem -LiteralPath $data -Recurse -File).Count
    $manifest = [ordered]@{
        schema = 1
        game = 'Theme Park PC CD'
        source = [IO.Path]::GetExtension($image).TrimStart('.').ToLowerInvariant()
        files = $files
        audio = 'file-based SB16 effects and AdLib music'
        mouseCompatibility = 'VGA/VESA freeze repaired in imported copy'
        widescreenCompatibility = 'reviewed engine framebuffer patch applied'
    }
    $manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $install 'import-manifest.json') -Encoding utf8
    Show-ImportMessage "Theme Park was imported successfully ($files files)." Information
} catch {
    Show-ImportMessage $_.Exception.Message Error
    exit 4
} finally {
    if (Test-Path -LiteralPath $work) {
        Remove-Item -LiteralPath $work -Recurse -Force
    }
    if ((Test-Path -LiteralPath $workRoot) -and
        -not (Get-ChildItem -LiteralPath $workRoot -Force)) {
        Remove-Item -LiteralPath $workRoot -Force
    }
}
