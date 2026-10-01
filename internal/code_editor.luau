if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local UI = require("@internal/editor_ui")

local TextService = game:GetService("TextService")

local tokens = UI.tokens

local TAB_STRIP_HEIGHT = 26
local TAB_MIN_WIDTH = 104
local TAB_CLOSE_SIZE = 18
local TAB_FONT = "builtin://fonts/Montserrat-Regular.ttf"

--
-- Suggestion popup metrics
--

local SUGGEST_WIDTH = 268
local SUGGEST_ROW_HEIGHT = 22
local SUGGEST_MAX_ROWS = 7
local SUGGEST_PADDING = 4

-- Matches the line height the engine draws the code editor with. The popup is
-- anchored below the caret line, so it has to know how tall that line is.
local SUGGEST_LINE_HEIGHT = 22

--
-- Completion sources
--
-- Keywords and standard library names come from static tables because they
-- never change. Instance members are resolved live against the DataModel,
-- which is what makes `workspace.` offer the parts that actually exist in the
-- open place rather than a generic member list.
--

local KEYWORDS = {
	{ name = "and", kind = "Keyword" },
	{ name = "break", kind = "Keyword" },
	{ name = "continue", kind = "Keyword" },
	{ name = "do", kind = "Keyword" },
	{ name = "else", kind = "Keyword" },
	{ name = "elseif", kind = "Keyword" },
	{ name = "end", kind = "Keyword" },
	{ name = "export", kind = "Keyword" },
	{ name = "false", kind = "Keyword" },
	{ name = "for", kind = "Keyword" },
	{ name = "function", kind = "Keyword" },
	{ name = "if", kind = "Keyword" },
	{ name = "in", kind = "Keyword" },
	{ name = "local", kind = "Keyword" },
	{ name = "nil", kind = "Keyword" },
	{ name = "not", kind = "Keyword" },
	{ name = "or", kind = "Keyword" },
	{ name = "repeat", kind = "Keyword" },
	{ name = "return", kind = "Keyword" },
	{ name = "then", kind = "Keyword" },
	{ name = "true", kind = "Keyword" },
	{ name = "type", kind = "Keyword" },
	{ name = "until", kind = "Keyword" },
	{ name = "while", kind = "Keyword" },
}

local GLOBALS = {
	{ name = "game", kind = "Global" },
	{ name = "workspace", kind = "Global" },
	{ name = "script", kind = "Global" },
	{ name = "shared", kind = "Global" },
	{ name = "_G", kind = "Global" },
	{ name = "bit32", kind = "Table" },
	{ name = "buffer", kind = "Table" },
	{ name = "coroutine", kind = "Table" },
	{ name = "debug", kind = "Table" },
	{ name = "math", kind = "Table" },
	{ name = "os", kind = "Table" },
	{ name = "string", kind = "Table" },
	{ name = "table", kind = "Table" },
	{ name = "task", kind = "Table" },
	{ name = "utf8", kind = "Table" },
	{ name = "vector", kind = "Table" },
	{ name = "assert", kind = "Function" },
	{ name = "delay", kind = "Function" },
	{ name = "error", kind = "Function" },
	{ name = "getmetatable", kind = "Function" },
	{ name = "ipairs", kind = "Function" },
	{ name = "next", kind = "Function" },
	{ name = "pairs", kind = "Function" },
	{ name = "pcall", kind = "Function" },
	{ name = "print", kind = "Function" },
	{ name = "rawequal", kind = "Function" },
	{ name = "rawget", kind = "Function" },
	{ name = "rawlen", kind = "Function" },
	{ name = "rawset", kind = "Function" },
	{ name = "require", kind = "Function" },
	{ name = "select", kind = "Function" },
	{ name = "setmetatable", kind = "Function" },
	{ name = "spawn", kind = "Function" },
	{ name = "tick", kind = "Function" },
	{ name = "tonumber", kind = "Function" },
	{ name = "tostring", kind = "Function" },
	{ name = "type", kind = "Function" },
	{ name = "typeof", kind = "Function" },
	{ name = "unpack", kind = "Function" },
	{ name = "warn", kind = "Function" },
	{ name = "wait", kind = "Function" },
	{ name = "waitforchild", kind = "Function" },
	{ name = "BrickColor", kind = "Type" },
	{ name = "CFrame", kind = "Type" },
	{ name = "Color3", kind = "Type" },
	{ name = "Color3uint8", kind = "Type" },
	{ name = "ColorSequence", kind = "Type" },
	{ name = "Enum", kind = "Type" },
	{ name = "Instance", kind = "Type" },
	{ name = "NumberRange", kind = "Type" },
	{ name = "NumberSequence", kind = "Type" },
	{ name = "Random", kind = "Type" },
	{ name = "Ray", kind = "Type" },
	{ name = "Rect", kind = "Type" },
	{ name = "Region3", kind = "Type" },
	{ name = "TweenInfo", kind = "Type" },
	{ name = "UDim", kind = "Type" },
	{ name = "UDim2", kind = "Type" },
	{ name = "Vector2", kind = "Type" },
	{ name = "Vector3", kind = "Type" },
}

