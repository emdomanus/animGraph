# Verification

AnimGraph separates deterministic local proof, static/package proof,
documentation proof, and Roblox engine evidence. A passing local command does
not prove behavior that depends on real `AnimationTrack` signals or timing.

## Deterministic suite

```powershell
lune run tests/lune/run.luau
```

The expected baseline is **51/51 tests** across the smoke, controller, and
Roblox-backend seam suites. The suite proves the typed event boundary, sampled
reader selection and baselines, atomic preflight, request validation, motion
evaluation, initial/live positioning semantics, idempotent apply, generation
retirement, tombstones, completion dispatch, stale-signal suppression, and
re-entrant lifecycle behavior through fakes. It does not create a real Roblox
`Animator`.

## Formatting, lint, and Luau analysis

```powershell
stylua --check src dev tests
selene src dev tests
.\scripts\check-luau.ps1
rojo sourcemap default.project.json --output sourcemap.json
```

StyLua checks authored formatting. Selene checks Luau lint rules. The Luau
script regenerates the dev sourcemap, analyzes `src` and `dev` with Roblox
definitions, and validates their require graph. The explicit default-project
sourcemap command checks the package-root mapping as well. Both sourcemaps are
generated local state; review them for unexpected changes and do not treat
their generated contents as documentation.

## Documentation and diff checks

```powershell
npm run docs:diagrams
npm run docs:build
git diff --check
```

Documentation diagrams require D2 `v0.7.1`; on Windows it is available as
`Terrastruct.D2` through Winget:

```powershell
winget install --id Terrastruct.D2 --version 0.7.1 --exact
```

The `.d2` files under `docs/diagrams` are the authored sources, while matching
SVG files under `docs/assets` are generated and checked in for base-safe
VitePress rendering. Do not edit generated SVG by hand. Both `docs:dev` and
`docs:build` regenerate diagrams before starting VitePress.

The VitePress build proves that the configured documentation tree renders and
that navigation targets can be built. `git diff --check` catches whitespace
errors. A final stale-link/path scan must also confirm that every sidebar and
Markdown target exists, generated diagrams are current, the architecture SVG
uses a base-safe relative path, and no generated docs output or cache is
tracked.

The architecture-page smoke additionally checks that both diagrams initially
fit without clipping, pointer and arrow-key panning work, the zoom/Fit/100%
controls update the view, Control/Command-wheel zoom anchors at the cursor, and
the SVG palette follows the site's light and dark appearances.

## Engine-only evidence

The [Studio Verification](./studio-verification.md) page is the canonical
record for the Rojo-connected Studio checklist and CP-TA3 operator results.
Studio evidence is intentionally separate from the 51 deterministic tests and
from static analysis. It covers native `AnimationTrack` length, signal order,
fade timing, physical cleanup, loop behavior, and re-entry that host fakes
cannot establish.

CP-TA3 is operator-reviewed and complete. The VoxelMMO timing-composition
proofs, package publication, and version decision remain separate follow-on or
release decisions; this page does not claim them as completed.
