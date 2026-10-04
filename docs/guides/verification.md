# Verification

AnimGraph separates deterministic local proof, static/package proof,
documentation proof, and Roblox engine evidence. A passing local command does
not prove behavior that depends on real `AnimationTrack` signals or timing.

## Deterministic suite

```powershell
pwsh -NoProfile -File scripts/verify/tests.ps1
```

The expected baseline is **119/119 tests** across smoke, controller, marker,
evaluation-reuse, native-Roblox-backend, and sampled-Roblox-backend seam suites. The controller
suite proves explicit finite/monotonic coordinates, equal-coordinate
re-evaluation, one atomic `{ position, rate }` read per selected reader, reader
precedence, literal position/replacement behavior, signed and zero rate, queued
graph intent, atomic invalid-sample rejection, and transition start-position
anchors. It also proves that reader/event-driven `clear` or `destroy`
invalidates the active update and that replay cannot regress or stall an active
transition. The backend suites prove both fixed position strategies, native
speed/rate composition without property churn, sampled forward/held/reverse/
nonlinear position evaluation, speed rebasing, request validation, initial/live
positioning semantics, unresolved-length sampling, generation retirement,
tombstones, completion dispatch, stale-signal suppression, and re-entrant
lifecycle behavior. Sampled coverage includes atomic derived-arithmetic
rejection, apply-depth recovery after exceptions, and resolver-driven lifecycle
invalidation. CP-AG-P additionally proves finite
relative-offset validation, exact boolean semantics, atomic known-length
read/modify/write, looping modulo, direction-aware terminals, unresolved
absolute/relative ordering, one-write resolution, reverse position-before-speed,
native-property preservation, stale-generation isolation, and completion
re-entry/error cleanup. It does not create a real Roblox `Animator`.

The marker suite loads the package root and exercises controller-to-backend
delivery, specific/global subscriptions, playback identity, release, stale
signals, reentry, and errors. The suites retain their behavioral expectations
across the shared-domain path migration. Only their module imports change.

## Formatting, lint, and Luau analysis

```powershell
pwsh -NoProfile -File scripts/verify/stylua.ps1
pwsh -NoProfile -File scripts/verify/selene.ps1
pwsh -NoProfile -File scripts/verify/analyze.ps1 -OutDir .verification/checkpoint
pwsh -NoProfile -File scripts/verify/type-errors.ps1 -OutDir .verification/checkpoint-type-errors
```

The wrappers resolve the Rokit-pinned tools (with the documented analyzer
override). StyLua checks authored formatting; Selene checks Luau lint rules.
The analyzer regenerates the dev sourcemap and analyzes `src`, `dev`, and
`tests/type-contracts` with Roblox definitions. Capture before and after source
changes using separate output directories and compare diagnostics. The current
baseline is zero TypeErrors and one existing development-client deprecation
warning. The negative contract suite expects 20 rejected expressions, including
attempts to use instance methods on constructor exports. Use a fresh output
directory for each negative-contract capture.

For source-layout changes, also generate the default-project sourcemap with
the pinned Rojo resolved by `scripts/verify/tools.ps1`. Inspect both generated
trees for duplicate sibling names, stale source paths, and missing modules;
successful generation alone does not prove those properties. All package leaves
except the host-required `src/init.luau` must have one owner-level execution
domain. Review generated artifacts rather than hand-editing them.

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
record for Rojo-connected engine evidence and the historical CP-TA3, CP-AG-R,
and CP-AG-P operator results. Studio evidence is intentionally separate from
the current 119 deterministic tests and from static analysis. It covers native
`AnimationTrack` length, signal order, fade timing, physical cleanup, loop
behavior, and re-entry that host fakes cannot establish.

CP-TA3 is operator-reviewed and complete. The VoxelMMO timing-composition
proofs, package publication, and version decision remain separate follow-on or
release decisions. CP-AG-R reverse-terminal Studio acceptance is also complete
by authoritative operator report; its 59-test deterministic suite at acceptance
time remains separate package proof rather than a substitute for that engine
evidence. CP-AG-P Studio acceptance is complete by the same authoritative
operator-report standard; its historical 72-test deterministic suite remains
separate package proof. The new `sampledPosition` mode still needs an explicit
Studio pass for real pose sampling, fades, completion, markers, and cleanup.
