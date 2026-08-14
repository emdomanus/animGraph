# RobloxAnimatorBackend

Source: `src/animGraph/backends/robloxAnimatorBackend/init.luau`

```luau
local backend = AnimGraph.robloxAnimatorBackend.new({
	animator = animator,
	resolveAssetId = function(clip: Clip): number
		return animationIds[clip]
	end,
	defaultFadeOut = 0.2,
})
```

The backend maps caller clip identities to positive Roblox asset ids and applies
backend-neutral request batches to `AnimationTrack` objects. It implements
`apply(requests)`, `setTrackPosition`, `bindToTrackCompleted`, `stopLayer`,
`clear`, `destroy`, `getCapabilities`, and `getDebugSnapshot`.

## Batch Contract

The entire batch is validated before track loading or mutation. Duplicate
`trackKey` values or invalid initial positions reject the whole batch. The
backend repeats this validation for direct users even though the controller also
validates assembled batches.

## Initial Position

An initial position remains pending until the track has positive finite length,
then applies once after `Play`:

- non-looping seconds clamp to `[0, Length]`;
- non-looping normalized values map to the same inclusive interval;
- an exact or beyond-terminal non-looping value lands at `Length` and prevents
  the unchanged materialization from replaying;
- looping seconds wrap modulo length;
- looping normalized `1` canonicalizes to zero.

`forceRestart` creates a new internal materialization generation. An explicit
`initialPosition` wins; without one, the new generation starts at zero.

## Live Position

`setTrackPosition(trackKey, position)` validates before mutation and addresses
only the active physical generation for the key. A valid command returns
`true`, including when it replaces a pending initial position while length is
zero. Missing, retiring, completed, and destroyed keys return `false` and load
nothing.

Forward and backward positions preserve generation, clip, loop setting, speed,
weight target, priority, and completion subscription. Non-looping exact or
beyond-terminal positions clamp to `Length` and complete once. Looping seconds
wrap modulo length and normalized `1` canonicalizes to zero without completion.

## Idempotence

For unchanged native desired state, repeated `apply` calls do not reload, replay,
rewrite position, churn an internal generation, adjust weight/speed, rewrite
loop/priority, or restart a fade. A delta-only request change remains visible to
custom backends but has no native Roblox operation. Resolving one pending
position after length becomes available is the sole permitted change during an
otherwise unchanged apply.

## Generations and Completion

The backend keeps three distinct ownership sets:

- one active generation per `trackKey`;
- retiring physical generations keyed by generation token;
- lightweight completed tombstones keyed by `trackKey`.

A tombstone retains only key, clip, layer/state, and generation identity. It
retains no `AnimationTrack`, `Animation`, or signal connection. The unchanged
request keeps the tombstone and cannot replay. A validated omission, different
clip, `forceRestart`, `clear`, or `destroy` retires it according to the public
contract.

`bindToTrackCompleted(callback)` observes natural non-looping terminal playback
and accepted initial/live terminal placement. Completion is latched before
dispatch and fires once. Explicit stop, request disappearance, replacement,
restart retirement, clear, and destroy suppress completion. Dispatch snapshots
listeners, so callbacks may synchronously mutate playback, positioning,
lifecycle, or subscriptions.

## Fade Retirement and Cleanup

Explicit retirement invalidates `Stopped` classification before
`AnimationTrack:Stop(fadeTime)`. Normal request disappearance uses the backend
default fade. `stopLayer` uses its explicit fade or the backend default;
controller calls supply the resolved layer default. Same-key replacement and
`forceRestart` use the incoming request fade. Clear and destroy are immediate
zero-fade boundaries.

The active key slot is released when retirement begins, allowing a new same-key
generation while old physics fades. `Ended` owns final connection, track, and
animation cleanup after non-zero fade. Zero-fade and already-inactive retirement
clean immediately. Captured generation tokens make delayed `Stopped` or `Ended`
callbacks harmless to newer generations.

Debug snapshots report `generation`, `lifecycle` (`active`, `retiring`, or
`completed`), and `physicalPresent` in each track's `details` table without
exposing raw Roblox objects.
