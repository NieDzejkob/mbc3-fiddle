INCLUDE "hardware.inc"
INCLUDE "macros.inc"

SECTION "VBlank", ROM0[$40]
VBlank:
    push af
    push bc
    push de
    push hl

    ld hl, $9841
    ld e, $0c
.readLoop:
    ld a, e
    ld [$4000], a
    ld a, [$a000]
    call PutHexByte
    inc l
    dec e
    bit 3, e
    jr nz, .readLoop ; stop at 7

    pop hl
    pop de
    pop bc

    ldh a, [hVBlankFlag]
    and a
    jr z, .lagFrame
    ; we're in WaitVBlank, so it's fine to clobber any registers we want
    xor a
    ldh [hVBlankFlag], a

    ld c, LOW(rP1)
    ld a, $20 ; Select D-pad
    ldh [c], a
REPT 6
    ldh a, [c]
ENDR
    or $F0 ; Set 4 upper bits (give them consistency)
    ld b, a

    ; Filter impossible D-pad combinations
    and $0C ; Filter only Down and Up
    ld a, b
    jr nz, .notUpAndDown
    or $0C ; If both are pressed, "unpress" them
    ld b, a
.notUpAndDown
    and $03 ; Filter only Left and Right
    jr nz, .notLeftAndRight
    ; If both are pressed, "unpress" them
    inc b
    inc b
    inc b
.notLeftAndRight
    swap b ; Put D-pad buttons in upper nibble

    ld a, $10 ; Select buttons
    ldh [c], a
REPT 6
    ldh a, [c]
ENDR

    or $F0 ; Set 4 upper bits
    xor b ; Mix with D-pad bits, and invert all bits (such that pressed=1) thanks to "or $F0"
    ld b, a

    ; Release joypad
    ld a, $30
    ldh [c], a

    ldh a, [hHeldKeys]
    cpl
    and b
    ldh [hPressedKeys], a
    ld a, b
    ldh [hHeldKeys], a

    pop af ; Pop off return address as well to exit infinite loop
.lagFrame:
    pop af
    reti

SECTION "WaitVBlank", ROM0
WaitVBlank:
    ld a, 1
    ldh [hVBlankFlag], a
    ; the vblank handler exits us out of this loop
.wait:
    halt
    jr .wait

SECTION "Entrypoint", ROM0[$100]
    jp Start

SECTION "Header", ROM0[$104]
    ds $150 - $104

SECTION "Start", ROM0
Start:
.disableLCD:
    ldh a, [rLY]
    cp SCRN_Y
    jr c, .disableLCD

    xor a
    ldh [rLCDC], a
    ldh [rSCX], a
    ldh [rSCY], a
    ld a, $e4
    ldh [rBGP], a
    ldh [rOBP0], a
    ldh [rOBP1], a
    ldh [rWY], a

    ld hl, vFont
    ld de, Font
    ld bc, Font.end - Font
.fontLoop:
    ld a, [de]
    ld [hli], a
    ld [hli], a
    inc de
    dec bc
    ld a, b
    or c
    jr nz, .fontLoop

    ld hl, $9801
    ld de, HeaderString
    call PlaceString

    ld l, $81
    ld de, LatchString
    call PlaceString

    ld l, $a1
    ld de, WriteString
    call PlaceString

    ld a, "*"
    ld [$9880], a

    ld a, $7f
    ld [$98cd], a

    ld a, LCDCF_ON | LCDCF_BGON
    ldh [rLCDC], a

    ld a, $0a
    ld [$0000], a

    ld a, IEF_VBLANK
    ldh [rIE], a
    xor a
    ldh [hVBlankFlag], a
    ldh [hHeldKeys], a
    ldh [rIF], a
    ei

    ld [wCursorPos], a
    ld [wWriteCursorPos], a
    ld [wWriteValue], a
    inc a
    ld [wLastLatch], a

NUM_OPTIONS EQU 2

