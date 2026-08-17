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

Transition progress uses an absolute `MotionEvaluateContext.logicalPosition`
anchor. A transition stores the position at which it starts and derives elapsed
as `currentPosition - startPosition`. First, held, backward-reader, revision,
and equal-coordinate samples hold progress. Layer and request speed do not
scale or rewind transition time.

Supported condition operators are `==`, `~=`, `>`, `>=`, `<`, `<=`, `truthy`,
`falsy`, and `trigger`. Trigger conditions consume the trigger. Create a
state-machine runtime per independent live graph because it contains mutable
active-state and transition progress.
