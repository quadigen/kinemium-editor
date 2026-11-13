if (IsServer or IsClient) or IsPlaytest then
	return nil
end
local UI = require("@internal/editor_ui")
local Explorer = require("@internal/explorer")
local Sync = require("@internal/project_sync")

local Project = game.Project
local Dialog = game.DialogService
local tokens = UI.tokens

local DEFAULT_ICON = "builtin://global-icons/project.png"

local Preferences = require("@internal/preferences")
local DELETE_METHODS = { "DeleteProject", "RemoveProject" }
local UPDATE_METHODS = { "UpdateProject", "EditProject", "SetProjectProperties" }

local QUALITY_ITEMS = {
	{ value = "Low", text = "Low" },
	{ value = "Medium", text = "Medium" },
	{ value = "High", text = "High" },
	{ value = "Performance", text = "Performance" },
}

local DIMENSION_ITEMS = {
	{ value = "2D", text = "2D" },
	{ value = "3D", text = "3D" },
}

local DIMENSION_NUMBERS = { ["2D"] = 2, ["3D"] = 1 }

local DEFAULT_QUALITY = "Medium"
local DEFAULT_DIMENSION = "3D"
local DEFAULT_GIT = true

local CHEVRON_ICON = "builtin://icons/ArrowDown.svg"

local function applyQuality(project, quality)
	-- e.g. Project:SetProjectQuality(quality)
