# Getting Started

Construct a backend, provide a default logical-time reader, declare layers, and
pass an explicit coordinate from caller-owned scheduling.

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimGraph = require(ReplicatedStorage.packages.animGraph)

type Layer = "base" | "action"
type State = "locomotion" | "empty" | "attack"
type Param = "speed" | "attack"
type Clip = "idle" | "walk" | "slash"
type LayerBackend = AnimGraph.RobloxLayerBackend

local backend = AnimGraph.robloxAnimatorBackend.new({
	animator = animator,
	positionMode = "nativeRate",
	resolveAssetId = function(clip: Clip): number
		return animationIds[clip]
	end,
})

local worldReader: AnimGraph.LogicalTimeReader = function(sampleTime: number): AnimGraph.LogicalTimeSample
	return {
		position = sampleTime,
		addressRevision = 0,
	}
end

local controller: AnimGraph.AnimationController<Layer, State, Param, Clip, LayerBackend> = AnimGraph.new({
	backend = backend,
	logicalTimeReader = worldReader,
	layers = {
		{ id = "base", logicalPriority = 0 },
		{ id = "action", logicalPriority = 100 },
	},
})

controller:play("base", AnimGraph.blend1D("speed", {
	samples = {
		{ threshold = 0, motion = AnimGraph.clip("idle") },
		{ threshold = 8, motion = AnimGraph.clip("walk") },
	},
}), {
	state = "locomotion",
	looped = true,
})
controller:setFloat("speed", 4)

local updateConnection = RunService.PreAnimation:Connect(function()
	controller:update(os.clock())
end)

-- later
updateConnection:Disconnect()
controller:destroy()
```

`play` and the parameter write above are queued until the first `update`.
Calling `update` again with the same coordinate can apply new commands without
advancing transition progress.

## Reader scopes

A layer or active play can override the controller reader:

```luau
controller:play("action", AnimGraph.clip("slash"), {
	state = "attack",
	logicalTimeReader = actionReader,
})
```

The active-play reader replaces the layer reader; the layer reader replaces the
controller default. Runtime changes are also available through
`setDefaultLogicalTimeReader`, `setLayerLogicalTimeReader`, and
`setActivePlayLogicalTimeReader`. Reader changes take effect on the next update
and hold/rebase existing logical phase.

Return a new `addressRevision` only for discontinuous re-addressing. Continuous
rate changes keep the revision stable.

## Backend mode

Choose `nativeRate` when Roblox should advance tracks through native signed
speed. Choose `sampledPosition` when the backend should derive and write
physical position from each `sampleTime`. This is one fixed backend strategy,
not a layer or content option; graph semantics are identical in both modes.

## Initial and live position

Use the discriminated `initialPosition` union for one-shot materialization:

```luau
controller:play("action", AnimGraph.clip("slash"), {
	initialPosition = { kind = "normalized", value = 0.5 },
})
```

Use synchronous `setTrackPosition` or `offsetTrackPosition` after a generation
exists. Those physical commands do not change logical graph phase.