--
-- Members of things the DataModel cannot describe
--
-- `CFrame.new` and `math.floor` are as common as any instance member, and no
-- amount of walking the DataModel produces them: a datatype is a global
-- binding rather than a child of the game, and the standard library is not an
-- Instance at all. These are listed explicitly, which is what makes
-- `CFrame.` and `math.` complete.
--
-- Entries are "name:Kind" so the list stays readable at a glance.
--

local BUILTIN_MEMBERS = {
	CFrame = {
		"new:Method",
		"fromEulerAnglesXYZ:Method",
		"fromMatrix:Method",
		"fromOrientation:Method",
		"fromQuaternion:Method",
		"lookAt:Method",
		"angles:Property",
		"identity:Property",
		"Axes:Property",
		"Position:Property",
		"RightVector:Property",
		"UpVector:Property",
		"LookVector:Property",
		"X:Property",
		"Y:Property",
		"Z:Property",
		"Add:Method",
		"Sub:Method",
		"Mul:Method",
		"Div:Method",
		"Cross:Method",
		"Dot:Method",
		"Inverse:Method",
		"Lerp:Method",
		"LerpCFrame:Method",
		"GetComponents:Method",
		"PointToObjectSpace:Method",
		"PointToWorldSpace:Method",
		"Rotate:Method",
		"ToObjectSpace:Method",
		"ToWorldSpace:Method",
		"cf:Function",
		"p:Function",
		"r:Function",
		"u:Function",
		"look:Function",
		"right:Function",
		"up:Function",
		"pos:Function",
	},

	Vector2 = {
		"new:Method",
		"Dot:Method",
		"Cross:Method",
		"Angle:Method",
		"Lerp:Method",
		"Abs:Method",
		"Ceil:Method",
		"Clamp:Method",
		"Floor:Method",
		"Max:Method",
		"Min:Method",
		"Round:Method",
		"Sign:Method",
		"Unit:Method",
		"Magnitude:Property",
		"X:Property",
		"Y:Property",
	},

	Vector3 = {
		"new:Method",
		"Dot:Method",
		"Cross:Method",
		"Angle:Method",
		"Lerp:Method",
		"Abs:Method",
		"Ceil:Method",
		"Clamp:Method",
		"Floor:Method",
		"Max:Method",
		"Min:Method",
		"Round:Method",
		"Sign:Method",
		"Unit:Method",
		"Magnitude:Property",
		"X:Property",
		"Y:Property",
		"Z:Property",
	},

	Color3 = {
		"new:Method",
		"fromHSV:Method",
		"fromRGB:Method",
		"fromHex:Method",
		"fromUint8:Method",
		"Lerp:Method",
		"ToHex:Method",
		"ToHSV:Method",
		"ToRGB:Method",
		"ToUint8:Method",
		"B:Property",
		"G:Property",
		"R:Property",
	},

	Color3uint8 = { "new:Method", "B:Property", "G:Property", "R:Property" },

	UDim = { "new:Method", "Scale:Property", "Offset:Property" },

	UDim2 = {
		"new:Method",
		"fromAxis:Method",
		"fromOffset:Method",
		"fromScale:Method",
		"Lerp:Method",
		"Scale:Property",
		"X:Property",
		"Y:Property",
	},

	Ray = { "new:Method", "Direction:Property", "Origin:Property" },

	Rect = {
		"new:Method",
		"Abs:Method",
		"Max:Property",
		"Min:Property",
		"Size:Property",
		"X:Property",
		"Y:Property",
	},

	Region3 = { "new:Method", "CFrame:Property", "Size:Property" },

	Region3int16 = { "new:Method", "CFrame:Property", "Size:Property" },

	NumberRange = { "new:Method", "Max:Property", "Min:Property" },

	NumberSequence = { "new:Method", "Keypoint:Method", "Keypoints:Property" },

	ColorSequence = { "new:Method", "Keypoint:Method", "Keypoints:Property" },

	TweenInfo = {
		"new:Method",
		"DelayTime:Property",
		"Duration:Property",
		"Enum:Property",
		"RepeatCount:Property",
		"Reverses:Property",
	},

	BrickColor = { "new:Method", "Color:Property", "Name:Property", "Number:Property" },

	Random = {
		"new:Method",
		"NextInteger:Method",
		"NextNumber:Method",
		"NextUnitVector:Method",
	},

	Instance = {
		"new:Method",
		"fromJSON:Method",
		"Clone:Method",
		"Destroy:Method",
		"FindFirstChild:Method",
		"FindFirstChildOfClass:Method",
		"GetChildren:Method",
		"GetDescendants:Method",
		"GetFullName:Method",
		"GetAttribute:Method",
		"GetAttributes:Method",
		"SetAttribute:Method",
		"IsA:Method",
		"IsAncestorOf:Method",
		"IsDescendantOf:Method",
		"ClassName:Property",
		"Name:Property",
		"Parent:Property",
	},

	Enum = { "GetEnumItems:Method", "FromName:Method" },
}

