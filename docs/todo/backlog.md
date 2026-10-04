# Backlog

These items are outside the implemented absolute-time library contract.

## Near Term

- Studio acceptance of real `sampledPosition` pose, fade, completion, marker,
  and cleanup behavior.
- VoxelMMO timing-composition and target-rematerialization proofs.
- Exit-time transition conditions and transition interruption policy.
- Focused blend-weight and transition-condition coverage.

## Consumer Driven

- VoxelMMO adapter and timing-binding composition in the consumer repository.
- Sampled-position marker metadata and crossing evaluation, including loop,
  reverse, and explicit-seek semantics. Native marker subscriptions are implemented;
  real Studio acceptance remains pending (VMMO-43).
- Consumer marker arbitration for blended footsteps, coordinated with VMMO-26.
- Optional layer stack behavior only after repeated consumer use proves a
  package-generic contract.

## Remaining Convention Work

The VMMO-26 package-layout checkpoint establishes owner-level shared domains,
mirrored type ownership, and a single root export surface. It does not claim a
complete migration of internal object contracts. Follow-up ownership work should
address:

- Controller-to-layer private field access and concrete `Impl` dependencies;
  define the actual timing/owned capabilities before replacing these reaches.
- Evaluation context parameter/event callbacks and their broad types; inject
  existing objects through appropriate capabilities instead of manufacturing
  forwarding closures.
- Backend playback maps and helper signatures that still use `any` despite the
  canonical playback surface.
- StackModifier's cross-object `_applyEntries` call and owner-only lifecycle
  naming; agree on the replacement contract before migrating callers.
- Mutable backend capability policy and native annotations on runtime modules
  without a measured or computational justification.

Controller decomposition and reusable evaluation output/dirty-state tracking
remain deferred until VoxelMMO integration and profiling. They are not part of
the path migration, and the current `evaluate`/`apply` contracts are unchanged.

## Custom Solver Research

- Crunchyroll or custom pose-solver backend prototype.
- Backend-neutral joint masks and capability reporting.
- Per-joint fallback policy tests.
