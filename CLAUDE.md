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
- `my-changes` — my personal work branch, created off `master`. This is where day-to-day edits happen.
- Additional short-lived branches can be created off `master` for large/experimental features I might want to keep separate or abandon independently (e.g. `mega-evolution`). Branches are cheap — don't hesitate to make more.

### Bringing upstream updates into `master`

Run this whenever I want the latest official changes:

```bash
git fetch upstream
git checkout master
git merge upstream/master      # always a clean fast-forward, since master is never modified directly
git push origin master         # optional: mirrors the update to my GitHub fork
```

### Bringing those updates into my personal branch

After `master` is updated, sync my work branch on top of it:

```bash
git checkout my-changes
git rebase master               # replays my commits on top of the updated master
# or: git merge master          # simpler, creates a merge commit instead of rewriting history
```

Rebase keeps history linear/clean but rewrites commits; merge is simpler to reason about and never rewrites history. Either is fine — rebase is preferred if there's no strong reason not to, but merge is the safer default when in doubt (e.g. if the branch has already been pushed/shared somewhere).

### Day-to-day workflow

1. Make sure I'm on `my-changes` (or the relevant feature branch): `git checkout my-changes`
2. Edit, build (`./build.sh`), test as normal.
3. `git add` / `git commit` as usual — commit freely, this branch is mine.
4. Push to my fork when I want a remote backup or to open a PR: `git push origin my-changes`
5. Periodically pull upstream changes into `master` (above), then rebase/merge `my-changes` on top.

**Never**: commit directly to `master`, or `git push origin master` with anything other than a real fast-forward from `upstream/master`.

## Build

Toolchain (RGBDS 1.0.2 + WinLibs mingw-w64 gcc/make) is already installed in this environment. Bare `make`/`gcc` do **not** work correctly here — something else on the native Windows PATH shadows `gcc` with a broken binary (missing `cc1`). Always build via the wrapper instead:

```bash
./build.sh              # -> polishedcrystal-3.2.3.gbc
./build.sh faithful     # or: debug, monochrome, hgss, noir, and combinations
```

`rgbds/` (the RGBDS binaries) and all build artifacts are gitignored — a clean `git status` is expected even after a full build.
