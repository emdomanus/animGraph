import { defineConfig } from "vitepress";

export default defineConfig({
	base: process.env.DOCS_BASE ?? "/",
	title: "AnimGraph",
	description: "Typed caller-scheduled animation graph primitives for Roblox.",
	cleanUrls: true,
	themeConfig: {
		nav: [
			{ text: "Guide", link: "/guides/getting-started" },
			{ text: "API", link: "/api/" },
			{ text: "Architecture", link: "/architecture" },
		],
		sidebar: [
			{
				text: "Overview",
				items: [
					{ text: "AnimGraph", link: "/" },
					{ text: "Architecture", link: "/architecture" },
				],
			},
			{
				text: "Guides",
				items: [
					{ text: "Getting Started", link: "/guides/getting-started" },
					{ text: "Motions", link: "/guides/motions" },
					{ text: "State Machines", link: "/guides/state-machines" },
					{ text: "Dev Harness", link: "/guides/dev-harness" },
				],
			},
			{
				text: "API",
				items: [
					{ text: "API Index", link: "/api/" },
					{ text: "AnimationController", link: "/api/controllers/animationController" },
					{ text: "ClipNode", link: "/api/motions/clipNode" },
					{ text: "Blend1DNode", link: "/api/motions/blend1DNode" },
					{ text: "Blend2DNode", link: "/api/motions/blend2DNode" },
					{ text: "StateMachineRuntime", link: "/api/runtimes/stateMachineRuntime" },
					{ text: "RobloxAnimatorBackend", link: "/api/backends/robloxAnimatorBackend" },
					{ text: "StackModifier", link: "/api/components/stackModifier" },
					{ text: "Type Index", link: "/api/types/" },
					{ text: "Definitions", link: "/api/types/definitions" },
				],
			},
			{
				text: "Research and TODO",
				items: [
					{ text: "VoxelMMO Migration", link: "/research/voxelmmo-migration" },
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
