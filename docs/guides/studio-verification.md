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
9. Hold the action time basis (`position` fixed, `rate = 0`) while base advances;
   confirm action native speed becomes zero, base remains at its composed speed,
   and the native fade still progresses.
10. Compose blend and transition weights without restarting generations.
11. Pivot live native speed across positive, zero, and negative in the interior
    and at exact boundaries. Confirm one unchanged track/generation, only changed
    `AdjustSpeed` calls, no seek or replay, and completion only on an outward
    boundary pivot. This does not claim continuous reverse graph traversal.
12. Seek across a named marker and then play continuously across it; record the
    absence/presence of marker events for deferred marker design.

## Absolute-time and sampled-position gate

This new gate is not yet operator-accepted. Run the harness once with
`BACKEND_POSITION_MODE = "nativeRate"` and once with
`"sampledPosition"`, using the same owned clips and rig.

1. Confirm both strategies receive one controller coordinate per
   `PreAnimation` update and graph transitions progress identically when their
   `TimeSample` values match.
2. Hold one reader at fixed position and zero rate while another advances.
   Confirm only the advancing layer's transition progresses and native physical
   speed on the held layer becomes zero.
3. Queue a parameter or weight change and evaluate twice at the same coordinate.
   Confirm the second evaluation observes the command while transition progress
   remains unchanged.
4. In `nativeRate`, confirm final speed is request speed multiplied by reader
   rate, unchanged effective-speed updates do not write `TimePosition` or churn
   properties, and changes continue through `Play`/`AdjustSpeed`.
5. In `sampledPosition`, confirm `Play` uses speed zero, `AdjustSpeed` is not
   used for phase, and each successful update writes the position derived from
   the reader's literal `position` and the sampled physical anchor.
6. Pivot sampled speed positive to negative at one coordinate. Confirm position
   is continuous at the pivot, then moves backward from the rebased anchor.
7. Confirm sampled looping wraps, non-looping outward boundaries complete once,
   and inward/zero boundary cases remain active.
8. Start sampled playback while `Length == 0`, change speed before resolution,
   then allow length to resolve. Confirm elapsed phase was retained and exactly
   one resolved address is applied without generation replacement.
9. Issue synchronous absolute and relative position commands between updates.
   Confirm each applies to the active generation immediately, an equal-
   coordinate update holds it, and later coordinates advance from the new
   physical anchor.
10. Jump a reader's position without changing its rate. Confirm sampled mode
    follows the literal jump, while native mode does not infer a physical seek;
    then issue an explicit position command and confirm the native generation
    moves without replacement.
11. Stop/restart a sampled native track externally or through lifecycle
    controls. Confirm native stop does not falsely complete an active sampled
    generation, while explicit retirement still fades and cleans once.
12. Record Roblox weight/fade behavior in sampled mode. Position determinism
    must not be reported as deterministic fade timing.
13. Record marker, keyframe-event, root-motion, and pose behavior under sampled
    `TimePosition` writes. Any difference from native playback is a consumer
    integration constraint, not evidence to silently emulate native signals.

## CP-AG-P operator acceptance

On 2026-08-16, the operator manually completed the documented CP-AG-P Studio
verification and reported that every case passed. That report is authoritative
for this checkpoint. The closure handoff did not include place/build,
client/server role, rig, animation-asset, log, or video metadata, so this record
does not invent those details. The deterministic 72-test suite remains separate
package proof rather than a substitute for this engine evidence.

The accepted relative-position matrix was:

1. On a known-length active generation, use **Offset +0.50s** and **Offset
   -0.50s**. Confirm exact signed movement from the current physical position,
   unchanged generation/playing state, and no `Play`, load, speed, weight,
   priority, loop, or fade churn.
2. Use **Offset Loop Wrap** in forward and reverse playback. Confirm positive
   and negative modulo wrapping, one write per accepted command, native
   `DidLoop` as applicable, and no forwarded `trackCompleted`.
3. Use **Offset Fwd End** and **Offset Rev End**. Confirm clamping to the upper
   and lower boundary respectively and one completion only after the backend
   lifecycle is committed. Repeat/stale signals must not duplicate completion.
4. Use **Offset Zero Hold**, then exercise the corresponding inward-speed upper
   and lower cases. Confirm boundary placement remains active; terminal outcome
   follows final desired speed rather than offset sign.
5. Run **Cold Offset Queue first in a fresh Play session**. Confirm `Length`
   begins at zero, both offsets are accepted without a write/completion, the
   pending normalized base plus ordered sum resolves to exactly one final write,
   and repeated updates do not reapply it. Separately verify a queued offset
   without an absolute base uses the physical position observed at resolution.
6. While length remains unresolved, issue offset then absolute then offset.
   Confirm the absolute command discards the older offset and the later offset
   composes from the new base. Repeat absolute then multiple offsets and confirm
   one combined write.
7. Run **Cold Rev + Offset first in a fresh Play session**. Confirm `Play`/native
   speed remains zero while unresolved, then observe exactly one combined
   position write before exactly one retained negative-speed application, with
   no replay or generation change.
8. Queue/issue an offset around **Replace Same Key** and **Reappear In Fade**.
   Confirm old pending state and stale `Stopped`/`Ended` callbacks cannot mutate
   the replacement, and both generations clean according to their owners.
9. Re-enter from relative outward completion through replacement, relative
   positioning, stop/clear/destroy, and record one completion with no leak or
   wedged dispatch. Use **Dump Native + Debug** before and after to establish the
   absence of replay/property churn.

This gate adds no continuous reverse graph traversal, marker forwarding,
position getter, raw-track API, VoxelMMO/hitstop behavior, publication, or
dependency-pin work.

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
