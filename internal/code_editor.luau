if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local UI = require("@internal/editor_ui")

local TextService = game:GetService("TextService")
local RunService = game:GetService("RunService")

local tokens = UI.tokens

local TAB_STRIP_HEIGHT = 26
local FIND_WIDTH = 300
local FIND_HEIGHT = 28
local TAB_MIN_WIDTH = 104
local TAB_CLOSE_SIZE = 18
local TAB_FONT = "builtin://fonts/Montserrat-Regular.ttf"

local SUGGEST_WIDTH = 268
local SUGGEST_ROW_HEIGHT = 22
local SUGGEST_MAX_ROWS = 7
local SUGGEST_PADDING = 4
local SUGGEST_ICON_SIZE = 12

local SUGGEST_LINE_HEIGHT = 22

local iconRoot = "builtin://global-icons/"

local KIND_ICONS = {
	Keyword = "sparkle.png",
	Local = "pencil.svg",
	Global = "folder.svg",
	Type = "folder.svg",
	Instance = "folder.svg",
	Table = "grid.svg",
	Property = "grid.svg",
	Member = "grid.svg",
	Value = "grid.svg",
	Function = "api.png",
	Method = "api.png",
	Event = "info.png",
	Service = "info.png",
}

local SIGNATURES = {
	["math.abs"] = { "x" },
	["math.acos"] = { "x" },
	["math.asin"] = { "x" },
	["math.atan"] = { "x" },
	["math.atan2"] = { "y", "x" },
	["math.ceil"] = { "x" },
	["math.clamp"] = { "value", "min", "max" },
	["math.cos"] = { "x" },
	["math.cosh"] = { "x" },
	["math.deg"] = { "x" },
	["math.exp"] = { "x" },
	["math.floor"] = { "x" },
	["math.fmod"] = { "x", "y" },
	["math.frexp"] = { "x" },
	["math.ldexp"] = { "m", "e" },
	["math.lerp"] = { "alpha", "from", "to" },
	["math.log"] = { "x", "base" },
	["math.log10"] = { "x" },
	["math.max"] = { "a", "b" },
	["math.min"] = { "a", "b" },
	["math.modf"] = { "x" },
	["math.noise"] = { "x", "y", "z" },
	["math.pow"] = { "x", "y" },
	["math.rad"] = { "x" },
	["math.random"] = { "m", "n" },
	["math.randomseed"] = { "x" },
	["math.round"] = { "x" },
	["math.sign"] = { "x" },
	["math.sin"] = { "x" },
	["math.sinh"] = { "x" },
	["math.sqrt"] = { "x" },
	["math.tan"] = { "x" },
	["math.tanh"] = { "x" },

	["string.byte"] = { "s", "i", "j" },
	["string.char"] = { "..." },
	["string.find"] = { "s", "pattern", "init", "plain" },
	["string.format"] = { "s", "..." },
	["string.gmatch"] = { "s", "pattern" },
	["string.gsub"] = { "s", "pattern", "replacement", "n" },
	["string.len"] = { "s" },
	["string.lower"] = { "s" },
	["string.match"] = { "s", "pattern", "init" },
	["string.pack"] = { "..." },
	["string.packsize"] = { "s" },
	["string.rep"] = { "s", "n", "separator" },
	["string.reverse"] = { "s" },
	["string.split"] = { "s", "separator" },
	["string.sub"] = { "s", "i", "j" },
	["string.unpack"] = { "s", "pos" },
	["string.upper"] = { "s" },

	["table.clear"] = { "list" },
	["table.clone"] = { "list" },
	["table.concat"] = { "list", "separator", "i", "j" },
	["table.create"] = { "count" },
	["table.find"] = { "list", "value", "init" },
	["table.foreach"] = { "list", "callback" },
	["table.foreachi"] = { "list", "callback" },
	["table.getn"] = { "list" },
	["table.insert"] = { "list", "value" },
	["table.isarray"] = { "list" },
	["table.isfrozen"] = { "list" },
	["table.join"] = { "..." },
	["table.maxn"] = { "list" },
	["table.move"] = { "source", "from", "to", "target", "targetFrom" },
	["table.pack"] = { "..." },
	["table.remove"] = { "list", "index" },
	["table.sort"] = { "list", "comparator" },
	["table.unfreeze"] = { "list" },

	["task.cancel"] = { "thread" },
	["task.defer"] = { "callback", "..." },
	["task.delay"] = { "seconds", "callback", "..." },
	["task.desynchronize"] = { "callback", "..." },
	["task.spawn"] = { "callback", "..." },
	["task.synchronize"] = { "callback", "..." },
	["task.wait"] = { "seconds" },

	["os.clock"] = {},
	["os.date"] = { "format", "time" },
	["os.difftime"] = { "t2", "t1" },
	["os.time"] = { "table" },

	["coroutine.close"] = { "co" },
	["coroutine.create"] = { "f" },
	["coroutine.isyieldable"] = {},
	["coroutine.resume"] = { "co", "..." },
	["coroutine.running"] = {},
	["coroutine.status"] = { "co" },
	["coroutine.wrap"] = { "f" },
	["coroutine.yield"] = { "..." },

	["utf8.char"] = { "..." },
	["utf8.codepoint"] = { "s", "i", "j" },
	["utf8.codes"] = { "s" },
	["utf8.graphemes"] = { "s" },
	["utf8.len"] = { "s", "i", "j" },
	["utf8.nfcnormalize"] = { "s" },
	["utf8.nfdnormalize"] = { "s" },
	["utf8.offset"] = { "s", "n", "i" },

	["bit32.arshift"] = { "x", "disp" },
	["bit32.band"] = { "x", "y" },
	["bit32.bnot"] = { "x" },
	["bit32.bor"] = { "x", "y" },
	["bit32.btest"] = { "x", "y" },
	["bit32.bxor"] = { "x", "y" },
	["bit32.byteswap"] = { "x" },
	["bit32.countlz"] = { "x" },
	["bit32.countrz"] = { "x" },
	["bit32.extract"] = { "x", "field", "width" },
	["bit32.lrotate"] = { "x", "disp" },
	["bit32.lshift"] = { "x", "disp" },
	["bit32.replace"] = { "x", "v", "field", "width" },
	["bit32.rrotate"] = { "x", "disp" },
	["bit32.rshift"] = { "x", "disp" },

	["debug.info"] = { "..." },
	["debug.profilebegin"] = { "label" },
	["debug.profileend"] = {},
	["debug.traceback"] = { "message", "level" },

	["vector.create"] = { "x", "y", "z" },
	["vector.angle"] = { "a", "b" },
	["vector.cross"] = { "a", "b" },
	["vector.dot"] = { "a", "b" },
	["vector.magnitude"] = { "v" },
	["vector.normalize"] = { "v" },

	["buffer.create"] = { "size" },
	["buffer.copy"] = { "target", "source", "targetStart", "sourceStart", "count" },
	["buffer.fill"] = { "buffer", "value", "start", "count" },
	["buffer.fromstring"] = { "s" },
	["buffer.len"] = { "buffer" },
	["buffer.readf32"] = { "buffer", "offset" },
	["buffer.readi32"] = { "buffer", "offset" },
	["buffer.readi8"] = { "buffer", "offset" },
	["buffer.readstring"] = { "buffer", "offset", "count" },
	["buffer.readu8"] = { "buffer", "offset" },
	["buffer.tostring"] = { "buffer" },
	["buffer.writef32"] = { "buffer", "offset", "value" },
	["buffer.writei32"] = { "buffer", "offset", "value" },
	["buffer.writei8"] = { "buffer", "offset", "value" },
	["buffer.writestring"] = { "buffer", "offset", "value", "count" },
	["buffer.writeu8"] = { "buffer", "offset", "value" },

	["Vector2.new"] = { "x", "y" },
	["Vector2.Unit"] = { "self" },
	["Vector2.Cross"] = { "a", "b" },
	["Vector2.Dot"] = { "a", "b" },
	["Vector2.FuzzyEq"] = { "other", "epsilon" },
	["Vector2.Lerp"] = { "alpha", "other" },

	["Vector3.new"] = { "x", "y", "z" },
	["Vector3.FromNormalId"] = { "normalId" },
	["Vector3.FromAxis"] = { "axis" },
	["Vector3.Unit"] = { "self" },
	["Vector3.Abs"] = { "self" },
	["Vector3.Ceil"] = { "self" },
	["Vector3.Floor"] = { "self" },
	["Vector3.Sign"] = { "self" },
	["Vector3.Cross"] = { "a", "b" },
	["Vector3.Angle"] = { "other" },
	["Vector3.Dot"] = { "a", "b" },
	["Vector3.FuzzyEq"] = { "other", "epsilon" },
	["Vector3.Lerp"] = { "alpha", "other" },
	["Vector3.Max"] = { "other" },
	["Vector3.Min"] = { "other" },

	["Vector2int16.new"] = { "x", "y" },
	["Vector3int16.new"] = { "x", "y", "z" },

	["Color3.new"] = { "red", "green", "blue" },
	["Color3.fromRGB"] = { "red", "green", "blue" },
	["Color3.fromHSV"] = { "hue", "saturation", "value" },
	["Color3.fromHex"] = { "hex" },
	["Color3.Lerp"] = { "alpha", "other" },
	["Color3.ToHSV"] = { "self" },
	["Color3.ToHex"] = { "self" },
	["Color3.ToRGB"] = { "self" },

	["CFrame.new"] = { "x", "y", "z" },
	["CFrame.Angles"] = { "rx", "ry", "rz" },
	["CFrame.fromEulerAnglesXYZ"] = { "rx", "ry", "rz" },
	["CFrame.fromEulerAnglesYXZ"] = { "ry", "rx", "rz" },
	["CFrame.fromOrientation"] = { "rx", "ry", "rz" },
	["CFrame.fromAxisAngle"] = { "axis", "angle" },
	["CFrame.lookAt"] = { "at", "look" },
	["CFrame.lookAlong"] = { "at", "dir" },
	["CFrame.fromMatrix"] = { "pos", "vX", "vY", "vZ" },
	["CFrame.Lerp"] = { "alpha", "other" },
	["CFrame.ToWorldSpace"] = { "other" },
	["CFrame.ToObjectSpace"] = { "other" },
	["CFrame.PointToWorldSpace"] = { "otherPoint" },
	["CFrame.PointToObjectSpace"] = { "otherPoint" },
	["CFrame.VectorToWorldSpace"] = { "otherVector" },
	["CFrame.VectorToObjectSpace"] = { "otherVector" },
	["CFrame.Orthonormalize"] = { "self" },
	["CFrame.AngleBetween"] = { "other" },
	["CFrame.FuzzyEq"] = { "other", "epsilon" },
	["CFrame.ToEulerAnglesXYZ"] = { "self" },
	["CFrame.ToEulerAnglesYXZ"] = { "self" },
	["CFrame.ToOrientation"] = { "self" },
	["CFrame.ToAxisAngle"] = { "self" },

	["Quaternion.new"] = { "x", "y", "z", "w" },
	["Quaternion.fromAxisAngle"] = { "axis", "angle" },
	["Quaternion.Unit"] = { "self" },
	["Quaternion.Conjugate"] = { "self" },
	["Quaternion.Inverse"] = { "self" },
	["Quaternion.Dot"] = { "a", "b" },
	["Quaternion.Lerp"] = { "alpha", "other" },
	["Quaternion.Slerp"] = { "alpha", "other" },
	["Quaternion.ToAxisAngle"] = { "self" },

	["Axes.new"] = { "x", "y", "z" },

	["UDim.new"] = { "scale", "offset" },
	["UDim.Lerp"] = { "alpha", "other" },
	["UDim.FuzzyEq"] = { "other", "epsilon" },

	["UDim2.new"] = { "xScale", "xOffset", "yScale", "yOffset" },
	["UDim2.fromScale"] = { "x", "y" },
	["UDim2.fromOffset"] = { "x", "y" },
	["UDim2.Lerp"] = { "alpha", "other" },
	["UDim2.FuzzyEq"] = { "other", "epsilon" },

	["Ray.new"] = { "origin", "direction" },
	["Ray.Unit"] = { "self" },
	["Ray.ClosestPoint"] = { "point" },
	["Ray.Distance"] = { "point" },

	["Rect.new"] = { "x", "y", "width", "height" },

	["Region3.new"] = { "cframe", "size" },
	["Region3.ExpandToGrid"] = { "step" },
	["Region3int16.new"] = { "cframe", "size" },

	["NumberRange.new"] = { "min", "max" },

	["NumberSequence.new"] = { "keypoints" },
	["NumberSequence.Keypoint"] = { "time", "value", "envelope" },

	["ColorSequence.new"] = { "keypoints" },
	["ColorSequence.Keypoint"] = { "time", "color" },

	["TweenInfo.new"] = { "time", "easingStyle", "easingDirection", "repeatCount", "reverses", "delayTime" },

	["BrickColor.new"] = { "value" },

	["Random.new"] = { "seed" },
	["Random.NextInteger"] = { "min", "max" },
	["Random.NextNumber"] = { "min", "max" },
	["Random.NextUnitVector"] = {},
	["Random.Shuffle"] = { "list" },
	["Random.Clone"] = { "self" },

	["DateTime.now"] = {},
	["DateTime.fromUnixTimestamp"] = { "seconds" },
	["DateTime.fromUnixTimestampMillis"] = { "milliseconds" },

	["PhysicalProperties.new"] = { "density", "friction", "elasticity", "frictionWeight", "elasticityWeight" },
	["OverlapParams.AddToFilter"] = { "instance" },

	["Instance.new"] = { "className", "parent" },
	["Instance.fromJSON"] = { "json" },
	["Instance.Clone"] = { "self" },
	["Instance.Destroy"] = { "self" },
	["Instance.FindFirstChild"] = { "name", "recursive" },
	["Instance.FindFirstChildOfClass"] = { "className", "recursive" },
	["Instance.GetChildren"] = { "self" },
	["Instance.GetDescendants"] = { "self" },
	["Instance.GetFullName"] = { "self" },
	["Instance.GetAttribute"] = { "attribute" },
	["Instance.GetAttributes"] = { "self" },
	["Instance.SetAttribute"] = { "attribute", "value" },
	["Instance.IsA"] = { "className" },
	["Instance.IsAncestorOf"] = { "instance" },
	["Instance.IsDescendantOf"] = { "instance" },
	["Instance.GetService"] = { "className" },

	["print"] = { "..." },
	["warn"] = { "..." },
	["error"] = { "message", "level" },
	["assert"] = { "value", "message" },
	["pcall"] = { "f", "..." },
	["xpcall"] = { "f", "handler" },
	["type"] = { "value" },
	["typeof"] = { "value" },
	["select"] = { "index", "..." },
	["setmetatable"] = { "table", "metatable" },
	["getmetatable"] = { "object" },
	["rawget"] = { "table", "index" },
	["rawset"] = { "table", "index", "value" },
	["rawequal"] = { "a", "b" },
	["rawlen"] = { "value" },
	["require"] = { "module" },
	["tostring"] = { "value" },
	["tonumber"] = { "value", "base" },
	["next"] = { "table", "key" },
	["unpack"] = { "table", "i", "j" },
	["pairs"] = { "table" },
	["ipairs"] = { "table" },
	["waitforchild"] = { "child", "timeout" },
	["tick"] = {},
	["delay"] = { "seconds", "callback", "..." },
	["spawn"] = { "callback", "..." },
}
local SIGNATURES_LOWER = {}

