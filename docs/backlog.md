# Backlog

This page tracks useful future slices without making them part of the current
API contract.

## Near Term

- Roblox animation marker forwarding through controller events.
- Exit-time transition conditions.
- Transition interruption policy.
- Better backend debug state for time position and normalized time.
- Focused tests around blend weights and transition conditions.

## Migration Driven

- VoxelMMO adapter helpers for category-style calls.
- Optional layer stack helper if multiple games need push/release semantics.
- Hitstop helper only if it can stay backend-neutral and not encode combat
  policy.

## Custom Solver Research

- Crunchyroll backend prototype.
- Backend-neutral joint mask metadata.
- Per-joint fallback policy tests.
- Capability-based warnings when a backend cannot represent authored behavior.

Promote backlog items into docs and types only after a real migration or dev
harness case proves the shape.

