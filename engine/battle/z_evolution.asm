; Z-Evolution: any fully-evolved Pokémon holding the Z Stone can Z-Evolve mid-battle.
; Unlike Mega Evolution, this never changes species/form/sprite -- it's a pure stat
; boost (computed from the mon's own base stats, not hardcoded per species) plus a
; palette recolor and a one-off animation. See Planned Features.md for the design.

MaybeOverlayZEvolvedStats::
; Called from SummaryScreen_BluePage right before it prints wTempMon's stats.
; (SummaryScreenInit runs the whole interactive summary screen loop internally
; and only returns once the player exits it, so hooking in afterward -- as a
; one-shot post-init call -- is too late to affect anything the player sees;
; this must run every time the stats page itself is actually drawn, including
; scrolling back to it.) That data source has no idea a battle-only stat boost
; exists, so if the mon being viewed is the player's currently active,
; Z-Evolved battler, overwrite wTempMon's stat fields with the live boosted ones from
; wBattleMon. wTempMon and wBattleMon store Attack/Defense/Speed/SpAtk/SpDef in the
; same order, so this is a straight 10-byte copy. Called via farcall from a
; context (blue_page.asm) that needs its own hl (the print cursor) AND bc (its
; column-spacing value, used right after this call returns) intact afterward --
; farcall only preserves what the target itself preserves, and this function
; uses both hl and bc as scratch (the CopyBytes length is 10), so both must be
; explicitly saved and restored around every exit path here, not left to chance.
	push hl
	push bc
	ld a, [wBattleMode]
	and a
	jr z, .done

	ld a, [wTempMonBox]
	and a
	jr nz, .done

	ld a, [wTempMonSlot]
	dec a
	ld hl, wCurBattleMon
	cp [hl]
	jr nz, .done

	ld a, [wPlayerSubStatus1]
	bit SUBSTATUS_Z_EVOLVED, a
	jr z, .done

	ld hl, wBattleMonAttack
	ld de, wTempMonAttack
	ld bc, 10
	rst CopyBytes

.done
	pop bc
	pop hl
	ret

IsFullyEvolved:
; Returns carry set if the species+form in wBattleMonSpecies/wBattleMonForm has no
; further evolutions (i.e. is eligible to Z-Evolve).
	ld a, [wBattleMonSpecies]
	ld c, a
	ld a, [wBattleMonForm]
	and SPECIESFORM_MASK
	ld b, a
	farcall GetEvosAttacksPointer
	ld a, BANK(EvosAttacks)
	call GetFarByte
	inc a
	jr nz, .not_fully_evolved
	scf
	ret
.not_fully_evolved
	and a
	ret

CanZEvolveNow::
; Returns carry set if the player's active Pokémon is currently eligible to Z-Evolve:
; holding the Z Stone, its species is fully evolved, and it hasn't already Z-Evolved
; this battle.
	ld a, BATTLE_VARS_SUBSTATUS1
	call GetBattleVarAddr
	bit SUBSTATUS_Z_EVOLVED, [hl]
	jr nz, .no

	ld a, [wBattleMonItem]
	cp Z_STONE
	jr nz, .no

	call IsFullyEvolved
	jr nc, .no

	scf
	ret

.no
	and a
	ret

TryZEvolve::
; Called once the player's move is locked in for the turn, before it executes. If the
; player toggled Z-Evolution on and the active Pokémon is eligible: recompute its
; Attack/Defense/SpAtk/SpDef/Speed with the tiered bonus and recolor its sprite red.
; (No animation for now -- deferred until the core mechanic is confirmed working; see
; Planned Features.md.) Species/form/type/ability/sprite graphic are all left
; alone -- only wBattleMon*/wCur* (transient, in-battle state) are touched, so
; switching out, fainting, or ending the battle reverts the stats for free. The
; palette override reverts for free too: every send-out unconditionally reloads the
; active mon's palette from scratch (see the patch in engine/gfx/color.asm), and that
; reload already checks this same flag, which is cleared here.
	ld a, [wZEvolveToggled]
	and a
	ret z
	xor a
	ld [wZEvolveToggled], a

	call CanZEvolveNow
	ret nc

	; wCurBaseData is a shared scratch buffer that other code may have overwritten
	; since send-out -- explicitly refresh it for the active battler's species/form
	; before relying on it (same precaution Mega Evolution's trigger takes).
	ld a, [wBattleMonSpecies]
	ld [wCurSpecies], a
	ld a, [wBattleMonForm]
	ld [wCurForm], a
	call GetBaseData

	call CalcZStatBonuses
	call CalcBattleMonZStats

	ld a, BATTLE_VARS_SUBSTATUS1
	call GetBattleVarAddr
	set SUBSTATUS_Z_EVOLVED, [hl]

	call UpdatePlayerHUD
	ret

; Scratch layout used below, inside wZStatsBuffer (12 bytes, otherwise unused until
; CalcBattleMonZStats runs afterward -- reusing it here avoids needing any new WRAM,
; since WRAMX has zero bytes free): offsets 0-4 hold the 5 base stats (display order),
; offset 5 is the loop counter (i, reused for both the ranking pass and the bonus
; pass below), offset 6 is the inner loop counter (j, ranking pass only), offsets
; 7-11 hold each stat's computed rank (one byte per stat, ranks[i] at offset 7+i).
; (These can't be named EQU constants -- wZStatsBuffer's address isn't known until
; link time, so only direct "wZStatsBuffer + N" expressions work, not an EQU alias
; built from it.)

CalcZStatBonuses:
; wCurBaseData must already hold the current species+form's base data (TryZEvolve
; refreshes it via GetBaseData just before calling this). Reads
; Attack/Defense/SpAtk/SpDef/Speed into wZStatsBuffer + 0 in DISPLAY order (Atk, Def, SpAtk,
; SpDef, Speed -- the order they're shown on the Stats page).
;
; Runs in two passes rather than one. The first pass computes every stat's rank
; (how many of the other 4 "beat" it -- a strictly higher value, or an equal value
; that appears earlier/lower-indexed in display order -- that count IS its 0-based
; rank, highest stat = rank 0) and stores all 5 ranks without touching any stat's
; value. The second pass applies each stat's tiered bonus (+25/+25/+20/+20/+10 for
; ranks 0-4), saturating at 255. The two passes must stay separate: applying each
; bonus immediately after computing its rank would let a later stat's rank get
; computed against an earlier stat's already-boosted value instead of its original,
; skewing the ranking.
;
; Finally writes the boosted values back into wCurBaseData (leaving BASE_HP
; untouched) so CalcBattleMonZStats can feed them straight into the normal stat
; formula.
	ld a, [wCurBaseData + BASE_ATK]
	ld [wZStatsBuffer + 0], a
	ld a, [wCurBaseData + BASE_DEF]
	ld [wZStatsBuffer + 1], a
	ld a, [wCurBaseData + BASE_SAT]
	ld [wZStatsBuffer + 2], a
	ld a, [wCurBaseData + BASE_SDF]
	ld [wZStatsBuffer + 3], a
	ld a, [wCurBaseData + BASE_SPE]
	ld [wZStatsBuffer + 4], a

	; Pass 1: compute ranks[i] for i = 0..4 into offsets 7-11, without ever
	; writing to offsets 0-4 (the stat values).
	xor a
	ld [wZStatsBuffer + 5], a
.rank_outer_loop
	; ranks[i] = 0
	ld a, [wZStatsBuffer + 5]
	ld c, a
	ld b, 0
	ld hl, wZStatsBuffer + 7
	add hl, bc
	xor a
	ld [hl], a

	xor a
	ld [wZStatsBuffer + 6], a
.rank_inner_loop
	ld a, [wZStatsBuffer + 6]
	ld hl, wZStatsBuffer + 5
	cp [hl]
	jr z, .rank_next_j

	ld a, [wZStatsBuffer + 6]
	ld c, a
	ld b, 0
	ld hl, wZStatsBuffer + 0
	add hl, bc
	ld a, [hl] ; a = statVal[j]

	ld c, a
	ld a, [wZStatsBuffer + 5]
	ld hl, wZStatsBuffer + 0
	ld b, 0
	push bc
	ld c, a
	add hl, bc
	pop bc
	ld a, [hl] ; a = statVal[i]

	ld b, a
	ld a, c
	cp b
	jr c, .rank_not_dominator ; statVal[j] < statVal[i]
	jr nz, .rank_dominator     ; statVal[j] > statVal[i]
	; equal: only counts if j < i
	ld a, [wZStatsBuffer + 6]
	ld hl, wZStatsBuffer + 5
	cp [hl]
	jr nc, .rank_not_dominator
.rank_dominator
	ld a, [wZStatsBuffer + 5]
	ld c, a
	ld b, 0
	ld hl, wZStatsBuffer + 7
	add hl, bc ; hl = &ranks[i]
	inc [hl]
.rank_not_dominator
.rank_next_j
	ld hl, wZStatsBuffer + 6
	inc [hl]
	ld a, [hl]
	cp 5
	jr nz, .rank_inner_loop

	ld hl, wZStatsBuffer + 5
	inc [hl]
	ld a, [hl]
	cp 5
	jr nz, .rank_outer_loop

	; Pass 2: apply each stat's bonus using its stored rank, saturating at 255.
	xor a
	ld [wZStatsBuffer + 5], a
.bonus_loop
	ld a, [wZStatsBuffer + 5]
	ld c, a
	ld b, 0
	ld hl, wZStatsBuffer + 7
	add hl, bc ; hl = &ranks[i]
	ld a, [hl] ; a = rank
	ld hl, ZBonusByRank
	ld e, a
	ld d, 0
	add hl, de
	ld a, [hl] ; a = bonus
	ld e, a    ; e = bonus, held here so it survives the address math below

	ld a, [wZStatsBuffer + 5]
	ld c, a
	ld b, 0
	ld hl, wZStatsBuffer + 0
	add hl, bc ; hl = &statVal[i]

	ld a, [hl]
	add e
	jr nc, .bonus_no_overflow
	ld a, 255
.bonus_no_overflow
	ld [hl], a

	ld hl, wZStatsBuffer + 5
	inc [hl]
	ld a, [hl]
	cp 5
	jr nz, .bonus_loop

	; Write the boosted stats back into wCurBaseData, in its own storage order.
	ld a, [wZStatsBuffer + 0]
	ld [wCurBaseData + BASE_ATK], a
	ld a, [wZStatsBuffer + 1]
	ld [wCurBaseData + BASE_DEF], a
	ld a, [wZStatsBuffer + 2]
	ld [wCurBaseData + BASE_SAT], a
	ld a, [wZStatsBuffer + 3]
	ld [wCurBaseData + BASE_SDF], a
	ld a, [wZStatsBuffer + 4]
	ld [wCurBaseData + BASE_SPE], a
	ret

ZBonusByRank:
	db 25, 25, 20, 20, 10

CalcBattleMonZStats:
; Recomputes Attack/Defense/Speed/SpAtk/SpDef into wBattleMonStats from the
; (now-boosted, courtesy of CalcZStatBonuses) wCurBaseData, using the active
; battler's real level/DVs/EVs. Never touches wBattleMonHP/MaxHP (Z-Evolution
; doesn't change max HP) or the party struct. Same approach as Mega Evolution's
; battle-only stat recompute.
	ld a, [wCurPartyMon]
	push af
	ld a, [wCurBattleMon]
	ld [wCurPartyMon], a

	ld a, MON_LEVEL
	call GetPartyParamLocationAndValue
	ld [wCurPartyLevel], a

	ld a, MON_EVS - 1
	call GetPartyParamLocationAndValue ; hl = EVs - 1

	ld de, wZStatsBuffer
	; GetHyperTraining lives in a different bank than this file (move_mon.asm,
	; bank 03), so it must be farcalled, not near-called -- every other
	; cross-bank caller (evolve.asm, load_trainer.asm) already does this.
	farcall GetHyperTraining
	inc a
	ld b, a
	; CalcPkmnStats lives in a different bank than this file (mon_stats.asm,
	; bank 14, vs this file's bank 0f) -- like GetHyperTraining above, it must
	; be farcalled, not near-called.
	farcall CalcPkmnStats

	pop af
	ld [wCurPartyMon], a

	ld hl, wZStatsBuffer + 2 ; skip the HP entry
	ld de, wBattleMonStats
	ld bc, 10
	rst CopyBytes
	ret

ZOnText::
	db "Z@"

ZOffText::
	db "z@"
