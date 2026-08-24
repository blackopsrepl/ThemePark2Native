param(
    [Parameter(Mandatory = $true)]
    [string]$Executable,
    [string]$OutputCsv
)

$ErrorActionPreference = 'Stop'

# Theme Park's DOS executable contains a Borland Turbo Debugger information
# block after the normal MZ image. This script reads that metadata without
# changing the game. It is deliberately plain PowerShell so contributors need
# only Windows and the same Visual Studio environment as the main project.
$bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Executable))
if ($bytes.Length -lt 64 -or $bytes[0] -ne 0x4D -or $bytes[1] -ne 0x5A) {
    throw 'The supplied file is not a DOS MZ executable.'
}

function Read-U16([int]$Offset) {
    return [BitConverter]::ToUInt16($script:bytes, $Offset)
}

function Read-U32([int]$Offset) {
    return [BitConverter]::ToUInt32($script:bytes, $Offset)
}

# MZ stores the byte count as 512-byte pages plus a possibly partial last page.
# The debugger block starts immediately after that declared executable image.
$lastPageBytes = Read-U16 2
$pageCount = Read-U16 4
$imageBytes = if ($lastPageBytes -eq 0) {
    $pageCount * 512
} else {
    (($pageCount - 1) * 512) + $lastPageBytes
}
if ($imageBytes + 80 -gt $bytes.Length -or
    (Read-U16 $imageBytes) -ne 0x52FB) {
    throw 'No supported Turbo Debugger information block follows the MZ image.'
}

$majorVersion = $bytes[$imageBytes + 3]
if ($majorVersion -ne 3) {
    throw "This inspector currently supports TDINFO v3; found v$majorVersion."
}

$namePoolBytes = Read-U32 ($imageBytes + 4)
$symbolCount = Read-U16 ($imageBytes + 14)
$namePoolStart = $bytes.Length - $namePoolBytes
if ($namePoolStart -le $imageBytes) {
    throw 'The TDINFO name pool lies outside the file.'
}

# Version 3 uses an 80-byte header. Each symbol is a packed nine-byte record:
# name index, type index, offset, segment identifier, and a final flags byte.
# Name indexes are one-based and point into the NUL-separated pool at EOF.
$symbolStart = $imageBytes + 80
$namesText = [Text.Encoding]::ASCII.GetString(
    $bytes, $namePoolStart, $bytes.Length - $namePoolStart)
$names = $namesText.Split([char]0)
$symbols = for ($index = 0; $index -lt $symbolCount; ++$index) {
    $record = $symbolStart + ($index * 9)
    if ($record + 9 -gt $namePoolStart) {
        throw 'A symbol record overlaps the TDINFO name pool.'
    }
    $nameIndex = Read-U16 $record
    if ($nameIndex -eq 0 -or $nameIndex -gt $names.Count) {
        continue
    }
    [pscustomobject]@{
        Name = $names[$nameIndex - 1]
        Type = '0x{0:X4}' -f (Read-U16 ($record + 2))
        Offset = '0x{0:X4}' -f (Read-U16 ($record + 4))
        Segment = '0x{0:X4}' -f (Read-U16 ($record + 6))
        Flags = '0x{0:X2}' -f $bytes[$record + 8]
    }
}

# Symbols can appear once per compilation unit. Collapsing exact duplicates
# makes the output useful while preserving genuinely different addresses.
$result = $symbols | Sort-Object Name, Segment, Offset, Type -Unique
if ($OutputCsv) {
    $parent = Split-Path -Parent $OutputCsv
    if ($parent) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $result | Export-Csv -LiteralPath $OutputCsv -NoTypeInformation
    Write-Host "Wrote $($result.Count) unique symbols to $OutputCsv"
} else {
    $result
}
