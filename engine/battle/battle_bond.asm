; Battle Bond: any Pokémon can Battle Bond mid-battle, given either high enough
; friendship or the Bond Charm (see CanBattleBondNow -- enemies currently still need
; the charm; see CanEnemyBattleBondNow). Unlike Mega Evolution, this never changes
; species/form/sprite -- it's a pure stat boost (computed from the mon's own base
; stats, not hardcoded per species) plus a palette recolor and a one-off animation.
; See Planned Features.md for the design.

; How close a bond (MON_HAPPINESS) qualifies a Pokémon to Battle Bond without needing
; the Bond Charm. Matches AFFECTION_THRESHOLD_2 (constants/pokemon_data_constants.asm)
; -- this fork's existing "very happy" bar -- but kept as its own constant so tuning
; Battle Bond's threshold doesn't also retune the unrelated Affection system.
DEF BOND_FRIENDSHIP_THRESHOLD EQU 220

; Tunable weights for the enemy AI's Battle Bond decision (see AIWantsBattleBond).
; All percentages; summed, then clamped to [0, BOND_AI_MAX_CHANCE] before the main
; roll. None of these are precious -- adjust freely while tuning.
DEF BOND_AI_BASE_CHANCE  EQU 15 ; baseline chance when no other signal applies
DEF BOND_AI_KO_BONUS     EQU 50 ; would newly KO the player's mon by Bonding
DEF BOND_AI_SPEED_BONUS  EQU 35 ; would newly outspeed, and no type disadvantage
DEF BOND_AI_HP_PENALTY   EQU 50 ; not at full HP
DEF BOND_AI_TYPE_PENALTY EQU 50 ; type disadvantage
DEF BOND_AI_MAX_CHANCE   EQU 95 ; cap -- never a guaranteed trigger except last-mon
DEF BOND_AI_FALLBACK_PCT EQU 5  ; flat re-roll chance if the main roll fails

MaybeOverlayBattleBondStats::
; Called from SummaryScreen_BluePage right before it prints wTempMon's stats.
; (SummaryScreenInit runs the whole interactive summary screen loop internally
; and only returns once the player exits it, so hooking in afterward -- as a
; one-shot post-init call -- is too late to affect anything the player sees;
; this must run every time the stats page itself is actually drawn, including
; scrolling back to it.) That data source has no idea a battle-only stat boost
; exists, so if the mon being viewed is the player's currently active,
; Bonded battler, overwrite wTempMon's stat fields with the live boosted ones from
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
	bit SUBSTATUS_BATTLE_BOND, a
	jr z, .done

	ld hl, wBattleMonAttack
	ld de, wTempMonAttack
	ld bc, 10
	rst CopyBytes

.done
	pop bc
	pop hl
	ret

CanBattleBondNow::
; Returns carry set if the player's active Pokémon is currently eligible to Battle
; Bond: it hasn't already Battle Bonded this battle, and either its friendship is at
; least BOND_FRIENDSHIP_THRESHOLD or it's holding the Bond Charm (the charm is a
; deterministic alternative to raising friendship, not an additional requirement on
; top of it). Any species/evolution stage is eligible -- unlike the old Z-Evolution
; prototype this replaced, there's no "must be fully evolved" restriction anymore.
	ld a, BATTLE_VARS_SUBSTATUS1
	call GetBattleVarAddr
	bit SUBSTATUS_BATTLE_BOND, [hl]
	jr nz, .no

	; TrueUserPartyAttr (home/battle.asm) reads whichever side is actually active,
	; the same turn-safe helper CheckAffection (effect_commands.asm) uses for its
	; own happiness-threshold check -- this function only ever runs in player-turn
	; context (called from TryBattleBond and the move-select toggle, both of which
	; run after SetPlayerTurn), so it always resolves to the player's own mon here.
	ld a, MON_HAPPINESS
	call TrueUserPartyAttr
	cp BOND_FRIENDSHIP_THRESHOLD
	jr nc, .eligible

	ld a, [wBattleMonItem]
	cp BOND_CHARM
	jr nz, .no

.eligible
	scf
	ret

.no
	and a
	ret