end

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
	local CARD_HEIGHT = 90
	local LIST_PADDING = 10
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

	local function showProject(project)
		Preferences.set("lastProject", project.Path)
		Preferences.set("sessionProject", project.Path)
		Sync.start(project)
		Explorer.filesController.Refresh()
		gui.Enabled = false
		UI.root().Enabled = true
		UI.widgetOverlay().Enabled = true
		UI.RootOverlay().Enabled = true
		if shared.ScriptLayer then
			shared.ScriptLayer.Enabled = true
		end
	end

	local function openProject(project)
		local opened
		if Sync.available then
			print("sync is available")
			opened = Project:OpenProject(project.Path)
		else
			print("sync is not available")
			opened = Project:SetActiveProject(project.Path)
		end
		if opened then
			showProject(project)
		else
			print(opened, project)
			notify("error", "Could not open project", project.Path)
		end
	end

	local function validate(props)
		if props.Name == "" then
			return "Please enter a project name."
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

			size = UDim2.fromOffset(480, config.showGameOptions and 520 or 410),

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
					callback = function()
						UI.closeDropdown(true)
					end,
				},

				{
					id = "submit",
					text = config.submitText,
					role = "primary",

					callback = function(controller)
						UI.closeDropdown(true)

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
				local COLUMN_GAP = 12

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

				-----------------------------------------------------------------
				-- Game options (Create prompt only)
				-----------------------------------------------------------------
				local quality = DEFAULT_QUALITY
				local dimension = DEFAULT_DIMENSION
				local git = DEFAULT_GIT

				local qualityDropdown, dimensionDropdown
				local setGit

				if config.showGameOptions then
					local function transparentFrame(parent, position, size)
						local frame = UI.frame(parent, position, size, UI.tokens.color.panel, 0)
						frame.BackgroundTransparency = 1
						return frame
					end

					local function addDropdownColumn(parent, position, size, labelText, items, defaultValue, onChange)
						local column = transparentFrame(parent, position, size)

						local label = UI.label(
							column,
							labelText,
							UDim2.fromOffset(0, 0),
							UDim2.new(1, 0, 0, LABEL_HEIGHT),
							12,
							UI.tokens.color.subtext
						)

						label.TextXAlignment = Enum.TextXAlignment.Left

						local _, _, dropdownController = UI.dropdown(
							column,
							defaultValue,
							UDim2.fromOffset(0, LABEL_HEIGHT + 4),
							UDim2.new(1, 0, 0, INPUT_HEIGHT),
							CHEVRON_ICON,
							{
								items = items,
								menuWidth = 190,
								onChanged = onChange,
							}
						)

						return dropdownController
					end

					local dropdownRowHeight = LABEL_HEIGHT + 4 + INPUT_HEIGHT

					local dropdownRow =
						transparentFrame(content, UDim2.fromOffset(0, y), UDim2.new(1, 0, 0, dropdownRowHeight))

					qualityDropdown = addDropdownColumn(
						dropdownRow,
						UDim2.fromOffset(0, 0),
						UDim2.new(0.5, -(COLUMN_GAP / 2), 1, 0),
						"Game Quality",
						QUALITY_ITEMS,
						DEFAULT_QUALITY,
						function(value)
							quality = value
						end
					)

					dimensionDropdown = addDropdownColumn(
						dropdownRow,
						UDim2.new(0.5, COLUMN_GAP / 2, 0, 0),
						UDim2.new(0.5, -(COLUMN_GAP / 2), 1, 0),
						"Dimension",
						DIMENSION_ITEMS,
						DEFAULT_DIMENSION,
						function(value)
							dimension = value
						end
					)

					y += dropdownRowHeight + FIELD_GAP

					-- Git switch (built from a button + knob, no native switch was available)
					local SWITCH_WIDTH, SWITCH_HEIGHT, KNOB_SIZE, KNOB_PAD = 40, 22, 18, 2
					local SWITCH_ROW_HEIGHT = 34

					local switchRow =
						transparentFrame(content, UDim2.fromOffset(0, y), UDim2.new(1, 0, 0, SWITCH_ROW_HEIGHT))

					local switchTitle = UI.label(
						switchRow,
						"Git Support",
						UDim2.fromOffset(0, 0),
						UDim2.new(1, -(SWITCH_WIDTH + 12), 0, 16),
						UI.tokens.type.small,
						UI.tokens.color.text
					)

					switchTitle.TextXAlignment = Enum.TextXAlignment.Left

					local switchHint = UI.label(
						switchRow,
						"Initialize a git repository for this project",
						UDim2.fromOffset(0, 17),
						UDim2.new(1, -(SWITCH_WIDTH + 12), 0, 16),
						11,
						UI.tokens.color.muted
					)

					switchHint.TextXAlignment = Enum.TextXAlignment.Left

					local track, _, trackRecord
					local knob

					local function renderSwitch()
						local trackColor = git and UI.tokens.color.accent or UI.tokens.color.input

						if trackRecord then
							trackRecord.color = trackColor
							trackRecord.defaultColor = trackColor
							trackRecord.hoverColor = trackColor
							trackRecord.defaultHoverColor = trackColor
							trackRecord.pressedColor = trackColor
						end

						track.BackgroundColor3 = trackColor

						knob.Position = git and UDim2.fromOffset(SWITCH_WIDTH - KNOB_SIZE - KNOB_PAD, KNOB_PAD)
							or UDim2.fromOffset(KNOB_PAD, KNOB_PAD)
					end

					setGit = function(value)
						git = value == true
						renderSwitch()
					end

					track, _, trackRecord = UI.button(
						switchRow,
						"",
						UDim2.new(1, -SWITCH_WIDTH, 0, (SWITCH_ROW_HEIGHT - SWITCH_HEIGHT) / 2),
						UDim2.fromOffset(SWITCH_WIDTH, SWITCH_HEIGHT),
						function()
							setGit(not git)
						end,
						{
							color = UI.tokens.color.input,
							hoverColor = UI.tokens.color.input,
							pressedColor = UI.tokens.color.input,
							radius = SWITCH_HEIGHT / 2,
							border = true,
							borderColor = UI.tokens.color.border,
						}
					)

					knob = UI.frame(
						track,
						UDim2.fromOffset(KNOB_PAD, KNOB_PAD),
						UDim2.fromOffset(KNOB_SIZE, KNOB_SIZE),
						Color3.new(1, 1, 1),
						KNOB_SIZE / 2
					)

					knob.Name = "Knob"
					knob.Active = false

					renderSwitch()

					y += SWITCH_ROW_HEIGHT + FIELD_GAP
				end

				controller.fields = {
					name = nameInput,
					description = descriptionInput,
					icon = iconInput,
					folderPath = folderInput,
					qualityDropdown = qualityDropdown,
					dimensionDropdown = dimensionDropdown,
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
						Quality = quality,
						Dimension = dimension,
						Git = git,
					}
				end

				function controller:SetProjectProperties(props)
					props = props or {}

					nameInput.Text = props.Name or "New Project"
					descriptionInput.Text = props.Description or ""
					iconInput.Text = props.Icon or DEFAULT_ICON
					folderInput.Text = props.FolderPath or ""

					quality = props.Quality or DEFAULT_QUALITY
					dimension = props.Dimension or DEFAULT_DIMENSION

					if props.Git == nil then
						git = DEFAULT_GIT
					else
						git = props.Git == true
					end

					if qualityDropdown then
						qualityDropdown:SetValue(quality, true)
					end

					if dimensionDropdown then
						dimensionDropdown:SetValue(dimension, true)
					end

					if setGit then
						setGit(git)
					end
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
		showGameOptions = true,

		onSubmit = function(props)
			local success = Project:CreateProject(
				props.Name,
				props.FolderPath,
				props.Description,
				props.Icon,
				props.Git,
				DIMENSION_NUMBERS[props.Dimension] or DIMENSION_NUMBERS[DEFAULT_DIMENSION]
			)

			if not success then
				return false, "The project could not be created. Check the folder path."
			end

			local created = Project:GetActiveProject()

			applyQuality(created, props.Quality)

			showProject(created)
			refreshList()

			notify(
				"success",
				"Successfully created project!",
				`Successfully created project {props.Name}.`,
				`Description: {props.Description}\nIcon: {props.Icon}\nPath: {props.FolderPath}\nDimension: {props.Dimension}\nQuality: {props.Quality}\nGit: {props.Git and "Enabled" or "Disabled"}`,
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

					local ok, err = Project:DeleteProject(target.Path)

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
	list.SortOrder = Enum.SortOrder.LayoutOrder

	local cards = UI.create("ScrollingFrame", {
		Name = "ProjectCards",
		Position = UDim2.fromOffset(LIST_PADDING, LIST_PADDING + BUTTON_SIZE + GAP),
		Size = UDim2.new(1, -LIST_PADDING * 2, 1, -(LIST_PADDING * 2 + BUTTON_SIZE + GAP)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, 0),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = tokens.color.subtext,
		ClipsDescendants = true,
	}, projectsList)
	list.Parent = cards

	local controls = UI.frame(
		projectsList,
		UDim2.fromOffset(LIST_PADDING, LIST_PADDING),
		UDim2.new(1, -LIST_PADDING * 2, 0, BUTTON_SIZE),
		tokens.color.surfaceAlt,
		0
	)

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

			if not Preferences.get("confirmDelete") then
				local target = selectedProject
				local ok, err = Project:DeleteProject(target.Path)
				if ok then
					refreshList()
				else
					notify("error", "Could not remove project", err)
				end
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

	if Sync.available then
		UI.iconButton(
			controls,
			"builtin://global-icons/folder.svg",
			UDim2.new(1, -(BUTTON_SIZE * 4 + GAP * 3), 0, 0),
			UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE),
			function()
				local path = Dialog:PickFolder()
				if not path or path == "" then
					return
				end
				local ok, manifest = pcall(function()
					local source = game.Filesystem:ReadFile(path .. "/default.project.json")
					return game.HttpService:JSONDecode(source)
				end)
				if
					not ok
					or type(manifest) ~= "table"
					or type(manifest.name) ~= "string"
					or type(manifest.tree) ~= "table"
					or not Project:RegisterProject(path, manifest.name)
				then
					notify(
						"error",
						"Could not add project",
						"Choose an unregistered folder containing default.project.json."
					)
					return
				end
				refreshList()
				notify("success", "Project added", manifest.name)
			end,
			{ bgTransparency = 0 }
		)
	end

	local search = UI.input(
		controls,
		"Search projects...",
		UDim2.new(0, 0, 0, 0),
		UDim2.new(1, -((BUTTON_SIZE + GAP) * (Sync.available and 4 or 3)), 0, BUTTON_SIZE),
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
		card, _, record = UI.button(cards, "", UDim2.fromOffset(0, 0), UDim2.new(1, -8, 0, CARD_HEIGHT), function()
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
		card.Parent = cards
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
		description.Text = Preferences.get("debugLabels") and project.Path or project.Description or "Kinemium project"
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

		for _, project in pairs(Preferences.get("showRecentProjects") and Project:GetProjects() or {}) do
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

		cards.CanvasSize = UDim2.fromOffset(0, order * CARD_HEIGHT + math.max(order - 1, 0) * GAP)

		if not selectionStillVisible then
			selectedProject = nil
		end

		applySelection()
	end

	search.TextChanged:Connect(function()
		cards.CanvasPosition = Vector2.new(0, 0)
		refreshList()
	end)

	Preferences.Changed:Connect(function(key)
		if key == "showRecentProjects" or key == "debugLabels" then
			refreshList()
		end
	end)

	refreshList()
	task.defer(function()
		local active = Project:GetActiveProject()
		if active then
			showProject(active)
			return
		end
		if
			Preferences.get("reopenLastProject")
			or Preferences.get("restoreSession")
			or not Preferences.get("showStartPage")
		then
			local last = Preferences.get("sessionProject")
			if Preferences.get("reopenLastProject") or not Preferences.get("showStartPage") then
				last = Preferences.get("lastProject")
			end
			for _, project in pairs(Project:GetProjects()) do
				if project.Path == last then
					openProject(project)
					return
				end
			end
		end
	end)

	return {
		showProject = showProject,
		openProject = openProject,
		refreshList = refreshList,
	}
end
