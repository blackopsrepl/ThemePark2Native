# Applies the reviewed widescreen changes to the owner's extracted MAIN.EXE.
# Theme Park is a Linear Executable: its code pages are not stored at their
# runtime addresses.  Mapping through the LE object/page tables keeps every
# patch tied to the reverse-engineered address documented in ENGINE-HOOKS.md.

function Get-ThemeParkFileOffset([byte[]]$Bytes, [uint32]$VirtualAddress) {
    $header = [BitConverter]::ToUInt32($Bytes, 0x3c)
    if ([Text.Encoding]::ASCII.GetString($Bytes, $header, 2) -ne 'LE') {
        throw 'MAIN.EXE is not the supported DOS/4GW Linear Executable.'
    }
    $pageSize = [BitConverter]::ToUInt32($Bytes, $header + 0x28)
    $objects = [BitConverter]::ToUInt32($Bytes, $header + 0x40)
    $objectCount = [BitConverter]::ToUInt32($Bytes, $header + 0x44)
    $pageMap = [BitConverter]::ToUInt32($Bytes, $header + 0x48)
    $dataPages = [BitConverter]::ToUInt32($Bytes, $header + 0x80)

    for ($index = 0; $index -lt $objectCount; $index++) {
        $entry = $header + $objects + $index * 24
        $size = [BitConverter]::ToUInt32($Bytes, $entry)
        $base = [BitConverter]::ToUInt32($Bytes, $entry + 4)
        if ($VirtualAddress -lt $base -or $VirtualAddress -ge $base + $size) {
            continue
        }
        $firstPage = [BitConverter]::ToUInt32($Bytes, $entry + 12)
        $relative = $VirtualAddress - $base
        $mapEntry = $header + $pageMap + ($firstPage - 1 +
            [Math]::Floor($relative / $pageSize)) * 4
        # LE stores the 24-bit physical-page number most-significant byte first.
        $pageNumber = ($Bytes[$mapEntry] -shl 16) -bor
            ($Bytes[$mapEntry + 1] -shl 8) -bor $Bytes[$mapEntry + 2]
        if ($pageNumber -eq 0 -or $Bytes[$mapEntry + 3] -ne 0) {
            throw 'A compressed or invalid MAIN.EXE code page cannot be patched safely.'
        }
        return [int]($dataPages + ($pageNumber - 1) * $pageSize +
            ($relative % $pageSize))
    }
    throw ('MAIN.EXE virtual address 0x{0:X} is outside its objects.' -f $VirtualAddress)
}

function Set-ThemeParkBytes {
    param([byte[]]$Bytes, [uint32]$Address, [byte[]]$Old, [byte[]]$New)
    $offset = Get-ThemeParkFileOffset $Bytes $Address
    $current = [byte[]]::new($Old.Length)
    [Array]::Copy($Bytes, $offset, $current, 0, $current.Length)
    if ([Linq.Enumerable]::SequenceEqual[byte]($current, $New)) { return }
    if (-not [Linq.Enumerable]::SequenceEqual[byte]($current, $Old)) {
        throw ('MAIN.EXE differs at reviewed address 0x{0:X}.' -f $Address)
    }
    [Array]::Copy($New, 0, $Bytes, $offset, $New.Length)
}

function Repair-ThemeParkWidescreen([string]$MainExecutable) {
    $bytes = [IO.File]::ReadAllBytes($MainExecutable)
    $u320 = [byte[]](0x40, 0x01, 0x00, 0x00)
    $u427 = [byte[]](0xAB, 0x01, 0x00, 0x00)
    $surface64000 = [byte[]](0x00, 0xFA, 0x00, 0x00)
    $surface85400 = [byte[]](0x98, 0x4D, 0x01, 0x00)

    # Allocate two 427x200 pages before the first video mode is entered.
    Set-ThemeParkBytes $bytes 0x105A6 ([byte[]](0x00,0xF4,0x01,0x00)) `
        ([byte[]](0x30,0x9B,0x02,0x00))
    foreach ($address in 0x5C25B,0x5C289,0x5C5CC,0x5C5E1,0x7C298,0x7C3F4) {
        Set-ThemeParkBytes $bytes $address $surface64000 $surface85400
    }

    # Width, clipping, sprite-mode selection, and 32-bit row arithmetic.
    foreach ($address in 0x66E3D,0x7EC97,0x7ECCF,0x1165F,0x11672,
            0x11680,0x7F5DC,0x7F5EE,0x80E9B,0x81418,0x8144E,0x8145A) {
        Set-ThemeParkBytes $bytes $address $u320 $u427
    }
    Set-ThemeParkBytes $bytes 0x80F25 ([byte[]](0x84,0xF8,0xFF,0xFF)) `
        ([byte[]](0x02,0xF6,0xFF,0xFF))

    # The original point primitive multiplies in 16 bits. A 427-byte stride
    # needs 32-bit arithmetic near the bottom of the 200-line framebuffer.
    $oldPoint = [byte[]](0xD1,0xF8,0x66,0x69,0xC0,0x40,0x01,0x03,0xF8,
        0x03,0x3D,0xBC,0xE5,0x02,0x00,0x66,0x8B,0x45,0x10,0x88,0x07)
    $newPoint = [byte[]](0xD1,0xE8,0x69,0xC0,0xAB,0x01,0x00,0x00,0x01,
        0xC7,0x03,0x3D,0xBC,0xE5,0x02,0x00,0x8A,0x45,0x10,0x88,0x07)
    Set-ThemeParkBytes $bytes 0x80C21 $oldPoint $newPoint
    [IO.File]::WriteAllBytes($MainExecutable, $bytes)
}
