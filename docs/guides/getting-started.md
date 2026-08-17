# Getting Started

Construct a backend, provide a default time reader, declare layers, and
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

local worldReader: AnimGraph.TimeReader = function(sampleTime: number): AnimGraph.TimeSample
	return {
		position = sampleTime,
		rate = 1,
	}
end

local controller: AnimGraph.AnimationController<Layer, State, Param, Clip, LayerBackend> = AnimGraph.new({
	backend = backend,
	timeReader = worldReader,
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
	timeReader = actionReader,
})
```

The active-play reader replaces the layer reader; the layer reader replaces the
controller default. Runtime changes are also available through
`setDefaultTimeReader`, `setLayerTimeReader`, and `setActivePlayTimeReader`.
Reader changes take effect on the next valid update, and the replacement's
position is observed literally.

Return position and rate together so both fields describe one clock sample.
AnimGraph does not infer rate from position changes or hide jumps. If a reader
replacement must remain continuous, map it before returning the sample. If a
native track must move physically, issue `setTrackPosition` or
`offsetTrackPosition` after its generation exists.

## Backend mode

Choose `nativeRate` when Roblox should advance tracks through native signed
speed. Choose `sampledPosition` when the backend should derive and write
physical position from each reader position. This is one fixed backend
strategy, not a layer or content option; graph semantics are identical in both
modes. Calling `update` every frame does not make `nativeRate` write
`TimePosition` every frame.

## Initial and live position

Use the discriminated `initialPosition` union for one-shot materialization:

```luau
controller:play("action", AnimGraph.clip("slash"), {
	initialPosition = { kind = "normalized", value = 0.5 },
})
```

Use synchronous `setTrackPosition` or `offsetTrackPosition` after a generation
exists. Those physical commands do not change state-machine progress.