CanEnemyBattleBondNow::
; Same as CanBattleBondNow, but for the enemy's active Pokémon -- no item or
; friendship requirement at all (enemy trainer Pokémon have no meaningful friendship
; value by default, and the Bond Charm was only ever a stand-in eligibility gate
; used before the real global unlock flag + AI decision existed; it was never meant
; to stick around once those landed). Any TRAINER-owned enemy Pokémon that hasn't
; already Battle Bonded this battle is a candidate -- TryEnemyBattleBond's own
; unlock-flag check and AIWantsBattleBond's decision (or a tr_battle_bond override)
; are what actually gate whether/when it happens. Wild Pokémon are never eligible,
; full stop -- Battle Bond is framed as something a Trainer and their Pokémon build
; together, not something a wild mon has access to; wOtherTrainerClass is 0 in wild
; battles, nonzero in trainer battles (same check start_battle.asm's own trainer-vs-
; wild music selection already uses). Must be called during SetEnemyTurn context
; (hBattleTurn nonzero) so BATTLE_VARS_SUBSTATUS1 resolves to wEnemySubStatus1 below.
	ld a, [wOtherTrainerClass]
	and a
	jr z, .no

	ld a, BATTLE_VARS_SUBSTATUS1
	call GetBattleVarAddr
	bit SUBSTATUS_BATTLE_BOND, [hl]
	jr nz, .no

	scf
	ret

.no
	and a
	ret

TryEnemyBattleBond::
; Called once the enemy's move is chosen for the turn (freshly selected, not a
; continuing locked-in move), before it executes. Unlike the player's TryBattleBond,
; there's no toggle/menu step -- eligibility (CanEnemyBattleBondNow) always applies
; first, then a per-mon deterministic override (tr_battle_bond, if the current
; trainer set one) can force the outcome outright; failing that, the global unlock
; flag plus either "this is their last Pokémon" or a weighted, never-certain AI roll
; (AIWantsBattleBond) together decide whether it fires.
	call CanEnemyBattleBondNow
	ret nc

	; Deterministic override, if this trainer's current mon has one. Checked before
	; the unlock flag/AI roll since force-on needs to be able to fire even before
	; the player has unlocked Battle Bond globally (that's how the introductory
	; battle itself works) -- and force-off should block it unconditionally,
	; without even consulting the AI.
	ld a, [wCurOTMon]
	ld e, a
	ld d, 0
	ld hl, wEnemyBattleBondOverrides
	add hl, de
	ld a, [hl]
	cp BOND_OVERRIDE_OFF
	ret z
	cp BOND_OVERRIDE_ON
	jr z, .commit

	; No override: global unlock gate, then the normal last-mon/AI decision.
	ld de, EVENT_BATTLE_BOND_UNLOCKED
	ld b, CHECK_FLAG
	call EventFlagAction
	ret z

	call IsEnemyLastMonStanding
	jr c, .commit

	call AIWantsBattleBond
	ret nc

.commit
	ld a, [wEnemyMonSpecies]
	ld [wCurSpecies], a
	ld a, [wEnemyMonForm]
	ld [wCurForm], a
	call GetBaseData

	call CalcBattleBondStatBonuses
	call CalcEnemyMonBondStats

	ld de, FOCUS_ENERGY
	call PlayBattleBondAnim

	ld hl, BattleBondPoweredUpText
	call StdBattleTextbox
	ret

IsEnemyLastMonStanding:
; Returns carry if the enemy trainer has no Pokémon left alive besides whichever one
; is currently battling (i.e. this is their last mon) -- per the approved AI
; ruleset, Battle Bond should then trigger unconditionally, skipping
; AIWantsBattleBond's probabilistic decision entirely. Mirrors the alive-check loop
; GetSwitchScores (engine/battle/ai/switch.asm) already uses over the same array.
	push hl
	push bc
	ld hl, wOTPartyMon1
	ld a, [wOTPartyCount]
	ld b, a
	ld c, 0 ; count of party members still alive
.loop
	push hl
	ld de, MON_HP
	add hl, de
	ld a, [hli]
	or [hl]
	pop hl
	jr z, .dead
	inc c
.dead
	push bc
	ld bc, PARTYMON_STRUCT_LENGTH
	add hl, bc
	pop bc
	dec b
	jr nz, .loop

	pop bc
	pop hl
	ld a, c
	cp 1
	jr nz, .not_last
	scf
	ret
