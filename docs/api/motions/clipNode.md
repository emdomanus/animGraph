# ClipNode

Source: `src/animGraph/motions/clipNode/init.luau`

Create with `AnimGraph.clip(clip, config?)` or `AnimGraph.clipNode.new`.

```luau
local clip = AnimGraph.clip("intro", {
	name = "Intro",
	trackKey = "action/intro",
	weight = 1,
	speed = 1,
	looped = false,
	logicalPriority = 100,
	initialPosition = { kind = "normalized", value = 0.25 },
})
```

Config supports debug name, track key, weight, speed, looping, logical priority,
typed layer-backend data, and one canonical `initialPosition`. The constructor
validates the position before creating the node. Evaluation returns one
backend-neutral `ClipRequest`. Logical phase remains in
`MotionEvaluateContext.logicalPosition`; it is not copied into the physical
request.
