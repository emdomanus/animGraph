# State Machines

`StateMachineRuntime` is a stateful motion node. It owns authored states,
transition selection, and transition progress, and emits state/transition events
through the controller context.

```luau
local action = AnimGraph.stateMachine({
	initialState = "empty",
	states = {
		{ id = "empty" },
		{ id = "attack", motion = AnimGraph.clip("slash") },
	},
	transitions = {
		{
			from = "empty",
			to = "attack",
			duration = 0.08,
			conditions = {
				{ parameter = "attack", op = "trigger" },
			},
		},
	},
})

controller:play("action", action)
controller:setTrigger("attack")
```

Transition progress uses an absolute `MotionEvaluateContext.timePosition`
anchor. A transition stores the position at which it starts and derives elapsed
as `currentPosition - startPosition`. Held and equal-position samples hold
progress. A backward time position shifts the anchor to preserve current
progress, keeping discrete state forward-only. Layer, request, and reader rate
do not independently scale transition time; position is authoritative.

Replaying the same runtime while it is transitioning does not synthesize a
phase-zero sample. Current blend progress is preserved, and later forward
positions continue immediately from the selected reader's coordinate.

Supported condition operators are `==`, `~=`, `>`, `>=`, `<`, `<=`, `truthy`,
`falsy`, and `trigger`. Trigger conditions consume the trigger. Create a
state-machine runtime per independent live graph because it contains mutable
active-state and transition progress.