.not_last
	and a
	ret

; Bit numbers within wBattleBondAIFacts (ram/wram0.asm), AIWantsBattleBond's own
; scratch byte. Kept as one packed byte rather than juggling six separate booleans
; through registers across several farcalls -- registers don't survive a farcall,
; and this way each fact is simply set once, read once, with nothing to lose track
; of in between.
DEF BOND_FACT_TYPE_DISADVANTAGE EQU 0
DEF BOND_FACT_NOT_FULL_HP       EQU 1
DEF BOND_FACT_OUTSPEEDS_NOW     EQU 2
DEF BOND_FACT_BASELINE_KOS      EQU 3
DEF BOND_FACT_BOOSTED_KOS       EQU 4 ; only meaningful if BASELINE_KOS is clear
DEF BOND_FACT_BOOSTED_OUTSPEEDS EQU 5 ; only meaningful if OUTSPEEDS_NOW is clear

AIWantsBattleBond:
; Weighs a handful of live battle-state signals into a single percentage, then rolls
; against it -- see the approved Battle Bond AI ruleset for the reasoning behind
; each weight (BOND_AI_* constants above). Returns carry set if the enemy should
; Battle Bond this turn.
;
; The KO/outspeed checks below need to know what Battle Bond's stat boost would
; actually do, so this temporarily applies it for real (via
; CalcBattleBondStatBonuses/CalcEnemyMonBondStats -- both pure functions of
; level/EVs/base stats, so "undo" is just recomputing without the bonus) rather
; than approximating. Regardless of the final answer, wCurBaseData/wEnemyMonStats
; are always left back in their original (unboosted) state before returning --
; TryEnemyBattleBond re-applies the boost for real, separately, if this returns
; carry set; recomputing it again there is trivially cheap and keeps this
; function's own bookkeeping simple.
	xor a
	ld [wBattleBondAIFacts], a

	; --- Type disadvantage: reuse the switch-in AI's own matchup scorer wholesale
	; (engine/battle/ai/switch.asm) -- CheckPlayerMoveTypeMatchups is the entry
	; point that already hardcodes hl/bc to the CURRENTLY ACTIVE enemy mon's own
	; moves/type (as opposed to AICheckMatchupForEnemyMon directly, which
	; GetSwitchScores uses with hl/bc pointing at a hypothetical bench candidate
	; instead) -- checks the player's actual known moves against my typing, and
	; vice versa, symmetric, in one call. Result is 7-13, BASE_AI_SWITCH_SCORE
	; (10) is neutral; below it is bad for the enemy.
	farcall CheckPlayerMoveTypeMatchups
	cp BASE_AI_SWITCH_SCORE
	jr nc, .no_type_disadvantage
	ld hl, wBattleBondAIFacts
	set BOND_FACT_TYPE_DISADVANTAGE, [hl]
.no_type_disadvantage

	; --- Full HP check ---
	farcall AICheckEnemyMaxHP
	jr c, .is_full_hp
	ld hl, wBattleBondAIFacts
	set BOND_FACT_NOT_FULL_HP, [hl]
.is_full_hp

	; --- Currently outspeeds? (before any stat change) ---
	farcall AICompareSpeed
	jr nc, .not_faster_yet
	ld hl, wBattleBondAIFacts
	set BOND_FACT_OUTSPEEDS_NOW, [hl]
.not_faster_yet

	; --- Baseline KO check: damage from the already-chosen move, current stats ---
	call .GetChosenMoveIntoEnemyMoveStruct
	farcall AIDamageCalc
	call .DidThatMoveJustKO
	jr nc, .no_baseline_ko
	ld hl, wBattleBondAIFacts
	set BOND_FACT_BASELINE_KOS, [hl]
.no_baseline_ko

	; --- Trial-apply the Battle Bond stat boost for real ---
	call .ApplyBoostedStats

	; --- Would newly outspeed? ---
	farcall AICompareSpeed
	jr nc, .not_faster_boosted
	ld hl, wBattleBondAIFacts
	set BOND_FACT_BOOSTED_OUTSPEEDS, [hl]
