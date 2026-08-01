# Polished Crystal — Personal Fork

This is my own personal, customized version of **Polished Crystal**, a Pokémon Crystal ROM hack (Game Boy Color, RGBDS assembly) built on the [pret/pokecrystal](https://github.com/pret/pokecrystal) disassembly. I use this repo to make my own gameplay tweaks and experiments on top of the official project, while staying able to freely pull in upstream's ongoing updates.

- **Official upstream project:** [Rangi42/polishedcrystal](https://github.com/Rangi42/polishedcrystal)
- **My fork (GitHub remote):** [Barmy90/polishedcrystal](https://github.com/Barmy90/polishedcrystal)

See `README.md`, `FEATURES.md`, `CHANGELOG.md`, and `TODO.md` for the official project's own documentation. `Planned Features.md` (untracked, personal) holds design/feasibility notes for features I'm considering adding myself.

## Git workflow

The core rule: **`master` is a pristine mirror of upstream. All personal work happens on branches, never on `master`.**

### Remotes

- `origin` → my fork (`Barmy90/polishedcrystal`)
- `upstream` → the official project (`Rangi42/polishedcrystal`)

### Branches

- `master` — tracks `upstream/master` exactly. Never commit here directly.
- `my-changes` — original general-purpose personal work branch, created off `master`. Currently inactive/unused: in practice each feature or fix gets its own dedicated branch (below) instead of piling everything onto one shared branch. Still fine to use for small, disposable one-off edits that don't warrant their own branch.
- `mega-evolution` — early scaffold branch prototyping a Mega Evolution mechanic (Mewtwo → Armored Mewtwo). Superseded by `z-evolution` below, which branched off it and evolved into a different, unrelated mechanic. Kept around for history/reference, not under active development.
- `z-evolution` — despite the name, this is the **Battle Bond** feature branch (a custom battle mechanic, unrelated to canon Mega Evolution/Z-Moves/Ash-Greninja's actual trigger condition — Battle Bond here is a renamed, redesigned evolution of the original Z-Evolution/Mega Evolution prototype this branch started from). All Battle Bond design/bug-fix work belongs here: eligibility rules, the AI's decision to use it, palette/animation, `engine/battle/battle_bond.asm`, `data/text/battle.asm`'s Battle Bond text, the Bond Charm item, and the `EVENT_BATTLE_BOND_UNLOCKED` unlock flag.
- `stat-changes` — general gameplay/content tuning that isn't Battle Bond: Pokémon stat/movepool reworks (e.g. Quilava/Typhlosion), shop/mart inventory changes (e.g. Goldenrod's evolution-stone stock), and wild encounter table edits (e.g. adding Mankey to Route 46). Default home for "just a tweak" changes that don't need their own dedicated branch.
- `encounter-rate-fix` — narrow bugfix branch, off `master`, for the wild-encounter-rate regression in `engine/overworld/wildmons.asm` (an upstream bug from commit `cb973fdd5`, not something introduced by any local branch). Branched off `master` rather than a feature branch because it's a correctness fix unrelated to any one feature — everyone benefits from it regardless of which features they've got merged in.
- `test-combined` — integration-only branch. Merges the latest state of `z-evolution`, `stat-changes`, `encounter-rate-fix`, and any other active feature/fix branches together, purely for full-game playtesting and producing a single playable `.gbc`. It is never the source of truth for any individual feature or fix — those always live and get fixed on their own dedicated branch first, then get re-merged here. Safe to treat as disposable/recreatable from its component branches at any time.
- Additional short-lived branches can be created off `master` for new large/experimental features or standalone fixes I might want to keep separate or abandon independently, following the same pattern as `z-evolution`/`stat-changes`/`encounter-rate-fix` above. Branches are cheap — don't hesitate to make more.

### Bringing upstream updates into `master`

Run this whenever I want the latest official changes:

```bash
git fetch upstream
git checkout master
git merge upstream/master      # always a clean fast-forward, since master is never modified directly
git push origin master         # optional: mirrors the update to my GitHub fork
```

### Bringing those updates into a personal/feature branch

After `master` is updated, sync whichever branch(es) need it on top of it (same command shape for `my-changes`, `z-evolution`, `stat-changes`, or any other feature branch — substitute the branch name):

```bash
git checkout <branch-name>
git rebase master               # replays my commits on top of the updated master
# or: git merge master          # simpler, creates a merge commit instead of rewriting history
```

Rebase keeps history linear/clean but rewrites commits; merge is simpler to reason about and never rewrites history. Either is fine — rebase is preferred if there's no strong reason not to, but merge is the safer default when in doubt (e.g. if the branch has already been pushed/shared somewhere).

### Day-to-day workflow

1. Make sure I'm on the branch that actually owns this kind of change (see Branches above — Battle Bond work goes on `z-evolution`, general tuning on `stat-changes`, standalone bugfixes on their own branch off `master`, etc.): `git checkout <branch-name>`
2. Edit, build (`./build.sh`), test as normal.
3. `git add` / `git commit` as usual — commit freely, these branches are mine.
4. Push to my fork when I want a remote backup or to open a PR: `git push origin <branch-name>`
5. Periodically pull upstream changes into `master` (above), then rebase/merge each active feature branch on top.
6. To playtest everything together, merge the relevant feature/fix branches into `test-combined` and build from there — never build a release or do further development directly on `test-combined` itself.

**Never**: commit directly to `master`, or `git push origin master` with anything other than a real fast-forward from `upstream/master`.

## Build

Toolchain (RGBDS 1.0.2 + WinLibs mingw-w64 gcc/make) is already installed in this environment. Bare `make`/`gcc` do **not** work correctly here — something else on the native Windows PATH shadows `gcc` with a broken binary (missing `cc1`). Always build via the wrapper instead:

```bash
./build.sh              # -> polishedcrystal-3.2.3.gbc
./build.sh faithful     # or: debug, monochrome, hgss, noir, and combinations
```

`rgbds/` (the RGBDS binaries) and all build artifacts are gitignored — a clean `git status` is expected even after a full build.