for key, params in pairs(SIGNATURES) do
	SIGNATURES_LOWER[string.lower(key)] = params
end

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
	{ name = "Axes", kind = "Type" },
	{ name = "CFrame", kind = "Type" },
	{ name = "Color3", kind = "Type" },
	{ name = "ColorSequence", kind = "Type" },
	{ name = "DateTime", kind = "Type" },
	{ name = "Enum", kind = "Type" },
	{ name = "Faces", kind = "Type" },
	{ name = "Font", kind = "Type" },
	{ name = "Instance", kind = "Type" },
	{ name = "NumberRange", kind = "Type" },
	{ name = "NumberSequence", kind = "Type" },
	{ name = "OverlapParams", kind = "Type" },
	{ name = "PathWaypoint", kind = "Type" },
	{ name = "PhysicalProperties", kind = "Type" },
	{ name = "Quaternion", kind = "Type" },
	{ name = "Random", kind = "Type" },
	{ name = "Ray", kind = "Type" },
	{ name = "Rect", kind = "Type" },
	{ name = "Region3", kind = "Type" },
	{ name = "Region3int16", kind = "Type" },
	{ name = "TweenInfo", kind = "Type" },
	{ name = "UDim", kind = "Type" },
	{ name = "UDim2", kind = "Type" },
	{ name = "UniqueId", kind = "Type" },
	{ name = "Vector2", kind = "Type" },
	{ name = "Vector2int16", kind = "Type" },
	{ name = "Vector3", kind = "Type" },
	{ name = "Vector3int16", kind = "Type" },
}

