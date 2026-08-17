# Guides

Guides explain repeatable workflows for using and validating AnimGraph. Exact
callable and type signatures live in the [API](../api/); ownership and
dependency rules live in [Architecture](../architecture.md).

## Pages

- [Getting Started](./getting-started.md) constructs a controller and drives it
  from caller-owned scheduling.
- [Motions](./motions.md) composes clips and blend nodes while keeping graph
  time position separate from physical clip phase.
- [State Machines](./state-machines.md) authors transitions and trigger-driven
  state changes.
- [Dev Harness](./dev-harness.md) exercises the Roblox-backed runtime in Studio.
- [Verification](./verification.md) records deterministic, static, documentation,
  and diff gates.
- [Studio Verification](./studio-verification.md) records the stable engine-only
  checklist and the operator-reviewed CP-TA3 observations.

Use the [VoxelMMO migration research](../research/voxelmmo-migration.md) only
for consumer composition requirements; it does not expand the package contract.
