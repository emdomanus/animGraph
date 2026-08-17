# Changelog

## Unreleased

- Replaced `TimeSource` and scalar `LogicalPositionReader` with explicit
  `controller:update(sampleTime)` and `LogicalTimeReader(sampleTime) ->
  { position, addressRevision }`. Equal coordinates re-evaluate, backward
  controller coordinates reject, and distinct readers are sampled once.
- Replaced graph `dt`/`ClipRequest.deltaTime` accumulation with layer logical
  phase rebasing and transition start-position anchors. Stationary/backward
  reader movement and revision/reader changes hold phase and rebase.
- Added a next-update graph-intent transaction for play/stop, parameters,
  layer properties, and timing-reader changes while retaining synchronous
  active-generation absolute/relative positioning.
- Added fixed backend `nativeRate` and `sampledPosition` strategies and
  `backend:apply(sampleTime, requests)`. Native behavior remains optimized;
  sampled playback uses physical phase anchors and zero-rate Roblox tracks.
- Added deterministic sampled-backend coverage and migrated the dev harness,
  public API, diagrams, and VoxelMMO integration boundary to the new contract.
- Added backend-neutral `controller:offsetTrackPosition` and backend relative
  positioning with finite signed seconds, active-generation boolean semantics,
  known-length atomic read/modify/write, and generation-local unresolved offset
  accumulation.
- Added deterministic CP-AG-P coverage for absolute/relative command ordering,
  loop/clamp behavior, desired-direction terminals, reverse-start ordering,
  idempotence, property preservation, stale generations, and completion
  re-entry/cleanup. Recorded authoritative operator acceptance of the complete
  CP-AG-P Studio matrix.
- Corrected non-looping terminal classification to use desired signed native
  speed, including held/inward boundaries, natural reverse completion, safe
  pending reverse starts, and seek-free live sign pivots on one generation.
- Added the deterministic reverse boundary/start/pivot/loop/rematerialization
  matrix and updated the backend/API/Studio contracts. Recorded authoritative
  operator acceptance of the complete CP-AG-R Studio matrix.
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
- Removed the controller-owned frame-binding helper; callers own update
  scheduling.
- Consolidated canonical public timing and positioning definitions under
  `types/def` and moved implementation helpers under `utils`.
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
