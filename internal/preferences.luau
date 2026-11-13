local Studio = game:GetService("Studio")

local defaults = {
	theme = "Dark",
	monochrome = false,
	reduceMotion = false,
	pageZoom = "100%",
	resolution = "Automatic",
	restoreSession = false,
	autoSave = true,
	autoSaveInterval = "1 minute",
	confirmExit = true,
	showStartPage = true,
	hour24 = true,
	dateFormat = "19 Oct 2026",
	enterNewline = true,
	tabSpaces = true,
	tabSize = "4",
	lineNumbers = true,
	relativeLineNumbers = false,
	wordWrap = false,
	minimap = true,
	highlightCurrentLine = true,
	bracketMatching = true,
	autoIndent = true,
	autoClosingBrackets = true,
	autoClosingQuotes = true,
	autocomplete = true,
	parameterHints = true,
	hoverDocumentation = true,
	diagnostics = true,
	formatOnSave = true,
	restoreLayout = true,
	showStatusBar = true,
	showToolbar = true,
	showExplorer = true,
	showProperties = true,
	showOutput = true,
	viewportGrid = true,
	viewportAxes = true,
	viewportGizmos = true,
	viewportSelectionOutline = true,
	viewportCameraControls = true,
	showRecentProjects = true,
	confirmDelete = true,
	showFileExtensions = true,
	reopenLastProject = false,
	playtestMode = "Local Server",
	playtestHeadlessServer = false,
	playtestHeadlessClient = false,
	playtestSingleplayer = false,
	playtestPauseOnError = false,
	playtestOutput = true,
	playtestClearOutput = false,
	enableKeyboardShortcuts = true,
	vimMode = false,
	developerMode = false,
	debugLabels = false,
	verboseLogging = false,
	showPerformanceStats = true,
	profilerEnabled = false,
}

local Preferences = { Changed = Studio.SettingChanged }

function Preferences.get(key)
	local default = defaults[key]
	if string.sub(key, 1, 5) == "dock." or (key == "lastProject" or key == "sessionProject") then
		default = ""
	end
	local value = Studio:GetSetting(key, default)
	if type(value) == type(default) then
		return value
	end
	return default
end

function Preferences.set(key, value)
	Studio:SetSetting(key, value)
end

function Preferences.observe(key, callback)
	local function update(changed)
		if changed == key then
			callback(Preferences.get(key))
		end
	end
	update(key)
	return Studio.SettingChanged:Connect(update)
end

return Preferences
