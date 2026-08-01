# Planned Features

Design/feasibility notes for features under consideration, kept here so implementation can be picked up later without re-deriving the research. Nothing in this file has been implemented yet.

## Custom Signature Abilities

### Context

Goal: give every unique evolutionary line its own distinctive ability, instead of many unrelated lines sharing the same generic pick. The existing roster is large — 166 abilities already implemented in `constants/ability_constants.asm`, essentially the full real Pokémon ability list through Gen 9 — so most of the work is curating what's already there (a deliberately-shared "generic" pool vs. a cull list of weak/narrow filler) before deciding how many genuinely new, invented abilities are worth building on top.

ROM space is the real constraint, not ability-ID space (ability slots are single bytes, room for ~90 more IDs before the byte ceiling). This build targets a fixed 128×16KB = 2MB ROM (MBC3); recent builds report only ~26-28KB free, concentrated almost entirely in the last one-and-a-half of 128 banks (bank $7F entirely empty, $7E ~10KB free) — every other bank is full. That pool is shared with whatever else gets built later (Mega Evolution, held items, etc.), not a dedicated abilities budget.

Sampling real per-ability code sizes in `engine/battle/abilities.asm` (`TraceAbility`/`AnticipationAbility` ~70 lines each, `IntimidateAbility`/`DownloadAbility` ~37-38 lines each, simple status-immunity abilities as little as 4 bytes via a shared handler) gives a working estimate of ~100-250 bytes per new, non-trivial custom ability (handler + jump-table row + name/description text), assuming it reuses an existing trigger hook (on-switch-in, on-contact, on-status, on-weather, stat-mod) rather than needing a brand-new hook mechanism. Culling the weak/filler abilities below frees relatively little on its own (~2KB) since most of them are already cheap thunks into shared handlers, not big dedicated routines.

**Feasibility verdict: roughly 60-100 new custom abilities are realistically buildable** within the ~28-30KB combined budget (baseline free space + culling gains), enough to cover every one of the ~120-150 distinct evolutionary lines currently in the dex, provided most lean on existing trigger patterns and this doesn't have to compete hard with several other big features landing at the same time.

### Generic pool (keep, safe to spread across many unrelated species)

Mechanically simple, or already an explicit "same effect, reflavored" family reused across canon species — repeating these further costs nothing narratively:

- **Single-status immunity family**: Limber, Insomnia, Vital Spirit, Immunity, Water Veil, Magma Armor, Own Tempo, Pastel Veil
- **On-contact status family**: Static, Flame Body, Poison Point, Effect Spore, Poison Touch, Cute Charm
- **Type-absorb/immunity family**: Volt Absorb, Water Absorb, Flash Fire, Sap Sipper, Motor Drive, Lightning Rod
- **Weather-setter family**: Drizzle, Drought, Sand Stream, Snow Warning
- **Weather-synergy family**: Swift Swim, Chlorophyll, Sand Rush, Slush Rush, Solar Power, Hydration, Leaf Guard, Rain Dish, Dry Skin, Ice Body, Sand Veil, Snow Cloak
- **Stat-drop immunity family**: Clear Body, White Smoke, Hyper Cutter, Keen Eye
- **Crit-immunity pair**: Battle Armor, Shell Armor
- **Starter-triad low-HP boost**: Overgrow, Blaze, Torrent, Swarm
- **Popular, mechanically-simple "safe to hand out" utility**: Intimidate, Levitate, Guts, Technician, Sturdy, Adaptability, Multiscale, Regenerator, Prankster, Contrary, Unaware, Magic Guard, Mold Breaker, Sheer Force, Moxie, Reckless, Iron Fist, Skill Link, Fur Coat, Tinted Lens, Filter, Solid Rock, Infiltrator, Rock Head, Scrappy, Analytic, Defiant, Competitive, Huge Power, Pressure, Thick Fat, Serene Grace, Natural Cure, Synchronize, Pickup, Hustle, Shed Skin, Unburden

### Cull list (mostly useless, or narrow-but-not-flavorful filler)

