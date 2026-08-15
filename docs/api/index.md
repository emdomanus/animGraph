# API

The public API tree mirrors the value modules under `src/animGraph`. Require
the package root; the root re-exports the constructors and public types listed
here. Private helpers such as `ParameterStore`, `EventBus`, `LayerRuntime`,
and `AnimPlayback` remain implementation details and have no public reference
page.

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnimGraph = require(ReplicatedStorage.packages.animGraph)
```

## Package exports

| Export | Convenience | Canonical reference |
| --- | --- | --- |
| `new` | `AnimGraph.new` | [AnimationController](./controllers/animationController.md) |
| `clip` | `AnimGraph.clip` | [ClipNode](./motions/clipNode.md) |
| `blend1D` | `AnimGraph.blend1D` | [Blend1DNode](./motions/blend1DNode.md) |
| `blend2D` | `AnimGraph.blend2D` | [Blend2DNode](./motions/blend2DNode.md) |
| `stateMachine` | `AnimGraph.stateMachine` | [StateMachineRuntime](./runtimes/stateMachineRuntime.md) |
| `animationController` | `AnimGraph.animationController.new` | [AnimationController](./controllers/animationController.md) |
| `clipNode` | `AnimGraph.clipNode.new` | [ClipNode](./motions/clipNode.md) |
| `blend1DNode` | `AnimGraph.blend1DNode.new` | [Blend1DNode](./motions/blend1DNode.md) |
| `blend2DNode` | `AnimGraph.blend2DNode.new` | [Blend2DNode](./motions/blend2DNode.md) |
| `stateMachineRuntime` | `AnimGraph.stateMachineRuntime.new` | [StateMachineRuntime](./runtimes/stateMachineRuntime.md) |
| `robloxAnimatorBackend` | `AnimGraph.robloxAnimatorBackend.new` | [RobloxAnimatorBackend](./backends/robloxAnimatorBackend.md) |
| `stackModifier` | `AnimGraph.stackModifier.new` | [StackModifier](./components/stackModifier.md) |

## Source-shaped reference

```text
api/
|-- backends/
|   '-- robloxAnimatorBackend
|-- components/
|   '-- stackModifier
|-- controllers/
|   '-- animationController
|-- motions/
|   |-- blend1DNode
|   |-- blend2DNode
|   '-- clipNode
|-- runtimes/
|   '-- stateMachineRuntime
'-- types/
    |-- definitions
    '-- type-index
```

The source has additional private implementation files beside these public
leaves. They are covered by the architecture page rather than exposed as
callable API. Every package-root type is inventoried in the [type index](./types/)
and canonical shared definitions live in [types/definitions](./types/definitions.md).
