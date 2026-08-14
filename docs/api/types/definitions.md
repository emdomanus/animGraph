# Canonical Definitions

Source: `src/animGraph/types/def/init.luau`

These definitions are declared once and re-exported through the type and package
barrels.

## AnimationPosition

```luau
export type AnimationPosition =
	{ kind: "seconds", value: number }
	| { kind: "normalized", value: number }
```

Seconds are finite and non-negative. Normalized values are finite and in the
inclusive interval `[0, 1]`. The union addresses native clip position for
initial materialization; it is not the graph's logical-time sample.

## TimeSource

```luau
export type TimeSource = () -> number
```

A controller samples its source exactly once per successful update attempt. The
finite result is a shared coordinate passed to all selected readers. AnimGraph
does not integrate it, treat it as a logical position, or own its lifetime.

## LogicalTimeReader

```luau
export type LogicalTimeReader = (frameNow: number) -> number
```

A reader returns one finite logical position. Each distinct selected function is
sampled at most once per update. AnimGraph derives delta from consecutive
per-activation samples; it does not accept a rate, timescale, clock, mutable
timeline, or reset/rebase operation.