local BUILTIN_MEMBERS = {
	Vector2 = {
		"new:Method",
		"X:Property",
		"Y:Property",
		"Magnitude:Property",
		"Unit:Method",
		"Cross:Method",
		"Dot:Method",
		"FuzzyEq:Method",
		"Lerp:Method",
	},

	Vector3 = {
		"new:Method",
		"FromNormalId:Method",
		"FromAxis:Method",
		"x:Property",
		"X:Property",
		"y:Property",
		"Y:Property",
		"z:Property",
		"Z:Property",
		"Magnitude:Property",
		"Unit:Method",
		"Abs:Method",
		"Ceil:Method",
		"Floor:Method",
		"Sign:Method",
		"Cross:Method",
		"Angle:Method",
		"Dot:Method",
		"FuzzyEq:Method",
		"Lerp:Method",
		"Max:Method",
		"Min:Method",
	},

	Vector2int16 = { "new:Method", "X:Property", "Y:Property" },

	Vector3int16 = { "new:Method", "X:Property", "Y:Property", "Z:Property" },

	Color3 = {
		"new:Method",
		"fromRGB:Method",
		"fromHSV:Method",
		"fromHex:Method",
		"R:Property",
		"G:Property",
		"B:Property",
		"Lerp:Method",
		"ToHSV:Method",
		"ToHex:Method",
		"ToRGB:Method",
	},

	CFrame = {
		"new:Method",
		"Angles:Method",
		"fromEulerAnglesXYZ:Method",
		"fromEulerAnglesYXZ:Method",
		"fromOrientation:Method",
		"fromAxisAngle:Method",
		"lookAt:Method",
		"lookAlong:Method",
		"fromMatrix:Method",
		"Position:Property",
		"p:Property",
		"Rotation:Property",
		"RightVector:Property",
		"XVector:Property",
		"UpVector:Property",
		"YVector:Property",
		"LookVector:Property",
		"ZVector:Property",
		"X:Property",
		"Y:Property",
		"Z:Property",
		"Inverse:Method",
		"Lerp:Method",
		"ToWorldSpace:Method",
		"ToObjectSpace:Method",
		"PointToWorldSpace:Method",
		"PointToObjectSpace:Method",
		"VectorToWorldSpace:Method",
		"VectorToObjectSpace:Method",
		"Orthonormalize:Method",
		"GetComponents:Method",
		"components:Method",
		"ToEulerAnglesXYZ:Method",
		"ToEulerAnglesYXZ:Method",
		"ToOrientation:Method",
		"ToAxisAngle:Method",
		"FuzzyEq:Method",
		"AngleBetween:Method",
	},

	Quaternion = {
		"new:Method",
		"fromAxisAngle:Method",
		"X:Property",
		"Y:Property",
		"Z:Property",
		"W:Property",
		"Magnitude:Property",
		"Unit:Method",
		"Conjugate:Method",
		"Inverse:Method",
		"Dot:Method",
		"Lerp:Method",
		"Slerp:Method",
		"ToAxisAngle:Method",
	},

	Axes = { "new:Method", "X:Property", "Y:Property", "Z:Property" },

	UDim = {
		"new:Method",
		"Scale:Property",
		"Offset:Property",
		"Lerp:Method",
		"FuzzyEq:Method",
	},

	UDim2 = {
		"new:Method",
		"fromScale:Method",
		"fromOffset:Method",
		"X:Property",
		"Y:Property",
		"XScale:Property",
		"XOffset:Property",
		"YScale:Property",
		"YOffset:Property",
		"Width:Property",
		"Height:Property",
		"Lerp:Method",
		"FuzzyEq:Method",
	},

	Ray = {
		"new:Method",
		"Origin:Property",
		"Direction:Property",
		"Unit:Method",
		"ClosestPoint:Method",
		"Distance:Method",
	},

	Rect = {
		"new:Method",
		"Min:Property",
		"Max:Property",
		"Width:Property",
		"Height:Property",
	},

	Region3 = {
		"new:Method",
		"Min:Property",
		"Max:Property",
		"Size:Property",
		"CFrame:Property",
		"ExpandToGrid:Method",
	},

	Region3int16 = {
		"new:Method",
		"Min:Property",
		"Max:Property",
		"Size:Property",
		"CFrame:Property",
	},

	NumberRange = { "new:Method", "Min:Property", "Max:Property" },

	NumberSequence = {
		"new:Method",
		"Keypoint:Method",
		"Time:Property",
		"Value:Property",
		"Envelope:Property",
		"Keypoints:Property",
	},

	ColorSequence = {
		"new:Method",
		"Keypoint:Method",
		"Time:Property",
		"Value:Property",
		"Keypoints:Property",
	},

	TweenInfo = {
		"new:Method",
		"Time:Property",
		"EasingStyle:Property",
		"EasingDirection:Property",
		"RepeatCount:Property",
		"Reverses:Property",
		"DelayTime:Property",
	},

	BrickColor = {
		"new:Method",
		"Number:Property",
		"Name:Property",
		"Color:Property",
	},

	Random = {
		"new:Method",
		"NextInteger:Method",
		"NextNumber:Method",
		"NextUnitVector:Method",
		"Shuffle:Method",
		"Clone:Method",
	},

	DateTime = {
		"now:Method",
		"fromUnixTimestamp:Method",
		"fromUnixTimestampMillis:Method",
	},

	PhysicalProperties = {
		"new:Method",
		"Density:Property",
		"Friction:Property",
		"Elasticity:Property",
		"FrictionWeight:Property",
		"ElasticityWeight:Property",
	},

	OverlapParams = {
		"FilterDescendantsInstances:Property",
		"ExcludeInstances:Property",
		"IncludeInstances:Property",
		"FilterType:Property",
		"MaxParts:Property",
		"CollisionGroup:Property",
		"Tolerance:Property",
		"RespectCanCollide:Property",
		"BruteForceAllSlow:Property",
		"AddToFilter:Method",
	},

	PathWaypoint = {
		"Position:Property",
		"Action:Property",
		"Label:Property",
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

	Enum = { "GetEnumItems:Method" },
}
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

local BUILTIN_MEMBERS_LOWER = {}

for key, entries in pairs(BUILTIN_MEMBERS) do
	BUILTIN_MEMBERS_LOWER[string.lower(key)] = entries
end

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

local CodeEditor = {}
CodeEditor.__index = CodeEditor
function CodeEditor.new(parent)
	local self = setmetatable({}, CodeEditor)

	self.documents = {}
	self.documentByInstance = {}
	self.activeDocument = nil
	self.suppressTextSync = false

	self.suggestions = {}
	self.suggestionIndex = 1
	self.suggestPrefix = nil
	self.suggestRange = nil
	self.suggestionScroll = 0
	self.applyingSuggestion = false
	self.hintSignature = nil

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
		BackgroundColor3 = tokens.color.input,
		TextColor3 = tokens.color.text,
	}, parent)

	UI.create("SyntaxHighlighter", { Parent = editor })
	UI.create("UIBackdrop", { Parent = editor })

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
		Color3 = tokens.color.canvas,
		Transparency = 0.4,
		Parent = popup,
	})

	local hint = UI.frame(
		suggestionLayer,
		UDim2.fromOffset(0, 0),
		UDim2.fromOffset(SUGGEST_WIDTH, SUGGEST_ROW_HEIGHT + SUGGEST_PADDING),
		tokens.color.panel,
		tokens.radius.sm
	)

	hint.Name = "ArgumentHint"
	hint.Visible = false

	UI.stroke(hint, tokens.color.border, 1, 0)

	self.TabStrip = tabStrip
	self.TextBox = editor
	self.SuggestionLayer = suggestionLayer
	self.Popup = popup
	self.Hint = hint
	self.rows = {}

	local find = UI.frame(
		suggestionLayer,
		UDim2.fromOffset(0, 0),
		UDim2.fromOffset(FIND_WIDTH, FIND_HEIGHT),
		tokens.color.panel,
		tokens.radius.sm
	)

	find.Name = "FindWidget"
	find.Visible = false
	find.Active = true
	find.ClipsDescendants = true

	UI.stroke(find, tokens.color.border, 1, 0)

	self.findInput = UI.create("TextBox", {
		Name = "FindInput",
		Size = UDim2.new(1, -152, 0, FIND_HEIGHT - 8),
		Position = UDim2.fromOffset(4, 4),
		BackgroundColor3 = tokens.color.input,
		BorderSizePixel = 0,
		Text = "",
		PlaceholderText = "Find",
		TextSize = tokens.type.small,
		TextColor3 = tokens.color.text,
		PlaceholderColor3 = tokens.color.muted,
		ClearTextOnFocus = false,
	}, find)

	self.findCount = UI.label(
		find,
		"No results",
		UDim2.new(1, -148, 0, 8),
		UDim2.fromOffset(100, 12),
		tokens.type.caption,
		tokens.color.muted
	)

	self.findButtons = {}

	local findOrder = { "prev", "next", "case", "word", "close" }
	local findIcons = {
		prev = "builtin://global-icons/chevron-up.svg",
		next = "builtin://global-icons/chevron-down.svg",
	}
	local findText = { case = "Aa", word = "ab", close = "x" }

	local findX = FIND_WIDTH - 8

	for index = #findOrder, 1, -1 do
		local id = findOrder[index]
		findX = findX - 24

		local callback = function()
			self:findAction(id)
		end

		local button, label, record

		if findIcons[id] then
			button, record = UI.iconButton(find, findIcons[id], UDim2.fromOffset(findX, 4), UDim2.fromOffset(22, 20), callback, {
				color = tokens.color.panel,
				hoverColor = tokens.color.hover,
				radius = tokens.radius.xs,
				border = false,
				iconSize = 12,
			})
		else
			button, label, record = UI.button(find, findText[id], UDim2.fromOffset(findX, 4), UDim2.fromOffset(22, 20), callback, {
				color = tokens.color.panel,
				hoverColor = tokens.color.hover,
				textColor = tokens.color.muted,
				textSize = tokens.type.caption,
				textY = 3,
				radius = tokens.radius.xs,
				border = false,
				paddingX = 3,
			})
		end

		self.findButtons[id] = { gui = button, label = label, record = record, text = findText[id] }
	end

	self.Find = find
	self.findVisible = false
	self.findMatches = {}
	self.findIndex = 0
	self.findCaseSensitive = false
	self.findWholeWord = false

	self.popupPosition = Vector2.new(0, 0)
	self.popupTarget = Vector2.new(0, 0)
	self.hintPosition = Vector2.new(0, 0)
	self.hintTarget = Vector2.new(0, 0)
	self.popupPlaced = false
	self.hintPlaced = false
	self.popupSize = Vector2.new(SUGGEST_WIDTH, SUGGEST_ROW_HEIGHT)
	self.hintHeight = SUGGEST_ROW_HEIGHT + SUGGEST_PADDING

	self:wireEditor()
	self:registerRenderStep()

	return self
