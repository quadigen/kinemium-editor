if (IsServer or IsClient) or IsPlaytest then
	return nil
end
local UI = require("@internal/editor_ui")
local user = require("@internal/user")
local Explorer = require("@internal/explorer")

local Project = game.Project
local Dialog = game.DialogService
local tokens = UI.tokens

local DEFAULT_ICON = "builtin://global-icons/project.png"

local DELETE_METHODS = { "DeleteProject", "RemoveProject" }
local UPDATE_METHODS = { "UpdateProject", "EditProject", "SetProjectProperties" }

local function callProject(methodNames, ...)
	for _, methodName in ipairs(methodNames) do
		local found, method = pcall(function()
			return Project[methodName]
		end)

		if found and type(method) == "function" then
			local ok, result = pcall(method, Project, ...)

			if not ok then
				return false, tostring(result)
			end

			if result == false then
				return false, "The operation was rejected."
			end

			return true
		end
	end

	return false, "Project:" .. methodNames[1] .. " is not available in this build."
end

return function(page, windowControls, gui)
	local BUTTON_SIZE = 28
	local GAP = 6
	local DOUBLE_CLICK = 0.35

	local projectsPage = windowControls.pages.Projects

	local function notify(kind, title, message, details, detailsTitle)
		UI.toast("projects", {
			type = kind,
			title = title,
			message = message,
			details = details,
			detailsTitle = detailsTitle,
			backgroundTransparency = 0.4,
			blur = true,
			duration = 5,
		})
	end

	local refreshList

	local function openProject(project)
		if not project.Path then
			return
		end

		Project:SetActiveProject(project.Path)
		Explorer.filesController.Refresh()

		gui.Enabled = false

		UI.root().Enabled = true
		UI.widgetOverlay().Enabled = true
		UI.RootOverlay().Enabled = true
	end

	local function validate(props)
		if props.Name == "" then
			return "Please enter a project name."
		end

		if props.Description == "" then
			return "Please enter a description."
		end

		if props.Icon == "" then
			return "Please enter an icon path."
		end

		if props.FolderPath == "" then
			return "Please choose a folder path."
		end

		return nil
	end

	local function buildProjectPrompt(config)
		local _, _, controller = UI.prompt({
			name = config.name,

			title = config.title,
			description = config.description,

			size = UDim2.fromOffset(480, 410),

			modal = true,
			dim = true,
			dimTransparency = 0.5,
			renderOnTop = true,
			blur = 12,

			glass = true,
			transparency = 0.5,
			glassBlur = 18,

			draggable = false,
			closable = false,
			closeOnBackdrop = false,

			shadow = true,

			buttonAlignment = "right",

			buttons = {
				{
					id = "cancel",
					text = "Cancel",
					role = "secondary",
				},

				{
					id = "submit",
					text = config.submitText,
					role = "primary",

					callback = function(controller)
						controller:SetBusy(true, "submit", config.busyText)

						local props = controller:GetProjectProperties()

						local ok, result = false, validate(props)

						if not result then
							ok, result = config.onSubmit(props, controller)
						end

						controller:SetBusy(false, "submit")

						if not ok then
							notify("error", config.failTitle, result or "Unknown error")

							return false
						end
					end,
				},
			},

			build = function(content, controller)
				local LABEL_HEIGHT = 18
				local INPUT_HEIGHT = 28
				local FIELD_GAP = 12
				local BROWSE_BUTTON_SIZE = 28
				local BROWSE_GAP = 6

				local y = 0

				local function addLabel(text)
					local label = UI.label(
						content,
						text,
						UDim2.fromOffset(0, y),
						UDim2.new(1, 0, 0, LABEL_HEIGHT),
						12,
						UI.tokens.color.subtext
					)

					label.TextXAlignment = Enum.TextXAlignment.Left

					y += LABEL_HEIGHT + 4

					return label
				end

				local function addField(labelText, placeholder, defaultValue, maxLength)
					addLabel(labelText)

					local input =
						UI.input(content, placeholder, UDim2.fromOffset(0, y), UDim2.new(1, 0, 0, INPUT_HEIGHT), {
							text = defaultValue or "",
							maxLength = maxLength or -1,
							selectAllOnFocus = true,
							focusColor = UI.tokens.color.accent,
						})

					y += INPUT_HEIGHT + FIELD_GAP

					return input
				end

				local nameInput = addField("Project Name", "My Project", "New Project", 64)

				local descriptionInput = addField("Description", "A short description of your project", "", 256)

				local iconInput = addField("Icon", DEFAULT_ICON, DEFAULT_ICON, 512)

				addLabel("Folder Path")

				local folderRow = UI.frame(
					content,
					UDim2.fromOffset(0, y),
					UDim2.new(1, 0, 0, INPUT_HEIGHT),
					UI.tokens.color.panel,
					0
				)

				folderRow.BackgroundTransparency = 1

				local folderInput = UI.input(
					folderRow,
					"C:/Users/devco/Documents/Kinemium Projects/New Project",
					UDim2.fromOffset(0, 0),
					UDim2.new(1, -(BROWSE_BUTTON_SIZE + BROWSE_GAP), 0, INPUT_HEIGHT),
					{
						text = "",
						maxLength = 1024,
						selectAllOnFocus = true,
						focusColor = UI.tokens.color.accent,
						textEditable = not config.lockFolder,
					}
				)

				local folderButton = UI.iconButton(
					folderRow,
					"builtin://global-icons/folder.svg",
					UDim2.new(1, -BROWSE_BUTTON_SIZE, 0, 0),
					UDim2.fromOffset(BROWSE_BUTTON_SIZE, BROWSE_BUTTON_SIZE),
					function()
						local path = Dialog:PickFolder("C:\\")
						if path then
							folderInput.Text = string.gsub(path, [[\]], "/")
						end
					end,
					{
						iconSize = 16,
						bgTransparency = 0,
						enabled = not config.lockFolder,
					}
				)

				if config.lockFolder then
					folderButton.Visible = false
					folderInput.Size = UDim2.new(1, 0, 0, INPUT_HEIGHT)
					folderInput.TextColor3 = UI.tokens.color.muted
				end

				y += INPUT_HEIGHT + FIELD_GAP

				controller.fields = {
					name = nameInput,
					description = descriptionInput,
					icon = iconInput,
					folderPath = folderInput,
				}

				controller.folderButton = folderButton

				function controller:SetFolderPath(path)
					folderInput.Text = path or ""
				end

				function controller:GetFolderPath()
					return folderInput.Text
				end

				function controller:GetProjectProperties()
					return {
						Name = nameInput.Text,
						Description = descriptionInput.Text,
						Icon = iconInput.Text,
						FolderPath = folderInput.Text,
					}
				end

				function controller:SetProjectProperties(props)
					props = props or {}

					nameInput.Text = props.Name or "New Project"
					descriptionInput.Text = props.Description or ""
					iconInput.Text = props.Icon or DEFAULT_ICON
					folderInput.Text = props.FolderPath or ""
				end
			end,
		})

		controller:Close()

		return controller
	end

	local createController = buildProjectPrompt({
		name = "CreateProject",
		title = "Create Project",
		description = "Configure your new Kinemium project.",
		submitText = "Create",
		busyText = "Creating...",
		failTitle = "Could not create project",

		onSubmit = function(props)
			local success = Project:CreateProject(props.Name, props.FolderPath, props.Description, props.Icon)

			if not success then
				return false, "The project could not be created. Check the folder path."
			end

			Project:SetActiveProject(props.FolderPath)

			gui.Enabled = false
			UI.root().Enabled = true
			UI.widgetOverlay().Enabled = true
			UI.RootOverlay().Enabled = true

			Explorer.filesController.Refresh()
			refreshList()

			notify(
				"success",
				"Successfully created project!",
				`Successfully created project {props.Name}.`,
				`Description: {props.Description}\nIcon: {props.Icon}\nPath: {props.FolderPath}`,
				"Project details"
			)

			return true
		end,
	})

	local editTarget = nil

	local editController = buildProjectPrompt({
		name = "EditProject",
		title = "Edit Project",
		description = "Change the details of this project.",
		submitText = "Save",
		busyText = "Saving...",
		failTitle = "Could not save project",
		lockFolder = true,

		onSubmit = function(props)
			if not editTarget then
				return false, "No project selected."
			end

			local ok, err = callProject(UPDATE_METHODS, editTarget.Path, props.Name, props.Description, props.Icon)

			if not ok then
				return false, err
			end

			refreshList()

			notify("success", "Project updated", `Saved changes to {props.Name}.`)

			return true
		end,
	})

	local deleteTarget = nil

	local _, _, deleteController = UI.prompt({
		name = "DeleteProject",

		title = "Remove Project",
		description = "This action cannot be undone.",

		size = UDim2.fromOffset(420, 190),

		modal = true,
		dim = true,
		dimTransparency = 0.5,
		renderOnTop = true,
		blur = 12,

		glass = true,
		transparency = 0.5,
		glassBlur = 18,

		draggable = false,
		closable = false,
		closeOnBackdrop = false,

		shadow = true,

		buttonAlignment = "right",

		buttons = {
			{
				id = "cancel",
				text = "Cancel",
				role = "secondary",
			},

			{
				id = "remove",
				text = "Remove",
				role = "danger",

				callback = function(controller)
					if not deleteTarget then
						return
					end

					local target = deleteTarget

					local ok, err = callProject(DELETE_METHODS, target.Path)

					if not ok then
						notify("error", "Could not remove project", err or "Unknown error")
						return false
					end

					deleteTarget = nil
					refreshList()

					notify("success", "Project removed", `Removed {target.Name or "project"}.`)
				end,
			},
		},

		build = function(content, controller)
			local message = UI.label(
				content,
				"",
				UDim2.fromOffset(0, 0),
				UDim2.new(1, 0, 1, 0),
				UI.tokens.type.body,
				UI.tokens.color.text
			)

			message.TextWrapped = true
			message.TextXAlignment = Enum.TextXAlignment.Left
			message.TextYAlignment = Enum.TextYAlignment.Top

			controller.message = message
		end,
	})

	deleteController:Close()

	local bannerFrame = UI.frame(
		projectsPage,
		UDim2.new(0, tokens.space.lg, 0, tokens.space.lg),
		UDim2.new(1, -(tokens.space.lg * 2), 0, 140),
		Color3.new(0, 0, 0),
		15
	)

	user(bannerFrame)

	bannerFrame.ClipsDescendants = true
	bannerFrame.Parent = projectsPage

	local banner =
		UI.image(bannerFrame, "builtin://global-icons/banner.png", UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 1, 0))
	banner.Parent = bannerFrame

	local filter = Instance.new("BlurImageFilter")
	filter.BlurRadius = UDim.new(0, 30)
	filter.Parent = banner

	local shadow = Instance.new("UIShadow")
	shadow.Parent = bannerFrame

	local logo = UI.image(
		bannerFrame,
		"builtin://global-icons/KinemiumFull.png",
		UDim2.new(0.01, 0, 0.5, 0),
		UDim2.new(0, 400, 0, 140)
	)

	logo.AnchorPoint = Vector2.new(0, 0.5)
	logo.ZIndex = 10

	local PROJECTS_Y = 140 + tokens.space.lg * 2

	local projectsList = UI.frame(
		projectsPage,
		UDim2.new(0, tokens.space.lg, 0, PROJECTS_Y),
		UDim2.new(1, -(tokens.space.lg * 2), 1, -(PROJECTS_Y + tokens.space.lg)),
		tokens.color.surfaceAlt,
		15
	)

	projectsList.ClipsDescendants = true
	projectsList.Parent = projectsPage

	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	list.Padding = UDim.new(0, 6)
	list.PaddingLeft = UDim.new(0, 10)
	list.PaddingRight = UDim.new(0, 10)
	list.PaddingTop = UDim.new(0, 10)
	list.PaddingBottom = UDim.new(0, 10)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Wraps = true
	list.LinePadding = UDim.new(0, 8)
	list.MaxItemsPerLine = 5
	list.Parent = projectsList

	local controls =
		UI.frame(projectsList, UDim2.new(0, 0, 0, 0), UDim2.new(1, -20, 0, BUTTON_SIZE), tokens.color.surfaceAlt, 0)

	controls.BackgroundTransparency = 1
	controls.LayoutOrder = 0
	controls.Parent = projectsList

	local selectedProject = nil
	local cardEntries = {}

	local deleteButton, deleteRecord, deleteIcon
	local editButton, editRecord, editIcon

	local function updateControls()
		local enabled = selectedProject ~= nil

		deleteRecord.enabled = enabled
		deleteButton.Active = enabled
		deleteIcon.ImageTransparency = enabled and 0 or 0.6

		editRecord.enabled = enabled
		editButton.Active = enabled
		editIcon.ImageTransparency = enabled and 0 or 0.6
	end

	deleteButton, deleteRecord, deleteIcon = UI.iconButton(
		controls,
		"builtin://global-icons/x.svg",
		UDim2.new(1, -BUTTON_SIZE, 0, 0),
		UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE),
		function()
			if not selectedProject then
				return
			end

			deleteTarget = selectedProject

			deleteController.message.Text =
				`Remove "{selectedProject.Name or "Untitled Project"}" from your projects?\n\n{selectedProject.Path or ""}`

			deleteController:Open()
		end,
		{
			bgTransparency = 0,
		}
	)

	editButton, editRecord, editIcon = UI.iconButton(
		controls,
		"builtin://global-icons/pencil.svg",
		UDim2.new(1, -(BUTTON_SIZE * 2 + GAP), 0, 0),
		UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE),
		function()
			if not selectedProject then
				return
			end

			editTarget = selectedProject

			editController:SetProjectProperties({
				Name = selectedProject.Name,
				Description = selectedProject.Description,
				Icon = selectedProject.Icon,
				FolderPath = selectedProject.Path,
			})

			editController:Open()
		end,
		{
			bgTransparency = 0,
		}
	)

	local newProject = UI.iconButton(
		controls,
		"builtin://global-icons/plus.svg",
		UDim2.new(1, -(BUTTON_SIZE * 3 + GAP * 2), 0, 0),
		UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE),
		function()
			createController:SetProjectProperties(nil)
			createController:Open()
		end,
		{
			bgTransparency = 0,
		}
	)

	local search = UI.input(
		controls,
		"Search projects...",
		UDim2.new(0, 0, 0, 0),
		UDim2.new(1, -(BUTTON_SIZE * 3 + GAP * 3), 0, BUTTON_SIZE),
		{
			text = "",
			maxLength = 64,
			selectAllOnFocus = true,
			focusColor = tokens.color.accent,
		}
	)

	local function applySelection()
		for _, entry in ipairs(cardEntries) do
			local selected = selectedProject ~= nil and entry.project.Path == selectedProject.Path

			UI.setButtonState(entry.record, selected and "selected" or nil)
			entry.shadow.Enabled = selected
		end

		updateControls()
	end

	local function addCard(project, order)
		local lastClick = 0

		local card, _, record
		card, _, record = UI.button(projectsList, "", UDim2.new(0, 0, 0, 0), UDim2.new(1, -20, 0, 90), function()
			local now = os.clock()

			if now - lastClick < DOUBLE_CLICK then
				lastClick = 0
				openProject(project)
				return
			end

			lastClick = now

			selectedProject = project
			applySelection()
		end, {
			color = tokens.color.surface,
			radius = 15,
			hoverColor = tokens.color.surface,
			pressedColor = tokens.color.surface,
		})
		card.Parent = projectsList
		card.LayoutOrder = order

		local iconFrame = UI.frame(card, UDim2.new(0, 8, 0.5, 0), UDim2.fromOffset(74, 74), tokens.color.surfaceAlt, 8)

		iconFrame.AnchorPoint = Vector2.new(0, 0.5)
		iconFrame.ClipsDescendants = true
		iconFrame.Parent = card

		local iconCorner = Instance.new("UICorner")
		iconCorner.CornerRadius = UDim.new(0, 8)
		iconCorner.Parent = iconFrame

		local icon = UI.image(iconFrame, project.Icon, UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 1, 0))

		icon.Parent = iconFrame

		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.BackgroundTransparency = 1
		title.Position = UDim2.new(0, 94, 0, 18)
		title.Size = UDim2.new(1, -110, 0, 24)
		title.Text = project.Name or "Untitled Project"
		title.TextColor3 = tokens.color.text
		title.TextSize = 16
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextYAlignment = Enum.TextYAlignment.Center
		title.Parent = card

		local description = Instance.new("TextLabel")
		description.Name = "Description"
		description.BackgroundTransparency = 1
		description.Position = UDim2.new(0, 94, 0, 44)
		description.Size = UDim2.new(1, -110, 0, 28)
		description.Text = project.Description or "Kinemium project"
		description.TextColor3 = tokens.color.subtext
		description.TextSize = 13
		description.TextWrapped = true
		description.TextXAlignment = Enum.TextXAlignment.Left
		description.TextYAlignment = Enum.TextYAlignment.Top
		description.Parent = card

		local projectsShadow = Instance.new("UIShadow")
		projectsShadow.BlurRadius = UDim.new(0, 5)
		projectsShadow.Enabled = false
		projectsShadow.Parent = card

		local entry = {
			frame = card,
			record = record,
			shadow = projectsShadow,
			project = project,
		}

		card.MouseEnter:Connect(function()
			projectsShadow.Enabled = true
		end)

		card.MouseLeave:Connect(function()
			projectsShadow.Enabled = selectedProject ~= nil and selectedProject.Path == project.Path
		end)

		table.insert(cardEntries, entry)
	end

	refreshList = function()
		for _, entry in ipairs(cardEntries) do
			UI.forgetButtons(entry.frame)
			entry.frame:Destroy()
		end

		cardEntries = {}

		local query = string.lower(search.Text or "")
		local order = 0
		local selectionStillVisible = false

		for _, project in pairs(Project:GetProjects()) do
			local haystack = string.lower((project.Name or "") .. " " .. (project.Description or ""))

			if query == "" or string.find(haystack, query, 1, true) then
				order += 1

				addCard(project, order)

				if selectedProject and selectedProject.Path == project.Path then
					selectedProject = project
					selectionStillVisible = true
				end
			end
		end

		if not selectionStillVisible then
			selectedProject = nil
		end

		applySelection()
	end

	search.TextChanged:Connect(refreshList)

	refreshList()
end