Stench, Damp, Cloud Nine, Shield Dust, Suction Cups, Illuminate, Soundproof, Run Away, Sticky Hold, Tangled Feet, Rivalry, Steadfast, Sniper, Super Luck, Bad Dreams, Pickpocket, Cursed Body, Light Metal, Harvest, Overcoat, Big Pecks, Wonder Skin, Rattled, Bulletproof, Corrosion, Fluffy, Tangling Hair, Screen Cleaner, Steely Spirit, Quick Draw, Cud Chew, Armor Tail, Minds Eye

(33 abilities. Originally also included Gluttony, Anger Point, Aftermath, Weak Armor, Sand Force, Mega Launcher, Perish Body, and Wind Rider — removed from the cull list per review; those 8 are kept as-is, species-specific, same as the "remainder" bucket below, not moved into the generic pool.)

### Remainder (kept as-is, not touched)

Everything not listed in either pool above (~85 abilities) stays exactly as it is now — already a good, distinctive, appropriately-limited signature fit for its current species/line. Notable examples: Trace, Imposter, Download, Anticipation, Forewarn, Shadow Tag, Arena Trap, Moody, No Guard, Magic Bounce, Parental Bond, Gorilla Tactics, Neutralizing Gas, Magnet Pull, Liquid Ooze, Poison Heal, Pixilate, Galvanize — plus the 8 reprieved-from-cull abilities noted above.

### Next steps (not yet started)

1. Audit which evolutionary lines currently share a generic-pool ability vs. already have a good unique one, to find the actual list of lines that need a brand-new invented ability.
2. Design the new abilities themselves (effect, name, description) for that list, reusing existing trigger hooks wherever possible to stay within the ROM budget above.
3. Reassign cull-list abilities off their current species onto either the generic pool or a new invented ability, species by species.

## Mega Evolution

### Context

Follows on from an earlier byte-width investigation (moves are capped at 255; species already extend past 255, to a 9-bit/511 range, via a stolen bit in the personality byte). The question was whether Mega Evolution — (1) a mid-battle form change affecting sprite/typing/stats, (2) a data entry for the mega form's stats, and (3) Mega Stones with a holding-check — is theoretically buildable on top of the existing engine, and if so, what it would take.

The feature decomposes into three subsystems of very different cost: the **data layer** (new form/stats/sprite entries) is essentially free, reusing an existing pattern; the **battle-engine transformation** (recompute types/stats/ability, reload sprite) is moderate, closely modeled on an existing mid-battle mechanic; and the **item layer** (stones that select which Pokémon can transform) is the real constraint, because the item-ID space is already 100% full.

Two scope decisions were settled to keep this concrete rather than open-ended:
- **Mega Stones are per-type, not per-species** (a "Fire Mega Stone" works for any Fire-type Mega, not one item per Mega-capable species). This cuts the number of new items needed from ~50 to at most 18 (one per type), further scoped down below to what's actually free to reclaim.
- **Mega Evolution is a player-chosen toggle** on the move-select screen, matching the real games, not an automatic on-holding trigger.

### Part 1 — Data layer: new Mega Form entries (cheap, fully precedented)

Existing pattern to clone directly: **Mewtwo's Armored Form** (`data/pokemon/variant_forms.asm:69`, sprite row `data/pokemon/pic_pointers.asm:366`) and **Arcanine's Hisuian Form** (`data/pokemon/base_stats/arcanine_hisuian.asm`) already give one species multiple independent `BaseData` rows — different stats, different type(s), different ability, different sprite — selected by form byte. A Mega Form is structurally identical to these: it's just another form.

Per Mega-capable species, add:
1. A new `BaseData` row (`data/pokemon/base_stats/<name>_mega.asm`, following the existing per-species file pattern, `constants/pokemon_data_constants.asm` field layout — HP/Atk/Def/Spe/SAtk/SDef, Type1/2, single fixed ability in all 3 ability slots since Mega forms have one non-negotiable ability).
2. A `VariantSpeciesAndFormTable` mapping entry (`data/pokemon/variant_forms.asm`) so `GetSpeciesAndFormIndex` resolves the mega form byte to this row.
3. A `PokemonPicPointers` row (`data/pokemon/pic_pointers.asm`, `pics <Name>` macro) plus new front/back sprite art under `gfx/pokemon/<name>_mega/`.