end

local POPUP_LERP_SPEED = 26

local function approach(current, target, delta)
	local weight = 1 - math.exp(-POPUP_LERP_SPEED * delta)

	return current + (target - current) * weight
end

function CodeEditor:registerRenderStep()
	self.heartbeat = RunService.Heartbeat:Connect(function(dt)
		self:update(dt or 1 / 60)
	end)
end

function CodeEditor:update(delta)
	if type(delta) ~= "number" then
		delta = 1 / 60
	end

	if self.findVisible then
		self:placeFindWidget()
	end

	if not UI.isAlive(self.Popup) or not UI.isAlive(self.Hint) then
		return
	end

	local popupVisible = self.Popup.Visible
	local hintVisible = self.Hint.Visible

	if not popupVisible and not hintVisible then
		return
	end

	self:updateTargets()

	if popupVisible then
		if self.popupPlaced then
			self.popupPosition = Vector2.new(
				approach(self.popupPosition.X, self.popupTarget.X, delta),
				approach(self.popupPosition.Y, self.popupTarget.Y, delta)
			)
		else
			self.popupPosition = self.popupTarget
			self.popupPlaced = true
		end

		self.Popup.Position = UDim2.fromOffset(math.floor(self.popupPosition.X), math.floor(self.popupPosition.Y))
	end

	if hintVisible then
		if self.hintPlaced then
			self.hintPosition = Vector2.new(
				approach(self.hintPosition.X, self.hintTarget.X, delta),
				approach(self.hintPosition.Y, self.hintTarget.Y, delta)
			)
		else
			self.hintPosition = self.hintTarget
			self.hintPlaced = true
		end

		self.Hint.Position = UDim2.fromOffset(math.floor(self.hintPosition.X), math.floor(self.hintPosition.Y))
	end
