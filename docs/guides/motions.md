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

Every request contains independent logical and native values:

```luau
{
	deltaTime = context.dt,
	speed = authoredNativeSpeed,
	initialPosition = nil,
	-- identity, layer/state, weight, looping, priority, fade, and restart fields
}
```

The layer runtime stamps its authoritative logical delta on every emitted
request and composes layer speed only into `request.speed`. Custom motions should
preserve stable track keys and keep those two domains separate.

Layer-play `initialPosition` and `forceRestart` overrides remain available until
the first evaluation that emits at least one request. Every request in that
first batch can receive them; later evaluations do not.