.not_faster_boosted

	; --- Would newly KO? (same move, now-boosted stats) ---
	call .GetChosenMoveIntoEnemyMoveStruct
	farcall AIDamageCalc
	call .DidThatMoveJustKO
	jr nc, .no_boosted_ko
	ld hl, wBattleBondAIFacts
	set BOND_FACT_BOOSTED_KOS, [hl]
.no_boosted_ko

	; --- Revert to the real (unboosted) stats before deciding anything ---
	ld a, [wEnemyMonSpecies]
	ld [wCurSpecies], a
	ld a, [wEnemyMonForm]
	ld [wCurForm], a
	call GetBaseData
	call CalcEnemyMonBondStats

	; --- Combine into a percentage ---
	ld a, [wBattleBondAIFacts]
	ld c, a
	ld b, BOND_AI_BASE_CHANCE

	; KO bonus: baseline doesn't KO, but boosted does.
	bit BOND_FACT_BASELINE_KOS, c
	jr nz, .skip_ko_bonus
	bit BOND_FACT_BOOSTED_KOS, c
	jr z, .skip_ko_bonus
	ld a, b
	add BOND_AI_KO_BONUS
	ld b, a
.skip_ko_bonus

	; Speed bonus: not already faster, boosted would be, and no type disadvantage.
	bit BOND_FACT_OUTSPEEDS_NOW, c
	jr nz, .skip_speed_bonus
	bit BOND_FACT_BOOSTED_OUTSPEEDS, c
	jr z, .skip_speed_bonus
	bit BOND_FACT_TYPE_DISADVANTAGE, c
	jr nz, .skip_speed_bonus
	ld a, b
	add BOND_AI_SPEED_BONUS
	ld b, a
.skip_speed_bonus

	; HP penalty.
	bit BOND_FACT_NOT_FULL_HP, c
	jr z, .skip_hp_penalty
	ld a, b
	sub BOND_AI_HP_PENALTY
	jr nc, .hp_penalty_applied
	xor a
.hp_penalty_applied
	ld b, a
.skip_hp_penalty

	; Type penalty.
	bit BOND_FACT_TYPE_DISADVANTAGE, c
	jr z, .skip_type_penalty
	ld a, b
	sub BOND_AI_TYPE_PENALTY
	jr nc, .type_penalty_applied
	xor a
.type_penalty_applied
	ld b, a
.skip_type_penalty

	; Clamp to the max, then roll.
	ld a, b
	cp BOND_AI_MAX_CHANCE + 1
	jr c, .under_max
	ld a, BOND_AI_MAX_CHANCE
.under_max
	ld b, a
	ld a, 100
	call RandomRange ; a = uniform [0, 99]
	cp b
	jr nc, .main_roll_failed
	scf
	ret

.main_roll_failed
	; Flat, final wildcard chance even when everything above says no.
	ld a, 100
	call RandomRange
	cp BOND_AI_FALLBACK_PCT
	ret nc
	scf
	ret