end

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

local function resolveRoot(name)
	if name == "game" then
		return game
	end

	if name == "workspace" then
		return workspace
	end

	return nil
end

local function resolveInstance(segments, upto, aliases)
	if upto <= 0 then
		return nil
	end

	local root = resolveRoot(segments[1])

	if root == nil and aliases ~= nil then
		local service = aliases[segments[1]]

		if service ~= nil then
			root = resolveRoot(service)

			if root == nil then

				local ok, resolved = pcall(function()
					return game:GetService(service)
				end)

				if ok then
					root = resolved
				else
					root = game:FindFirstChild(service)
				end
			end
		end
	end

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

local function resolveLongestPrefix(segments, aliases)
	local instance = nil
	local resolved = 0

	for index = 1, #segments do
		local candidate = resolveInstance(segments, index, aliases)

		if candidate == nil then
			break
		end

		instance = candidate
		resolved = index
	end

	return instance, resolved
end

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

local function resolveSignature(callee)
	if callee == nil then
		return nil
	end

	if SIGNATURES[callee] ~= nil then
		return SIGNATURES[callee]
	end

	return SIGNATURES_LOWER[string.lower(callee)]
end

local function isGetServiceCall(callee)
	if callee == nil then
		return false
	end

	return string.lower(callee) == "getservice" or string.find(callee, "%.getservice$") ~= nil
end

local enumTypeCache = nil
local enumItemCache = {}

local function enumTypeCandidates()
	if enumTypeCache == nil then
		enumTypeCache = {}

		local ok = pcall(function()
			for name, enumType in pairs(Enum) do
				if type(name) == "string" and enumType ~= nil then
					local count = 0

					pcall(function()
						count = #enumType:GetEnumItems()
					end)

					table.insert(enumTypeCache, {
						name = name,
						kind = "Type",
						detail = count > 0 and (count .. " items") or "Enum",
					})
				end
			end
		end)

		if not ok then
			enumTypeCache = {}
		end

		table.sort(enumTypeCache, function(a, b)
			return a.name < b.name
		end)
	end

	return enumTypeCache
end

local function enumItemCandidates(enumName)
	if enumItemCache[enumName] ~= nil then
		return enumItemCache[enumName]
	end

	local members = {}

	pcall(function()
		local enumType = Enum[enumName]

		if enumType == nil then
			return
		end

		for _, item in ipairs(enumType:GetEnumItems()) do
			local name = item.Name

			if type(name) == "string" then
				table.insert(members, {
					name = name,
					kind = "Value",
					detail = tostring(item.Value),
				})
			end
		end
	end)

	enumItemCache[enumName] = members

	return members
end

local function collectEnumMembers(receiver)
	if #receiver < 1 or #receiver > 2 then
		return nil
	end

	if string.lower(receiver[1]) ~= "enum" then
		return nil
	end

	if #receiver == 1 then
		return enumTypeCandidates()
	end

	local members = enumItemCandidates(receiver[2])

	if #members > 0 then
		return members
	end

	return enumTypeCandidates()
end

local function serviceNames()
	local names = {}

	for _, child in ipairs(game:GetChildren()) do
		table.insert(names, child.Name)
	end

	table.sort(names)

	return names
end

local function serviceCandidates()
	local candidates = {}

	for _, name in ipairs(serviceNames()) do
		table.insert(candidates, {
			name = name,
			kind = "Service",
			detail = "Service",
		})
	end

	return candidates
