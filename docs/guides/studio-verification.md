# Studio Verification

Local Lune tests and static tools cannot establish Roblox engine behavior. The
stable checklist below is for a Rojo-connected disposable Studio place with
owned test animations. Record the place/build context and return Studio to Edit
mode after the run.

## Checklist

1. Load the test animations and confirm initial `Length = 0` positioning
   resolves; seconds, normalized, forward, and backward seeks are exact.
2. Confirm non-looping terminal positions clamp and complete, while looping
   positions use modulo and normalized `1` canonicalizes to `0`.
3. Record signal order for natural completion, `Stop(0)`, and `Stop(1)`.
4. Confirm completed tombstones remain stopped and physically absent.
5. Reapply unchanged state and confirm the generation, signals, speed, weight,
   priority, loop, and fade state do not churn.
6. Confirm looped playback produces no completion.
7. Replace a same-key clip and reappear during a fade; confirm stale callbacks
   are suppressed and old generations clean up.
8. Re-enter from a completion callback through play/stop/position/clear/destroy
   and confirm one completion, no recursion/errors, and no leaked generations.
9. Hold action logical time while base advances; confirm action native speed can
   be `0.5`, base remains `1.0`, and native fade progresses while action logical
   delta is zero.
10. Compose blend and transition weights without restarting generations.
11. Apply negative `AdjustSpeed`, observe backward movement and `DidLoop`; this
    does not claim continuous reverse graph traversal.
12. Seek across a named marker and then play continuously across it; record the
    absence/presence of marker events for deferred marker design.

## CP-TA3 operator record

The operator connected to **Place1** and personally completed all 12 cases.
These observations are authoritative for the checkpoint:

1. Initial `Length=0` positioning resolved after loading; seconds, normalized,
   forward, and backward seeks were exact.
2. Non-looping positions clamped/completed at terminal; looping positions used
   modulo and normalized `1` became `0`.
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

## Closure

- Deterministic/static suite: **51/51 tests passed**.
- Formatting, lint, Luau analysis, both sourcemaps, documentation build, and
  diff checks passed.
- The migration brief remained accurate.
- Studio was returned to **Edit** mode.
- **CP-TA3 is operator-reviewed and complete.**
- VMMO timing-composition proofs remain a separate consumer follow-on.
- Package publication and version decisions remain deferred.

This page records engine evidence; it does not turn deferred marker forwarding,
continuous reverse graph traversal, package publication, or VoxelMMO consumer
work into AnimGraph implementation scope.
