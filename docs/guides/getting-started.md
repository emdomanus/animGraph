# Getting Started

Construct a backend, provide one time source and one default logical-position
reader, declare layers, and schedule `update()` from caller-owned code.

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
	resolveAssetId = function(clip: Clip): number
		return animationIds[clip]
	end,
})

local controller: AnimGraph.AnimationController<Layer, State, Param, Clip, LayerBackend> = AnimGraph.new({
	backend = backend,
	timeSource = os.clock,
	logicalPositionReader = function(time: number): number
		return time
	end,
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
	controller:update()
end)

-- later
updateConnection:Disconnect()
controller:destroy()
```

`time` is the one shared time sampled for the update, not an AnimGraph clock or
timescale. A consumer may replace the default reader on a layer definition or
one active play:

```luau
controller:play("action", AnimGraph.clip("slash"), {
	state = "attack",
	logicalPositionReader = actionReader,
})
```

The play reader replaces the layer reader; the layer reader replaces the
controller default. Values are never multiplied through that chain.

## Initial Position

Use one discriminated `initialPosition`. There are no numeric aliases:

```luau
controller:play("action", AnimGraph.clip("slash"), {
	initialPosition = { kind = "normalized", value = 0.5 },
})
```

Seconds must be finite and non-negative. Normalized values must be finite and in
the inclusive interval `[0, 1]`. Initial position is a one-shot materialization
instruction, not a live seek operation.
