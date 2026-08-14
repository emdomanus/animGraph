# AnimationController

Source: `src/animGraph/controller/animationController/init.luau`

Create a controller with `AnimGraph.new(config)` or
`AnimGraph.animationController.new(config)`.

```luau
local controller = AnimGraph.new({
	backend = backend,
	timeSource = timeSource,
	logicalTimeReader = defaultReader,
	layers = layerDefinitions,
})
```

`backend`, `timeSource`, and `logicalTimeReader` are required. `layers` is
optional because layers may be added later.

## Timing Contract

`controller:update()` takes no arguments. It samples `timeSource` exactly once,
passes the finite result to each distinct selected logical reader at most once,
preflights every selected sample, derives per-activation deltas, evaluates the
graph, and applies the resulting request batch.

Reader precedence is:

1. active `LayerPlayOptions.logicalTimeReader`;
2. `LayerDefinition.logicalTimeReader`;
3. `AnimationControllerConfig.logicalTimeReader`.

Starting any replacement play establishes a fresh baseline. The first sample is
zero; equal positions remain zero; forward positions use their exact finite
difference. Non-finite or backward positions reject the whole update without
changing graph state, backend state, or prior baselines.

The caller owns scheduling:

```luau
local connection = RunService.PreAnimation:Connect(function()
	controller:update()
end)
```

## Main Methods

- `addLayer(definition)`
- `hasLayer(layer)`
- `play(layer, motion, options?)`
- `setTrackPosition(trackKey, position) -> boolean`
- `stopLayer(layer, fadeTime?)`
- `setLayerWeight` / `getLayerWeight`
- `setLayerSpeed` / `getLayerSpeed`
- `setLayerLogicalPriority` / `getLayerLogicalPriority`
- `setLayerBackend` / `getLayerBackend`
- parameter, float, bool, and trigger accessors
- `on(eventName, callback)`
- `update()`
- `getDebugSnapshot()`
- `clear()`
- `destroy()`

`LayerPlayOptions.initialPosition` and `forceRestart` are one-shot request
commands consumed after the play first emits requests. `logicalTimeReader`
persists for the whole active play.

## Live Position and Completion

`setTrackPosition(trackKey, position)` validates the same `AnimationPosition`
union used by initial placement, then addresses only the currently live backend
generation. It returns `true` when the valid command is accepted, including
when positive track length is still pending, and `false` for an unknown,
retiring, completed, or destroyed key. It does not change logical reader
baselines, replay graph history, replace the generation, or emit graph state
transitions.

Subscribe with `controller:on("trackCompleted", callback)`. The event is:

```luau
{
	name = "trackCompleted",
	trackKey = trackKey,
	layer = layer,
	state = state,
}
```

The controller binds the backend completion port exactly once and forwards it
through its snapshot-dispatched event bus. Destroying the controller releases
that binding before backend teardown.
