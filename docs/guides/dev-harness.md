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

There is no controller-owned frame connection and no delta argument. The
Temporal Lifecycle controls independently hold or advance the base and action
readers while leaving native speed controls separate.

The same section can play a known non-looping track to natural completion, play
a loop, position the live track forward to 75% and backward to 25%, address the
exact terminal boundary, force restart, replace a clip under the same key,
reappear while old physics fades, stop with a one-second fade, and invoke the
hard clear boundary. Completion appears in the console. The debug panel reports
generation, active/retiring/completed lifecycle, and whether physical ownership
is still present so fade and cleanup ordering are observable.

Use the [verification guide](./verification.md) for the deterministic and
static commands. Studio-only observations belong in the
[Studio checklist](./studio-verification.md).
