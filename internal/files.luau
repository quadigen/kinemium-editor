local UI = require("@internal/editor_ui")

local Project = game:GetService("Project")

return function(content)
	return {
		Refresh = function()
			local project = Project:GetActiveProject()
			if not project then
				return
			end

			local function BuildTree(directory)
				local entries = Project:GetProjectEntries(directory)
				local list = {}

				if not entries then
					return list
				end

				table.sort(entries, function(a, b)
					if a.Type == "Directory" and b.Type ~= "Directory" then
						return true
					end

					if a.Type ~= "Directory" and b.Type == "Directory" then
						return false
					end

					return a.Name:lower() < b.Name:lower()
				end)

				for _, entry in ipairs(entries) do
					if entry.Type == "Directory" then
						list[entry.Name] = BuildTree(entry.Path)
					else
						list[entry.Name] = entry.Path
					end
				end

				return list
			end

			local treeData = BuildTree(project.Path)

			local tree, treeController = UI.tree(content, UDim2.fromOffset(0, 0), UDim2.fromScale(1, 1), treeData, {
				startExpanded = false,

				onSelect = function(path, value, isBranch)
					print("Selected:", table.concat(path, "/"), isBranch)

					if not isBranch and type(value) == "string" then
						print("File:", value)
					end
				end,

				onActivate = function(path, value)
					if type(value) == "string" then
						print("Open:", table.concat(path, "/"), value)
					end
				end,

				getIcon = function(path, value, isBranch, expanded)
					local name = tostring(path[#path]):lower()

					if isBranch then
						return nil
					end

					if name:match("%.lua$") or name:match("%.luau$") then
						return "builtin://icons/Script.svg"
					end

					if name:match("%.odin$") then
						return "builtin://icons/Script.svg"
					end

					if name:match("%.cs$") or name:match("%.py$") then
						return "builtin://icons/Script.svg"
					end

					if name:match("%.tscn$") or name:match("%.scene$") then
						return "builtin://icons/ImageLabel.svg"
					end

					if
						name:match("%.png$")
						or name:match("%.jpg$")
						or name:match("%.jpeg$")
						or name:match("%.webp$")
					then
						return "builtin://icons/ImageLabel.svg"
					end

					if name:match("%.wav$") or name:match("%.mp3$") or name:match("%.ogg$") then
						return "builtin://icons/Sound.svg"
					end

					return nil
				end,
			})
		end,
	}
end
