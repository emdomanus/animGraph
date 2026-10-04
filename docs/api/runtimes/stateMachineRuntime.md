# StateMachineRuntime

Source: `src/animGraph/runtime/stateMachineRuntime/shared/stateMachineRuntime.luau`

Create with `AnimGraph.stateMachine(config)` or
`AnimGraph.stateMachineRuntime.new(config)`. The runtime is a stateful motion
node with authored states, ordered transitions, conditions, event emission, and
debug state.

Transition progress derives from `MotionEvaluateContext.timePosition`. Each
transition stores its start-position anchor and computes elapsed from the
current literal sample. Held or equal-position evaluation holds progress;
native request speed does not scale or rewind it. Create separate runtime
instances for independent live graph state.

Replaying the same runtime does not inject a phase-zero sample. If an active
transition observes a lower time position, it shifts its start anchor by the
same amount. Elapsed progress is preserved rather than moving backward, and
later forward samples continue immediately from the new coordinate.
