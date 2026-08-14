# Dev Harness

The Rojo dev harness mounts AnimGraph and creates a local R6 test rig with layer,
blend, priority, state-machine, sequence, console, and debug controls.

```sh
rojo serve dev.project.json
```
Connect a blank Roblox Studio place and press Play. The harness constructs the
controller with `os.clock` as `TimeSource` and an identity default
`LogicalTimeReader`, then owns this update connection:

```luau
local updateConnection = RunService.PreAnimation:Connect(function()
	controller:update()
end)
```

There is no controller-owned frame connection and no delta argument. For manual
timing experiments, replace a layer or active play reader with a caller-owned
reader that holds or advances its logical position.

Useful Studio observations for CP-TA1 include initial seconds/normalized starts,
zero-length pending resolution, loop wrapping, terminal non-loop starts,
`forceRestart`, repeated unchanged apply, and independent logical reader versus
native speed behavior.

Run deterministic and static checks from the repository root:

```sh
lune run tests/lune/run.luau
stylua --check src dev tests
selene src dev tests
npm run docs:build
```

For Roblox-aware analysis and require-graph validation:

```powershell
.\scripts\check-luau.ps1
```