.GetChosenMoveIntoEnemyMoveStruct:
; Loads wEnemyMoveStruct with the move the AI already locked in for this turn
; (wCurEnemyMoveNum, a 0-based slot index into wEnemyMonMoves -- same convention
; ParseEnemyAction's own .finish block, engine/battle/core.asm, already uses).
	ld a, [wCurEnemyMoveNum]
	ld c, a
	ld b, 0
	ld hl, wEnemyMonMoves
	add hl, bc
	ld a, [hl]
	farcall AIGetEnemyMove
	ret

.DidThatMoveJustKO:
; Returns carry if wCurDamage (the last AIDamageCalc result) meets or exceeds the
; player's current HP. Same comparison AI_Risky (engine/battle/ai/scoring.asm)
; already uses to detect a lethal move.
	ld a, [wCurDamage + 1]
	ld e, a
	ld a, [wCurDamage]
	ld d, a
	ld a, [wBattleMonHP + 1]
	cp e
	ld a, [wBattleMonHP]
	sbc d
	ret nc
	scf
	ret

.ApplyBoostedStats:
	ld a, [wEnemyMonSpecies]
	ld [wCurSpecies], a
	ld a, [wEnemyMonForm]
	ld [wCurForm], a
	call GetBaseData
	call CalcBattleBondStatBonuses
	jmp CalcEnemyMonBondStats

TryBattleBond::
; Called once the player's move is locked in for the turn, before it executes (i.e.
; before the move's own animation runs). If the player toggled Battle Bond on and the
; active Pokémon is eligible: recompute its Attack/Defense/SpAtk/SpDef/Speed with the
; tiered bonus, recolor its sprite red, then play the Focus Energy animation and a
; "<mon> powered up!" message. The message ends on a prompt, which blocks until the
; player dismisses it, so the move's own animation can't start until this one has
; been seen and cleared. Species/form/type/ability/sprite graphic are all left
; alone -- only wBattleMon*/wCur* (transient, in-battle state) are touched, so
; switching out, fainting, or ending the battle reverts the stats for free. The
; palette override reverts for free too: every send-out unconditionally reloads the
; active mon's palette from scratch (see the patch in engine/gfx/color.asm), and that
; reload already checks this same flag, which is cleared here.
	ld a, [wBattleBondToggled]
	and a
	ret z
	xor a
	ld [wBattleBondToggled], a

	call CanBattleBondNow
	ret nc

	; wCurBaseData is a shared scratch buffer that other code may have overwritten
	; since send-out -- explicitly refresh it for the active battler's species/form
	; before relying on it (same precaution Mega Evolution's trigger takes).
	ld a, [wBattleMonSpecies]
	ld [wCurSpecies], a
	ld a, [wBattleMonForm]
	ld [wCurForm], a
	call GetBaseData

	call CalcBattleBondStatBonuses
	call CalcBattleMonBondStats

	; See PlayBattleBondAnim below for why this doesn't just farcall
	; PlayBattleAnimDE directly.
	ld de, FOCUS_ENERGY
	call PlayBattleBondAnim

	; BattleBondPoweredUpText is defined in data/text/battle.asm, not here --
	; StdBattleTextbox's real implementation is hardcoded to run from bank 20
	; (it farjps there internally regardless of the caller's own bank), so any
	; text it prints must actually live in bank 20 too, the same as every
	; other battle message (e.g. GettingPumpedText, right next to it).
	ld hl, BattleBondPoweredUpText
	call StdBattleTextbox
	ret

PlayBattleBondAnim:
; Plays the animation in de, mirroring PlayBattleAnimDE + PlayBattleAnim +
; _PlayBattleAnim (engine/battle/core.asm, engine/battle_anims/anim_commands.asm)
; line for line -- except the palette flag is set and reloaded (via
; FinishBattleAnim) in the middle, immediately before the script itself starts
; running (the farcall BattleAnimRunScript below), rather than before or after
; the whole animation call.
;
; Both of those simpler options were tried first and didn't work: setting the
; flag/reloading before calling the animation at all left the recolor visible
; during _PlayBattleAnim's own ~7-frame startup (the DelayFrames(6) and
; DelayFrame below, which run before the script's visuals start at all) --
; several visibly red frames before anything masks it. Reloading after
; PlayBattleAnimDE returned put it after a separate, always-perceptible gap
; instead (WaitSFX plus BattleAnimRunScript's own internal HUD-restore/
; palette-revert cleanup). Landing it right here, between the startup and the
; script itself, means the recolor happens at most one frame before Focus
; Energy's script starts its own white/yellow charge-up flash (an OBP0 shade
; remap) -- which is what actually masks it.
	ld a, e
	ld [wFXAnimIDLo], a
	ld a, d
	ld [wFXAnimIDHi], a
	call ApplyTilemapInVBlank

	farcall CheckBattleAnimSubstitution
	ldh a, [rWBK]
	ld [wMoveSwapBuffer], a ; also kept here for the mid-sequence restore below
	push af
	ld a, 5
	ldh [rWBK], a

	ld c, 6
	call DelayFrames

	farcall BattleAnimAssignPals
	farcall BattleAnimRequestPals
	call DelayFrame

	ld c, 1
	ldh a, [rSPD]
	bit 7, a
	jr nz, .got_speed
	ld c, 3

.got_speed
	ld hl, hVBlank
	ld a, [hl]
	push af
	ld [hl], c

	ld a, BATTLE_VARS_SUBSTATUS1
	call GetBattleVarAddr
	set SUBSTATUS_BATTLE_BOND, [hl]

	; FinishBattleAnim reloads both the player's AND enemy's palettes together
	; (_CGB_BattleColors), and does so assuming the normal WRAM bank is active
	; -- not bank 5, the animation engine's own scratch bank set above. Calling
	; it while still on bank 5 was cross-contaminating the enemy's palette
	; with the player's, tinting the enemy sprite red too. Restore the real
	; bank just for this call, then switch back to 5 for the rest of the
	; animation.
	ld a, [wMoveSwapBuffer]
	ldh [rWBK], a
	call FinishBattleAnim
	ld a, 5
	ldh [rWBK], a

	farcall BattleAnimRunScript

	pop af
	ldh [hVBlank], a

	ld a, $1
	ldh [hBGMapMode], a

	ld c, 3
	call DelayFrames
	call WaitSFX

	pop af
	ldh [rWBK], a
	ret

; Scratch layout used below, inside wBattleBondStatsBuffer (12 bytes, otherwise
; unused until CalcBattleMonBondStats runs afterward -- reusing it here avoids
; needing any new WRAM, since WRAMX has zero bytes free): offsets 0-4 hold the 5 base
; stats (display order), offset 5 is the loop counter (i, reused for both the ranking
; pass and the bonus pass below), offset 6 is the inner loop counter (j, ranking pass
; only), offsets 7-11 hold each stat's computed rank (one byte per stat, ranks[i] at
; offset 7+i). (These can't be named EQU constants -- wBattleBondStatsBuffer's address
; isn't known until link time, so only direct "wBattleBondStatsBuffer + N" expressions
; work, not an EQU alias built from it.)

CalcBattleBondStatBonuses:
; wCurBaseData must already hold the current species+form's base data (TryBattleBond
; refreshes it via GetBaseData just before calling this). Reads
; Attack/Defense/SpAtk/SpDef/Speed into wBattleBondStatsBuffer + 0 in DISPLAY order
; (Atk, Def, SpAtk, SpDef, Speed -- the order they're shown on the Stats page).
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
; untouched) so CalcBattleMonBondStats can feed them straight into the normal stat
; formula.
	ld a, [wCurBaseData + BASE_ATK]
	ld [wBattleBondStatsBuffer + 0], a
	ld a, [wCurBaseData + BASE_DEF]
	ld [wBattleBondStatsBuffer + 1], a
	ld a, [wCurBaseData + BASE_SAT]
	ld [wBattleBondStatsBuffer + 2], a
	ld a, [wCurBaseData + BASE_SDF]
	ld [wBattleBondStatsBuffer + 3], a
	ld a, [wCurBaseData + BASE_SPE]
	ld [wBattleBondStatsBuffer + 4], a

	; Pass 1: compute ranks[i] for i = 0..4 into offsets 7-11, without ever
	; writing to offsets 0-4 (the stat values).
	xor a
	ld [wBattleBondStatsBuffer + 5], a
