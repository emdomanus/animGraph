import { defineConfig } from "vitepress";

export default defineConfig({
	base: process.env.DOCS_BASE ?? "/",
	title: "AnimGraph",
	description: "Typed caller-scheduled animation graph primitives for Roblox.",
	cleanUrls: true,
	themeConfig: {
		nav: [
			{ text: "AnimGraph", link: "/" },
			{ text: "Guides", link: "/guides/" },
			{ text: "API", link: "/api/" },
			{ text: "Architecture", link: "/architecture" },
		],
		sidebar: [
			{
				text: "AnimGraph",
				collapsed: true,
				items: [
					{ text: "AnimGraph", link: "/" },
					{ text: "Architecture", link: "/architecture" },
				],
			},
			{
				text: "Guides",
				collapsed: true,
				items: [
					{ text: "Overview", link: "/guides/" },
					{ text: "Getting Started", link: "/guides/getting-started" },
					{ text: "Motions", link: "/guides/motions" },
					{ text: "State Machines", link: "/guides/state-machines" },
					{ text: "Dev Harness", link: "/guides/dev-harness" },
					{ text: "Verification", link: "/guides/verification" },
					{ text: "Studio Verification", link: "/guides/studio-verification" },
				],
			},
			{
				text: "API",
				collapsed: true,
				items: [
					{ text: "Package Root", link: "/api/" },
					{
						text: "backends/",
						collapsed: true,
						items: [{ text: "robloxAnimatorBackend", link: "/api/backends/robloxAnimatorBackend" }],
					},
					{
						text: "components/",
						collapsed: true,
						items: [{ text: "stackModifier", link: "/api/components/stackModifier" }],
					},
					{
						text: "controllers/",
						collapsed: true,
						items: [{ text: "animationController", link: "/api/controllers/animationController" }],
					},
					{
						text: "motions/",
						collapsed: true,
						items: [
							{ text: "blend1DNode", link: "/api/motions/blend1DNode" },
							{ text: "blend2DNode", link: "/api/motions/blend2DNode" },
							{ text: "clipNode", link: "/api/motions/clipNode" },
						],
					},
					{
						text: "runtimes/",
						collapsed: true,
						items: [{ text: "stateMachineRuntime", link: "/api/runtimes/stateMachineRuntime" }],
					},
					{
						text: "types/",
						collapsed: true,
						items: [
							{ text: "type index", link: "/api/types/" },
							{ text: "definitions", link: "/api/types/definitions" },
						],
					},
				],
			},
			{
				text: "Design / Research",
				collapsed: true,
				items: [
					{ text: "VoxelMMO Migration", link: "/research/voxelmmo-migration" },
				],
			},
			{
				text: "TODO",
				collapsed: true,
				items: [
					{ text: "TODO Index", link: "/todo/" },
					{ text: "Temporal Amendment", link: "/todo/temporalAmendment" },
					{ text: "Backlog", link: "/todo/backlog" },
				],
			},
		],
		search: {
			provider: "local",
		},
		outline: {
			level: [2, 3],
		},
		socialLinks: [
			{ icon: "github", link: "https://github.com/emdomanus/animGraph" },
		],
		editLink: {
			pattern: "https://github.com/emdomanus/animGraph/edit/main/docs/:path",
			text: "Edit this page on GitHub",
		},
	},
});
