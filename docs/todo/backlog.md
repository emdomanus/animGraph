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

## Custom Solver Research

- Crunchyroll or custom pose-solver backend prototype.
- Backend-neutral joint masks and capability reporting.
- Per-joint fallback policy tests.