.rank_outer_loop
	; ranks[i] = 0
	ld a, [wBattleBondStatsBuffer + 5]
	ld c, a
	ld b, 0
	ld hl, wBattleBondStatsBuffer + 7
	add hl, bc
	xor a
	ld [hl], a

	xor a
	ld [wBattleBondStatsBuffer + 6], a
.rank_inner_loop
	ld a, [wBattleBondStatsBuffer + 6]
	ld hl, wBattleBondStatsBuffer + 5
	cp [hl]
	jr z, .rank_next_j

	ld a, [wBattleBondStatsBuffer + 6]
	ld c, a
	ld b, 0
	ld hl, wBattleBondStatsBuffer + 0
	add hl, bc
	ld a, [hl] ; a = statVal[j]

	ld c, a
	ld a, [wBattleBondStatsBuffer + 5]
	ld hl, wBattleBondStatsBuffer + 0
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
	ld a, [wBattleBondStatsBuffer + 6]
	ld hl, wBattleBondStatsBuffer + 5
	cp [hl]
	jr nc, .rank_not_dominator
.rank_dominator
	ld a, [wBattleBondStatsBuffer + 5]
	ld c, a
	ld b, 0
	ld hl, wBattleBondStatsBuffer + 7
	add hl, bc ; hl = &ranks[i]
	inc [hl]