-- The Luau standard library. Same "name:Kind" encoding as above.
BUILTIN_MEMBERS.math = {
	"abs:Function",
	"acos:Function",
	"asin:Function",
	"atan:Function",
	"atan2:Function",
	"ceil:Function",
	"clamp:Function",
	"cos:Function",
	"cosh:Function",
	"deg:Function",
	"exp:Function",
	"floor:Function",
	"fmod:Function",
	"frexp:Function",
	"ldexp:Function",
	"lerp:Function",
	"log:Function",
	"log10:Function",
	"max:Function",
	"min:Function",
	"modf:Function",
	"noise:Function",
	"pow:Function",
	"rad:Function",
	"random:Function",
	"randomseed:Function",
	"round:Function",
	"sign:Function",
	"sin:Function",
	"sinh:Function",
	"sqrt:Function",
	"tan:Function",
	"tanh:Function",
	"huge:Value",
	"pi:Value",
}

BUILTIN_MEMBERS.string = {
	"byte:Function",
	"char:Function",
	"find:Function",
	"format:Function",
	"gmatch:Function",
	"gsub:Function",
	"len:Function",
	"lower:Function",
	"match:Function",
	"pack:Function",
	"packsize:Function",
	"rep:Function",
	"reverse:Function",
	"split:Function",
	"sub:Function",
	"unpack:Function",
	"upper:Function",
}

BUILTIN_MEMBERS.table = {
	"clear:Function",
	"clone:Function",
	"concat:Function",
	"create:Function",
	"find:Function",
	"foreach:Function",
	"foreachi:Function",
	"freeze:Function",
	"getn:Function",
	"insert:Function",
	"isarray:Function",
	"isfrozen:Function",
	"join:Function",
	"maxn:Function",
	"move:Function",
	"pack:Function",
	"remove:Function",
	"sort:Function",
	"unfreeze:Function",
	"unpack:Function",
}

BUILTIN_MEMBERS.task = {
	"cancel:Function",
	"defer:Function",
	"delay:Function",
	"desynchronize:Function",
	"spawn:Function",
	"synchronize:Function",
	"wait:Function",
}

BUILTIN_MEMBERS.os = {
	"clock:Function",
	"date:Function",
	"difftime:Function",
	"time:Function",
}

BUILTIN_MEMBERS.coroutine = {
	"close:Function",
	"create:Function",
	"isyieldable:Function",
	"resume:Function",
	"running:Function",
	"status:Function",
	"wrap:Function",
	"yield:Function",
}

BUILTIN_MEMBERS.utf8 = {
	"char:Function",
	"codepoint:Function",
	"codes:Function",
	"graphemes:Function",
	"len:Function",
	"nfcnormalize:Function",
	"nfdnormalize:Function",
	"offset:Function",
}

BUILTIN_MEMBERS.bit32 = {
	"arshift:Function",
	"band:Function",
	"bnot:Function",
	"bor:Function",
	"btest:Function",
	"bxor:Function",
	"byteswap:Function",
	"countlz:Function",
	"countrz:Function",
	"extract:Function",
	"lrotate:Function",
	"lshift:Function",
	"replace:Function",
	"rrotate:Function",
	"rshift:Function",
}

BUILTIN_MEMBERS.debug = {
	"info:Function",
	"profilebegin:Function",
	"profileend:Function",
	"traceback:Function",
}

BUILTIN_MEMBERS.vector = {
	"angle:Function",
	"create:Function",
	"cross:Function",
	"dot:Function",
	"magnitude:Function",
	"normalize:Function",
}

BUILTIN_MEMBERS.buffer = {
	"copy:Function",
	"create:Function",
	"fill:Function",
	"fromstring:Function",
	"len:Function",
	"readf32:Function",
	"readf64:Function",
	"readi16:Function",
	"readi32:Function",
	"readi8:Function",
	"readstring:Function",
	"readu16:Function",
	"readu32:Function",
	"readu8:Function",
	"tostring:Function",
	"writef32:Function",
	"writef64:Function",
	"writei16:Function",
	"writei32:Function",
	"writei8:Function",
	"writestring:Function",
	"writeu16:Function",
	"writeu32:Function",
	"writeu8:Function",
}

-- Lowercased index of the tables above, so a member completion is not case
-- sensitive: `Cframe.` and `CFrame.` should both find CFrame, the same way
-- instance lookups are matched on exact names but candidates are matched
-- case insensitively.
local BUILTIN_MEMBERS_LOWER = {}

for key, entries in pairs(BUILTIN_MEMBERS) do
	BUILTIN_MEMBERS_LOWER[string.lower(key)] = entries
end

