# AnimGraph

AnimGraph is a caller-scheduled Roblox Luau animation graph. It turns typed
layers, parameters, motions, and state machines into backend-neutral clip
requests, then delegates materialization to an injected backend.

The package owns sampled graph evaluation. It does not own a clock, a
`RunService` connection, character policy, Tempo, or TemporalService. A caller
chooses when to invoke `controller:update()` and supplies plain functions that
read logical time at one shared frame coordinate.

## Start Here

- [Guide overview](/guides/)
- [Getting started](/guides/getting-started)
- [Architecture and ownership](/architecture)
- [Public API](/api/)
- [Public type index](/api/types/)
- [Dev harness](/guides/dev-harness)

## Runtime Model

```text
caller-owned scheduler
        |
        | controller:update()
        v
AnimationController --samples--> TimeSource once
        |
        | selects play > layer > default LogicalTimeReader
        | preflights every selected sample
        v
LayerRuntime(s) --evaluate with logical dt--> ClipRequest[]
        |
        | backend:apply(requests) on every successful sample
        v
RobloxAnimatorBackend / custom backend
```

Each active play has its own logical-time baseline. Its first sample produces
zero delta. An unchanged position holds graph state, a forward position uses the
exact finite difference, and a backward or non-finite sample rejects the whole
update before graph or backend mutation. Request speed remains a separate native
playback input.

## Package Boundary

AnimGraph owns:

- typed layers and caller-authored motions;
- sampled reader selection and per-activation baselines;
- parameters, triggers, state machines, and graph events;
- request assembly and duplicate-key validation;
- backend-neutral logical delta, initial/live positioning, and completion contracts;
- Roblox track materialization through the shipped backend.

AnimGraph does not own character spawning, combat, VFX, network replication,
timing bindings, clock rate/discontinuity policy, or target rematerialization
across a game-owned playback handle. Those concerns belong in consumer code.

## Documentation map

- [Verification](/guides/verification) owns the deterministic and static gate inventory.
- [Studio verification](/guides/studio-verification) owns the engine-only checklist and CP-TA3 record.
- [Temporal amendment](/todo/temporalAmendment) preserves completed design and checkpoint history.
- [VoxelMMO consumer research](/research/voxelmmo-migration) records integration requirements only.
