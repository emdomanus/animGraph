# Blend1DNode

Source: `src/animGraph/motions/blend1DNode/init.luau`

`AnimGraph.blend1D(parameter, config)` evaluates numeric threshold samples and
scales child request weights.

```luau
local locomotion = AnimGraph.blend1D("speed", {
	name = "Locomotion",
	defaultValue = 0,
	samples = {
		{ threshold = 0, motion = AnimGraph.clip("idle") },
		{ threshold = 8, motion = AnimGraph.clip("walk") },
	},
})
```

The blend parameter selects weights; it is not layer playback speed. Every
child receives the same sampled motion context and logical delta.