-- Turns a "name:Kind" entry into a candidate.
local function parseMember(entry)
	local separator = string.find(entry, ":", 1, true)

	if separator == nil then
		return { name = entry, kind = "Member" }
	end

	return {
		name = string.sub(entry, 1, separator - 1),
		kind = string.sub(entry, separator + 1),
	}
end

-- The members of a built-in type or standard library table, or nil when the
-- name is not one this table knows about.
local function collectBuiltinMembers(path)
	local entries = BUILTIN_MEMBERS[path] or BUILTIN_MEMBERS_LOWER[string.lower(path)]

	if entries == nil then
		return nil
	end

	local members = {}

	for _, entry in ipairs(entries) do
		table.insert(members, parseMember(entry))
	end

	return members
end

local KIND_COLORS = {
	Keyword = tokens.color.accent,
	Global = tokens.color.accent,
	Table = tokens.color.warning,
	Function = tokens.color.success,
	Method = tokens.color.success,
	Value = tokens.color.subtext,
	Type = tokens.color.subtext,
	Property = tokens.color.text,
	Member = tokens.color.text,
	Event = tokens.color.warning,
	Instance = tokens.color.text,
	Local = tokens.color.subtext,
}
local function kindColor(kind)
	return KIND_COLORS[kind] or tokens.color.text
end

--
-- CodeEditor
--
-- Owns the script TextBox, the tab strip, the open documents and the
-- autocomplete popup. The viewport requires this module and delegates to it:
-- the viewport owns the panel the editor sits in, the editor owns everything
-- that happens inside it.
--

local CodeEditor = {}
CodeEditor.__index = CodeEditor
function CodeEditor.new(parent)
	local self = setmetatable({}, CodeEditor)

	self.documents = {}
	self.documentByInstance = {}
	self.activeDocument = nil
	self.suppressTextSync = false

	-- Autocomplete state
	self.suggestions = {}
	self.suggestionIndex = 1
	self.suggestPrefix = nil
	self.suggestRange = nil
	self.applyingSuggestion = false

	local tabStrip = UI.create("ScrollingFrame", {
		Name = "ScriptTabs",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, TAB_STRIP_HEIGHT),
		BackgroundColor3 = tokens.color.panel,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		ScrollingEnabled = true,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = tokens.color.subtext,
		ScrollBarImageTransparency = 0.4,
		ScrollBarAutoHide = true,
		ScrollBarFadeDelay = 0.45,
		ScrollBarFadeSpeed = 12,
		ScrollBarMinimumHandleSize = 24,
		ClipsDescendants = true,
		Active = true,
		InputSink = true,
		Visible = false,
	}, parent)

	local editor = UI.create("TextBox", {
		Name = "CodeEditor",
		Size = UDim2.new(1, 0, 1, -TAB_STRIP_HEIGHT),
		Position = UDim2.fromOffset(0, TAB_STRIP_HEIGHT),
		CodeEditor = true,
		Visible = false,
		Active = true,
		AutoIndent = true,
		ShowMinimap = true,
		BackgroundTransparency = 0.3,
		BackgroundColor3 = Color3.new(0, 0, 0),
		TextColor3 = Color3.new(1, 1, 1),
	}, parent)

	UI.create("SyntaxHighlighter", { Parent = editor })
	UI.create("UIBackdrop", { Parent = editor })

	-- The popup lives in its own layer so it renders above the editor and is
	-- not clipped by the tab strip. CoreGui matches the layer the viewport
	-- already uses for the script editor.
	local suggestionLayer = UI.create("ScreenGui", {
		Name = "CodeEditorSuggestions",
		DisplayOrder = 2100,
		IgnoreGuiInset = true,
	}, game.CoreGui)

	suggestionLayer.RenderOnTop = true

	local popup = UI.frame(
		suggestionLayer,
		UDim2.fromOffset(0, 0),
		UDim2.fromOffset(SUGGEST_WIDTH, SUGGEST_ROW_HEIGHT + SUGGEST_PADDING * 2),
		tokens.color.surface,
		tokens.radius.sm
	)

	popup.Name = "SuggestionPopup"
	popup.Visible = false
	popup.Active = true
	popup.ClipsDescendants = true

	UI.stroke(popup, tokens.color.borderStrong, 1, 0)
	UI.create("UIShadow", {
		BlurRadius = UDim.new(0, 6),
		Offset = UDim2.fromOffset(0, 2),
		Spread = UDim2.fromOffset(0, 1),
		Color3 = Color3.new(0, 0, 0),
		Transparency = 0.4,
		Parent = popup,
	})

	self.TabStrip = tabStrip
	self.TextBox = editor
	self.SuggestionLayer = suggestionLayer
	self.Popup = popup
	self.rows = {}

	self:wireEditor()

	return self
end

--
-- Document helpers
--

function CodeEditor:isScriptInstance(instance)
	return instance ~= nil and (instance:IsA("Script") or instance:IsA("ModuleScript") or instance:IsA("LocalScript"))
