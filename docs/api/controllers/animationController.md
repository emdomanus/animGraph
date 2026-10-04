# AnimationController

Source: `src/animGraph/controller/animationController/shared/animationController/init.luau`

```luau
local config: AnimGraph.AnimationControllerConfig<Layer, State, Param, Clip, LayerBackend> = {
	backend = backend,
	timeReader = defaultReader,
	layers = layerDefinitions,
	parameterDefaults = { speed = 0, grounded = true },
}
local controller = AnimGraph.new(config)
```

`backend` and `timeReader` are required. `layers` is optional because
layers may be added later.

`parameterDefaults` optionally seeds the parameter store with number, boolean,
or string values. Construction copies the table once; controllers never share
mutable parameter storage with the config or each other. Boolean defaults do not
arm triggers. Setters can override defaults, and omitted defaults leave an empty
store. Defaults apply only at construction: `clear()` still empties parameters.

## Controller types

The controller takes five independent type arguments. Use local aliases to name
the graph's vocabulary and shorten consumer annotations:

```luau
type Layer = "base" | "action"
type State = "idle" | "run"
type Param = "speed" | "grounded"
type Clip = string
type LayerBackend = AnimGraph.RobloxLayerBackend

type Controller = AnimGraph.AnimationController<Layer, State, Param, Clip, LayerBackend>
type DebugSnapshot = AnimGraph.AnimationControllerDebugSnapshot<Layer, State, Param, LayerBackend>
```

These arguments preserve the graph's layer, state, parameter, clip, and
backend-data restrictions. The snapshot takes four arguments: `Layer`, `State`,
`Param`, and `LayerBackend`. It has no clip generic of its own. A local assigned
from `controller:getDebugSnapshot()` already infers the snapshot type, so an
explicit annotation is optional.

`AnimationControllerConfig<LayerT, StateT, ParamT, ClipT, LayerBackendT>` takes the
same five arguments as the controller. `ParamT` types the keys of
`parameterDefaults`. Give the config a concrete type so construction can infer
the parameter vocabulary without a constructor cast:

```luau
type Config = AnimGraph.AnimationControllerConfig<Layer, State, Param, Clip, LayerBackend>
local config: Config = {
	backend = backend,
	timeReader = defaultReader,
	layers = layerDefinitions,
	parameterDefaults = { speed = 0, grounded = true },
}
local controller = AnimGraph.new(config)
```

The pinned analyzer does not reliably infer literal parameter keys from an
unannotated defaults table alone. The typed config is the supported inference
boundary; it also works when defaults are omitted. Values remain the shared
`ParameterValue` union rather than a different value type for each key.

When migrating from the temporary `GraphTypes` bundle, pass its fields as the
controller/config's five arguments and the snapshot's four arguments shown above.
Existing five-argument config consumers need no change. Consumers of the temporary
four-argument config restore `ParamT` as its third argument.

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
- `onTrackMarker(trackKey, markerName, callback) -> release`
- `onMarker(markerName, callback) -> release`
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

## Track markers

```luau
-- Observe a named marker on every current and future track in this controller.
local releaseAll = controller:onMarker("Footstep", function(track, value: string)
    print(track:getTrackKey(), track:getLayer(), track:getState(), value)
end)

-- Observe just one logical track; its callback receives only the parameter string.
local releaseTrack = controller:onTrackMarker("locomotion/walk", "Footstep", function(value: string)
    print(value)
end)
local walk = AnimGraph.clipNode.new("walk", { trackKey = "locomotion/walk", looped = true })
controller:play("base", walk)
-- Call releaseAll() / releaseTrack() when the respective observer is no longer needed.
```

`onMarker` automatically observes the specified name on tracks already active and
tracks materialized later. This is all tracks owned by this controller's backend,
not every Animator in the game, and it does not discover arbitrary marker names.
A track without the specified marker simply produces no matching notification.

The controller delegates both operations through the backend contract. Check
`backend:getCapabilities().trackMarkers`: Roblox `nativeRate` supports them;
`sampledPosition` rejects both with an error. Marker subscriptions are separate
from `on`, which observes graph events and track completion. The parameter is a
single string, matching Roblox's marker value. Legacy named-keyframe events are
not included.

The all-track callback receives `(track, value)`. `track` has the readonly
`TrackMarkerSource<LayerT, StateT, ClipT>` surface: `getTrackKey()`,
`getGeneration()`, `getLayer()`, `getState()`, and `getClip()`. It is the existing
AnimGraph playback object with an observation-only type, not a Roblox
AnimationTrack, a newly allocated wrapper, or a mutable playback command handle.
Repeated markers from one generation provide the same object; replacement creates
a different object. A retained old source never retargets to the new generation.
Its layer/state getters reflect the playback's latest applied context, not an
immutable snapshot from the instant a marker was queued. Its identity getters
remain readable after retirement. Generations are unique within one backend's
lifetime, not globally.

Both subscriptions may be registered before or after materialization. They
survive `clear()` and stop/play. A specific subscription follows its logical key
across restarts and replacement clips. Subscriptions end on release or controller
destruction. Release is idempotent, including after destruction; registration on a
destroyed controller is an error. Use distinct track keys for distinct occurrences,
including the same asset on two layers.

Only active generations emit. Retirement/completion disconnects physical signals
and invalidates queued callbacks from that generation. Continuous native playback
forwards each engine notification, including repeated markers on successive loops.
Explicit seeks do not synthesize skipped events. No clip metadata is downloaded.

Callbacks wait for an in-progress backend apply to finish. For each event, specific
observers run before all-track observers, in registration order within each group.
Both groups' iteration bounds are captured before delivery: listeners added during
a callback start with a subsequent event; released listeners are skipped. Clearing,
destroying, retiring, or replacing the source cancels its remaining delivery.
Recursive signals queue until the current dispatch finishes. Callback errors
propagate after dispatch state is restored, and queued marker events are discarded.
Graph commands from callbacks still take effect on the next controller update.

Global and specific observers share one native signal connection per active
track/marker pair. Dispatch uses existing playback references and string parameters
in reusable queue arrays; it creates no event records, queue records, track wrappers,
or listener snapshots. Arrays may grow with demand, and subscription/materialization
still allocates storage and connections. This is not a claim that Roblox's signal
machinery or consumer callbacks allocate nothing.

Each actively blended track may notify independently, even at zero weight. There
is no dominant-track selection, weight threshold, or footstep deduplication; that
policy belongs to the consumer.
