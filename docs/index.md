# AnimGraph

AnimGraph is a caller-scheduled Roblox Luau animation graph. It evaluates typed
layers, parameters, motions, and state machines at an explicit sampling
coordinate, produces backend-neutral clip requests, and delegates physical
playback to an injected backend.

The package owns no engine clock or RunService connection. Consumers call
`controller:update(sampleTime)` and provide `TimeReader` functions that return
an atomic `{ position, rate }` time basis.

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
AnimationController --samples once--> selected TimeReader functions
        |
        | active play > layer > controller default
        | atomic sample preflight, command commit
        v
LayerRuntime(s) --timePosition + timeRate--> MotionNode graph
        |
        | validated ClipRequest[]
        v
backend:apply(sampleTime, requests)
        |
        +-- nativeRate: Roblox advances physical phase
        '-- sampledPosition: backend evaluates physical phase anchors
```

The reader's position is used literally; its rate is not inferred from position
deltas. AnimGraph does not classify discontinuities or make reader replacement
continuous. A backward controller coordinate is rejected; an equal coordinate
is legal and can re-evaluate newly queued commands.

## Boundary

AnimGraph owns:

- typed layers, parameters, triggers, motions, and state machines;
- selected-reader caching and atomic sample validation;
- next-update graph-intent commands;
- backend-neutral requests, synchronous physical positioning, and completion;
- Roblox native-rate and sampled-position playback strategies.

Consumers own scheduling, clock mapping, discontinuity policy, continuity
offsets, native physical re-addressing, character policy, replication, VFX,
content, and any pre-materialization position command. Graph time position and
physical clip phase are deliberately separate.
