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
`apply(requests)`, `setTrackPosition`, `offsetTrackPosition`,
`bindToTrackCompleted`, `stopLayer`, `clear`, `destroy`, `getCapabilities`, and
`getDebugSnapshot`.

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
- looping seconds wrap modulo length;
- looping normalized `1` canonicalizes to zero.

Non-looping boundary classification uses the request's desired signed speed:

| Resolved position | Desired speed | Result |
| --- | --- | --- |
| `Length` | positive | completed |
| `Length` | negative | active, moving inward |
| `0` | negative | completed |
| `0` | positive | active, moving inward |
| either boundary | zero | active, held |
| interior | any finite value | active |

For a known-length reverse start, `Play` receives the desired negative speed
before the exact upper position is written. For an unknown-length reverse start,
`Play` receives `0`; the backend retains the desired negative speed, waits for a
positive length, writes the requested upper position exactly once, and then
calls `AdjustSpeed` with the retained value. It does not replay, replace, or
change generation during resolution.

`forceRestart` creates a new internal materialization generation. An explicit
`initialPosition` wins; without one, the new generation starts at zero.

## Absolute and Relative Position

`setTrackPosition(trackKey, position)` validates before mutation and addresses
only the active physical generation for the key. A valid command returns
`true`, including when it replaces a pending initial position while length is
zero. Missing, retiring, completed, and destroyed keys return `false` and load
nothing.

Forward and backward positions preserve generation, clip, loop setting, speed,
weight target, priority, and completion subscription. Non-looping exact or
beyond-upper positions clamp to `Length`; lower and upper completion follows the
same desired-speed table as initial placement. Looping seconds wrap modulo length
and normalized `1` canonicalizes to zero without completion.

A live speed change uses only `AdjustSpeed`. It does not seek, call `Play`, change
the key, or replace the generation. At an exact non-looping boundary an outward
pivot completes once; an inward or zero pivot remains active.

`offsetTrackPosition(trackKey, deltaSeconds)` accepts only finite signed
seconds. Each supplied delta and the accumulated unresolved offset must remain
finite and representable; cumulative overflow raises before pending state,
native playback, or lifecycle mutation and preserves the previous valid sum.
The method returns `true` when the current active generation accepts the command,
including when `Length == 0` delays the physical write. It returns `false` for a
missing, retiring, completed, cleaned, stale, or destroyed target.
It exposes no position getter or raw `AnimationTrack`.

With positive length, the method performs one generation-bound physical
read/modify/write. Looping sums wrap modulo length and never complete;
non-looping sums clamp to `[0, Length]`. Terminal classification uses the
playback's final desired signed speed, not offset sign or a temporary native
zero: zero holds either boundary, inward remains active, and outward completes
once after committed position/lifecycle state.

With unresolved length, accepted offsets accumulate separately from the pending
absolute initial/live position. A pending absolute address becomes the base;
without one, the backend observes physical `TimePosition` when length resolves.
It adds the ordered offset sum, wraps/clamps once, and performs exactly one final
write. `setTrackPosition` supersedes offsets issued before it, while later
offsets compose from that absolute base. For an unresolved reverse start, native
speed remains zero until the combined position write, then the retained desired
negative speed is applied without replay or generation replacement.

## Idempotence

For unchanged native desired state, repeated `apply` calls do not reload, replay,
rewrite position, churn an internal generation, adjust weight/speed, rewrite
loop/priority, or restart a fade. A delta-only request change remains visible to
custom backends but has no native Roblox operation. Resolving one pending
absolute/relative address after length becomes available is the only permitted
position change during an otherwise unchanged apply. The combined address and
accumulated offsets are consumed once. A held pending reverse start also applies
its retained speed once after that position write.

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

`bindToTrackCompleted(callback)` observes natural non-looping forward completion
at the upper end, natural reverse completion at the lower end, and accepted
initial/live outward boundary placement. Completion is latched before dispatch
and fires once. Explicit stop, request disappearance, replacement, restart
retirement, clear, and destroy suppress completion. Dispatch snapshots listeners,
so callbacks may synchronously mutate playback, absolute/relative positioning,
lifecycle, or subscriptions. Per-generation pending offsets are discarded on
completion, retirement, cleanup, replacement, clear, and destroy.

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
