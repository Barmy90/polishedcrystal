MegaFormTable:
; species, mega form. Terminated by -1.
; Extend this table (and add the corresponding BaseData/variant-form/sprite
; entries) to support more Mega Evolutions later.
	db MEWTWO, MEWTWO_ARMORED_FORM
	db -1 ; end

GetMegaForm:
; Input: a = species
; Output: carry set and a = that species' Mega Form, if it has one.
;         carry clear otherwise.
	ld b, a
	ld hl, MegaFormTable
.loop
	ld a, [hli]
	cp -1
	jr z, .none
	cp b
	jr z, .found
	inc hl
	jr .loop

.found
	ld a, [hl]
	scf
	ret

.none
	and a
	ret

CanMegaEvolveNow::
; Returns carry set if the player's active Pokémon is currently eligible to
; Mega Evolve: holding a Mega Stone, its species has a Mega Form, and it
; hasn't already Mega Evolved this battle.
	ld a, BATTLE_VARS_SUBSTATUS1
	call GetBattleVarAddr
	bit SUBSTATUS_MEGA_EVOLVED, [hl]
	jr nz, .no

	ld a, [wBattleMonItem]
	cp MEGA_STONE
	jr nz, .no

	ld a, [wBattleMonSpecies]
	call GetMegaForm
	jr nc, .no

	scf
	ret

.no
	and a
	ret

TryMegaEvolve::
; Called once the player's move is locked in for the turn, before it
; executes. If the player toggled Mega Evolution on at the move-select
; screen and the active Pokémon is eligible, transform it: recompute type
; and stats from its Mega Form's base data, refresh its ability, and reload
; its battle sprite. Only wBattleMon*/wCur* (transient, in-battle state) are
; touched -- the party struct is never written, so switching out, fainting,
; or ending the battle reverts to the base form for free.
	ld a, [wMegaEvolveToggled]
	and a
	ret z
	xor a
	ld [wMegaEvolveToggled], a

	call CanMegaEvolveNow
	ret nc

	ld a, [wBattleMonSpecies]
	call GetMegaForm

	ld [wBattleMonForm], a
	ld [wCurForm], a
	ld a, [wBattleMonSpecies]
	ld [wCurSpecies], a
	ld [wCurPartySpecies], a

	call GetBaseData
	ld hl, wBaseType1
	ld de, wBattleMonType1
	ld bc, 2
	rst CopyBytes

	call CalcBattleMonMegaStats
	call ResetPlayerAbility

	ld a, BATTLE_VARS_SUBSTATUS1
	call GetBattleVarAddr
	set SUBSTATUS_MEGA_EVOLVED, [hl]

	call UpdatePlayerHPPal
	call _LoadBattleFontsHPBar
	call GetMonBackpic
	call LoadTempTileMapToTileMap
	call UpdatePlayerHUD
	ld a, $31
	ldh [hGraphicStartTile], a
	hlcoord 2, 6
	lb bc, 6, 6
	farcall PlaceGraphic
	call EmptyBattleTextbox

	farjp RunEntryAbilitiesInner

CalcBattleMonMegaStats:
; wCurBaseData must already hold the Mega Form's base stats (via GetBaseData,
; called by TryMegaEvolve just before this). Recomputes Attack/Defense/
; Speed/SpAtk/SpDef into wBattleMonStats from the active battler's real
; level/DVs/EVs. Deliberately does not touch wBattleMonHP/MaxHP (Mega
; Evolution never changes max HP) or the party struct.
	ld a, [wCurPartyMon]
	push af
	ld a, [wCurBattleMon]
	ld [wCurPartyMon], a

	ld a, MON_LEVEL
	call GetPartyParamLocationAndValue
	ld [wCurPartyLevel], a

	ld a, MON_EVS - 1
	call GetPartyParamLocationAndValue ; hl = EVs - 1

	ld de, wMegaStatsBuffer
	call GetHyperTraining
	inc a
	ld b, a
	call CalcPkmnStats

	pop af
	ld [wCurPartyMon], a

	ld hl, wMegaStatsBuffer + 2 ; skip the HP entry
	ld de, wBattleMonStats
	ld bc, 10
	rst CopyBytes
	ret

; vTiles2 $52/$53 hold the <DONE>/"@" text-flow control codes -- these are
; pure parser directives (like <START>/<WAIT>/<PARA>), never drawn as
; visible glyphs, so their VRAM tile slots are safe to repurpose for a
; custom graphic. This mirrors how MoveInfoBox already borrows the
; neighboring $59-$5e control-code tiles for its category/type icons.
; $5f+ ("Battle characters" per constants/charmap.asm) must NOT be touched:
; those are live HUD glyphs (HP/XP bar segments, the ball icon, and the
; <MALE>/<FEMALE> gender symbols) rendered on screen at the same time as
; the move-select screen.
DEF MEGA_ICON_TILE EQU $52

DrawMegaIcon::
; Draws the Mega Evolution toggle icon (a two-tile-tall twisting
; double-helix glyph, one column wide) at the bottom-left of the move-select
; screen: blank if the active Pokémon isn't eligible to Mega Evolve, a thin
; outline if eligible but not toggled on, bold/solid once toggled on.
	call CanMegaEvolveNow
	jr nc, .blank

	ld de, MegaIconOffGFX
	ld a, [wMegaEvolveToggled]
	and a
	jr z, .load
	ld de, MegaIconOnGFX
.load
	ld hl, vTiles2 tile MEGA_ICON_TILE
	lb bc, BANK(MegaIconOnGFX), 2
	call Request2bpp
	hlcoord 2, 14
	ld a, MEGA_ICON_TILE
	ld [hl], a
	hlcoord 2, 15
	ld a, MEGA_ICON_TILE + 1
	ld [hl], a
	ret

.blank
	ld a, ' '
	hlcoord 2, 14
	ld [hl], a
	hlcoord 2, 15
	ld [hl], a
	ret

; A two-tile-tall crossing-strands shape (the same 8x8 hourglass motif
; stacked twice, giving a twisting-strand look). Both states draw solid
; (both bitplanes set, same as any other black-on-white glyph) so they're
; visible under any palette -- "off" just uses a thinner outline instead of
; a filled shape, rather than relying on a dimmer shade.
MegaIconOnGFX::
	db $C3, $C3
	db $66, $66
	db $3C, $3C
	db $18, $18
	db $18, $18
	db $3C, $3C
	db $66, $66
	db $C3, $C3
	db $C3, $C3
	db $66, $66
	db $3C, $3C
	db $18, $18
	db $18, $18
	db $3C, $3C
	db $66, $66
	db $C3, $C3

MegaIconOffGFX::
	db $81, $81
	db $42, $42
	db $24, $24
	db $18, $18
	db $18, $18
	db $24, $24
	db $42, $42
	db $81, $81
	db $81, $81
	db $42, $42
	db $24, $24
	db $18, $18
	db $18, $18
	db $24, $24
	db $42, $42
	db $81, $81
