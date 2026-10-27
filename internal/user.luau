local Auth = require("@internal/auth")
local UI = require("@internal/editor_ui")
local MatrixService = game:GetService("MatrixService")
local http = game:GetService("HttpService")

local colors = UI.tokens.color
local tokens = UI.tokens

shared.CurrentSession = shared.CurrentSession or MatrixService:GetSession()

local function svgIcon(body)
	return "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24' viewBox='0 0 24 24' fill='none' stroke='white' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'>"
		.. body
		.. "</svg>"
end

local ICONS = {
	general = "builtin://icons/Settings.svg",
	account = "builtin://icons/Player.svg",
	notifications = "builtin://icons/UINotificationLayout.svg",
	devices = "builtin://icons/MultipleDevices.svg",
	emojis = "builtin://icons/Sparkles.svg",
	developer = "builtin://icons/Script.svg",
	about = "builtin://global-icons/Info.svg",
	power = svgIcon("<path d='M12 2v10'/><path d='M18.4 6.6a9 9 0 1 1-12.77.04'/>"),
	editor = "builtin://icons/Script.svg",
	studio = "builtin://icons/Settings.svg",
	projects = "builtin://icons/Folder.svg",
	playtest = "builtin://icons/PlaySolo.svg",
	shortcuts = "builtin://icons/Keyboard.svg",
}

local state = {
	theme = UI.getTheme(),
	monochrome = false,
	twitterEmoji = true,
	pageZoom = "100%",
	hour24 = false,
	dateFormat = "19 Oct 2026",
	enterNewline = false,
	tabSpaces = true,
	tabSize = "4",
	rememberSession = MatrixService.RememberSession ~= false,

	notifyDirect = true,
	notifyMentions = true,
	notifyInvites = true,
	notifySounds = false,
	notificationSound = "Chime",

	verifyDevices = true,
	offlineDevices = false,

	emojiAutocomplete = true,
	largeEmoji = true,
	stickerSuggestions = true,
	emojiSet = "Twitter",

	developerMode = false,
	syncLogging = false,
	debugLabels = false,
	restoreSession = true,
	autoSave = true,
	autoSaveInterval = "5 minutes",
	confirmExit = true,
	showStartPage = true,
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
	formatOnSave = false,
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
	reopenLastProject = true,
	playtestMode = "Client",
	playtestHeadlessServer = false,
	playtestHeadlessClient = false,
	playtestSingleplayer = false,
	playtestPauseOnError = true,
	playtestOutput = true,
	playtestClearOutput = false,
	enableKeyboardShortcuts = true,
	vimMode = false,
	verboseLogging = false,
	showPerformanceStats = false,
	profilerEnabled = false,
	reduceMotion = UI.shared().reduceMotion == true,
}

do
	local ok, studio = pcall(function()
		return game:GetService("Studio")
	end)
	if ok and studio then
		if studio.GetSetting then
			local rm = studio:GetSetting("reduceMotion")
			if rm ~= nil then
				state.reduceMotion = rm == true
			end
			local d = studio:GetSetting("diagnostics")
			if d ~= nil then
				state.diagnostics = d == true
				UI.shared().scriptDiagnostics = d == true
			end
			local t = studio:GetSetting("theme")
			if t ~= nil then
				state.theme = t
				UI.setTheme(t)
			end
		end
	end
end

local function SetImage(session, image)
	local ok, profile = MatrixService:GetProfile(session)

	if not ok or not profile.avatarUrl then
		return
	end

	local url = MatrixService:MxcToHttp(session.homeserver, profile.avatarUrl, {
		authenticated = true,
		width = 128,
		height = 128,
		method = "crop",
	})

	if not url then
		return
	end

	local content = http:GetImageBytes(url, {
		Authorization = "Bearer " .. session.accessToken,
	})

	image.Image = content
end

local function dropdownItems(values)
	local result = {}

	for _, value in ipairs(values) do
		table.insert(result, {
			value = value,
			label = value,
		})
	end

	return result
end
