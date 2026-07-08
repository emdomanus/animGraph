# State Machines

`StateMachineRuntime` is a motion node that owns authored states and transitions.
It evaluates the active state's motion and emits transition/state events through
the controller event bus.

## Minimal State Machine

```luau
local action = AnimGraph.stateMachine({
	name = "Action",
	initialState = "empty",
	states = {
		{ id = "empty" },
		{ id = "attack", motion = AnimGraph.clip("slash") },
	},
	transitions = {
		{
			name = "startAttack",
			from = "empty",
			to = "attack",
			duration = 0.08,
			conditions = {
				{ parameter = "attack", op = "trigger" },
			},
		},
		{
			name = "clearAttack",
			from = "attack",
			to = "empty",
			duration = 0.12,
			conditions = {
				{ parameter = "clearAction", op = "trigger" },
			},
		},
	},
})

controller:play("action", action, { state = "empty" })
controller:setTrigger("attack")
```

## States

A state has an id and optional motion.

```luau
export type StateDefinition<LayerT, StateT, ParamT, ClipT, LayerBackendT> = {
	id: StateT,
	motion: MotionNode<LayerT, StateT, ParamT, ClipT, LayerBackendT>?,
}
```

Empty states are useful for idle action layers, disabled overlays, or action
slots that should stop producing clip requests until triggered.

## Transitions

```luau
export type TransitionDefinition<StateT, ParamT> = {
	name: string?,
	from: StateT?,
	to: StateT,
	duration: number?,
	priority: number?,
	conditions: { TransitionCondition<ParamT> }?,
}
```

`from = nil` means the transition can be considered from any active state.
`priority` controls transition ordering when multiple transitions are valid.
`duration` controls transition progress and event/debug timing. Backend fades are
still driven by request fade time from the layer/play context.

## Conditions

Transition conditions read controller parameters.

Supported operators:

```text
==, ~=, >, >=, <, <=, truthy, falsy, trigger
```

Use floats and bools for persistent state:

```luau
{ parameter = "grounded", op = "truthy" }
{ parameter = "speed", op = ">", value = 0.1 }
```

Use triggers for one-shot requests:

```luau
{ parameter = "attack", op = "trigger" }
```

Trigger conditions consume the trigger. A consumed trigger will not fire again
until code calls `controller:setTrigger(parameter)` again.

## Events

State machines emit backend-neutral events through the controller:

```luau
local release = controller:on("stateEntered", function(event)
	print(event.layer, event.state)
end)
```

Use these events for observability, debugging, presentation hooks, and safe
gameplay-facing markers. Avoid putting backend handles or raw tracks in events.

## Current Limits

The current slice intentionally keeps transition behavior small:

- no exit-time conditions yet;
- no authored interruption policy yet;
- no marker-driven transitions yet;
- no automatic state duration completion yet;
- no visual editor serialization format yet.

Those are valid future additions, but they should preserve the same public
separation: state machines produce motion requests; backends execute requests.

## Authoring Guidance

For game code, prefer small state machines per concern:

- base locomotion;
- action slot;
- stance or guard overlay;
- reaction layer.

Do not force all character behavior into one giant graph unless you need a
single authored graph for tooling. Smaller machines are easier to debug with
`getDebugSnapshot()` and easier to migrate from older category-based animators.
