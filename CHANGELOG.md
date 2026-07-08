# Changelog

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
