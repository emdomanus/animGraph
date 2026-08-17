# AnimationController

Source: `src/animGraph/controller/animationController/init.luau`

```luau
local controller = AnimGraph.new({
	backend = backend,
	timeReader = defaultReader,
	layers = layerDefinitions,
})
```

`backend` and `timeReader` are required. `layers` is optional because
layers may be added later.

## Timing contract

```luau
controller:update(sampleTime)
```

`sampleTime` must be finite and cannot move backward. Equal values are legal.
Every distinct selected reader is called once with that same coordinate and
returns:

```luau
{
	position = timePosition,
	rate = timeRate,
}
```

Reader resolution is controller default, then layer override, then active-play
override. Use `LayerPlayOptions.timeReader`, `LayerDefinition.timeReader`, or
the runtime setters listed below. There are no motion-node/subtree readers.

The controller preflights all selected samples before mutation. Invalid sample
data rejects the complete update and preserves pending commands. Position and
rate are used literally and atomically; the controller does not derive rate,
classify discontinuities, or make reader replacement continuous.

Borrowed readers and graph-event listeners may call back into the controller.
If either invokes `clear` or `destroy`, a lifecycle epoch invalidates the active
update before stale command commit or backend apply. Commands deliberately
issued after `clear` remain queued for the next update; `destroy` remains final.

The caller owns scheduling:

```luau
local connection = RunService.PreAnimation:Connect(function()
	controller:update(os.clock())
end)
```

## Command timing

Graph-intent calls take effect at the next valid update:

- `play` and `stopLayer`;
- parameter/float/bool/trigger writes;
- layer weight, speed, logical priority, and backend data;
- time-reader changes.

Getters expose committed state. Calling `update` again at the same coordinate
applies new commands without advancing a transition when the reader returns the
same position.

`setTrackPosition` and `offsetTrackPosition` are synchronous physical-
generation operations, not queued graph intent. `clear` and `destroy` are also
immediate lifecycle boundaries.

## Methods

- `addLayer(definition)`
- `hasLayer(layer)`
- `play(layer, motion, options?)`
- `stopLayer(layer, fadeTime?)`
- `setLayerWeight` / `getLayerWeight`
- `setLayerSpeed` / `getLayerSpeed`
- `setLayerLogicalPriority` / `getLayerLogicalPriority`
- `setLayerBackend` / `getLayerBackend`
- `setDefaultTimeReader(reader)`
- `setLayerTimeReader(layer, reader?)`
- `setActivePlayTimeReader(layer, reader?)`
- parameter, float, bool, and trigger accessors
- `setTrackPosition(trackKey, position) -> boolean`
- `offsetTrackPosition(trackKey, deltaSeconds) -> boolean`
- `on(eventName, callback) -> release`
- `update(sampleTime)`
- `getDebugSnapshot()`
- `clear()`
- `destroy()`

`LayerPlayOptions.initialPosition` and `forceRestart` are one-shot request
commands consumed only after the play first emits requests. A play-scoped time
reader persists for that active play unless changed through the runtime setter.
Replaying the same stateful motion does not synthesize a phase-zero position.
If an active transition later observes a lower literal
position, it preserves elapsed progress and continues from the new coordinate.

## Physical positioning

`setTrackPosition(trackKey, position)` validates `AnimationPosition` and
addresses only the current active backend generation. `offsetTrackPosition`
accepts finite signed seconds and atomically offsets that same generation.
Both return `true` when the current generation accepted the command, including
when positive Roblox length delays the write, and `false` when no eligible
generation exists.

Neither operation changes state-machine progress, replaces a generation, or
rewinds the graph. In `sampledPosition` mode, the physical anchor is reset at
the request's last accepted time position.

Subscribe to `trackCompleted` through `on`. Completion is committed before
dispatch and listener iteration is snapshot-safe.