No struct or constant-width changes needed anywhere in this part.

### Part 2 — Item layer: Type Mega Stones (the real constraint)

**The blocker:** `constants/item_constants.asm:323,325` — `MIRAGE_MAIL` at `0xFE` is the last item, `NUM_ITEMS = 254`, and `0xFF` is permanently reserved as the `ITEM_FROM_MEM`/`ALWAYS_ITEM_2` sentinel (line 328-329). **Zero item IDs are free.** Any new item — even one — requires either freeing an existing slot or widening item-ID storage everywhere it's read/written/compared (bag arrays, `MON_ITEM` party field, `wBattleMonItem`, script `additem`/`giveitem` args, `ItemAttributes` indexing). Unlike species, items have no adjacent spare bit anywhere to steal the way `MON_EXTSPECIES` reused a personality-byte bit — this would be a broad, invasive change, so it is **not** the recommended path.

**Recommended source of free slots:** the 10 cosmetic Mail items (`constants/item_constants.asm:313-324`, `FLOWER_MAIL` through `MIRAGE_MAIL`). These are flavor-only held items (attach a note, no battle mechanics), the safest reclaim target in the whole item table. Repurposing all 10 frees exactly 10 item IDs — enough for **10 Type Mega Stones**, not the full 18-type roster. Getting to all 18 needs 8 more freed slots from some other low-value category (not identified yet — would need a follow-up audit of vestigial/rarely-used items), or the roster simply ships with 10 types covered and expands later.

