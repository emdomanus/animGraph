# Public API

AnimGraph's value API mirrors the implementation modules under
`src/animGraph`. Consumers normally require the package root and use these
re-exported constructors.

| Public module | Root convenience | Purpose |
| --- | --- | --- |
| [`animationController`](/api/controllers/animationController) | `AnimGraph.new` | sampled graph owner |
| [`clipNode`](/api/motions/clipNode) | `AnimGraph.clip` | one-clip motion |
| [`blend1DNode`](/api/motions/blend1DNode) | `AnimGraph.blend1D` | one-axis blend motion |
| [`blend2DNode`](/api/motions/blend2DNode) | `AnimGraph.blend2D` | two-axis blend motion |
| [`stateMachineRuntime`](/api/runtimes/stateMachineRuntime) | `AnimGraph.stateMachine` | authored state-machine motion |
| [`robloxAnimatorBackend`](/api/backends/robloxAnimatorBackend) | none | Roblox track backend |
| [`stackModifier`](/api/components/stackModifier) | none | reusable stacked numeric modifier |

See the [type index](/api/types/) for every type re-exported from
`src/init.luau` and [definitions](/api/types/definitions) for the canonical
timing, position, release, and completion types.