end

local function collectServiceAliases(source, services)
	local aliases = {}

	for name, service in string.gmatch(
		source,
		"local%s+([%a_][%w_]*)%s*=%s*[%a_][%w_]*[%.:]GetService%s*%(%s*[\"']([^\"']+)[\"']"
	) do
		aliases[name] = service
	end

	for name, target in string.gmatch(source, "local%s+([%a_][%w_]*)%s*=%s*([%a_][%w_]*)%s") do
		if aliases[name] == nil then
			if target == "game" or target == "workspace" then
				aliases[name] = target
			elseif services[target] then
				aliases[name] = target
			end
		end
	end

	return aliases
end

local function callContextAt(text, cursor)
	local head = string.sub(text, 1, math.max(cursor - 1, 0))

	local depth = 0
	local open = nil

	for index = #head, 1, -1 do
		local character = string.sub(head, index, index)

		if character == ")" or character == "]" or character == "}" then
			depth += 1
		elseif character == "[" or character == "{" then
			if depth == 0 then
				return nil
			end

			depth -= 1
		elseif character == "(" then
			if depth == 0 then
				open = index
				break
			end

			depth -= 1
		end
	end

	if open == nil then
		return nil
	end

	local finish = open - 1
	local start = finish

	while start >= 1 do
		local character = string.sub(head, start, start)

		if string.match(character, "[%w_%.]") == nil then
			break
		end

		start -= 1
	end

	local callee = string.sub(head, start + 1, finish)

	if callee == "" then
		return nil
	end

	local index = 0
	local nested = 0

	for position = open + 1, #head do
		local character = string.sub(head, position, position)

		if character == "(" or character == "[" or character == "{" then
			nested += 1
		elseif character == ")" or character == "]" or character == "}" then
			nested -= 1
		elseif character == "," and nested == 0 then
			index += 1
		end
	end

	return callee, index, open
end

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

function CodeEditor:collectCandidates(segments, ends_with_dot, aliases)
	local receiver = {}

	local count = ends_with_dot and #segments or #segments - 1

	for index = 1, count do
		receiver[index] = segments[index]
	end

	if #receiver > 0 then
		local enum = collectEnumMembers(receiver)

		if enum ~= nil and #enum > 0 then
			return enum
		end

		local instance, resolved = resolveLongestPrefix(receiver, aliases)

		if instance ~= nil and resolved == #receiver then
			local members = collectInstanceMembers(instance)

			if #members > 0 then
				return members
			end
		else
			local members = collectBuiltinMembers(table.concat(receiver, "."))

			if members ~= nil then
				return members
			end
		end
	end

	return collectVocabulary(self:activeSource())
end

function CodeEditor:activeSource()
	if self.activeDocument ~= nil then
		return self.activeDocument.source
	end

	return self.TextBox.Text
end

function CodeEditor:serviceSet()
	local set = {}

	for _, name in ipairs(serviceNames()) do
		set[name] = true
	end

	return set
end

function CodeEditor:dismissSuggestions()
	self.suggestions = {}
	self.suggestionIndex = 1
	self.suggestPrefix = nil
	self.suggestRange = nil
	self.suggestionScroll = 0

	if UI.isAlive(self.Popup) then
		self.Popup.Visible = false
	end

	self:dismissArgumentHint()
end

function CodeEditor:refreshSuggestions()
	self:updateSuggestionList()

	self:renderArgumentHint()
end

