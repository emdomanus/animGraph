# AnimationController

Source: `src/animGraph/controller/animationController/init.luau`

Create a controller with `AnimGraph.new(config)` or
`AnimGraph.animationController.new(config)`.

```luau
local controller = AnimGraph.new({
	backend = backend,
	timeSource = timeSource,
	logicalPositionReader = defaultReader,
	layers = layerDefinitions,
})
```

`backend`, `timeSource`, and `logicalPositionReader` are required. `layers` is
optional because layers may be added later.

## Timing Contract

`controller:update()` takes no arguments. It samples `timeSource` exactly once,
passes that finite time to each distinct selected logical-position reader at
most once, preflights every returned position, derives per-activation deltas,
evaluates the graph, and applies the resulting request batch.

Reader precedence is:

1. active `LayerPlayOptions.logicalPositionReader`;
2. `LayerDefinition.logicalPositionReader`;
3. `AnimationControllerConfig.logicalPositionReader`.

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
- `offsetTrackPosition(trackKey, deltaSeconds) -> boolean`
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
commands consumed after the play first emits requests. `logicalPositionReader`
persists for the whole active play.

## Atomic Positioning and Completion

`setTrackPosition(trackKey, position)` validates the same `AnimationPosition`
union used by initial placement, then addresses only the currently live backend
generation. It returns `true` when the valid command is accepted, including
when positive track length is still pending, and `false` for an unknown,
retiring, completed, or destroyed key. It does not change logical reader
baselines, replay graph history, replace the generation, or emit graph state
transitions.

`offsetTrackPosition(trackKey, deltaSeconds)` is the distinct atomic relative
operation. `deltaSeconds` must be a finite signed number. It returns `true` when
the current active generation accepts the command, including while its physical
write is pending on positive length, and `false` when the controller/backend is
destroyed or no eligible active generation exists. For known length, the backend
reads that generation's physical position and writes the wrapped or clamped sum
within the same call. AnimGraph exposes no public position getter or physical
playback handle.

While length is unresolved, relative offsets accumulate separately from a
pending absolute base. A later `setTrackPosition` discards earlier offsets;
offsets issued after that absolute command compose from its new base. With no
absolute base, resolution uses the physical position observed when length
becomes positive. The combined address is consumed by one final position write
and is not reapplied by ordinary `update()` calls.

For the Roblox backend, non-looping boundary completion is direction-aware. The
upper boundary completes only with positive desired speed, and the lower boundary
completes only with negative desired speed. Zero or inward speed keeps the
generation active. These rules use desired native speed, never relative-offset
sign or a temporary unresolved reverse hold. Looping absolute and relative
addressing wraps and does not complete. A live sign pivot changes native speed
without seeking, replaying, or replacing the generation.

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
that binding before backend teardown. Natural forward upper-end playback,
natural reverse lower-end playback, and explicitly addressed outward boundaries
can produce the event; explicit retirement cannot.
