# Motions

Motion nodes evaluate authored intent into backend-neutral `ClipRequest`
records. They do not own concrete tracks.

## Clip

```luau
local intro = AnimGraph.clip("intro", {
	trackKey = "action/intro",
	weight = 1,
	speed = 1,
	looped = false,
	initialPosition = { kind = "seconds", value = 0.25 },
})
```

A configured initial position is declarative for each new materialization. The
Roblox backend applies it once, including when length initially equals zero, and
later evaluations cannot snap the live materialization back.

## Blend Nodes

`AnimGraph.blend1D(parameter, config)` blends numeric threshold samples.

```luau
local locomotion = AnimGraph.blend1D("speed", {
	samples = {
		{ threshold = 0, motion = AnimGraph.clip("idle") },
		{ threshold = 8, motion = AnimGraph.clip("walk") },
		{ threshold = 16, motion = AnimGraph.clip("run") },
	},
})
```

`AnimGraph.blend2D(parameterX, parameterY, config)` blends positioned samples
and can limit influences with `maxInfluences`.

## Request Contract

The evaluation context carries one atomic time sample while requests carry that
sample plus physical intent:

```luau
local timePosition = context.timePosition
local timeRate = context.timeRate

local request = {
	speed = authoredPhysicalSpeed * layerSpeed,
	timePosition = timePosition,
	timeRate = timeRate,
	initialPosition = nil,
	-- identity, layer/state, weight, looping, priority, fade, and restart fields
}
```

The layer runtime composes layer speed into `request.speed`; the backend later
composes `timeRate` for native playback. `ClipRequest` contains no `dt`.
Custom motions should preserve stable track keys and propagate `timePosition`
and `timeRate` without deriving or independently resampling them.

Layer-play `initialPosition` and `forceRestart` overrides remain available until
the first evaluation that emits at least one request. Every request in that
first batch can receive them; later evaluations do not.