function CodeEditor:updateSuggestionList()
	local source = self:activeSource()
	local aliases = collectServiceAliases(source, self:serviceSet())

	local service = self:serviceArgumentAt()

	if service ~= nil then
		self:showServiceList(service.prefix, service.start, service.finish)
		return
	end

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

	local prefix = ends_with_dot and "" or (segments[#segments] or "")

	if prefix == "" and not ends_with_dot then
		self:dismissSuggestions()
		return
	end

	local ranked = {}

	for _, candidate in ipairs(self:collectCandidates(segments, ends_with_dot, aliases)) do
		local score = scoreMatch(candidate.name, prefix)

		if score ~= nil then
			table.insert(ranked, {
				name = candidate.name,
				kind = candidate.kind,
				detail = candidate.detail,
				score = score,
				quote = false,
			})
		end
	end

	self:showRanked(ranked, prefix, self:completionRange(word, segments, ends_with_dot))
end

function CodeEditor:showRanked(ranked, prefix, range)
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
	self.suggestRange = range
	self.suggestionIndex = 1
	self.suggestionScroll = 0

	self:renderSuggestions()
end

function CodeEditor:serviceArgumentAt()
	local callee, _, open = callContextAt(self.TextBox.Text, self.TextBox.CursorPosition)

	if not isGetServiceCall(callee) then
		return nil
	end

	local cursor = self.TextBox.CursorPosition
	local argumentStart = open + 1

	return {
		prefix = string.sub(self.TextBox.Text, argumentStart, cursor - 1),
		start = argumentStart,
		finish = cursor,
	}
end

function CodeEditor:showServiceList(prefix, start, finish)
	local ranked = {}

	for _, candidate in ipairs(serviceCandidates()) do
		local score = scoreMatch(candidate.name, prefix)

		if score ~= nil then
			table.insert(ranked, {
				name = candidate.name,
				kind = candidate.kind,
				detail = candidate.detail,
				score = score,
				quote = true,
			})
		end
	end

	self:showRanked(ranked, prefix, { start = start, finish = finish })
end

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

function CodeEditor:visibleRowCount()
	return math.min(#self.suggestions, SUGGEST_MAX_ROWS)
end

function CodeEditor:scrollToSelection()
	local total = #self.suggestions
	local visible = self:visibleRowCount()

	if self.suggestionIndex < self.suggestionScroll + 1 then
		self.suggestionScroll = self.suggestionIndex - 1
	elseif self.suggestionIndex > self.suggestionScroll + visible then
		self.suggestionScroll = self.suggestionIndex - visible
	end

	self.suggestionScroll = math.clamp(self.suggestionScroll, 0, math.max(total - visible, 0))
end

function CodeEditor:moveSuggestion(delta)
	local count = #self.suggestions

	if count == 0 then
		return
	end

	self.suggestionIndex = ((self.suggestionIndex - 1 + delta) % count) + 1

	self:scrollToSelection()
	self:renderSuggestions()
end

function CodeEditor:updateTargets()
	local anchor = self.TextBox.CaretScreenPosition or Vector2.new(0, 0)
	local camera = workspace.CurrentCamera
	local screen = camera and camera.ViewportSize or Vector2.new(1280, 720)

	local popupHeight = self.popupSize.Y
	local hintVisible = self.Hint.Visible

	local stack = hintVisible and (self.hintHeight + 4) or 0

	local y = anchor.Y + SUGGEST_LINE_HEIGHT

	if y + popupHeight > screen.Y - 8 then
		y = math.max(8, anchor.Y - popupHeight - 4 - stack)
	end

	local x = math.clamp(anchor.X, 8, math.max(8, screen.X - SUGGEST_WIDTH - 8))

	self.popupTarget = Vector2.new(x, y)

	local hintY = hintVisible and (y - self.hintHeight - 4) or math.max(8, anchor.Y - self.hintHeight - 4)

	self.hintTarget = Vector2.new(x, math.max(8, hintY))
end

function CodeEditor:renderArgumentHint()
	local callee, index = callContextAt(self.TextBox.Text, self.TextBox.CursorPosition)

	if callee == nil then
		self:dismissArgumentHint()
		return
	end

	local params = resolveSignature(callee)

	if params == nil then
		self:dismissArgumentHint()
		return
	end

	local current = params[index + 1]

	if #params > 0 and params[#params] ~= "..." and current == nil then
		self:dismissArgumentHint()
		return
	end

	self.hintHeight = SUGGEST_ROW_HEIGHT + SUGGEST_PADDING

	self.Hint.Size = UDim2.fromOffset(SUGGEST_WIDTH, self.hintHeight)

	UI.clear(self.Hint)

	local padding = math.floor(SUGGEST_PADDING / 2)

	if current ~= nil then
		UI.label(
			self.Hint,
			current,
			UDim2.fromOffset(8, padding + 1),
			UDim2.fromOffset(90, SUGGEST_ROW_HEIGHT - 2),
			tokens.type.small,
			tokens.color.accent
		)
	end

	UI.label(
		self.Hint,
		callee .. "(" .. table.concat(params, ", ") .. ")",
		UDim2.fromOffset(current and 102 or 8, padding + 1),
		UDim2.new(1, -12, 1, -padding - 2),
		tokens.type.caption,
		tokens.color.subtext
	)

	self.hintSignature = callee

	if not self.Hint.Visible then
		self.hintPlaced = false
	end

	self.Hint.Visible = true
end

function CodeEditor:dismissArgumentHint()
	self.hintSignature = nil

	if UI.isAlive(self.Hint) then
		self.Hint.Visible = false
	end
end

function CodeEditor:renderSuggestions()
	local count = self:visibleRowCount()

	if count == 0 then
		self:dismissSuggestions()
		return
	end

	self:scrollToSelection()

	local height = count * SUGGEST_ROW_HEIGHT + SUGGEST_PADDING * 2

	self.Popup.Size = UDim2.fromOffset(SUGGEST_WIDTH, height)
	self.popupSize = Vector2.new(SUGGEST_WIDTH, height)

	if not self.Popup.Visible then
		self.popupPlaced = false
	end

	self.Popup.Visible = true

	UI.clear(self.Popup)

	self.rows = {}

	local first = self.suggestionScroll

	for offset = 0, count - 1 do
		local index = first + offset + 1
		local suggestion = self.suggestions[index]
		local isSelected = index == self.suggestionIndex

		local row = UI.button(
			self.Popup,
			"",
			UDim2.fromOffset(SUGGEST_PADDING, SUGGEST_PADDING + offset * SUGGEST_ROW_HEIGHT),
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

		local icon = UI.image(
			row,
			iconRoot .. (KIND_ICONS[suggestion.kind] or "placeholder.png"),
			UDim2.fromOffset(5, math.floor((SUGGEST_ROW_HEIGHT - SUGGEST_ICON_SIZE) / 2)),
			UDim2.fromOffset(SUGGEST_ICON_SIZE, SUGGEST_ICON_SIZE)
		)

		icon.ImageTransparency = isSelected and 0 or 0.45

		UI.label(
			row,
			suggestion.name,
			UDim2.fromOffset(SUGGEST_ICON_SIZE + 11, 3),
			UDim2.new(1, -76 - SUGGEST_ICON_SIZE, 1, -6),
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

	local total = #self.suggestions

	if total > count then
		local track = count * SUGGEST_ROW_HEIGHT
		local thumb = math.max(18, math.floor(track * (count / total)))

		UI.frame(
			self.Popup,
			UDim2.new(1, -3, 0, SUGGEST_PADDING + (track - thumb) * (first / (total - count))),
			UDim2.fromOffset(2, thumb),
			tokens.color.subtext,
			1
		)
	end
end

function CodeEditor:acceptSuggestion(index)
	local suggestion = self.suggestions[index or self.suggestionIndex]
	local range = self.suggestRange

	if suggestion == nil or range == nil then
		self:dismissSuggestions()
		return
	end

	local insert = suggestion.quote and ('"' .. suggestion.name .. '"') or suggestion.name

	local callable = suggestion.kind == "Method" or suggestion.kind == "Function"

	if callable then
		insert = insert .. "("
	end

	self:dismissSuggestions()

	self.applyingSuggestion = true

	self.TextBox:ReplaceRange(range.start, range.finish, insert)

	if callable then
		self.TextBox.CursorPosition = range.start + #insert
	end

	self.applyingSuggestion = false

	self.TextBox:CaptureFocus()

	self:renderArgumentHint()
end

local function paintToggle(entry, active)
	if not entry or not UI.isAlive(entry.gui) then
		return
	end

	local color = tokens.color.panel

	if active then
		color = tokens.color.selection
	end

	if entry.record then
		entry.record.color = color
	end

	entry.gui.BackgroundColor3 = color
end

local MAGIC_CHARACTERS = {
	["^"] = true,
	["$"] = true,
	["("] = true,
	[")"] = true,
	["%"] = true,
	["."] = true,
	["["] = true,
	["]"] = true,
	["*"] = true,
	["+"] = true,
	["-"] = true,
	["?"] = true,
}

local function escapePattern(text)
	local buffer = {}

	for index = 1, #text do
		local character = text:sub(index, index)

		if MAGIC_CHARACTERS[character] then
			table.insert(buffer, "%")
		end

		table.insert(buffer, character)
	end

	return table.concat(buffer)
end

local function isModifierDown(code)
	local service = game:GetService("UserInputService")

	return service and service:IsKeyDown(code) == true
end

local function modifierHeld()
	return isModifierDown(Enum.KeyCode.LeftControl)
		or isModifierDown(Enum.KeyCode.RightControl)
		or isModifierDown(Enum.KeyCode.LeftSuper)
		or isModifierDown(Enum.KeyCode.RightSuper)
end

function CodeEditor:isWordCharacter(char)
	return char ~= nil and char:match("[%a_0-9]") ~= nil
end

function CodeEditor:scanFindMatches()
	local query = self.findInput.Text
	self.findMatches = {}

	if query == "" then
		self.findIndex = 0

		return
	end

	local text = self.TextBox.Text
	local haystack = text
	local needle = query

	if not self.findCaseSensitive then
		haystack = string.lower(haystack)
		needle = string.lower(needle)
	end

	local cursor = 1
	local pattern = escapePattern(needle)

	while cursor <= #haystack do
		local start, finish = string.find(haystack, pattern, cursor)

		if not start then
			break
		end

		local boundary = true

		if self.findWholeWord then
			local before = haystack:sub(start - 1, start - 1)
			local after = haystack:sub(finish + 1, finish + 1)

			boundary = not self:isWordCharacter(before) and not self:isWordCharacter(after)
		end

		if boundary then
			table.insert(self.findMatches, { start, finish })
		end

		cursor = finish + 1
	end

	self.findIndex = 0
end

function CodeEditor:stepFindMatch(direction)
	local total = #self.findMatches

	if total == 0 then
		return
	end

	self.findIndex = (self.findIndex - 1 + direction) % total + 1
end

function CodeEditor:selectFindMatch()
	local match = self.findMatches[self.findIndex]

	if not match then
		return
	end

	self.TextBox.SelectionStart = match[1]
	self.TextBox.SelectionEnd = match[2]
end

function CodeEditor:updateFindCount()
	local total = #self.findMatches

	if total == 0 then
		self.findCount.Text = "No results"

		return
	end

	local index = self.findIndex

	if index == 0 then
		index = 1
	end

	self.findCount.Text = ('%d of %d'):format(index, total)
end

function CodeEditor:runFind(direction)
	self:scanFindMatches()

	local total = #self.findMatches

	if total == 0 then
		self:updateFindCount()

		return
	end

	local cursor = self.TextBox.CursorPosition
	self.findIndex = 1

	for index, match in self.findMatches do
		if cursor >= match[1] and cursor <= match[2] then
			self.findIndex = index

			break
		end
	end

	if direction and direction ~= 0 then
		self:stepFindMatch(direction)
	end

	self:updateFindCount()
	self:selectFindMatch()
end

function CodeEditor:openFind()
	if self.findVisible then
		self:closeFind()

		return
	end

	local box = self.TextBox
	local selected = box.Text:sub(math.min(box.SelectionStart, box.SelectionEnd) + 1, math.max(box.SelectionStart, box.SelectionEnd))

	if selected ~= "" and not selected:find("\n") then
		self.findInput.Text = selected
	elseif #self.findInput.Text > 200 then
		self.findInput.Text = ""
	end

	self.findVisible = true
	self.Find.Visible = true
	self:placeFindWidget()
	self.findInput:CaptureFocus()
	self.findInput.SelectAll()
	self:runFind(0)
end

function CodeEditor:placeFindWidget()
	if not self.findVisible or not UI.isAlive(self.Find) then
		return
	end

	local camera = workspace.CurrentCamera
	local screen = camera and camera.ViewportSize or Vector2.new(1280, 720)

	self.Find.Position = UDim2.fromOffset(
		math.max(8, screen.X - FIND_WIDTH - 16),
		math.max(8, TAB_STRIP_HEIGHT + 12)
	)
end

function CodeEditor:closeFind()
	self.findVisible = false
	self.Find.Visible = false
	self.findMatches = {}
	self.findIndex = 0
	self.TextBox:CaptureFocus()
end

function CodeEditor:findAction(id)
	if id == "close" then
		self:closeFind()

		return
	end

	if id == "case" then
		self.findCaseSensitive = not self.findCaseSensitive
		self:markFindToggle("case", self.findCaseSensitive)
	elseif id == "word" then
		self.findWholeWord = not self.findWholeWord
		self:markFindToggle("word", self.findWholeWord)
	else
		self:runFind(id == "prev" and -1 or 1)

		return
	end

	self:runFind(1)
end

function CodeEditor:markFindToggle(id, on)
	paintToggle(self.findButtons[id], on)
end

function CodeEditor:wireEditor()
	self.TextBox.TextChanged:Connect(function()
		if self.suppressTextSync then
			return
		end

		if self.activeDocument ~= nil then
			self.activeDocument.source = self.TextBox.Text

			self:commitDocument(self.activeDocument)
		end

		if self.applyingSuggestion then
			self:renderArgumentHint()
		else
			self:refreshSuggestions()
		end

		if self.findVisible then
			self:scanFindMatches()
			self:updateFindCount()
		end
	end)

	self.findInput.TextChanged:Connect(function()
		self:runFind(1)
	end)

	self.findInput.KeyDown:Connect(function(input)
		local keyCode = input and input.KeyCode

		if keyCode == Enum.KeyCode.Escape then
			self:closeFind()
			self.findInput.KeyHandled = true
		elseif keyCode == Enum.KeyCode.Return or keyCode == Enum.KeyCode.KeypadEnter then
			self:runFind(isModifierDown(Enum.KeyCode.LeftShift) and -1 or 1)
			self.findInput.KeyHandled = true
		end
	end)

	self.TextBox.FocusLost:Connect(function()
		task.defer(function()
			if not self.TextBox:IsFocused() then
				self:dismissSuggestions()
			end
		end)
	end)

	self.TextBox.KeyDown:Connect(function(input)
		local keyCode = input and input.KeyCode

		if keyCode == Enum.KeyCode.F then
			if modifierHeld() then
				self:openFind()
				self.TextBox.KeyHandled = true
			end

			return
		end

		if keyCode == Enum.KeyCode.F3 then
			if self.findVisible then
				self:runFind(isModifierDown(Enum.KeyCode.LeftShift) and -1 or 1)
			end

			return
		end

		if keyCode == Enum.KeyCode.Escape then
			if self.findVisible then
				self:closeFind()
				self.TextBox.KeyHandled = true

				return
			end

			if #self.suggestions > 0 or self.Hint.Visible then
				self:dismissSuggestions()
				self.TextBox.KeyHandled = true
			end

			return
		end

		if self.findVisible then
			return
		end

		if #self.suggestions == 0 then
			return
		end

		if keyCode == Enum.KeyCode.Up then
			self:moveSuggestion(-1)
			self.TextBox.KeyHandled = true
		elseif keyCode == Enum.KeyCode.Down then
			self:moveSuggestion(1)
			self.TextBox.KeyHandled = true
		elseif keyCode == Enum.KeyCode.Return or keyCode == Enum.KeyCode.Tab or keyCode == Enum.KeyCode.KeypadEnter then
			self:acceptSuggestion()
			self.TextBox.KeyHandled = true
		end
	end)
end

return CodeEditor
