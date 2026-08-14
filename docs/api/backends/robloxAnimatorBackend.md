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
`apply(requests)`, `stopLayer`, `clear`, `destroy`, `getCapabilities`, and
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
- an exact or beyond-terminal non-looping value lands at `Length` and prevents
  the unchanged materialization from replaying;
- looping seconds wrap modulo length;
- looping normalized `1` canonicalizes to zero.

`forceRestart` creates a new internal materialization generation. An explicit
`initialPosition` wins; without one, the new generation starts at zero.

## Idempotence

For unchanged native desired state, repeated `apply` calls do not reload, replay,
rewrite position, churn an internal generation, adjust weight/speed, rewrite
loop/priority, or restart a fade. A delta-only request change remains visible to
custom backends but has no native Roblox operation. Resolving one pending
position after length becomes available is the sole permitted change during an
otherwise unchanged apply.

CP-TA1 exposes no track completion or live positioning API.
