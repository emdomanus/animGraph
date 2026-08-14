--!strict
--!optimize 2
--!native

export type AnimationPosition =
	{ kind: "seconds", value: number }
	| { kind: "normalized", value: number }

export type TimeSource = () -> number

export type LogicalTimeReader = (frameNow: number) -> number

return {}
