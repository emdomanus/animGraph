# Changelog

## Unreleased

- Renamed the timing seam to `LogicalPositionReader` / `logicalPositionReader`
  and its input to `time`, distinguishing the shared sampled time from each
  reader's returned logical position without retaining compatibility aliases.
- Recorded operator-reviewed CP-TA3 closure: the 51-test deterministic/static
  gate and all 12 Studio cases passed; VoxelMMO timing proofs and release
  decisions remain deferred.
- Added canonical `TrackCompletedEvent`, the discriminated `AnimationEvent`
  union, `controller:setTrackPosition`, and backend live-position/completion
  ports; removed the unused `motionRequested` event name.
- Added Roblox generation tokens, same-key clip replacement, force-restart
  rematerialization, completed tombstones, stale-signal guards, and snapshot-safe
  re-entrant completion dispatch.
- Added explicit fade-retirement ownership: `Stopped` classifies only natural
  active completion, `Ended` owns non-zero-fade physical cleanup, and zero-fade,
  clear, and destroy boundaries clean immediately without false completion.
- Extended deterministic lifecycle coverage and the Studio dev harness for live
  addressing, terminal/natural completion, looping, replacement, reappearance
  during fade, listener mutation, and physical cleanup visibility.
- Replaced the controller-wide delta argument with caller-scheduled `update()` that
  samples one `TimeSource` time and selected play/layer/default
  `LogicalPositionReader` functions, derives per-activation deltas, and adds
  request-local `deltaTime`.
- Removed the controller-owned frame-binding helper; callers now own update scheduling. Non-finite or
  backward samples reject atomically while first, held, and exact-forward
  samples use the documented baseline behavior.
- Added canonical `AnimationPosition`, `TimeSource`, and `LogicalPositionReader`
  declarations under `types/def`, moved implementation helpers under `utils`,
  and deleted the superseded public delta-map surface completely.
- Replaced the two legacy numeric position fields with the canonical, validated
  `AnimationPosition` union and one-shot `initialPosition`.
- Made Roblox backend apply idempotent for unchanged live generations, added
  pending-length resolution and exact looping/non-looping boundaries, and
  retained an internal completed-materialization latch that prevents replay.
- Added duplicate request-key rejection before backend mutation and executable
  Lune coverage for the CP-TA1 timing and initial-position contract.
- Reorganized documentation into architecture, guides, filesystem-aligned API,
  shared types, consumer research, and engineering TODO sections.

## 0.1.0

- Replaced the category mixer API with the first `AnimationController` vertical
  slice.
- Added typed logical layers, clip motion nodes, controller parameters, debug
  snapshots, and a Roblox `Animator` backend.
- Added `Blend1DNode`, `Blend2DNode`, transition runtime, authored
  state-machine runtime, and controller event dispatch.
- Added runtime setters/getters for layer logical priority and explicit Roblox
  priority overrides.
- Added backend-neutral clip request contracts so a future Crunchyroll/custom
  solver backend can share the public controller API.
- Kept `StackModifier` as a shared component for future speed/weight modifier
  stacks.
- Added an interactive Rojo dev harness for spawning a local R6 dummy and testing
  blend parameters, state-machine triggers, event logs, weights, priority
  mapping, and debug snapshots.