**Data-side cost is trivial once slots exist:** `data/items/attributes.asm` + `constants/item_data_constants.asm:108-201` already support this exact shape — existing type-boost items (Charcoal, Mystic Water) use `held_effect = HELD_TYPE_BOOST` with `param = <type>`. Add one new `HELD_MEGA_STONE` effect (list terminates at `NUM_HELD_ITEM_TYPES`, `item_data_constants.asm:219` — plenty of room here, this isn't the constrained axis) with `param = <type>`, and give each repurposed item ID a new name/description/icon and this held-effect. This is a pure data change once the ID slot exists.

### Part 3 — Battle engine: the transformation itself

**Best existing precedent (stronger than the `Transform` move):** `EvolveDuringBattle` (`engine/battle/evolve_battle.asm:1-140`). Verified directly — it already does everything a Mega trigger needs, on a live battler, without a full battle re-init:
- Re-copies species/form/moves/DVs/level/stats from the party struct into `wBattleMon*` (`.load_mon_data`, lines 38-86).
- Recomputes type via `GetBaseData` → copies `wBaseType1`/`wBaseType2` into `wBattleMonType1`/`wBattleMonType2` (lines 73-77) — a trivial, safe-to-repeat 2-byte copy.
- **Reloads the battle sprite mid-turn** via `call GetMonBackpic` (line 120) — proof that sprite reload outside initial send-out is already safe (bank switching / VRAM timing handled inside `GetMonBackpic`).
- Resets ability via `ResetPlayerAbility` and re-triggers switch-in-style ability effects via `RunEntryAbilitiesInner` (lines 138-139) — ability is stored in standalone `wPlayerAbility`/`wEnemyAbility` (`ram/wram0.asm:370,379`), not the battle-mon struct, so overwriting it for the Mega's fixed ability is a 1-byte write via the same mechanism.

**The one genuinely new piece:** stats are *not* recomputed here — `EvolveDuringBattle` copies pre-computed stats from the party struct (which was updated earlier by `CalcPkmnStats`, `engine/pokemon/mon_stats.asm:654-881`). A Mega transformation must instead **call `CalcPkmnStats` directly against the Mega `BaseData`'s stats**, feeding it the mon's existing DVs/EVs/level/nature, and write the result straight into `wBattleMonStats` — without ever touching the persisted party struct. This is a new, self-contained routine modeled on the existing call pattern, not a new mechanism.

**Reverting is nearly free by construction:** because the Mega transformation only ever touches the runtime `wBattleMon*`/`wEnemyMon*` struct and never the party struct, switching out, fainting, or ending the battle already fully restores the original form for free (send-in code, `SendInUserPkmn`, `engine/battle/core.asm:1150`, always re-populates from the party struct from scratch).

**Once-per-battle flag:** three spare bits already exist and are unused — `wPlayerSubStatus1` bit 4, `wPlayerSubStatus2` bit 0, `wPlayerSubStatus4` bit 1 (`ram/wram0.asm:310-354`, mirrored for `wEnemySubStatus*`). Use one of these as "already Mega Evolved this battle," following the existing `SUBSTATUS_x` bit-test pattern used throughout `core.asm`/`effect_commands.asm`.

**Scope note:** `EvolveDuringBattle`'s sprite reload is player-side only (`GetMonBackpic`). Enemy-side (AI trainer) Mega Evolution would need the enemy equivalent (`GetMonFrontpic`) proven at a mid-battle call site — not confirmed. **Recommend scoping v1 to the player's Pokémon only**; AI trainers Mega Evolving is a separate stretch goal needing its own AI decision logic anyway (when should the AI choose to Mega Evolve?).

### Part 4 — UI: player-chosen toggle on the move-select screen

This is the largest *new* (non-precedented) chunk of engineering, because — unlike an automatic on-holding trigger — it needs real player-facing interaction:

- **Gating logic** (evaluated when entering the Fight submenu, `engine/battle/menu.asm` / `BattleMenu_Fight`, `engine/battle/core.asm:4303`): active Pokémon holds a Mega Stone whose type matches one of the Mega form's types, that species has a Mega form defined (Part 1 data), and the once-per-battle flag (Part 3) isn't already set.
- **Toggle state + indicator:** a new UI element next to/within the move-select screen (mirrors real games' Mega icon next to Fight) with its own sprite and cursor/input handling, distinct from move selection itself — this needs new state (is the toggle currently on for this turn's action) threaded through `ParsePlayerAction`/`PerformMove` so the transformation actually fires at the right point in the turn (before move resolution, likely right alongside where `EvolveDuringBattle`-style hooks are invoked).
- **Interaction edges to handle:** back/cancel out of move selection must not consume the "already Mega Evolved" flag; the toggle must reset each turn if not confirmed; Mega Evolving must be blocked if the Pokémon is about to switch out/is fainting this turn.

This part has no close existing analog in the codebase (the closest is the Fight/PKMN/Pack/Run menu cursor itself) and would need to be designed and iterated on directly rather than cloned from a precedent — flagged as the highest-uncertainty piece of the whole feature.

### Summary verdict

| Subsystem | Cost | Precedent reused |
|---|---|---|
| Mega Form data (stats/type/ability/sprite) | Low | Mewtwo Armored Form / Arcanine Hisuian Form pattern |
| Mega Stones (per-type, 10 via reclaimed Mail slots) | Medium (item-ID scarcity is the ceiling) | Existing `HELD_TYPE_BOOST` item pattern |
| Mid-battle transform engine (types/stats/ability/sprite, revert-for-free) | Medium | `EvolveDuringBattle` (`engine/battle/evolve_battle.asm`) |
| Move-select Mega toggle UI | Medium-High (least precedented) | Fight/PKMN/Pack/Run menu as a loose structural reference only |

**Overall: yes, theoretically buildable**, scoped to 10 types' worth of Mega Stones (expandable later if more item slots are freed or item-ID storage is eventually widened) and player's-own-Pokémon-only Mega Evolution for v1. No part of it is blocked outright the way move IDs are blocked at 255 — the item-ID scarcity is a real constraint but has a concrete, safe workaround (reclaiming the 10 Mail items) rather than a hard wall.

### Verification approach (whenever this moves to implementation)

Build the ROM (`./build.sh`) after each subsystem lands, then in an emulator confirm (a) a mega-eligible mon's stats/type/sprite change correctly on toggling in battle, (b) switching out / fainting / battle-ending correctly reverts to the base form with no corruption of the saved party data, (c) the once-per-battle flag actually prevents re-triggering, and (d) a non-eligible mon (wrong/no stone, or already mega-evolved this battle) cannot toggle it.