end

function CodeEditor:tabWidthFor(name)
	local textSize = TextService:GetTextSize(name, tokens.type.small, TAB_FONT, Vector2.new(10000, 10000))

	return math.max(TAB_MIN_WIDTH, math.ceil(textSize.X) + 52)
end

function CodeEditor:commitDocument(document)
	local instance = document.instance

	if instance == nil or not UI.isAlive(instance) then
		return
	end

	pcall(function()
		instance.Source = document.source
	end)
end

function CodeEditor:hasDocument()
	return self.activeDocument ~= nil
end
--
-- Tab strip
--

function CodeEditor:rebuildTabs()
	UI.clear(self.TabStrip)

	local x = 0

	for _, document in ipairs(self.documents) do
		local isActive = document == self.activeDocument
		local background = isActive and tokens.color.surfaceAlt or tokens.color.panel

		local width = self:tabWidthFor(document.name)

		local tab, _, record = UI.button(
			self.TabStrip,
			"",
			UDim2.fromOffset(x, 0),
			UDim2.fromOffset(width, TAB_STRIP_HEIGHT),
			function()
				self:focusDocument(document)
			end,
			{
				color = background,
				hoverColor = tokens.color.hover,
				textColor = tokens.color.subtext,
				radius = 0,
				border = false,
			}
		)

		document.tab = tab
		document.tabRecord = record
		document.tabWidth = width

		document.tabLabel = UI.label(
			tab,
			document.name,
			UDim2.fromOffset(10, 6),
			UDim2.new(1, -TAB_CLOSE_SIZE - 16, 0, 14),
			tokens.type.small,
			isActive and tokens.color.text or tokens.color.subtext
		)

		UI.iconButton(
			tab,
			"builtin://global-icons/x.svg",
			UDim2.new(1, -TAB_CLOSE_SIZE - 4, 0.5, -math.floor(TAB_CLOSE_SIZE / 2)),
			UDim2.fromOffset(TAB_CLOSE_SIZE, TAB_CLOSE_SIZE),
			function()
				self:closeDocument(document)
			end,
			{
				color = background,
				hoverColor = tokens.color.error,
				radius = 0,
				border = false,
				iconSize = 10,
			}
		)

		if isActive then
			UI.frame(tab, UDim2.new(0, 0, 1, -2), UDim2.new(1, 0, 0, 2), tokens.color.accent, 0)
		end

		x += width
	end

	self.TabStrip.CanvasSize = UDim2.fromOffset(x, 0)

	UI.frame(self.TabStrip, UDim2.new(0, 0, 1, -1), UDim2.new(1, 0, 0, 1), tokens.color.border)
end

--
-- Document lifecycle
--

function CodeEditor:loadDocument(document)
	self.activeDocument = document

	self.suppressTextSync = true
	self.TextBox.Text = document.source
	self.suppressTextSync = false

	self:dismissSuggestions()

	self:rebuildTabs()
	self:updateVisibility()
end

function CodeEditor:focusDocument(document)
	if document == nil or document == self.activeDocument then
		return
	end

	if self.activeDocument ~= nil then
		self.activeDocument.source = self.TextBox.Text

		self:commitDocument(self.activeDocument)
	end

	self:loadDocument(document)
end

function CodeEditor:closeDocument(document)
	if document == nil then
		return
	end

	local index = table.find(self.documents, document)

	if index == nil then
		return
	end

	local wasActive = document == self.activeDocument

	if wasActive then
		document.source = self.TextBox.Text
	end

	self:commitDocument(document)

	if document.instance ~= nil then
		self.documentByInstance[document.instance] = nil
	end

	table.remove(self.documents, index)

	if wasActive then
		self.activeDocument = nil

		local neighbour = self.documents[index] or self.documents[index - 1]

		if neighbour ~= nil then
			self:loadDocument(neighbour)
		else
			self.suppressTextSync = true
			self.TextBox.Text = ""
			self.suppressTextSync = false

			self:dismissSuggestions()

			self:rebuildTabs()
			self:updateVisibility()
		end
	end
end

function CodeEditor:OpenScript(instance)
	if not self:isScriptInstance(instance) then
		return
	end

	local document = self.documentByInstance[instance]

	if document == nil then
		local source = ""
		local ok, value = pcall(function()
			return instance.Source
		end)

		if ok and type(value) == "string" then
			source = value
		end

		document = {
			instance = instance,
			name = instance.Name,
			source = source,
		}

		table.insert(self.documents, document)
		self.documentByInstance[instance] = document
	end

	self:focusDocument(document)
end

function CodeEditor:CloseScript(instance)
	self:closeDocument(self.documentByInstance[instance])
end

function CodeEditor:CloseAllScripts()
	local snapshot = table.clone(self.documents)

	for _, document in ipairs(snapshot) do
		self:closeDocument(document)
	end
end

function CodeEditor:IsScriptOpen(instance)
	return self.documentByInstance[instance] ~= nil
