import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { basename, dirname, relative, resolve } from "node:path";

const expectedVersion = "v0.7.1";
const diagrams = [
	["docs/diagrams/animgraph-runtime.d2", "docs/assets/animgraph-runtime.svg"],
	[
		"docs/diagrams/animgraph-completion.d2",
		"docs/assets/animgraph-completion.svg",
	],
];

const version = spawnSync("d2", ["version"], {
	encoding: "utf8",
});

if (version.error?.code === "ENOENT") {
	throw new Error(
		"D2 is required to render documentation diagrams. Install Terrastruct.D2 0.7.1 and ensure d2 is on PATH.",
	);
}

if (version.status !== 0) {
	throw new Error(version.stderr.trim() || "Unable to read the installed D2 version.");
}

const installedVersion = version.stdout.trim();
if (installedVersion !== expectedVersion) {
	throw new Error(`D2 ${expectedVersion} is required; found ${installedVersion}.`);
}

for (const [source, output] of diagrams) {
	const sourceDirectory = dirname(source);
	const result = spawnSync(
		"d2",
		["--scale=1", basename(source), relative(sourceDirectory, output)],
		{
			cwd: resolve(sourceDirectory),
			stdio: "inherit",
		},
	);

	if (result.error) {
		throw result.error;
	}

	if (result.status !== 0) {
		throw new Error(`D2 failed to render ${source}.`);
	}

	const outerSvg = readFileSync(resolve(output), "utf8").match(
		/<svg\b[^>]*>/,
	)?.[0];
	if (
		outerSvg == null ||
		!/\bwidth="[^"]+"/.test(outerSvg) ||
		!/\bheight="[^"]+"/.test(outerSvg)
	) {
		throw new Error(
			`D2 rendered ${output} without intrinsic dimensions; the diagram viewer cannot calculate its initial fit reliably.`,
		);
	}
}