.rank_not_dominator
.rank_next_j
	ld hl, wBattleBondStatsBuffer + 6
	inc [hl]
	ld a, [hl]
	cp 5
	jr nz, .rank_inner_loop

	ld hl, wBattleBondStatsBuffer + 5
	inc [hl]
	ld a, [hl]
	cp 5
	jr nz, .rank_outer_loop

	; Pass 2: apply each stat's bonus using its stored rank, saturating at 255.
	xor a
	ld [wBattleBondStatsBuffer + 5], a
.bonus_loop
	ld a, [wBattleBondStatsBuffer + 5]
	ld c, a
	ld b, 0
	ld hl, wBattleBondStatsBuffer + 7
	add hl, bc ; hl = &ranks[i]
	ld a, [hl] ; a = rank
	ld hl, BattleBondBonusByRank
	ld e, a
	ld d, 0
	add hl, de
	ld a, [hl] ; a = bonus
	ld e, a    ; e = bonus, held here so it survives the address math below

	ld a, [wBattleBondStatsBuffer + 5]
	ld c, a
	ld b, 0
	ld hl, wBattleBondStatsBuffer + 0
	add hl, bc ; hl = &statVal[i]

	ld a, [hl]
	add e
	jr nc, .bonus_no_overflow
	ld a, 255
.bonus_no_overflow
	ld [hl], a

	ld hl, wBattleBondStatsBuffer + 5
	inc [hl]
	ld a, [hl]
	cp 5
	jr nz, .bonus_loop

	; Write the boosted stats back into wCurBaseData, in its own storage order.
	ld a, [wBattleBondStatsBuffer + 0]
	ld [wCurBaseData + BASE_ATK], a
	ld a, [wBattleBondStatsBuffer + 1]
	ld [wCurBaseData + BASE_DEF], a
	ld a, [wBattleBondStatsBuffer + 2]
	ld [wCurBaseData + BASE_SAT], a
	ld a, [wBattleBondStatsBuffer + 3]
	ld [wCurBaseData + BASE_SDF], a
	ld a, [wBattleBondStatsBuffer + 4]
	ld [wCurBaseData + BASE_SPE], a
	ret

BattleBondBonusByRank:
	db 25, 25, 20, 20, 10

CalcBattleMonBondStats:
; Recomputes Attack/Defense/Speed/SpAtk/SpDef into wBattleMonStats from the
; (now-boosted, courtesy of CalcBattleBondStatBonuses) wCurBaseData, using the active
; battler's real level/DVs/EVs. Never touches wBattleMonHP/MaxHP (Battle Bond doesn't
; change max HP) or the party struct. Same approach as Mega Evolution's battle-only
; stat recompute.
	ld a, [wCurPartyMon]
	push af
	ld a, [wCurBattleMon]
	ld [wCurPartyMon], a

	ld a, MON_LEVEL
	call GetPartyParamLocationAndValue
	ld [wCurPartyLevel], a

	ld a, MON_EVS - 1
	call GetPartyParamLocationAndValue ; hl = EVs - 1

	ld de, wBattleBondStatsBuffer
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

	ld hl, wBattleBondStatsBuffer + 2 ; skip the HP entry
	ld de, wBattleMonStats
	ld bc, 10
	rst CopyBytes
	ret

CalcEnemyMonBondStats:
; Same as CalcBattleMonBondStats, but for the enemy's active battler -- reads its
; level/EVs from wOTPartyMons (via OTPartyAttr, home/battle.asm) instead of
; wPartyMons, and writes the result into wEnemyMonStats instead of wBattleMonStats.
; Trainer-owned Pokémon are never Hyper Trained in this game's trainer data (see
; read_trainer_party.asm's own "ld b, TRUE" before its CalcPkmnStats call), so this
; skips the GetHyperTraining lookup the player-side version needs and just always
; applies EVs.
	ld a, MON_LEVEL
	call OTPartyAttr
	ld [wCurPartyLevel], a

	ld a, MON_EVS - 1
	call OTPartyAttr ; hl = EVs - 1

	ld de, wBattleBondStatsBuffer
	ld b, TRUE
	farcall CalcPkmnStats

	ld hl, wBattleBondStatsBuffer + 2 ; skip the HP entry
	ld de, wEnemyMonStats
	ld bc, 10
	rst CopyBytes
	ret

BattleBondOnText::
	db "B@"

BattleBondOffText::
	db "b@"
