# AnimGraph

AnimGraph is a caller-scheduled Roblox Luau animation graph. It evaluates typed
layers, parameters, motions, and state machines at an explicit sampling
coordinate, produces backend-neutral clip requests, and delegates physical
playback to an injected backend.

The package owns no engine clock or RunService connection. Consumers call
`controller:update(sampleTime)` and provide `LogicalTimeReader` functions that
map that coordinate to `{ position, addressRevision }`.

## Start here

- [Getting started](/guides/getting-started)
- [Architecture and ownership](/architecture)
- [Absolute-time amendment](/todo/temporalAmendment)
- [Public API](/api/)
- [Public type index](/api/types/)
- [Verification](/guides/verification)

## Runtime model

```text
caller-owned scheduler
        |
        | controller:update(sampleTime)
        v
AnimationController --samples once--> selected LogicalTimeReader functions
        |
        | active play > layer > controller default
        | atomic preflight, command commit, logical phase rebasing
        v
LayerRuntime(s) --absolute logicalPosition--> MotionNode graph
        |
        | validated ClipRequest[]
        v
backend:apply(sampleTime, requests)
        |
        +-- nativeRate: Roblox advances physical phase
        '-- sampledPosition: backend evaluates physical phase anchors
```

A new play starts graph phase at zero. Forward source movement with an unchanged
revision advances by the exact difference. Stationary/backward source movement,
reader replacement, or an address revision holds graph phase and rebases the
source baseline. A backward controller coordinate is rejected; an equal
coordinate is legal and can re-evaluate newly queued commands.

## Boundary

AnimGraph owns:

- typed layers, parameters, triggers, motions, and state machines;
- selected-reader caching, sample validation, and monotonic logical phase;
- next-update graph-intent commands;
- backend-neutral requests, synchronous physical positioning, and completion;
- Roblox native-rate and sampled-position playback strategies.

Consumers own scheduling, clock selection, discontinuity/revision policy,
character policy, replication, VFX, content, and any pre-materialization
position command. Logical graph phase and physical clip phase are deliberately
separate.