end

function CodeEditor:OpenScriptCount()
	return #self.documents
end

function CodeEditor:ActiveScript()
	return self.activeDocument and self.activeDocument.instance or nil
end

function CodeEditor:GetSource()
	if self.activeDocument ~= nil then
		return self.activeDocument.source
	end

	return self.TextBox.Text
end

function CodeEditor:updateVisibility()
	self.TextBox.Visible = self:hasDocument()
	self.TabStrip.Visible = #self.documents > 0

	if not self:hasDocument() then
		self:dismissSuggestions()
	end
end
--
-- Autocomplete: candidate collection
--

-- Splits a dotted path into its segments, and reports whether the path ends
-- in a dot. A trailing dot is an explicit "members of" request, which is
-- different from a partially typed member name.
local function splitPath(path)
	local segments = {}
	local current = ""

	for index = 1, #path do
		local character = string.sub(path, index, index)

		if character == "." then
			table.insert(segments, current)
			current = ""
		else
			current ..= character
		end
	end

	local ends_with_dot = current == ""

	if not ends_with_dot then
		table.insert(segments, current)
	end

	return segments, ends_with_dot
end

-- The roots a script reaches the DataModel through. They are globals rather
-- than children of the game, so `game` and `workspace` have to be recognised
-- explicitly or `game.` would list nothing.
local function resolveRoot(name)
	if name == "game" then
		return game
	end

	if name == "workspace" then
		return workspace
	end

	return nil
end

-- Resolves the first `upto` segments against the DataModel, returning the
-- Instance they name or nil when any step is missing.
local function resolveInstance(segments, upto)
	if upto <= 0 then
		return nil
	end

	local root = resolveRoot(segments[1])

	if root == nil then
		root = game:FindFirstChild(segments[1])
	end

	if root == nil then
		return nil
	end

	for index = 2, upto do
		local child = root:FindFirstChild(segments[index])

		if child == nil then
			return nil
		end

		root = child
	end

	return root
end

-- Resolves as much of a path as the DataModel knows about, so `workspace.Part`
-- still resolves `workspace` when no child is named `Part`. The segment that
-- failed to resolve is the member being typed.
local function resolveLongestPrefix(segments)
	local instance = nil
	local resolved = 0

	for index = 1, #segments do
		local candidate = resolveInstance(segments, index)

		if candidate == nil then
			break
		end

		instance = candidate
		resolved = index
	end

	return instance, resolved
end

-- Reflection reports the members of any class the engine knows about, which
-- covers properties, methods and events for an instance we can resolve but
-- whose members are not its children.
local function collectReflectionMembers(instance)
	local results = {}

	local ReflectionService = game:GetService("ReflectionService")

	local lists = {
		{ kind = "Property", method = "GetPropertiesOfClass" },
		{ kind = "Method", method = "GetMethodsOfClass" },
		{ kind = "Event", method = "GetEventsOfClass" },
	}

	for _, list in ipairs(lists) do
		local ok, members = pcall(function()
			return ReflectionService[list.method](ReflectionService, instance.ClassName)
		end)

		if ok and type(members) == "table" then
			for _, member in ipairs(members) do
				local name = type(member) == "table" and member.Name or member

				if type(name) == "string" then
					table.insert(results, {
						name = name,
						kind = list.kind,
					})
				end
			end
		end
	end

	return results
end

-- Identifiers already present in the buffer. Completing a name the script
-- itself defines is usually the most useful thing an editor can offer, and it
-- costs one pattern pass over the source.
local function collectDocumentWords(source)
	local words = {}
	local seen = {}

	for word in string.gmatch(source, "[%a_][%w_]*") do
		if not seen[word] then
			seen[word] = true

			table.insert(words, {
				name = word,
				kind = "Local",
			})
		end
	end

	return words
end

