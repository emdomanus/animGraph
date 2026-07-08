import { defineConfig } from "vitepress";

export default defineConfig({
	base: process.env.DOCS_BASE ?? "/",
	title: "AnimGraph",
	description: "Typed authored animation controller primitives for Roblox.",
	cleanUrls: true,
	themeConfig: {
		nav: [
			{ text: "Guide", link: "/" },
			{ text: "Types", link: "/types" },
			{ text: "Architecture", link: "/ARCHITECTURE" },
		],
		sidebar: [
			{
				text: "AnimGraph",
				items: [
					{ text: "Overview", link: "/" },
					{ text: "Architecture", link: "/ARCHITECTURE" },
					{ text: "Types", link: "/types" },
					{ text: "Motions", link: "/motions" },
					{ text: "State Machines", link: "/state-machines" },
					{ text: "Backends", link: "/backends" },
					{ text: "VoxelMMO Migration", link: "/voxelmmo-migration" },
					{ text: "Dev Harness", link: "/dev-harness" },
					{ text: "Backlog", link: "/backlog" },
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