MainLoop:
    call WaitVBlank
    ldh a, [hPressedKeys]
    bit PADB_SELECT, a
    jr z, .notSelect

    ld hl, wCursorPos
    inc [hl]
    ld a, [hl]
    cp NUM_OPTIONS
    jr nz, .newCursorPos
    xor a
    ld [hl], a
.newCursorPos

    add a
    swap a
    add $80
    ld l, a
    ld h, $98
    wait_vram
    xor a
    ld [$9880], a
    ld [$98a0], a
    ld [hl], "*"
    jr MainLoop

.notSelect:
    and a
    jr z, MainLoop

    ld a, [wCursorPos]
    and a
    jr z, HandleLatch
    ; fallthrough

NUM_WRITE_SETTINGS EQU 2

HandleWrite:
    ld hl, wWriteCursorPos
    ldh a, [hPressedKeys]
    bit PADB_RIGHT, a
    jr z, .notRight
    inc [hl]
    ld a, [hl]
    sub NUM_WRITE_SETTINGS
    jr nz, .updateCursor
    xor a
    ld [hl], a
.updateCursor:
    ld a, [hl]
    add $cd
    ld l, a
    ld h, $98
    wait_vram
    xor a
    ld [$98cd], a
    ld [$98ce], a
    ld [hl], $7f
    jr MainLoop
.notRight:
    bit PADB_LEFT, a
    jr z, .notLeft
    dec [hl]
    ld a, [hl]
    inc a
    jr nz, .updateCursor
    ld a, NUM_WRITE_SETTINGS - 1
    ld [hl], a
    jr .updateCursor
.notLeft:
    bit PADB_UP, a
    jr z, .notUp
    ld a, [hl]
    and a
    ld a, 1
    jr nz, .gotIncrement
    ld a, $10
.gotIncrement:
    ld hl, wWriteValue
    add [hl]
    ld [hl], a
    ld hl, $98ad
    call PutHexByte
    jp MainLoop
.notUp:
    bit PADB_DOWN, a
    jr z, .notDown
    ld a, [hl]
    and a
    ld a, -1
    jr nz, .gotIncrement
    ld a, -$10
    jr .gotIncrement
.notDown:
    bit PADB_A, a
    jp z, MainLoop
    di
    ld a, $0c
    ld [$4000], a
    ld a, [wWriteValue]
    ld [$a000], a
    ei
    jp MainLoop

HandleLatch:
    ldh a, [hPressedKeys]
    assert PADF_A == 1
    rrca
    jp nc, MainLoop
    ld hl, wLastLatch
    ld a, [hl]
    xor 1
    ld [hl], a
    ld [$6000], a
    ld hl, $9888
    call PutHexByte
    jp MainLoop

SECTION "PlaceString", ROM0
PlaceString:
    ld a, [de]
    and a
    ret z
    ld [hli], a
    inc de
    jr PlaceString

SECTION "GetJoypad", ROM0
GetJoypad:
    ret

SECTION "PutHex", ROM0
; Converts A to hex and stores it at [hl].
; Clobbers BC.
; Output: HL is one byte after the second hexdigit.
PutHexByte:
    ld c, a
    swap a
    call PutHexDigit
    ld a, c
    ; fallthrough

; Converts the lower nibble of A into a hex character, and stores it in [hl].
; The pointer is incremented. Clobbers B.
PutHexDigit:
    and $0f
    add "0"
    cp "9" + 1
    jr c, .notLetter
    add "A" - "0" - 10
.notLetter:
    ld b, a
    wait_vram
    ld a, b
    ld [hli], a
    ret

SECTION "Font", ROM0
Font:
    INCBIN "font.1bpp"
.end:

SECTION "vFont", VRAM[$9200]
vFont: ds 48 * 16

SECTION "Strings", ROM0
HeaderString:
    db "MBC3 RTC Test", 0

LatchString:
    db "Latch: ??", 0

WriteString:
    db "Write @ 0C: 00", 0

SECTION "Variables", WRAM0
wCursorPos: db
wLastLatch: db
wWriteValue: db
wWriteCursorPos: db

SECTION "HRAM Variables", HRAM
hVBlankFlag: db
hPressedKeys: db
hHeldKeys: db