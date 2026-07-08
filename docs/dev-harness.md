# Dev Harness

The dev harness is a Rojo-connected local Roblox test rig for exercising AnimGraph
without a full game place.

## Run

```sh
rojo serve dev.project.json
```

Open a blank Roblox place, connect Rojo, and press Play.

The dev project mounts:

- `ReplicatedStorage.packages.animGraph` from `src`;
- `StarterPlayerScripts.animGraphDev` from `dev/client`.

## What It Spawns

The client harness creates:

- a floating R6 dummy in empty space;
- a Scriptable camera pointed at the dummy;
- a left-side control panel;
- grouped controls for base/action layers;
- a collapsible console;
- debug snapshot output;
- scripted sequence buttons that simulate gameplay-like animation operations.

The harness uses public AnimGraph APIs rather than private implementation modules.
It is a practical regression surface for require paths, backend behavior, layer
weights, priorities, blend parameters, and state-machine events.

## Current Test Clips

The harness uses Roblox sample animation ids for:

- idle;
- walk;
- jump;
- wave;
- cheer;
- dance.

These are only dev assets. Production games should resolve clip identities
through their own asset table in `RobloxAnimatorBackendConfig.resolveAssetId`.

## Common Checks

Use the harness to verify:

- controller construction succeeds under `ReplicatedStorage.packages.animGraph`;
- camera is Scriptable and centered on the dummy;
- base locomotion updates when the locomotion parameter changes;
- layer weight changes affect request weights;
- layer playback rate changes track speed, not blend parameter value;
- action triggers enter and clear state-machine states;
- Roblox priority mapping behaves as expected;
- debug snapshots reflect current parameters, layers, and backend tracks.

## Static Checks

Run these from the repo root:

```sh
stylua --check src dev scripts
selene src dev
rojo sourcemap default.project.json --output sourcemap.json
```

For Roblox-aware Luau analysis and require-graph validation:

```powershell
.\scripts\check-luau.ps1
```

That script regenerates the dev sourcemap, runs `luau-lsp analyze` with Roblox
definitions, and validates the require graph for `src` and `dev`.

## Agent Notes

When the harness breaks after a refactor, check in this order:

1. Rojo project names and mounted package names.
2. `src/init.luau` requiring `script.animGraph`.
3. Dev harness requiring `ReplicatedStorage.packages.animGraph`.
4. Sourcemap regeneration.
5. `luau-lsp require-graph`.

Do not fix harness require errors by adding compatibility aliases unless the
public package name intentionally changes.