-- Ranks a candidate against what the user typed. Lower is better; nil means
-- no match at all.
local function scoreMatch(name, prefix)
	if prefix == "" then
		return 1
	end

	local lowered = string.lower(name)
	local loweredPrefix = string.lower(prefix)

	if lowered == loweredPrefix then
		return 0
	end

	if string.sub(lowered, 1, #loweredPrefix) == loweredPrefix then
		return 1
	end

	-- Subsequence match (`gws` matching `GetWorkspace`) is what makes
	-- abbreviated queries useful against long member names.
	local index = 1

	for position = 1, #lowered do
		if
			index <= #loweredPrefix
			and string.sub(lowered, position, position) == string.sub(loweredPrefix, index, index)
		then
			index += 1
		end
	end

	if index > #loweredPrefix then
		return 2
	end

	if string.find(lowered, loweredPrefix, 1, true) ~= nil then
		return 3
	end

	return nil
end

-- Children and reflected members of an instance, which is what a member
-- completion offers. Children come first and carry their class name as the
-- detail: in a real place those are what a script is reaching for.
local function collectInstanceMembers(instance)
	local members = {}

	for _, child in ipairs(instance:GetChildren()) do
		table.insert(members, {
			name = child.Name,
			kind = "Instance",
			detail = child.ClassName,
		})
	end

	for _, member in ipairs(collectReflectionMembers(instance)) do
		table.insert(members, member)
	end

	return members
end

-- The language vocabulary plus the words already present in the buffer, which
-- is what a non-member completion offers.
local function collectVocabulary(source)
	local candidates = {}

	for _, keyword in ipairs(KEYWORDS) do
		table.insert(candidates, keyword)
	end

	for _, global in ipairs(GLOBALS) do
		table.insert(candidates, global)
	end

	for _, word in ipairs(collectDocumentWords(source)) do
		table.insert(candidates, word)
	end

	return candidates
end

-- Chooses the candidate source for the path under the cursor.
--
-- The receiver is everything in the path except the segment being typed: for
-- `workspace.Pa` that is `workspace`, and for `workspace.` it is the whole
-- path. A completion with a receiver is a member completion, and completes
-- against either the Instance the receiver names or, for a datatype or
-- standard library the DataModel cannot describe, its listed members.
function CodeEditor:collectCandidates(segments, ends_with_dot)
	local receiver = {}

	local count = ends_with_dot and #segments or #segments - 1

	for index = 1, count do
		receiver[index] = segments[index]
	end

	if #receiver > 0 then
		local instance, resolved = resolveLongestPrefix(receiver)

		if instance ~= nil and resolved == #receiver then
			local members = collectInstanceMembers(instance)

			if #members > 0 then
				return members
			end
		else
			-- A datatype (CFrame) or a standard library table (math) is not
			-- reachable through the DataModel at all.
			local members = collectBuiltinMembers(table.concat(receiver, "."))

			if members ~= nil then
				return members
			end
		end
	end

	local source = self.activeDocument and self.activeDocument.source or self.TextBox.Text

	return collectVocabulary(source)
end
--
-- Autocomplete: popup
--

function CodeEditor:dismissSuggestions()
	self.suggestions = {}
	self.suggestionIndex = 1
	self.suggestPrefix = nil
	self.suggestRange = nil

	if UI.isAlive(self.Popup) then
		self.Popup.Visible = false
	end
end

function CodeEditor:refreshSuggestions()
	local word = self.TextBox:GetWordRangeAtCursor()

	if word == nil then
		self:dismissSuggestions()
		return
	end

	local path = word.text or ""

	if path == "" then
		self:dismissSuggestions()
		return
	end

	local segments, ends_with_dot = splitPath(path)

	-- The prefix is the part of the member being typed. A trailing dot means
	-- nothing has been typed yet and everything the target offers is fair
	-- game, which is why the list is unfiltered in that case.
	local prefix = ends_with_dot and "" or (segments[#segments] or "")

	if prefix == "" and not ends_with_dot then
		self:dismissSuggestions()
		return
	end

	local ranked = {}

	for _, candidate in ipairs(self:collectCandidates(segments, ends_with_dot)) do
		local score = scoreMatch(candidate.name, prefix)

		if score ~= nil then
			table.insert(ranked, {
				name = candidate.name,
				kind = candidate.kind,
				detail = candidate.detail,
				score = score,
			})
		end
	end

	if #ranked == 0 then
		self:dismissSuggestions()
		return
	end

	table.sort(ranked, function(a, b)
		if a.score ~= b.score then
			return a.score < b.score
		end

		return string.lower(a.name) < string.lower(b.name)
	end)

	self.suggestions = ranked
	self.suggestPrefix = prefix
	self.suggestRange = self:completionRange(word, segments, ends_with_dot)
	self.suggestionIndex = 1

	self:renderSuggestions()
end

-- The range a completion replaces. The box reports the whole dotted path, but
-- a suggestion names only the final member, so only the last segment is
-- replaced: accepting `Part` for `workspace.Pa` must leave `workspace.` alone.
--
-- After a trailing dot nothing has been typed, so the range is empty and the
-- completion is inserted at the caret instead of replacing anything.
function CodeEditor:completionRange(word, segments, ends_with_dot)
	if ends_with_dot then
		return { start = word.finish, finish = word.finish }
	end

	local offset = 0

	for index = 1, #segments - 1 do
		offset += #segments[index] + 1
	end

	return { start = word.start + offset, finish = word.finish }
end

function CodeEditor:moveSuggestion(delta)
	local count = #self.suggestions

	if count == 0 then
		return
	end

	self.suggestionIndex = ((self.suggestionIndex - 1 + delta) % count) + 1

	self:renderSuggestions()
end

function CodeEditor:renderSuggestions()
	local count = math.min(#self.suggestions, SUGGEST_MAX_ROWS)

	if count == 0 then
		self:dismissSuggestions()
		return
	end

	local height = count * SUGGEST_ROW_HEIGHT + SUGGEST_PADDING * 2

	self.Popup.Size = UDim2.fromOffset(SUGGEST_WIDTH, height)

	-- The caret position is published by the code editor renderer, so the
	-- popup anchors to where the caret was actually drawn rather than
	-- re-deriving the gutter width and scroll offset itself.
	local anchor = self.TextBox.CaretScreenPosition or Vector2.new(0, 0)
	local camera = workspace.CurrentCamera
	local screen = camera and camera.ViewportSize or Vector2.new(1280, 720)

	local x = anchor.X
	local y = anchor.Y + SUGGEST_LINE_HEIGHT

	-- Flip above the caret when the list would run off the bottom edge, and
	-- clamp horizontally so the popup never leaves the window.
	if y + height > screen.Y - 8 then
		y = math.max(8, anchor.Y - height - 4)
	end

	x = math.clamp(x, 8, math.max(8, screen.X - SUGGEST_WIDTH - 8))

	self.Popup.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
	self.Popup.Visible = true

	UI.clear(self.Popup)

	self.rows = {}

	for index = 1, count do
		local suggestion = self.suggestions[index]
		local isSelected = index == self.suggestionIndex

		local row = UI.button(
			self.Popup,
			"",
			UDim2.fromOffset(SUGGEST_PADDING, SUGGEST_PADDING + (index - 1) * SUGGEST_ROW_HEIGHT),
			UDim2.new(1, -SUGGEST_PADDING * 2, 0, SUGGEST_ROW_HEIGHT),
			function()
				self:acceptSuggestion(index)
			end,
			{
				color = isSelected and tokens.color.selection or tokens.color.surface,
				hoverColor = tokens.color.selectionHover,
				radius = tokens.radius.xs,
				border = false,
			}
		)

		UI.label(
			row,
			suggestion.name,
			UDim2.fromOffset(6, 3),
			UDim2.new(1, -76, 1, -6),
			tokens.type.small,
			isSelected and tokens.color.text or kindColor(suggestion.kind)
		)

		UI.label(
			row,
			suggestion.detail or suggestion.kind or "",
			UDim2.new(1, -70, 0, 3),
			UDim2.fromOffset(64, SUGGEST_ROW_HEIGHT - 6),
			tokens.type.caption,
			tokens.color.muted
		)

		table.insert(self.rows, row)
	end
end

function CodeEditor:acceptSuggestion(index)
	local suggestion = self.suggestions[index or self.suggestionIndex]
	local range = self.suggestRange

	if suggestion == nil or range == nil then
		self:dismissSuggestions()
		return
	end

	-- The range is captured before dismissing, since dismissing clears the
	-- state this method still needs.
	local insert = suggestion.name

	self:dismissSuggestions()

	self.applyingSuggestion = true

	-- The range is replaced wholesale with the full suggestion name. The box
	-- performs the swap as a single undoable edit, so accepting a completion
	-- costs one undo step exactly like typing the word by hand.
	self.TextBox:ReplaceRange(range.start, range.finish, insert)

	self.applyingSuggestion = false

	self.TextBox:CaptureFocus()
end

--
-- Wiring
--

function CodeEditor:wireEditor()
	self.TextBox.TextChanged:Connect(function()
		if self.suppressTextSync then
			return
		end

		if self.activeDocument ~= nil then
			self.activeDocument.source = self.TextBox.Text

			self:commitDocument(self.activeDocument)
		end

		-- Re-query on every keystroke so the list tracks the word being typed.
		-- Applying a suggestion drives TextChanged itself and that edit is
		-- already decided, so it is skipped here.
		if not self.applyingSuggestion then
			self:refreshSuggestions()
		end
	end)

	self.TextBox.FocusLost:Connect(function()
		-- Clicking a popup row blurs the editor before the row handles the
		-- click, so dismissal waits a frame to let that click land.
		task.defer(function()
			if not self.TextBox:IsFocused() then
				self:dismissSuggestions()
			end
		end)
	end)

	-- KeyDown fires before the box acts on a key, which is what lets the popup
	-- claim the navigation and accept keys. Setting KeyHandled tells the box
	-- to skip its own handling of that same key.
	self.TextBox.KeyDown:Connect(function(input)
		if #self.suggestions == 0 then
			return
		end

		local keyCode = input and input.KeyCode

		if keyCode == Enum.KeyCode.Up then
			self:moveSuggestion(-1)
			self.TextBox.KeyHandled = true
		elseif keyCode == Enum.KeyCode.Down then
			self:moveSuggestion(1)
			self.TextBox.KeyHandled = true
		elseif keyCode == Enum.KeyCode.Return or keyCode == Enum.KeyCode.Tab or keyCode == Enum.KeyCode.KeypadEnter then
			self:acceptSuggestion()
			self.TextBox.KeyHandled = true
		elseif keyCode == Enum.KeyCode.Escape then
			self:dismissSuggestions()
			self.TextBox.KeyHandled = true
		end
	end)
end

return CodeEditor
