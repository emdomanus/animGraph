# RobloxAnimatorBackend

Source: `src/animGraph/backends/robloxAnimatorBackend/init.luau`

```luau
local backend = AnimGraph.robloxAnimatorBackend.new({
	animator = animator,
	positionMode = "nativeRate",
	resolveAssetId = function(clip: Clip): number
		return animationIds[clip]
	end,
	defaultFadeOut = 0.2,
})
```

`positionMode` is optional and defaults to `nativeRate`. The resolved strategy
is fixed for the backend's lifetime and is reported by
`getCapabilities().positionMode`.

The backend implements `apply(sampleTime, requests)`, synchronous absolute and
relative positioning, completion and marker binding, layer stop, clear/destroy, capability
reporting, and debug snapshots.

## Coordinate and batch contract

`sampleTime` must be finite and cannot move backward from the backend's last
accepted coordinate. Equal values are valid. The controller passes the same
coordinate it used for graph evaluation.

The entire request batch is validated before track loading. Duplicate keys,
invalid positions, non-finite weight/speed/time-position/time-rate/priority/fade,
or negative fade reject before materialization. Direct backend users receive
the same checks as controller users.

For unchanged sampled generations, all anchor-derived position and offset
arithmetic is also preflighted before the backend accepts the batch or mutates
playback. Finite inputs whose subtraction or multiplication overflows therefore
reject without advancing accepted state or partially sampling the batch.

## Position strategies

```luau
export type BackendPositionMode =
	"nativeRate"
	| "sampledPosition"
```

### nativeRate

Roblox advances physical phase at:

```luau
finalNativeSpeed = request.speed * request.timeRate
```

A new generation calls `Play` with that signed speed; later effective-speed
changes use `AdjustSpeed`. Unchanged effective speed does not replay, seek,
rewrite position, or churn native properties. Calling `controller:update`
every frame therefore does not write `TimePosition` every frame.

Initial position is a one-shot generation instruction. If length is unknown,
it remains pending. Reverse starts hold native rate at zero only when required
to place an unresolved upper position safely, then adopt the retained negative
speed after the write.

### sampledPosition

The backend advances physical phase from the request's literal time position
while Roblox runs at native rate zero:

```luau
physicalPosition = physicalAnchor
	+ request.speed * (request.timePosition - timeAnchor)
```

It wraps looping positions and clamps non-looping positions on every apply.
Before speed or loop policy changes, it samples with the old values and rebases
the anchors, then adopts the new request. A positive length is required for the
physical write, but elapsed anchor-relative phase continues to accrue while
length is unresolved.

`request.timeRate` does not advance a sampled track; the supplied position does.
The final composed sign `request.speed * request.timeRate` is used when a
non-looping boundary needs an intended terminal direction.

Roblox still owns weight interpolation, fades, asset loading, and final pose
application. `sampledPosition` makes physical position sampling deterministic;
it does not make all Roblox animation behavior deterministic. Marker, keyframe-
event, and root-motion behavior under per-update `TimePosition` writes requires
consumer-specific Studio verification.

## Absolute and relative positioning

`setTrackPosition(trackKey, position)` and
`offsetTrackPosition(trackKey, deltaSeconds)` address only the current active
generation. They return `true` for an accepted command even if unknown length
delays the write, and `false` for missing, retiring, completed, stale, or
destroyed targets.

In native mode these commands preserve the existing generation and desired
native rate. In sampled mode they synchronously write when possible and rebase
physical phase at the request's last accepted time position. The next apply at
that same position holds the explicit address; later positions advance from it.

A `TimeSample.position` jump is literal in sampled mode. Native mode cannot
infer whether the same-rate jump should move an already-running Roblox track;
the caller must use one of these synchronous positioning commands when native
physical playback needs re-addressing. The backend intentionally has no
discontinuity detector or reconciliation tolerance.

Pending absolute and relative commands remain generation-local. A later
absolute command supersedes earlier offsets; later offsets compose from the new
base. Looping addresses wrap. Non-looping addresses clamp and complete only
when desired signed speed points outward.

| Boundary | Desired speed | Result |
| --- | --- | --- |
| upper | positive | completed |
| upper | zero or negative | active |
| lower | negative | completed |
| lower | zero or positive | active |
| looping boundary | any finite speed | wraps, active |

## Generations and completion

The shared backend manager owns:

- one active generation per `trackKey`;
- retiring physical generations keyed by generation token;
- lightweight completed tombstones keyed by `trackKey`.

Native mode classifies natural `Stopped`/`Ended` behavior. Sampled mode
classifies completion from sampled non-looping phase and ignores native stop
signals while its active zero-rate generation remains owned. Both modes commit
the tombstone before dispatching `trackCompleted`; sampled completion cleans its
otherwise-frozen zero-rate physical track immediately.

Explicit stop, request omission, replacement retirement, restart retirement,
clear, and destroy suppress natural completion. Listener snapshots permit
re-entrant commands. Non-zero retirement fades keep physical generations until
`Ended`; zero-fade or inactive retirement cleans immediately.

Apply depth is restored even when asset resolution or Roblox operations throw,
so a failed apply cannot permanently suppress later completion dispatch. If a
borrowed `resolveAssetId` callback calls `clear` or `destroy`, a lifecycle epoch
invalidates that materialization before an `AnimationTrack` is loaded.

Debug track details include `positionMode`, `generation`, `lifecycle`, and
`physicalPresent` without exposing raw Roblox objects.

## Marker capability

`getCapabilities().trackMarkers` is `true` for `nativeRate` and `false` for
`sampledPosition`. Both operations return idempotent release functions:

- `bindToTrackMarker(trackKey, markerName, callback)` calls `callback(value: string)`.
- `bindToMarker(markerName, callback)` calls `callback(track, value: string)` for
  the named marker on any current or future active track owned by this backend.

`track` is the existing playback object observed through the backend-independent
`TrackMarkerSource<LayerT, StateT, ClipT>` contract. Both scopes share one
`GetMarkerReachedSignal(markerName)` connection per observed track/marker pair.
They do not fetch keyframes or marker metadata. Sampled mode rejects both.

Logical subscriptions survive `clear()`; physical connections do not. Final
`destroy()` removes subscriptions and connections. Retirement disconnects marker
signals immediately, even while Roblox continues a visual fade. Stale physical
bindings and queued callbacks are invalidated. See the controller's
[marker contract](../controllers/animationController.md#track-markers) for callback
ordering, source lifetime, positioning, blending, and error semantics.

Custom backends must provide `BackendCapabilities.trackMarkers`, `bindToTrackMarker`,
and `bindToMarker`. Unsupported backends report `false` and reject either direct
binding operation. Supporting backends provide an observation surface over their
own track objects and the same subscription/lifecycle semantics. Neither the API
nor `TrackMarkerSource` depends on Roblox instances. No sampled crossing evaluator
is introduced here.
