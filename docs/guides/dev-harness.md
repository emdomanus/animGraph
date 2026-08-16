# Dev Harness

The Rojo dev harness mounts AnimGraph and creates a local R6 test rig with layer,
blend, priority, state-machine, sequence, console, and debug controls.

```sh
rojo serve dev.project.json
```
Connect a blank Roblox Studio place and press Play. The harness constructs the
controller with `os.clock` as `TimeSource` and an identity default
`LogicalPositionReader`, then owns this update connection:

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
exact forward upper terminal boundary, force restart, replace a clip under the
same key, reappear while old physics fades, stop with a one-second fade, and
invoke the hard clear boundary. Completion appears in the console. The debug
panel reports generation, active/retiring/completed lifecycle, and whether
physical ownership is still present so fade and cleanup ordering are observable.

For CP-AG-R Studio evidence and future regression checks, the Action State
Machine section exposes signed native speed presets at `-1`, `0`, and `+1`, plus
`0.1` adjustments. The Temporal Lifecycle section can force a fresh generation
at the initial upper or lower boundary, position the live generation at either
boundary, and run the cold `0 -> -1` sequence. Run **Cold 0 -> -1 first in a
fresh Play session** so the `wave` asset has not already entered Studio's
animation cache. That control materializes and immediately updates at zero
speed, pivots the desired action speed negative without yielding a frame, then
leaves normal `PreAnimation` updates to resolve the pending length.

**Dump Native + Debug** records every captured native track alongside the
backend generation and lifecycle. Ordered `evidence NNN` console entries cover
`AnimationPlayed`, the first observed `TimePosition` change, `Length` and `Speed`
changes, `Stopped`, `Ended`, `DidLoop`, `Destroying`, and `trackCompleted` after
its committed lifecycle can be inspected. Use these controls with the
[Studio checklist](./studio-verification.md); direct calls to
`AnimationTrack:AdjustSpeed` bypass AnimGraph and are not package acceptance.

Use the [verification guide](./verification.md) for the deterministic and
static commands. Studio-only observations belong in the
[Studio checklist](./studio-verification.md).
