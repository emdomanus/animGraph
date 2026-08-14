# Blend2DNode

Source: `src/animGraph/motions/blend2DNode/init.luau`

`AnimGraph.blend2D(parameterX, parameterY, config)` evaluates positioned motion
samples from two numeric parameters.

```luau
local strafe = AnimGraph.blend2D("moveX", "moveY", {
	maxInfluences = 4,
	samples = {
		{ x = 0, y = 0, motion = AnimGraph.clip("idle") },
		{ x = 0, y = 1, motion = AnimGraph.clip("forward") },
		{ x = 1, y = 0, motion = AnimGraph.clip("right") },
	},
})
```

The node limits participating samples with `maxInfluences` and scales child
request weights without changing logical delta or native speed domains.
