# Studio Verification

Local Lune tests and static tools cannot establish Roblox engine behavior. The
stable checklist below is for a Rojo-connected disposable Studio place with
owned test animations. Record the place/build context and return Studio to Edit
mode after the run.

## Checklist

1. Load the test animations and confirm initial `Length = 0` positioning
   resolves. A pending reverse start must `Play` at speed `0`, remain at the
   default lower position without completion, write the requested upper position
   once after positive length, and only then adopt the retained negative speed.
2. Confirm the non-looping signed boundary table: upper/positive and
   lower/negative complete; upper/negative and lower/positive move inward;
   either boundary at zero holds active. Confirm looping positions use modulo,
   normalized `1` canonicalizes to `0`, and addressing does not complete.
3. Record signal order for natural forward upper-end completion, natural reverse
   lower-end completion, `Stop(0)`, and `Stop(1)`.
4. Confirm completed tombstones remain stopped and physically absent.
5. Reapply unchanged state and confirm the generation, signals, speed, weight,
   priority, loop, and fade state do not churn.
6. Confirm forward and reverse looped playback wrap, reverse emits native
   `DidLoop`, and neither direction produces completion.
7. Replace a same-key clip and reappear during a fade; confirm stale callbacks
   are suppressed and old generations clean up.
8. Re-enter from a completion callback through play/stop/position/clear/destroy
   and confirm one completion, no recursion/errors, and no leaked generations.
9. Hold action logical time while base advances; confirm action native speed can
   be `0.5`, base remains `1.0`, and native fade progresses while action logical
   delta is zero.
10. Compose blend and transition weights without restarting generations.
11. Pivot live native speed across positive, zero, and negative in the interior
    and at exact boundaries. Confirm one unchanged track/generation, only changed
    `AdjustSpeed` calls, no seek or replay, and completion only on an outward
    boundary pivot. This does not claim continuous reverse graph traversal.
12. Seek across a named marker and then play continuously across it; record the
    absence/presence of marker events for deferred marker design.

## CP-AG-R operator acceptance

On 2026-08-15, the operator manually completed the documented CP-AG-R Studio
verification and reported that every case passed. That report is authoritative
for this checkpoint. The closure handoff did not include place/build,
client/server role, rig, animation-asset, log, or video metadata, so this record
does not invent those details.

The operator verified:

1. the complete initial and live signed non-looping boundary matrix: upper with
   positive speed and lower with negative speed completed, inward directions
   remained active and moved inward, and zero held either boundary active;
2. known-length reverse startup remained active when negative `Play` preceded
   the exact upper `TimePosition` write, with no transient-lower completion and
   one unchanged generation;
3. unknown-length reverse startup used `Play` speed `0`, remained held without
   premature completion, wrote the requested upper position once after positive
   length, then applied the retained negative speed without replay, rewrite,
   reapplication, or generation replacement;
4. the unresolved `0 -> negative` transition remained held until length
   resolved, then observed one position resolution followed by one negative
   speed application;
5. live positive/zero/negative pivots in the interior used native speed
   adjustment without seek, `Play`, replacement, or generation change;
6. exact-boundary pivots completed exactly once only when the new direction
   pointed outward;
7. natural reverse playback completed at the lower boundary exactly once after
   committed state, then cleaned physical ownership without stale signals
   affecting a later same-key generation; and
8. reverse looping wrapped and emitted native `DidLoop` without forwarding
   `trackCompleted`, while live loop positioning remained non-completing.

The deterministic 59-test suite remains separate package proof; the operator
run closes the engine-dependent CP-AG-R gate.

## CP-TA3 operator record

The operator connected to **Place1** and personally completed all 12 cases.
These observations are authoritative for the checkpoint:

1. Initial `Length=0` positioning resolved after loading; seconds, normalized,
   forward, and backward seeks were exact.
2. At the then-tested positive speed, non-looping upper positions clamped and
   completed; looping positions used modulo and normalized `1` became `0`.
3. Signal order was `Stopped`, then `Ended` at zero weight for natural
   completion; `Stop(0)` produced both immediately; `Stop(1)` produced
   `Stopped` immediately and `Ended` after the fade reached zero.
4. Completed tombstones remained stopped and physically absent.
5. Unchanged apply retained its generation, did not restart, emitted no
   stop/end signals, and caused no speed/weight/priority/loop churn.
6. Looped playback produced no completion.
7. Same-key replacement and fade reappearance suppressed stale callbacks and
   cleaned old generations.
8. Completion callback re-entry completed A and B exactly once with no
   recursion, errors, playing tracks, or leaked generations.
9. Base logical timing advanced while action timing was held. Action native
   speed changed to `0.5`, base remained `1.0`, and the native fade completed
   while action logical delta was zero.
10. Blend/transition weights composed correctly without restarting generations.
11. Negative `AdjustSpeed` moved backward and wrapped at zero, emitting
    `DidLoop`. This does not claim continuous reverse graph traversal.
12. Direct forward/backward seeks across a named marker emitted no marker
    event; continuous playback crossing it emitted one. This remains deferred
    marker-design evidence.

## CP-TA3 closure

- Deterministic/static suite: **51/51 tests passed**.
- Formatting, lint, Luau analysis, both sourcemaps, documentation build, and
  diff checks passed.
- The migration brief remained accurate.
- Studio was returned to **Edit** mode.
- **CP-TA3 is operator-reviewed and complete.**
- VMMO timing-composition proofs remain a separate consumer follow-on.
- Package publication and version decisions remain deferred.

This historical CP-TA3 record remains separate from the completed CP-AG-R
operator record above.

This page records engine evidence; it does not turn deferred marker forwarding,
continuous reverse graph traversal, package publication, or VoxelMMO consumer
work into AnimGraph implementation scope.
