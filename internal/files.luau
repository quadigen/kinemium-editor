local UI = require("@internal/editor_ui")

return function(content)
	local tree, treeController = UI.tree(content, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), {
		Component = {
			Stage = {},
			["GDebugger.cs"] = "script",
			["GLabel.cs"] = "script",
		},
		Properties = {},
		Scenes = {
			["Album.tscn"] = "scene",
			["Launcher.cs"] = "script",
		},
		Game = {
			Car = { speed = 10 }, -- table = treated as a folder by default
		},
	}, {
		startExpanded = false,
		onSelect = function(path, value, isBranch)
			print("Selected:", table.concat(path, "/"), isBranch)
		end,
		onActivate = function(path, value) -- double-click on a leaf
			print("Open:", table.concat(path, "/"), value)
		end,
		getIcon = function(path, value, isBranch, expanded)
			local name = tostring(path[#path])
			if name:match("%.cs$") then
				return "builtin://global-icons/script.svg"
			end
			if name:match("%.tscn$") then
				return "builtin://global-icons/scene.svg"
			end
			-- return nil to fall back to the default folder/file icon
		end,
	})
end
