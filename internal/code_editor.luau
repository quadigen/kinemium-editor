if (IsServer or IsClient) or IsPlaytest then
	return nil
end

local UI = require("@internal/editor_ui")

local TextService = game:GetService("TextService")
local RunService = game:GetService("RunService")
local Project = game:GetService("Project")
local LuauService = game:GetService("LuauService")

local function C(key)
	local colors = UI.tokens.color

	return colors[key] or colors.text
end

local function fontSize(key)
	return UI.tokens.type[key]
end

local function cornerRadius(key)
	return UI.tokens.radius[key]
end

local function snapshotColors()
	local snapshot = {}

	for key, value in pairs(UI.tokens.color) do
		snapshot[key] = value
	end

	return snapshot
end

local function colorsChanged(snapshot)
	if snapshot == nil then
		return true
	end

	local colors = UI.tokens.color

	for key, value in pairs(colors) do
		if snapshot[key] ~= value then
			return true
		end
	end

	for key in pairs(snapshot) do
		if colors[key] == nil then
			return true
		end
	end

	return false
end

local TAB_STRIP_HEIGHT = 26
local STATUS_HEIGHT = 20
local FIND_WIDTH = 340
local FIND_HEIGHT = 28
local FIND_HEIGHT_REPLACE = FIND_HEIGHT * 2 - 4
local GOTO_WIDTH = 220
local TAB_MIN_WIDTH = 104
local TAB_MAX_WIDTH = 240
local TAB_CLOSE_SIZE = 18
local TAB_FONT = "builtin://fonts/Montserrat-Regular.ttf"

local SUGGEST_WIDTH = 268
local SUGGEST_ROW_HEIGHT = 25
local SUGGEST_MAX_ROWS = 7
local SUGGEST_PADDING = 4
local SUGGEST_ICON_SIZE = 12
local SUGGEST_LINE_HEIGHT = 22

local DIAGNOSTIC_WIDTH = 320
local DIAGNOSTIC_DELAY = 0.18

local CODE_CHAR_WIDTH = 8
local SUPPRESS_ON_CURRENT_LINE = false

local TRIM_ON_SAVE = true
local AUTO_CLOSE_PAIRS = true

local AUTO_END_BLOCKS = true

local COMMIT_DELAY = 0.35
local MAX_FIND_MATCHES = 5000
local MAX_CLOSED_TABS = 10
local POPUP_LERP_SPEED = 26

local SELECTION_BASE = 0

local iconRoot = "builtin://global-icons/"

local KIND_ICONS = {
	Keyword = "sparkle.png",
	Snippet = "sparkle.png",
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

local KIND_COLOR_KEYS = {
	Keyword = "accent",
	Snippet = "accent",
	Global = "accent",
	Table = "warning",
	Function = "success",
	Method = "success",
	Value = "subtext",
	Type = "subtext",
	Property = "text",
	Member = "text",
	Event = "warning",
	Instance = "text",
	Local = "subtext",
	Service = "text",
}

local function kindColor(kind)
	return C(KIND_COLOR_KEYS[kind] or "text")
end

local SIGNATURES = {}
local SIGNATURES_LOWER = {}

local function addSignatures(prefix, text)
	for name, params in string.gmatch(text, "([%w_]+)%(([^)]*)%)") do
		local list = {}

		for param in string.gmatch(params, "[^,%s]+") do
			table.insert(list, param)
		end

		local key = prefix == "" and name or (prefix .. "." .. name)

		SIGNATURES[key] = list
		SIGNATURES_LOWER[string.lower(key)] = list
	end
end

addSignatures(
	"math",
	[[abs(x) acos(x) asin(x) atan(x) atan2(y,x) ceil(x) clamp(value,min,max) cos(x) cosh(x) deg(x) exp(x)
	floor(x) fmod(x,y) frexp(x) ldexp(m,e) lerp(alpha,from,to) log(x,base) log10(x) max(a,b) min(a,b) modf(x)
	noise(x,y,z) pow(x,y) rad(x) random(m,n) randomseed(x) round(x) sign(x) sin(x) sinh(x) sqrt(x) tan(x) tanh(x)]]
)
addSignatures(
	"string",
	[[byte(s,i,j) char(...) find(s,pattern,init,plain) format(s,...) gmatch(s,pattern) gsub(s,pattern,replacement,n)
	len(s) lower(s) match(s,pattern,init) pack(...) packsize(s) rep(s,n,separator) reverse(s) split(s,separator)
	sub(s,i,j) unpack(s,pos) upper(s)]]
)
addSignatures(
	"table",
	[[clear(list) clone(list) concat(list,separator,i,j) create(count) find(list,value,init) foreach(list,callback)
	foreachi(list,callback) freeze(list) getn(list) insert(list,value) isarray(list) isfrozen(list) join(...)
	maxn(list) move(source,from,to,target,targetFrom) pack(...) remove(list,index) sort(list,comparator)
	unfreeze(list) unpack(list,i,j)]]
)
addSignatures(
	"task",
	[[cancel(thread) defer(callback,...) delay(seconds,callback,...) desynchronize(callback,...) spawn(callback,...)
	synchronize(callback,...) wait(seconds)]]
)
addSignatures("os", [[clock() date(format,time) difftime(t2,t1) time(table)]])
addSignatures("coroutine", [[close(co) create(f) isyieldable() resume(co,...) running() status(co) wrap(f) yield(...)]])
addSignatures(
	"utf8",
	[[char(...) codepoint(s,i,j) codes(s) graphemes(s) len(s,i,j) nfcnormalize(s) nfdnormalize(s) offset(s,n,i)]]
)
addSignatures(
	"bit32",
	[[arshift(x,disp) band(x,y) bnot(x) bor(x,y) btest(x,y) bxor(x,y) byteswap(x) countlz(x) countrz(x)
	extract(x,field,width) lrotate(x,disp) lshift(x,disp) replace(x,v,field,width) rrotate(x,disp) rshift(x,disp)]]
)
addSignatures("debug", [[info(...) profilebegin(label) profileend() traceback(message,level)]])
addSignatures("vector", [[create(x,y,z) angle(a,b) cross(a,b) dot(a,b) magnitude(v) normalize(v)]])
addSignatures(
	"buffer",
	[[create(size) copy(target,source,targetStart,sourceStart,count) fill(buffer,value,start,count) fromstring(s)
	len(buffer) readf32(buffer,offset) readf64(buffer,offset) readi8(buffer,offset) readi16(buffer,offset)
	readi32(buffer,offset) readu8(buffer,offset) readu16(buffer,offset) readu32(buffer,offset)
	readstring(buffer,offset,count) tostring(buffer) writef32(buffer,offset,value) writef64(buffer,offset,value)
	writei8(buffer,offset,value) writei16(buffer,offset,value) writei32(buffer,offset,value)
	writeu8(buffer,offset,value) writeu16(buffer,offset,value) writeu32(buffer,offset,value)
	writestring(buffer,offset,value,count)]]
)
addSignatures("Vector2", [[new(x,y) Unit(self) Cross(a,b) Dot(a,b) FuzzyEq(other,epsilon) Lerp(alpha,other)]])
addSignatures(
	"Vector3",
	[[new(x,y,z) FromNormalId(normalId) FromAxis(axis) Unit(self) Abs(self) Ceil(self) Floor(self) Sign(self)
	Cross(a,b) Angle(other) Dot(a,b) FuzzyEq(other,epsilon) Lerp(alpha,other) Max(other) Min(other)]]
)
addSignatures("Vector2int16", [[new(x,y)]])
addSignatures("Vector3int16", [[new(x,y,z)]])
addSignatures(
	"Color3",
	[[new(red,green,blue) fromRGB(red,green,blue) fromHSV(hue,saturation,value) fromHex(hex) Lerp(alpha,other)
	ToHSV(self) ToHex(self) ToRGB(self)]]
)
addSignatures(
	"CFrame",
	[[new(x,y,z) Angles(rx,ry,rz) fromEulerAnglesXYZ(rx,ry,rz) fromEulerAnglesYXZ(ry,rx,rz) fromOrientation(rx,ry,rz)
	fromAxisAngle(axis,angle) lookAt(at,look) lookAlong(at,dir) fromMatrix(pos,vX,vY,vZ) Lerp(alpha,other)
	ToWorldSpace(other) ToObjectSpace(other) PointToWorldSpace(otherPoint) PointToObjectSpace(otherPoint)
	VectorToWorldSpace(otherVector) VectorToObjectSpace(otherVector) Orthonormalize(self) AngleBetween(other)
	FuzzyEq(other,epsilon) ToEulerAnglesXYZ(self) ToEulerAnglesYXZ(self) ToOrientation(self) ToAxisAngle(self)]]
)
addSignatures(
	"Quaternion",
	[[new(x,y,z,w) fromAxisAngle(axis,angle) Unit(self) Conjugate(self) Inverse(self) Dot(a,b) Lerp(alpha,other)
	Slerp(alpha,other) ToAxisAngle(self)]]
)
addSignatures("Axes", [[new(x,y,z)]])
addSignatures("UDim", [[new(scale,offset) Lerp(alpha,other) FuzzyEq(other,epsilon)]])
addSignatures(
	"UDim2",
	[[new(xScale,xOffset,yScale,yOffset) fromScale(x,y) fromOffset(x,y) Lerp(alpha,other) FuzzyEq(other,epsilon)]]
)
addSignatures("Ray", [[new(origin,direction) Unit(self) ClosestPoint(point) Distance(point)]])
addSignatures("Rect", [[new(x,y,width,height)]])
addSignatures("Region3", [[new(cframe,size) ExpandToGrid(step)]])
addSignatures("Region3int16", [[new(cframe,size)]])
addSignatures("NumberRange", [[new(min,max)]])
addSignatures("NumberSequence", [[new(keypoints) Keypoint(time,value,envelope)]])
addSignatures("ColorSequence", [[new(keypoints) Keypoint(time,color)]])
addSignatures("TweenInfo", [[new(time,easingStyle,easingDirection,repeatCount,reverses,delayTime)]])
addSignatures("BrickColor", [[new(value)]])
addSignatures(
	"Random",
	[[new(seed) NextInteger(min,max) NextNumber(min,max) NextUnitVector() Shuffle(list) Clone(self)]]
)
addSignatures("DateTime", [[now() fromUnixTimestamp(seconds) fromUnixTimestampMillis(milliseconds)]])
addSignatures("PhysicalProperties", [[new(density,friction,elasticity,frictionWeight,elasticityWeight)]])
addSignatures("OverlapParams", [[AddToFilter(instance)]])
addSignatures(
	"Instance",
	[[new(className,parent) fromJSON(json) Clone(self) Destroy(self) FindFirstChild(name,recursive)
	FindFirstChildOfClass(className,recursive) GetChildren(self) GetDescendants(self) GetFullName(self)
	GetAttribute(attribute) GetAttributes(self) SetAttribute(attribute,value) IsA(className)
	IsAncestorOf(instance) IsDescendantOf(instance) GetService(className)]]
)
addSignatures(
	"",
	[[print(...) warn(...) error(message,level) assert(value,message) pcall(f,...) xpcall(f,handler) type(value)
	typeof(value) select(index,...) setmetatable(table,metatable) getmetatable(object) rawget(table,index)
	rawset(table,index,value) rawequal(a,b) rawlen(value) require(module) tostring(value) tonumber(value,base)
	next(table,key) unpack(table,i,j) pairs(table) ipairs(table) waitforchild(child,timeout) tick()
	delay(seconds,callback,...) spawn(callback,...) wait(seconds)]]
)

local function listOf(kind, text)
	local list = {}

	for name in string.gmatch(text, "[%w_]+") do
		table.insert(list, { name = name, kind = kind })
	end

	return list
end

local KEYWORDS = listOf(
	"Keyword",
	[[and break continue do else elseif end export false for function if in local nil not or repeat return then
	true type until while]]
)

local GLOBALS = {}

for _, group in ipairs({
	listOf("Global", "game workspace script shared _G"),
	listOf("Table", "bit32 buffer coroutine debug math os string table task utf8 vector"),
	listOf(
		"Function",
		[[assert delay error getmetatable ipairs next pairs pcall print rawequal rawget rawlen rawset require select
		setmetatable spawn tick tonumber tostring type typeof unpack warn wait waitforchild xpcall]]
	),
	listOf(
		"Type",
		[[BrickColor Axes CFrame Color3 ColorSequence DateTime Enum Faces Font Instance NumberRange NumberSequence
		OverlapParams PathWaypoint PhysicalProperties Quaternion Random Ray Rect Region3 Region3int16 TweenInfo
		UDim UDim2 UniqueId Vector2 Vector2int16 Vector3 Vector3int16]]
	),
}) do
	for _, entry in ipairs(group) do
		table.insert(GLOBALS, entry)
	end
end

local KIND_LETTERS = { M = "Method", P = "Property", F = "Function", V = "Value" }
local BUILTIN_MEMBERS = {}
local BUILTIN_MEMBERS_LOWER = {}

local function addMembers(path, text)
	local list = {}

	for name, letter in string.gmatch(text, "([%w_]+):(%a)") do
		table.insert(list, { name = name, kind = KIND_LETTERS[letter] or "Member" })
	end

	BUILTIN_MEMBERS[path] = list
	BUILTIN_MEMBERS_LOWER[string.lower(path)] = list
end

addMembers("Vector2", "new:M X:P Y:P Magnitude:P Unit:M Cross:M Dot:M FuzzyEq:M Lerp:M")
addMembers(
	"Vector3",
	[[new:M FromNormalId:M FromAxis:M x:P X:P y:P Y:P z:P Z:P Magnitude:P Unit:M Abs:M Ceil:M Floor:M Sign:M
	Cross:M Angle:M Dot:M FuzzyEq:M Lerp:M Max:M Min:M]]
)
addMembers("Vector2int16", "new:M X:P Y:P")
addMembers("Vector3int16", "new:M X:P Y:P Z:P")
addMembers("Color3", "new:M fromRGB:M fromHSV:M fromHex:M R:P G:P B:P Lerp:M ToHSV:M ToHex:M ToRGB:M")
addMembers(
	"CFrame",
	[[new:M Angles:M fromEulerAnglesXYZ:M fromEulerAnglesYXZ:M fromOrientation:M fromAxisAngle:M lookAt:M
	lookAlong:M fromMatrix:M Position:P p:P Rotation:P RightVector:P XVector:P UpVector:P YVector:P LookVector:P
	ZVector:P X:P Y:P Z:P Inverse:M Lerp:M ToWorldSpace:M ToObjectSpace:M PointToWorldSpace:M
	PointToObjectSpace:M VectorToWorldSpace:M VectorToObjectSpace:M Orthonormalize:M GetComponents:M
	components:M ToEulerAnglesXYZ:M ToEulerAnglesYXZ:M ToOrientation:M ToAxisAngle:M FuzzyEq:M AngleBetween:M]]
)
addMembers(
	"Quaternion",
	"new:M fromAxisAngle:M X:P Y:P Z:P W:P Magnitude:P Unit:M Conjugate:M Inverse:M Dot:M Lerp:M Slerp:M ToAxisAngle:M"
)
addMembers("Axes", "new:M X:P Y:P Z:P")
addMembers("UDim", "new:M Scale:P Offset:P Lerp:M FuzzyEq:M")
addMembers(
	"UDim2",
	[[new:M fromScale:M fromOffset:M X:P Y:P XScale:P XOffset:P YScale:P YOffset:P Width:P Height:P Lerp:M
	FuzzyEq:M]]
)
addMembers("Ray", "new:M Origin:P Direction:P Unit:M ClosestPoint:M Distance:M")
addMembers("Rect", "new:M Min:P Max:P Width:P Height:P")
addMembers("Region3", "new:M Min:P Max:P Size:P CFrame:P ExpandToGrid:M")
addMembers("Region3int16", "new:M Min:P Max:P Size:P CFrame:P")
addMembers("NumberRange", "new:M Min:P Max:P")
addMembers("NumberSequence", "new:M Keypoint:M Time:P Value:P Envelope:P Keypoints:P")
addMembers("ColorSequence", "new:M Keypoint:M Time:P Value:P Keypoints:P")
addMembers("TweenInfo", "new:M Time:P EasingStyle:P EasingDirection:P RepeatCount:P Reverses:P DelayTime:P")
addMembers("BrickColor", "new:M Number:P Name:P Color:P")
addMembers("Random", "new:M NextInteger:M NextNumber:M NextUnitVector:M Shuffle:M Clone:M")
addMembers("DateTime", "now:M fromUnixTimestamp:M fromUnixTimestampMillis:M")
addMembers("PhysicalProperties", "new:M Density:P Friction:P Elasticity:P FrictionWeight:P ElasticityWeight:P")
addMembers(
	"OverlapParams",
	[[FilterDescendantsInstances:P ExcludeInstances:P IncludeInstances:P FilterType:P MaxParts:P CollisionGroup:P
	Tolerance:P RespectCanCollide:P BruteForceAllSlow:P AddToFilter:M]]
)
addMembers("PathWaypoint", "Position:P Action:P Label:P")
addMembers(
	"Instance",
	[[new:M fromJSON:M Clone:M Destroy:M FindFirstChild:M FindFirstChildOfClass:M GetChildren:M GetDescendants:M
	GetFullName:M GetAttribute:M GetAttributes:M SetAttribute:M IsA:M IsAncestorOf:M IsDescendantOf:M ClassName:P
	Name:P Parent:P]]
)
addMembers("Enum", "GetEnumItems:M")
addMembers(
	"math",
	[[abs:F acos:F asin:F atan:F atan2:F ceil:F clamp:F cos:F cosh:F deg:F exp:F floor:F fmod:F frexp:F ldexp:F
	lerp:F log:F log10:F max:F min:F modf:F noise:F pow:F rad:F random:F randomseed:F round:F sign:F sin:F sinh:F
	sqrt:F tan:F tanh:F huge:V pi:V]]
)
addMembers(
	"string",
	[[byte:F char:F find:F format:F gmatch:F gsub:F len:F lower:F match:F pack:F packsize:F rep:F reverse:F
	split:F sub:F unpack:F upper:F]]
)
addMembers(
	"table",
	[[clear:F clone:F concat:F create:F find:F foreach:F foreachi:F freeze:F getn:F insert:F isarray:F isfrozen:F
	join:F maxn:F move:F pack:F remove:F sort:F unfreeze:F unpack:F]]
)
addMembers("task", "cancel:F defer:F delay:F desynchronize:F spawn:F synchronize:F wait:F")
addMembers("os", "clock:F date:F difftime:F time:F")
addMembers("coroutine", "close:F create:F isyieldable:F resume:F running:F status:F wrap:F yield:F")
addMembers("utf8", "char:F codepoint:F codes:F graphemes:F len:F nfcnormalize:F nfdnormalize:F offset:F")
addMembers(
	"bit32",
	[[arshift:F band:F bnot:F bor:F btest:F bxor:F byteswap:F countlz:F countrz:F extract:F lrotate:F lshift:F
	replace:F rrotate:F rshift:F]]
)
addMembers("debug", "info:F profilebegin:F profileend:F traceback:F")
addMembers("vector", "angle:F create:F cross:F dot:F magnitude:F normalize:F")
addMembers(
	"buffer",
	[[copy:F create:F fill:F fromstring:F len:F readf32:F readf64:F readi16:F readi32:F readi8:F readstring:F
	readu16:F readu32:F readu8:F tostring:F writef32:F writef64:F writei16:F writei32:F writei8:F writestring:F
	writeu16:F writeu32:F writeu8:F]]
)

local SNIPPETS = {
	{ name = "fori", detail = "numeric for", body = "for i = 1, $0 do\n\t\nend" },
	{ name = "foreach", detail = "ipairs loop", body = "for _, value in ipairs($0) do\n\t\nend" },
	{ name = "forpairs", detail = "pairs loop", body = "for key, value in pairs($0) do\n\t\nend" },
	{ name = "lfunc", detail = "local function", body = "local function $0()\n\t\nend" },
	{ name = "ifelse", detail = "if / else", body = "if $0 then\n\t\nelse\n\t\nend" },
	{ name = "whiledo", detail = "while loop", body = "while $0 do\n\t\nend" },
	{ name = "pcallf", detail = "protected call", body = "local ok, result = pcall(function()\n\t$0\nend)" },
	{ name = "svc", detail = "GetService", body = 'game:GetService("$0")' },
	{ name = "tspawn", detail = "task.spawn", body = "task.spawn(function()\n\t$0\nend)" },
	{ name = "conn", detail = ":Connect", body = ":Connect(function($0)\n\t\nend)" },
	{ name = "module", detail = "module skeleton", body = "local Module = {}\n\n$0\n\nreturn Module" },
}

local SNIPPET_CANDIDATES = {}

for _, snippet in ipairs(SNIPPETS) do
	table.insert(SNIPPET_CANDIDATES, {
		name = snippet.name,
		kind = "Snippet",
		detail = snippet.detail,
		snippet = snippet.body,
	})
end

local OPEN_BRACKETS = { ["("] = ")", ["["] = "]", ["{"] = "}" }
local CLOSE_BRACKETS = { [")"] = "(", ["]"] = "[", ["}"] = "{" }

local function parseMember(entry)
	return entry
end

local function collectBuiltinMembers(path)
	return BUILTIN_MEMBERS[path] or BUILTIN_MEMBERS_LOWER[string.lower(path)]
end

local function approach(current, target, delta)
	local weight = 1 - math.exp(-POPUP_LERP_SPEED * delta)

	return current + (target - current) * weight
end

local function lineBounds(text, position)
	position = math.clamp(position, 1, #text + 1)

	local index = position - 1

	while index >= 1 and string.sub(text, index, index) ~= "\n" do
		index -= 1
	end

	local newline = string.find(text, "\n", position, true)

	return index + 1, newline or (#text + 1)
end

local function lineColumn(text, cursor)
	local line = 1
	local lineStart = 1
	local position = 1

	while true do
		local newline = string.find(text, "\n", position, true)

		if newline == nil or newline >= cursor then
			break
		end

		line += 1
		lineStart = newline + 1
		position = newline + 1
	end

	return line, cursor - lineStart + 1
end

local function countLines(text)
	local _, newlines = string.gsub(text, "\n", "")

	return newlines + 1
end

local function positionOfLine(text, line)
	local position = 1
	local current = 1

	while current < line do
		local newline = string.find(text, "\n", position, true)

		if newline == nil then
			break
		end

		position = newline + 1
		current += 1
	end

	return position, current
end

local function insideCommentOrString(text, cursor)
	local lineStart = lineBounds(text, cursor)
	local before = string.sub(text, lineStart, cursor - 1)
	local quote = nil
	local index = 1

	while index <= #before do
		local character = string.sub(before, index, index)

		if quote ~= nil then
			if character == "\\" then
				index += 1
			elseif character == quote then
				quote = nil
			end
		elseif character == '"' or character == "'" or character == "`" then
			quote = character
		elseif character == "-" and string.sub(before, index + 1, index + 1) == "-" then
			return true
		end

		index += 1
	end

	return quote ~= nil
end

local function bracketPairs(text)
	local map = {}
	local stack = {}
	local index = 1
	local length = #text

	while index <= length do
		local character = string.sub(text, index, index)

		if character == "-" and string.sub(text, index + 1, index + 1) == "-" then
			local level = string.match(text, "^%-%-%[(=*)%[", index)

			if level ~= nil then
				local _, finish = string.find(text, "]" .. level .. "]", index, true)

				index = (finish or length) + 1
			else
				local newline = string.find(text, "\n", index, true)

				index = (newline or length) + 1
			end
		elseif character == '"' or character == "'" or character == "`" then
			index += 1

			while index <= length do
				local inner = string.sub(text, index, index)

				if inner == "\\" then
					index += 2
				elseif inner == character or inner == "\n" then
					break
				else
					index += 1
				end
			end

			index += 1
		elseif character == "[" and string.match(text, "^%[=*%[", index) ~= nil then
			local level = string.match(text, "^%[(=*)%[", index)
			local _, finish = string.find(text, "]" .. level .. "]", index, true)

			index = (finish or length) + 1
		elseif OPEN_BRACKETS[character] ~= nil then
			table.insert(stack, { index = index, character = character })

			index += 1
		elseif CLOSE_BRACKETS[character] ~= nil then
			local top = stack[#stack]

			if top ~= nil and top.character == CLOSE_BRACKETS[character] then
				stack[#stack] = nil
				map[top.index] = index
				map[index] = top.index
			end

			index += 1
		else
			index += 1
		end
	end

	return map
end

local QUOTES = { ['"'] = true, ["'"] = true, ["`"] = true }

local function blockBalance(text)
	text = (string.gsub(text, "%-%-[^\n]*", ""))
	text = (string.gsub(text, '"[^"\n]*"', ""))
	text = (string.gsub(text, "'[^'\n]*'", ""))

	local balance = 0

	for word in string.gmatch(text, "[%a_][%w_]*") do
		if word == "function" or word == "if" or word == "do" or word == "repeat" then
			balance += 1
		elseif word == "end" or word == "until" then
			balance -= 1
		end
	end

	return balance
end

local function identifierAt(text, cursor)
	local start = cursor
	local finish = cursor

	while start > 1 and string.match(string.sub(text, start - 1, start - 1), "[%w_]") ~= nil do
		start -= 1
	end

	while finish <= #text and string.match(string.sub(text, finish, finish), "[%w_]") ~= nil do
		finish += 1
	end

	if finish == start then
		return nil
	end

	return start, finish
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

	return SIGNATURES[callee] or SIGNATURES_LOWER[string.lower(callee)]
end

local function isGetServiceCall(callee)
	if callee == nil then
		return false
	end

	return string.lower(callee) == "getservice" or string.find(callee, "%.getservice$") ~= nil
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
		local character = string.sub(text, index, index)

		if MAGIC_CHARACTERS[character] then
			table.insert(buffer, "%")
		end

		table.insert(buffer, character)
	end

	return table.concat(buffer)
end

local function isModifierDown(code)
	local service = game:GetService("UserInputService")

	return service ~= nil and service:IsKeyDown(code) == true
end

local function modifierHeld()
	return isModifierDown(Enum.KeyCode.LeftControl)
		or isModifierDown(Enum.KeyCode.RightControl)
		or isModifierDown(Enum.KeyCode.LeftSuper)
		or isModifierDown(Enum.KeyCode.RightSuper)
end

local function shiftHeld()
	return isModifierDown(Enum.KeyCode.LeftShift) or isModifierDown(Enum.KeyCode.RightShift)
end

local function altHeld()
	return isModifierDown(Enum.KeyCode.LeftAlt) or isModifierDown(Enum.KeyCode.RightAlt)
end

local function selectAllText(input)
	if not pcall(function()
		input:SelectAll()
	end) then
		pcall(function()
			input.SelectAll()
		end)
	end
end

local function transparentFrame(parent, name)
	return UI.create("Frame", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, parent)
end

local serviceCache = nil
local serviceSetCache = nil
local serviceCacheTime = 0

local function refreshServiceCache()
	local now = os.clock()

	if serviceCache ~= nil and now - serviceCacheTime < 2 then
		return
	end

	local names = {}
	local set = {}

	for _, child in ipairs(game:GetChildren()) do
		table.insert(names, child.Name)
		set[child.Name] = true
	end

	table.sort(names)

	serviceCache = names
	serviceSetCache = set
	serviceCacheTime = now
end

local function serviceNames()
	refreshServiceCache()

	return serviceCache
end

local function serviceCandidates()
	local candidates = {}

	for _, name in ipairs(serviceNames()) do
		table.insert(candidates, { name = name, kind = "Service", detail = "Service" })
	end

	return candidates
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
				table.insert(members, { name = name, kind = "Value", detail = tostring(item.Value) })
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
					table.insert(results, { name = name, kind = list.kind })
				end
			end
		end
	end

	return results
end

local function collectInstanceMembers(instance)
	local members = {}

	for _, child in ipairs(instance:GetChildren()) do
		table.insert(members, { name = child.Name, kind = "Instance", detail = child.ClassName })
	end

	for _, member in ipairs(collectReflectionMembers(instance)) do
		table.insert(members, member)
	end

	return members
end

local function collectDocumentWords(source)
	local words = {}
	local seen = {}

	for word in string.gmatch(source, "[%a_][%w_]*") do
		if not seen[word] then
			seen[word] = true

			table.insert(words, { name = word, kind = "Local" })

			if #words >= 5000 then
				break
			end
		end
	end

	return words
end

local function collectServiceAliases(source)
	refreshServiceCache()

	local aliases = {}

	for name, service in
		string.gmatch(source, "local%s+([%a_][%w_]*)%s*=%s*[%a_][%w_]*[%.:]GetService%s*%(%s*[\"']([^\"']+)[\"']")
	do
		aliases[name] = service
	end

	for name, target in string.gmatch(source, "local%s+([%a_][%w_]*)%s*=%s*([%a_][%w_]*)%s") do
		if aliases[name] == nil then
			if target == "game" or target == "workspace" then
				aliases[name] = target
			elseif serviceSetCache[target] then
				aliases[name] = target
			end
		end
	end

	return aliases
end

local function diagnosticSpan(source, lineNumber, message)
	local lines = string.split(source, "\n")
	local line = lines[lineNumber]

	if line == nil or line == "" then
		return 1, 1
	end

	local token = message:match("near '([^']+)'")
		or message:match('near "([^"]+)"')
		or message:match("got '([^']+)'")
		or message:match('got "([^"]+)"')

	if token ~= nil and token ~= "" then
		local start = string.find(line, token, 1, true)

		if start ~= nil then
			return start, math.min(#line, start + #token - 1)
		end
	end

	local first = string.find(line, "%S")

	if first ~= nil then
		return first, #line
	end

	return 1, 1
end

local CodeEditor = {}
CodeEditor.__index = CodeEditor

function CodeEditor:bindTheme(instance, property, key)
	if instance == nil then
		return instance
	end

	if not pcall(function()
		local _ = instance[property]
	end) then
		return instance
	end

	local resolve = type(key) == "function" and key or function()
		return C(key)
	end

	table.insert(self.themed, { instance = instance, property = property, resolve = resolve })

	instance[property] = resolve()

	return instance
end

function CodeEditor:addStroke(target, key, thickness, transparency)
	local stroke = UI.stroke(target, C(key), thickness, transparency)

	if typeof(stroke) ~= "Instance" then
		stroke = nil

		for _, child in ipairs(target:GetChildren()) do
			if child.ClassName == "UIStroke" then
				stroke = child

				break
			end
		end
	end

	if stroke ~= nil then
		self:bindTheme(stroke, "Color", key)
	end
end

function CodeEditor:applyTheme()
	local list = self.themed
	local write = 0

	for read = 1, #list do
		local binding = list[read]

		if UI.isAlive(binding.instance) then
			write += 1
			list[write] = binding

			local value = binding.resolve()

			if binding.instance[binding.property] ~= value then
				binding.instance[binding.property] = value
			end
		end
	end

	for index = #list, write + 1, -1 do
		list[index] = nil
	end
end

function CodeEditor:rebuildThemedContent()
	self:rebuildTabs()
	self:buildFindButtons()

	if UI.isAlive(self.Popup) and self.Popup.Visible then
		self:renderSuggestions()
	end

	if UI.isAlive(self.Hint) and self.Hint.Visible then
		self:renderArgumentHint()
	end
end

function CodeEditor:syncTheme()
	if colorsChanged(self.themeSnapshot) then
		self.themeSnapshot = snapshotColors()
		self:applyTheme()
		self:rebuildThemedContent()
	else
		self:applyTheme()
	end
end

function CodeEditor:RefreshTheme()
	self.themeSnapshot = nil
	self:syncTheme()
end

function CodeEditor.new(parent)
	local self = setmetatable({}, CodeEditor)

	self.documents = {}
	self.documentByInstance = {}
	self.documentByPath = {}
	self.activeDocument = nil
	self.suppressTextSync = false
	self.destroyed = false

	self.themed = {}
	self.connections = {}
	self.themeSnapshot = snapshotColors()

	self.suggestions = {}
	self.suggestionIndex = 1
	self.suggestPrefix = nil
	self.suggestRange = nil
	self.suggestionScroll = 0
	self.applyingSuggestion = false
	self.forceSuggest = false
	self.hintSignature = nil
	self.usage = {}
	self.closedStack = {}
	self.pollTimer = 0

	self.currentDiagnostic = nil
	self.diagnosticActive = false
	self.diagnosticShown = nil
	self.diagnosticPinned = false
	self.pinnedCursor = nil
	self.lastMouse = Vector2.new(0, 0)
	self.lastText = ""
	self.pendingCloser = nil
	self.toastExpires = nil

	local tabStrip = UI.create("ScrollingFrame", {
		Name = "ScriptTabs",
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, TAB_STRIP_HEIGHT),
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		ScrollingEnabled = true,
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 4,
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

	self:bindTheme(tabStrip, "BackgroundColor3", "panel")
	self:bindTheme(tabStrip, "ScrollBarImageColor3", "subtext")

	local editor = UI.create("TextBox", {
		Name = "CodeEditor",
		Size = UDim2.new(1, 0, 1, -(TAB_STRIP_HEIGHT + STATUS_HEIGHT)),
		Position = UDim2.fromOffset(0, TAB_STRIP_HEIGHT),
		CodeEditor = true,
		Visible = false,
		Active = true,
		AutoIndent = true,
		ShowMinimap = true,
		BackgroundTransparency = 0.3,
	}, parent)

	self:bindTheme(editor, "BackgroundColor3", "input")
	self:bindTheme(editor, "TextColor3", "text")

	UI.create("SyntaxHighlighter", { Parent = editor })
	UI.create("UIBackdrop", { Parent = editor })

	local statusBar =
		UI.frame(parent, UDim2.new(0, 0, 1, -STATUS_HEIGHT), UDim2.new(1, 0, 0, STATUS_HEIGHT), C("panel"), 0)

	statusBar.Name = "StatusBar"
	statusBar.Visible = false
	self:bindTheme(statusBar, "BackgroundColor3", "panel")

	local statusBorder = UI.frame(statusBar, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 1), C("border"), 0)

	self:bindTheme(statusBorder, "BackgroundColor3", "border")

	self.StatusBar = statusBar
	self.StatusPosition = UI.label(
		statusBar,
		"Ln 1, Col 1",
		UDim2.fromOffset(10, 3),
		UDim2.fromOffset(170, 14),
		fontSize("caption"),
		C("subtext")
	)
	self.StatusMessage =
		UI.label(statusBar, "", UDim2.fromOffset(190, 3), UDim2.new(1, -450, 0, 14), fontSize("caption"), C("accent"))
	self.StatusInfo = UI.label(
		statusBar,
		"No problems",
		UDim2.new(1, -250, 0, 3),
		UDim2.fromOffset(240, 14),
		fontSize("caption"),
		C("subtext")
	)
	self.StatusInfo.TextXAlignment = Enum.TextXAlignment.Right

	self:bindTheme(self.StatusPosition, "TextColor3", "subtext")
	self:bindTheme(self.StatusMessage, "TextColor3", "accent")
	self:bindTheme(self.StatusInfo, "TextColor3", function()
		return self.diagnosticActive and C("error") or C("subtext")
	end)

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
		C("surface"),
		cornerRadius("sm")
	)

	popup.Name = "SuggestionPopup"
	popup.Visible = false
	popup.Active = true
	popup.ClipsDescendants = true

	self:bindTheme(popup, "BackgroundColor3", "surface")
	self:addStroke(popup, "borderStrong", 1, 0)
	self:bindTheme(
		UI.create("UIShadow", {
			BlurRadius = UDim.new(0, 6),
			Offset = UDim2.fromOffset(0, 2),
			Spread = UDim2.fromOffset(0, 1),
			Transparency = 0.4,
			Parent = popup,
		}),
		"Color3",
		"canvas"
	)

	self.PopupRows = transparentFrame(popup, "Rows")

	local hint = UI.frame(
		suggestionLayer,
		UDim2.fromOffset(0, 0),
		UDim2.fromOffset(SUGGEST_WIDTH, SUGGEST_ROW_HEIGHT + SUGGEST_PADDING),
		C("panel"),
		cornerRadius("sm")
	)

	hint.Name = "ArgumentHint"
	hint.Visible = false

	self:bindTheme(hint, "BackgroundColor3", "panel")
	self:addStroke(hint, "border", 1, 0)

	self.HintContent = transparentFrame(hint, "Content")

	local diagnostic = UI.frame(
		suggestionLayer,
		UDim2.fromOffset(0, 0),
		UDim2.fromOffset(DIAGNOSTIC_WIDTH, 54),
		C("panel"),
		cornerRadius("sm")
	)

	diagnostic.Name = "DiagnosticPopup"
	diagnostic.Visible = false
	diagnostic.Active = false
	diagnostic.ClipsDescendants = true
	diagnostic.ZIndex = 100

	self:bindTheme(diagnostic, "BackgroundColor3", "panel")
	self:addStroke(diagnostic, "error", 1, 0.35)
	self:bindTheme(
		UI.create("UIShadow", {
			BlurRadius = UDim.new(0, 8),
			Offset = UDim2.fromOffset(0, 3),
			Spread = UDim2.fromOffset(0, 1),
			Transparency = 0.35,
			Parent = diagnostic,
		}),
		"Color3",
		"canvas"
	)

	local diagnosticTitle = UI.label(
		diagnostic,
		"Syntax error",
		UDim2.fromOffset(10, 6),
		UDim2.new(1, -20, 0, 15),
		fontSize("caption"),
		C("error")
	)

	diagnosticTitle.ZIndex = 101
	self:bindTheme(diagnosticTitle, "TextColor3", "error")

	local diagnosticText =
		UI.label(diagnostic, "", UDim2.fromOffset(10, 24), UDim2.new(1, -20, 1, -30), fontSize("small"), C("text"))

	diagnosticText.TextWrapped = true
	diagnosticText.TextYAlignment = Enum.TextYAlignment.Top
	diagnosticText.ZIndex = 101
	self:bindTheme(diagnosticText, "TextColor3", "text")

	self.TabStrip = tabStrip
	self.TextBox = editor
	self.SuggestionLayer = suggestionLayer
	self.Popup = popup
	self.Hint = hint
	self.DiagnosticPopup = diagnostic
	self.DiagnosticTitle = diagnosticTitle
	self.DiagnosticText = diagnosticText
	self.diagnosticSerial = 0
	self.rows = {}

	local find = UI.frame(
		suggestionLayer,
		UDim2.fromOffset(0, 0),
		UDim2.fromOffset(FIND_WIDTH, FIND_HEIGHT),
		C("panel"),
		cornerRadius("sm")
	)

	find.Name = "FindWidget"
	find.Visible = false
	find.Active = true
	find.ClipsDescendants = true

	self:bindTheme(find, "BackgroundColor3", "panel")
	self:addStroke(find, "border", 1, 0)

	local function styleInput(input)
		self:bindTheme(input, "BackgroundColor3", "input")
		self:bindTheme(input, "TextColor3", "text")
		self:bindTheme(input, "PlaceholderColor3", "muted")
	end

	self.findInput = UI.create("TextBox", {
		Name = "FindInput",
		Size = UDim2.new(1, -(26 + 132), 0, FIND_HEIGHT - 8),
		Position = UDim2.fromOffset(26, 4),
		BorderSizePixel = 0,
		Text = "",
		PlaceholderText = "Find",
		TextSize = fontSize("small"),
		ClearTextOnFocus = false,
	}, find)

	styleInput(self.findInput)

	self.replaceInput = UI.create("TextBox", {
		Name = "ReplaceInput",
		Size = UDim2.new(1, -(26 + 8 + 36 + 4 + 56 + 4), 0, FIND_HEIGHT - 8),
		Position = UDim2.fromOffset(26, FIND_HEIGHT),
		BorderSizePixel = 0,
		Text = "",
		PlaceholderText = "Replace",
		TextSize = fontSize("small"),
		ClearTextOnFocus = false,
		Visible = false,
	}, find)

	styleInput(self.replaceInput)

	self.findCount = UI.label(
		find,
		"No results",
		UDim2.new(1, -(132 + 76), 0, 8),
		UDim2.fromOffset(72, 12),
		fontSize("caption"),
		C("muted")
	)
	self.findCount.TextXAlignment = Enum.TextXAlignment.Right
	self:bindTheme(self.findCount, "TextColor3", "muted")

	self.findButtonHost = transparentFrame(find, "Buttons")
	self.findButtons = {}
	self.replaceButtons = {}

	self.Find = find
	self.findVisible = false
	self.replaceMode = false
	self.findMatches = {}
	self.findIndex = 0
	self.findCaseSensitive = false
	self.findWholeWord = false

	local goTo = UI.frame(
		suggestionLayer,
		UDim2.fromOffset(0, 0),
		UDim2.fromOffset(GOTO_WIDTH, FIND_HEIGHT),
		C("panel"),
		cornerRadius("sm")
	)

	goTo.Name = "GoToLineWidget"
	goTo.Visible = false
	goTo.Active = true
	goTo.ClipsDescendants = true

	self:bindTheme(goTo, "BackgroundColor3", "panel")
	self:addStroke(goTo, "border", 1, 0)

	self.goToInput = UI.create("TextBox", {
		Name = "GoToInput",
		Size = UDim2.new(1, -96, 0, FIND_HEIGHT - 8),
		Position = UDim2.fromOffset(4, 4),
		BorderSizePixel = 0,
		Text = "",
		PlaceholderText = "Go to line",
		TextSize = fontSize("small"),
		ClearTextOnFocus = false,
	}, goTo)

	styleInput(self.goToInput)

	self.goToHint =
		UI.label(goTo, "", UDim2.new(1, -88, 0, 8), UDim2.fromOffset(82, 12), fontSize("caption"), C("muted"))
	self.goToHint.TextXAlignment = Enum.TextXAlignment.Right
	self:bindTheme(self.goToHint, "TextColor3", "muted")

	self.GoTo = goTo
	self.goToVisible = false

	self.popupPosition = Vector2.new(0, 0)
	self.popupTarget = Vector2.new(0, 0)
	self.hintPosition = Vector2.new(0, 0)
	self.hintTarget = Vector2.new(0, 0)
	self.popupPlaced = false
	self.hintPlaced = false
	self.popupSize = Vector2.new(SUGGEST_WIDTH, SUGGEST_ROW_HEIGHT)
	self.hintHeight = SUGGEST_ROW_HEIGHT + SUGGEST_PADDING

	self:buildFindButtons()
	self:wireEditor()
	self:registerRenderStep()

	return self
end

function CodeEditor:Destroy()
	if self.destroyed then
		return
	end

	self.destroyed = true

	for _, document in ipairs(self.documents) do
		if document == self.activeDocument and UI.isAlive(self.TextBox) then
			document.source = self.TextBox.Text
		end

		self:commitDocument(document)
	end

	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end

	self.connections = {}

	for _, instance in ipairs({ self.SuggestionLayer, self.TabStrip, self.TextBox, self.StatusBar }) do
		if UI.isAlive(instance) then
			instance:Destroy()
		end
	end
end

function CodeEditor:connect(signal, callback)
	local connection = signal:Connect(callback)

	table.insert(self.connections, connection)

	return connection
end

function CodeEditor:registerRenderStep()
	self:connect(RunService.Heartbeat, function(dt)
		self:update(dt or 1 / 60)
	end)
end

function CodeEditor:update(delta)
	if self.destroyed then
		return
	end

	if type(delta) ~= "number" then
		delta = 1 / 60
	end

	self:syncTheme()

	if self.diagnosticShown ~= nil then
		if self.diagnosticPinned and self.TextBox.CursorPosition ~= self.pinnedCursor then
			self:hideDiagnosticPopup()
		else
			self:placeDiagnosticPopup()
		end
	end

	if self.findVisible or self.goToVisible then
		self:placeFindWidget()
	end

	self.pollTimer += delta

	if self.pollTimer >= 1 then
		self.pollTimer = 0
		self:pollDocuments()
	end

	if self.toastExpires ~= nil and os.clock() >= self.toastExpires then
		self.toastExpires = nil
		self.StatusMessage.Text = ""
	end

	self:updateStatus()

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

function CodeEditor:pollDocuments()
	local renamed = false

	for _, document in ipairs(table.clone(self.documents)) do
		local instance = document.instance

		if instance ~= nil then
			if not UI.isAlive(instance) then
				self:closeDocument(document, true)
			else
				local ok, name = pcall(function()
					return instance.Name
				end)

				if ok and name ~= document.name then
					document.name = name
					renamed = true
				end
			end
		end
	end

	if renamed then
		self:rebuildTabs()
	end
end

function CodeEditor:notify(text, seconds)
	if not UI.isAlive(self.StatusMessage) then
		return
	end

	self.StatusMessage.Text = text
	self.toastExpires = os.clock() + (seconds or 1.8)
end

function CodeEditor:getSelection()
	local box = self.TextBox
	local first = box.SelectionStart
	local second = box.SelectionEnd
	local cursor = math.max(box.CursorPosition or 1, 1)

	if type(first) ~= "number" or type(second) ~= "number" or first < 0 or second < 0 or first == second then
		return cursor, cursor, false
	end

	return math.min(first, second) + 1 - SELECTION_BASE, math.max(first, second) + 1 - SELECTION_BASE, true
end

function CodeEditor:setSelection(first, finish)
	local box = self.TextBox

	if first == finish then
		box.CursorPosition = first

		return
	end

	box.SelectionStart = first - 1 + SELECTION_BASE
	box.SelectionEnd = finish - 1 + SELECTION_BASE
end

function CodeEditor:isScriptInstance(instance)
	return instance ~= nil
		and (
			instance:IsA("Script")
			or instance:IsA("PostProcess")
			or instance:IsA("ModuleScript")
			or instance:IsA("LocalScript")
		)
end

function CodeEditor:tabWidthFor(name)
	local textSize = TextService:GetTextSize(name, fontSize("small"), TAB_FONT, Vector2.new(10000, 10000))

	return math.clamp(math.ceil(textSize.X) + 52, TAB_MIN_WIDTH, TAB_MAX_WIDTH)
end

function CodeEditor:commitDocument(document)
	if document.committed == document.source then
		return
	end

	if document.path ~= nil then
		document.commitSerial = (document.commitSerial or 0) + 1

		local ok = pcall(function()
			Project:WriteFile(document.path, document.source)
		end)

		if ok then
			document.committed = document.source
		end

		return
	end

	local instance = document.instance

	if instance == nil or not UI.isAlive(instance) then
		return
	end

	local ok = pcall(function()
		instance.Source = document.source
	end)

	if ok then
		document.committed = document.source
	end
end

function CodeEditor:scheduleCommit(document)
	if document.path == nil then
		self:commitDocument(document)

		return
	end

	document.commitSerial = (document.commitSerial or 0) + 1

	local serial = document.commitSerial

	task.delay(COMMIT_DELAY, function()
		if not self.destroyed and document.commitSerial == serial then
			self:commitDocument(document)
		end
	end)
end

function CodeEditor:tidyForSave()
	local box = self.TextBox
	local text = box.Text

	local cleaned = string.gsub(text, "[ \t]+(\r?\n)", "%1")
	cleaned = string.gsub(cleaned, "[ \t]+$", "")
	cleaned = string.gsub(cleaned, "\n+$", "")

	if cleaned ~= "" then
		cleaned ..= "\n"
	end

	if cleaned == text then
		return
	end

	local line, column = lineColumn(text, math.max(box.CursorPosition or 1, 1))

	box:ReplaceRange(1, #text + 1, cleaned)

	local lineStart = positionOfLine(cleaned, line)
	local _, lineEnd = lineBounds(cleaned, lineStart)

	box.CursorPosition = math.min(lineStart + column - 1, lineEnd)
end

function CodeEditor:saveActive()
	local document = self.activeDocument

	if document == nil then
		return
	end

	if TRIM_ON_SAVE then
		self:tidyForSave()
	end

	document.source = self.TextBox.Text
	document.committed = nil

	self:commitDocument(document)
	self:notify("Saved " .. document.name)
end

function CodeEditor:hasDocument()
	return self.activeDocument ~= nil
end

function CodeEditor:rebuildTabs()
	UI.clear(self.TabStrip)

	local x = 0
	local activeX, activeWidth = 0, 0

	for _, document in ipairs(self.documents) do
		local isActive = document == self.activeDocument
		local background = isActive and C("surfaceAlt") or C("panel")

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
				hoverColor = C("hover"),
				textColor = C("subtext"),
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
			fontSize("small"),
			isActive and C("text") or C("subtext")
		)

		pcall(function()
			document.tabLabel.TextTruncate = Enum.TextTruncate.AtEnd
		end)

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
				hoverColor = C("error"),
				radius = 0,
				border = false,
				iconSize = 10,
			}
		)

		if isActive then
			UI.frame(tab, UDim2.new(0, 0, 1, -2), UDim2.new(1, 0, 0, 2), C("accent"), 0)

			activeX, activeWidth = x, width
		end

		x += width
	end

	self.TabStrip.CanvasSize = UDim2.fromOffset(x, 0)

	UI.frame(self.TabStrip, UDim2.new(0, 0, 1, -1), UDim2.new(1, 0, 0, 1), C("border"), 0)

	pcall(function()
		local viewWidth = self.TabStrip.AbsoluteSize.X
		local position = self.TabStrip.CanvasPosition.X

		if viewWidth > 0 then
			if activeX < position then
				position = activeX
			elseif activeX + activeWidth > position + viewWidth then
				position = activeX + activeWidth - viewWidth
			end

			self.TabStrip.CanvasPosition = Vector2.new(math.max(position, 0), 0)
		end
	end)
end

function CodeEditor:loadDocument(document)
	self.activeDocument = document

	self.suppressTextSync = true
	self.TextBox.Text = document.source
	self.suppressTextSync = false

	if document.cursor ~= nil and document.cursor >= 1 then
		pcall(function()
			self.TextBox.CursorPosition = math.min(document.cursor, #document.source + 1)
		end)
	end

	self:dismissSuggestions()
	self:refreshDiagnostics()

	if self.findVisible then
		self:scanFindMatches()
		self:updateFindCount()
	end

	self:rebuildTabs()
	self:updateVisibility()
end

function CodeEditor:focusDocument(document)
	if document == nil or document == self.activeDocument then
		return
	end

	if self.activeDocument ~= nil then
		self.activeDocument.source = self.TextBox.Text
		self.activeDocument.cursor = self.TextBox.CursorPosition

		self:commitDocument(self.activeDocument)
	end

	self:loadDocument(document)
end

function CodeEditor:cycleDocument(direction)
	local count = #self.documents

	if count < 2 or self.activeDocument == nil then
		return
	end

	local index = table.find(self.documents, self.activeDocument) or 1
	local nextIndex = (index - 1 + direction) % count + 1

	self:focusDocument(self.documents[nextIndex])
	self.TextBox:CaptureFocus()
end

function CodeEditor:closeDocument(document, silent)
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

	if not silent then
		table.insert(self.closedStack, { instance = document.instance, path = document.path, name = document.name })

		if #self.closedStack > MAX_CLOSED_TABS then
			table.remove(self.closedStack, 1)
		end
	end

	if document.instance ~= nil then
		self.documentByInstance[document.instance] = nil
	end

	if document.path ~= nil then
		self.documentByPath[document.path] = nil
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

			self.TextBox:ClearDiagnostics()
			self.currentDiagnostic = nil
			self:hideDiagnosticPopup()

			self:dismissSuggestions()

			if self.findVisible then
				self:closeFind(true)
			end

			if self.goToVisible then
				self:closeGoTo(true)
			end

			self:rebuildTabs()
			self:updateVisibility()
		end
	else
		self:rebuildTabs()
	end
end

function CodeEditor:reopenClosed()
	while #self.closedStack > 0 do
		local entry = table.remove(self.closedStack)

		if entry.path ~= nil then
			self:OpenFile(entry.path, entry.name)

			return true
		elseif entry.instance ~= nil and UI.isAlive(entry.instance) then
			self:OpenScript(entry.instance)

			return true
		end
	end

	self:notify("No recently closed tabs")

	return false
end

function CodeEditor:OpenScript(instance, line)
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
			committed = source,
		}

		table.insert(self.documents, document)
		self.documentByInstance[instance] = document
	end

	self:focusDocument(document)

	if line ~= nil then
		self:GoToLine(line)
	end
end

function CodeEditor:OpenFile(path, name, line)
	if type(path) ~= "string" then
		return
	end

	if name == nil or name == "" then
		name = path:match("[^/\\]+$") or path
	end

	local document = self.documentByPath[path]

	if document == nil then
		local source = ""
		local ok, value = pcall(function()
			return Project:ReadFile(path)
		end)

		if ok and type(value) == "string" then
			source = value
		end

		document = {
			path = path,
			name = name,
			source = source,
			committed = source,
		}

		table.insert(self.documents, document)
		self.documentByPath[path] = document
	end

	self:focusDocument(document)

	if line ~= nil then
		self:GoToLine(line)
	end
end

function CodeEditor:CloseFile(path)
	self:closeDocument(self.documentByPath[path])
end

function CodeEditor:IsFileOpen(path)
	return self.documentByPath[path] ~= nil
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
	local has = self:hasDocument()

	self.TextBox.Visible = has
	self.TabStrip.Visible = #self.documents > 0
	self.StatusBar.Visible = has

	if not has then
		self:dismissSuggestions()
	end
end

function CodeEditor:activeSource()
	if self.activeDocument ~= nil then
		return self.activeDocument.source
	end

	return self.TextBox.Text
end

function CodeEditor:GoToLine(line, column)
	if not self:hasDocument() then
		return
	end

	local text = self.TextBox.Text
	local position = positionOfLine(text, math.max(1, math.floor(tonumber(line) or 1)))

	if column ~= nil then
		local _, finish = lineBounds(text, position)

		position = math.min(position + math.max(column - 1, 0), finish)
	end

	self.TextBox.CursorPosition = position
	self.TextBox:CaptureFocus()
end

function CodeEditor:goToDiagnostic()
	local diagnostic = self.currentDiagnostic

	if diagnostic == nil then
		self:notify("No syntax errors")

		return
	end

	self:GoToLine(diagnostic.Line, diagnostic.Column)

	self:showDiagnosticPopup(diagnostic)
	self.diagnosticPinned = true
	self.pinnedCursor = self.TextBox.CursorPosition
end

function CodeEditor:openGoTo()
	if not self:hasDocument() then
		return
	end

	self:closeFind(true)

	self.goToVisible = true
	self.GoTo.Visible = true
	self.goToInput.Text = ""
	self:updateGoToHint()
	self:placeFindWidget()
	self.goToInput:CaptureFocus()
end

function CodeEditor:closeGoTo(skipFocus)
	if not self.goToVisible then
		return
	end

	self.goToVisible = false
	self.GoTo.Visible = false

	if not skipFocus then
		self.TextBox:CaptureFocus()
	end
end

function CodeEditor:updateGoToHint()
	local total = countLines(self.TextBox.Text)
	local requested = tonumber(self.goToInput.Text)

	if requested == nil then
		self.goToHint.Text = "1 - " .. total
	elseif requested < 1 or requested > total then
		self.goToHint.Text = "max " .. total
	else
		self.goToHint.Text = "Line " .. math.floor(requested)
	end
end

function CodeEditor:updateStatus()
	if not self.TextBox.Visible then
		return
	end

	local box = self.TextBox
	local text = box.Text
	local cursor = math.max(box.CursorPosition or 1, 1)
	local first, finish, hasSelection = self:getSelection()

	if
		text == self.statusText
		and cursor == self.statusCursor
		and first == self.statusFirst
		and finish == self.statusFinish
		and self.currentDiagnostic == self.statusDiagnostic
	then
		return
	end

	if text ~= self.statusText then
		self.statusLines = countLines(text)
	end

	self.statusText = text
	self.statusCursor = cursor
	self.statusFirst = first
	self.statusFinish = finish
	self.statusDiagnostic = self.currentDiagnostic

	local line, column = lineColumn(text, cursor)
	local position = ("Ln %d, Col %d"):format(line, column)

	if hasSelection then
		position ..= (" (%d selected)"):format(finish - first)
	end

	self.StatusPosition.Text = position

	local diagnostic = self.currentDiagnostic
	local info

	if diagnostic ~= nil then
		self.diagnosticActive = true
		info = ("Syntax error · Ln %d   %d lines"):format(diagnostic.Line, self.statusLines)
	else
		self.diagnosticActive = false
		info = ("No problems   %d lines"):format(self.statusLines)
	end

	self.StatusInfo.Text = info
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

	local source = self:activeSource()
	local candidates = {}

	for _, list in ipairs({ KEYWORDS, GLOBALS, SNIPPET_CANDIDATES }) do
		for _, entry in ipairs(list) do
			table.insert(candidates, entry)
		end
	end

	if self.wordCacheSource ~= source then
		self.wordCacheSource = source
		self.wordCache = collectDocumentWords(source)
	end

	for _, word in ipairs(self.wordCache) do
		table.insert(candidates, word)
	end

	return candidates
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

function CodeEditor:hideSuggestionList()
	self.suggestions = {}
	self.suggestionIndex = 1
	self.suggestPrefix = nil
	self.suggestRange = nil
	self.suggestionScroll = 0

	if UI.isAlive(self.Popup) then
		self.Popup.Visible = false
	end
end

function CodeEditor:suggestionsBlocked()
	local diagnostic = self.currentDiagnostic

	if diagnostic == nil or self.forceSuggest then
		return false
	end

	if SUPPRESS_ON_CURRENT_LINE then
		return true
	end

	local box = self.TextBox
	local line = lineColumn(box.Text, math.max(box.CursorPosition or 1, 1))

	return diagnostic.Line ~= line
end

function CodeEditor:refreshSuggestions()
	self:updateSuggestionList()

	self:renderArgumentHint()
end

function CodeEditor:updateSuggestionList()
	local box = self.TextBox
	local text = box.Text
	local cursor = box.CursorPosition or 1

	if self:suggestionsBlocked() then
		self:hideSuggestionList()

		return
	end

	local service = self:serviceArgumentAt()

	if service ~= nil then
		self.forceSuggest = false
		self:showServiceList(service.prefix, service.start, service.finish)

		return
	end

	local forced = self.forceSuggest

	self.forceSuggest = false

	if cursor >= 1 and insideCommentOrString(text, cursor) then
		self:dismissSuggestions()

		return
	end

	local word = box:GetWordRangeAtCursor()

	if word == nil then
		if forced then
			word = { text = "", start = cursor, finish = cursor }
		else
			self:dismissSuggestions()

			return
		end
	end

	local path = word.text or ""

	if path == "" and not forced then
		self:dismissSuggestions()

		return
	end

	local segments, ends_with_dot = splitPath(path)

	local prefix = ends_with_dot and "" or (segments[#segments] or "")

	if prefix == "" and not ends_with_dot and not forced then
		self:dismissSuggestions()

		return
	end

	if self.aliasSource ~= text then
		self.aliasSource = text
		self.aliasCache = collectServiceAliases(text)
	end

	local ranked = {}

	for _, candidate in ipairs(self:collectCandidates(segments, ends_with_dot, self.aliasCache)) do
		local skip = candidate.kind == "Local" and candidate.name == prefix
		local score = not skip and scoreMatch(candidate.name, prefix) or nil

		if score ~= nil then
			table.insert(ranked, {
				name = candidate.name,
				kind = candidate.kind,
				detail = candidate.detail,
				snippet = candidate.snippet,
				score = candidate.snippet and score + 0.5 or score,
				quote = false,
			})
		end
	end

	if #ranked == 1 and ranked[1].name == prefix then
		self:dismissSuggestions()

		return
	end

	self:showRanked(ranked, prefix, self:completionRange(word, segments, ends_with_dot))
end

function CodeEditor:showRanked(ranked, prefix, range)
	if #ranked == 0 then
		self:dismissSuggestions()

		return
	end

	local usage = self.usage

	table.sort(ranked, function(a, b)
		if a.score ~= b.score then
			return a.score < b.score
		end

		local usageA = usage[a.name] or 0
		local usageB = usage[b.name] or 0

		if usageA ~= usageB then
			return usageA > usageB
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

	if current == nil and #params > 0 and params[#params] == "..." then
		current = "..."
	end

	self.hintHeight = SUGGEST_ROW_HEIGHT + SUGGEST_PADDING

	self.Hint.Size = UDim2.fromOffset(SUGGEST_WIDTH, self.hintHeight)

	UI.clear(self.HintContent)

	local padding = math.floor(SUGGEST_PADDING / 2)

	if current ~= nil then
		UI.label(
			self.HintContent,
			current,
			UDim2.fromOffset(8, padding + 1),
			UDim2.fromOffset(90, SUGGEST_ROW_HEIGHT - 2),
			fontSize("small"),
			C("accent")
		)
	end

	UI.label(
		self.HintContent,
		callee .. "(" .. table.concat(params, ", ") .. ")",
		UDim2.fromOffset(current and 102 or 8, padding + 1),
		UDim2.new(1, -12, 1, -padding - 2),
		fontSize("caption"),
		C("subtext")
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

	UI.clear(self.PopupRows)

	self.rows = {}

	local first = self.suggestionScroll

	for offset = 0, count - 1 do
		local index = first + offset + 1
		local suggestion = self.suggestions[index]
		local isSelected = index == self.suggestionIndex

		local row = UI.button(
			self.PopupRows,
			"",
			UDim2.fromOffset(SUGGEST_PADDING, SUGGEST_PADDING + offset * SUGGEST_ROW_HEIGHT),
			UDim2.new(1, -SUGGEST_PADDING * 2, 0, SUGGEST_ROW_HEIGHT),
			function()
				self:acceptSuggestion(index)
			end,
			{
				color = isSelected and C("selection") or C("surface"),
				hoverColor = C("selectionHover"),
				radius = cornerRadius("xs"),
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
			fontSize("small"),
			isSelected and C("text") or kindColor(suggestion.kind)
		)

		UI.label(
			row,
			suggestion.detail or suggestion.kind or "",
			UDim2.new(1, -70, 0, 3),
			UDim2.fromOffset(64, SUGGEST_ROW_HEIGHT - 6),
			fontSize("caption"),
			C("muted")
		)

		table.insert(self.rows, row)
	end

	local total = #self.suggestions

	if total > count then
		local track = count * SUGGEST_ROW_HEIGHT
		local thumb = math.max(18, math.floor(track * (count / total)))

		UI.frame(
			self.PopupRows,
			UDim2.new(1, -3, 0, SUGGEST_PADDING + (track - thumb) * (first / (total - count))),
			UDim2.fromOffset(2, thumb),
			C("subtext"),
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

	if suggestion.jumpLine ~= nil then
		self:dismissSuggestions()
		self:GoToLine(suggestion.jumpLine)

		return
	end

	self.usage[suggestion.name] = (self.usage[suggestion.name] or 0) + 1

	self:dismissSuggestions()

	self.applyingSuggestion = true

	if suggestion.snippet ~= nil then
		local text = self.TextBox.Text
		local lineStart = lineBounds(text, range.start)
		local indent = string.match(string.sub(text, lineStart, range.start - 1), "^[ \t]*") or ""
		local body = (string.gsub(suggestion.snippet, "\n", "\n" .. indent))
		local marker = string.find(body, "$0", 1, true)
		local clean = marker and (string.sub(body, 1, marker - 1) .. string.sub(body, marker + 2)) or body

		self.TextBox:ReplaceRange(range.start, range.finish, clean)
		self.TextBox.CursorPosition = range.start + (marker and marker - 1 or #clean)
	else
		local insert = suggestion.quote and ('"' .. suggestion.name .. '"') or suggestion.name

		local callable = suggestion.kind == "Method" or suggestion.kind == "Function"

		if callable then
			insert ..= "("
		end

		self.TextBox:ReplaceRange(range.start, range.finish, insert)

		if callable then
			self.TextBox.CursorPosition = range.start + #insert
		end
	end

	self.applyingSuggestion = false

	self.TextBox:CaptureFocus()

	self:renderArgumentHint()
end

function CodeEditor:forceSuggestions()
	self.forceSuggest = true
	self:refreshSuggestions()
end

local function paintToggle(entry, active)
	if not entry or not UI.isAlive(entry.gui) then
		return
	end

	local color = active and C("selection") or C("panel")

	if entry.record then
		entry.record.color = color
	end

	entry.gui.BackgroundColor3 = color
end

function CodeEditor:buildFindButtons()
	local host = self.findButtonHost

	UI.clear(host)

	self.findButtons = {}
	self.replaceButtons = {}

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
			button, record =
				UI.iconButton(host, findIcons[id], UDim2.fromOffset(findX, 4), UDim2.fromOffset(22, 20), callback, {
					color = C("panel"),
					hoverColor = C("hover"),
					radius = cornerRadius("xs"),
					border = false,
					iconSize = 12,
				})
		else
			button, label, record =
				UI.button(host, findText[id], UDim2.fromOffset(findX, 4), UDim2.fromOffset(22, 20), callback, {
					color = C("panel"),
					hoverColor = C("hover"),
					textColor = C("muted"),
					textSize = fontSize("caption"),
					textY = 3,
					radius = cornerRadius("xs"),
					border = false,
					paddingX = 3,
				})
		end

		self.findButtons[id] = { gui = button, label = label, record = record, text = findText[id] }
	end

	local toggle, _, toggleRecord = UI.button(
		host,
		self.replaceMode and "v" or ">",
		UDim2.fromOffset(4, 4),
		UDim2.fromOffset(18, 20),
		function()
			self:setReplaceMode(not self.replaceMode)
		end,
		{
			color = C("panel"),
			hoverColor = C("hover"),
			textColor = C("muted"),
			textSize = fontSize("caption"),
			textY = 3,
			radius = cornerRadius("xs"),
			border = false,
			paddingX = 3,
		}
	)

	self.findButtons.expand = { gui = toggle, record = toggleRecord }

	local allX = FIND_WIDTH - 8 - 36
	local oneX = allX - 4 - 56

	local function replaceButton(text, x, width, callback)
		local button, _, record = UI.button(
			host,
			text,
			UDim2.fromOffset(x, FIND_HEIGHT),
			UDim2.fromOffset(width, FIND_HEIGHT - 8),
			callback,
			{
				color = C("surfaceAlt"),
				hoverColor = C("hover"),
				textColor = C("text"),
				textSize = fontSize("caption"),
				textY = 3,
				radius = cornerRadius("xs"),
				border = false,
				paddingX = 3,
			}
		)

		button.Visible = self.replaceMode

		table.insert(self.replaceButtons, { gui = button, record = record })
	end

	replaceButton("Replace", oneX, 56, function()
		self:replaceCurrent()
	end)
	replaceButton("All", allX, 36, function()
		self:replaceAll()
	end)

	paintToggle(self.findButtons.case, self.findCaseSensitive)
	paintToggle(self.findButtons.word, self.findWholeWord)
end

function CodeEditor:setReplaceMode(on)
	self.replaceMode = on == true
	self.replaceInput.Visible = self.replaceMode
	self.Find.Size = UDim2.fromOffset(FIND_WIDTH, self.replaceMode and FIND_HEIGHT_REPLACE or FIND_HEIGHT)

	self:buildFindButtons()
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

	local haystack = self.TextBox.Text
	local needle = query

	if not self.findCaseSensitive then
		haystack = string.lower(haystack)
		needle = string.lower(needle)
	end

	local cursor = 1
	local pattern = escapePattern(needle)

	while cursor <= #haystack and #self.findMatches < MAX_FIND_MATCHES do
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

function CodeEditor:selectFindMatch()
	local match = self.findMatches[self.findIndex]

	if not match then
		return
	end

	self:setSelection(match[1], match[2] + 1)
end

function CodeEditor:updateFindCount()
	local total = #self.findMatches

	if total == 0 then
		self.findCount.Text = self.findInput.Text == "" and "" or "No results"

		return
	end

	local index = math.max(self.findIndex, 1)
	local suffix = total >= MAX_FIND_MATCHES and "+" or ""

	self.findCount.Text = ("%d of %d%s"):format(index, total, suffix)
end

function CodeEditor:runFind(direction)
	self:scanFindMatches()

	local total = #self.findMatches

	if total == 0 then
		self:updateFindCount()

		return
	end

	local from = self:getSelection()
	local chosen

	if direction < 0 then
		for index = total, 1, -1 do
			if self.findMatches[index][1] < from then
				chosen = index

				break
			end
		end

		chosen = chosen or total
	else
		local threshold = direction == 0 and from or from + 1

		for index = 1, total do
			if self.findMatches[index][1] >= threshold then
				chosen = index

				break
			end
		end

		chosen = chosen or 1
	end

	self.findIndex = chosen

	self:updateFindCount()
	self:selectFindMatch()
end

function CodeEditor:replaceCurrent()
	if not self:hasDocument() then
		return
	end

	self:scanFindMatches()

	if #self.findMatches == 0 then
		self:updateFindCount()

		return
	end

	local first, finish, hasSelection = self:getSelection()
	local target

	for _, match in ipairs(self.findMatches) do
		if hasSelection and match[1] == first and match[2] + 1 == finish then
			target = match

			break
		end
	end

	if target == nil then
		self:runFind(0)

		return
	end

	local replacement = self.replaceInput.Text

	self.TextBox:ReplaceRange(target[1], target[2] + 1, replacement)
	self.TextBox.CursorPosition = target[1] + #replacement

	self:runFind(0)
end

function CodeEditor:replaceAll()
	if not self:hasDocument() then
		return
	end

	self:scanFindMatches()

	local total = #self.findMatches

	if total == 0 then
		return
	end

	local text = self.TextBox.Text
	local replacement = self.replaceInput.Text
	local pieces = {}
	local cursor = 1

	for _, match in ipairs(self.findMatches) do
		table.insert(pieces, string.sub(text, cursor, match[1] - 1))
		table.insert(pieces, replacement)

		cursor = match[2] + 1
	end

	table.insert(pieces, string.sub(text, cursor))

	self.TextBox:ReplaceRange(1, #text + 1, table.concat(pieces))

	self:scanFindMatches()
	self:updateFindCount()
	self:notify(("Replaced %d occurrence%s"):format(total, total == 1 and "" or "s"))
end

function CodeEditor:openFind(withReplace)
	if not self:hasDocument() then
		return
	end

	self:closeGoTo(true)

	if withReplace and not self.replaceMode then
		self:setReplaceMode(true)
	end

	local box = self.TextBox
	local text = box.Text
	local first, finish, hasSelection = self:getSelection()

	if hasSelection then
		local selected = string.sub(text, first, finish - 1)

		if selected ~= "" and not selected:find("\n") and #selected <= 200 then
			self.findInput.Text = selected
		end
	elseif #self.findInput.Text > 200 then
		self.findInput.Text = ""
	end

	self.findVisible = true
	self.Find.Visible = true
	self:placeFindWidget()
	self.findInput:CaptureFocus()
	selectAllText(self.findInput)
	self:runFind(0)
end

function CodeEditor:placeFindWidget()
	local camera = workspace.CurrentCamera
	local screen = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local y = math.max(8, TAB_STRIP_HEIGHT + 12)

	if self.findVisible and UI.isAlive(self.Find) then
		self.Find.Position = UDim2.fromOffset(math.max(8, screen.X - FIND_WIDTH - 16), y)
	end

	if self.goToVisible and UI.isAlive(self.GoTo) then
		self.GoTo.Position = UDim2.fromOffset(math.max(8, screen.X - GOTO_WIDTH - 16), y)
	end
end

function CodeEditor:closeFind(skipFocus)
	if not self.findVisible then
		return
	end

	self.findVisible = false
	self.Find.Visible = false
	self.findMatches = {}
	self.findIndex = 0

	if not skipFocus then
		self.TextBox:CaptureFocus()
	end
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

	self:runFind(0)
end

function CodeEditor:markFindToggle(id, on)
	paintToggle(self.findButtons[id], on)
end

function CodeEditor:selectedBlock()
	local text = self.TextBox.Text
	local first, finish, hasSelection = self:getSelection()
	local last = (hasSelection and finish > first) and (finish - 1) or first

	local blockStart = lineBounds(text, first)
	local _, blockEnd = lineBounds(text, last)

	return text, blockStart, blockEnd, first, finish, hasSelection
end

function CodeEditor:duplicateLines()
	if not self:hasDocument() then
		return
	end

	local text, blockStart, blockEnd, first, finish, hasSelection = self:selectedBlock()
	local block = string.sub(text, blockStart, blockEnd - 1)

	self.TextBox:ReplaceRange(blockEnd, blockEnd, "\n" .. block)

	local shift = #block + 1

	if hasSelection then
		self:setSelection(first + shift, finish + shift)
	else
		self.TextBox.CursorPosition = first + shift
	end
end

function CodeEditor:deleteLines()
	if not self:hasDocument() then
		return
	end

	local text, blockStart, blockEnd = self:selectedBlock()
	local removeStart, removeEnd = blockStart, blockEnd

	if blockEnd <= #text then
		removeEnd = blockEnd + 1
	elseif blockStart > 1 then
		removeStart = blockStart - 1
	end

	self.TextBox:ReplaceRange(removeStart, removeEnd, "")
	self.TextBox.CursorPosition = math.min(removeStart, #self.TextBox.Text + 1)
end

function CodeEditor:moveLines(direction)
	if not self:hasDocument() then
		return
	end

	local text, blockStart, blockEnd, first, finish, hasSelection = self:selectedBlock()
	local block = string.sub(text, blockStart, blockEnd - 1)
	local shift

	if direction < 0 then
		if blockStart <= 1 then
			return
		end

		local previousStart = lineBounds(text, blockStart - 1)
		local previous = string.sub(text, previousStart, blockStart - 2)

		self.TextBox:ReplaceRange(previousStart, blockEnd, block .. "\n" .. previous)

		shift = -(#previous + 1)
	else
		if blockEnd > #text then
			return
		end

		local _, nextEnd = lineBounds(text, blockEnd + 1)
		local following = string.sub(text, blockEnd + 1, nextEnd - 1)

		self.TextBox:ReplaceRange(blockStart, nextEnd, following .. "\n" .. block)

		shift = #following + 1
	end

	if hasSelection then
		self:setSelection(first + shift, finish + shift)
	else
		self.TextBox.CursorPosition = first + shift
	end
end

function CodeEditor:toggleComment()
	if not self:hasDocument() then
		return
	end

	local text, blockStart, blockEnd, first, finish, hasSelection = self:selectedBlock()
	local block = string.sub(text, blockStart, blockEnd - 1)
	local lines = string.split(block, "\n")

	local anyCode = false
	local allCommented = true

	for _, line in ipairs(lines) do
		if string.match(line, "%S") then
			anyCode = true

			if not string.match(line, "^%s*%-%-") then
				allCommented = false

				break
			end
		end
	end

	local uncomment = anyCode and allCommented
	local out = {}

	for index, line in ipairs(lines) do
		if not string.match(line, "%S") then
			out[index] = line
		elseif uncomment then
			out[index] = (string.gsub(line, "^(%s*)%-%- ?", "%1", 1))
		else
			local indent = string.match(line, "^%s*")

			out[index] = indent .. ""
		end
	end

	local replaced = table.concat(out, "\n")

	self.TextBox:ReplaceRange(blockStart, blockEnd, replaced)

	if hasSelection or #lines > 1 then
		self:setSelection(blockStart, blockStart + #replaced)
	else
		self.TextBox.CursorPosition = math.max(blockStart, first + (#replaced - #block))
	end
end

function CodeEditor:selectLine()
	if not self:hasDocument() then
		return
	end

	local text, blockStart, blockEnd, first, finish, hasSelection = self:selectedBlock()
	local target = math.min(blockEnd + 1, #text + 1)

	if hasSelection and first == blockStart and finish == target and blockEnd <= #text then
		local _, nextEnd = lineBounds(text, target)

		target = math.min(nextEnd + 1, #text + 1)
	end

	self:setSelection(blockStart, target)
end

function CodeEditor:insertLine(above)
	if not self:hasDocument() then
		return
	end

	local text, blockStart, blockEnd = self:selectedBlock()

	if above then
		local indent = string.match(string.sub(text, blockStart, blockEnd - 1), "^[ \t]*") or ""

		self.TextBox:ReplaceRange(blockStart, blockStart, indent .. "\n")
		self.TextBox.CursorPosition = blockStart + #indent
	else
		local lastStart = lineBounds(text, blockEnd)
		local indent = string.match(string.sub(text, lastStart, blockEnd - 1), "^[ \t]*") or ""

		self.TextBox:ReplaceRange(blockEnd, blockEnd, "\n" .. indent)
		self.TextBox.CursorPosition = blockEnd + 1 + #indent
	end
end

function CodeEditor:joinLines()
	if not self:hasDocument() then
		return
	end

	local text, blockStart, blockEnd = self:selectedBlock()
	local rangeEnd = blockEnd

	if string.find(string.sub(text, blockStart, blockEnd - 1), "\n", 1, true) == nil then
		if blockEnd > #text then
			return
		end

		local _, nextEnd = lineBounds(text, blockEnd + 1)

		rangeEnd = nextEnd
	end

	local lines = string.split(string.sub(text, blockStart, rangeEnd - 1), "\n")
	local joined = (string.gsub(lines[1], "%s+$", ""))
	local joinPoint = #joined

	for index = 2, #lines do
		local trimmed = string.match(lines[index], "^%s*(.-)%s*$")

		if trimmed ~= "" then
			joined ..= (joined == "" and "" or " ") .. trimmed
		end
	end

	self.TextBox:ReplaceRange(blockStart, rangeEnd, joined)
	self.TextBox.CursorPosition = blockStart + joinPoint
end

function CodeEditor:shiftIndent(direction)
	if not self:hasDocument() then
		return
	end

	local text, blockStart, blockEnd = self:selectedBlock()
	local lines = string.split(string.sub(text, blockStart, blockEnd - 1), "\n")
	local out = {}

	for index, line in ipairs(lines) do
		if direction > 0 then
			out[index] = string.match(line, "%S") and ("\t" .. line) or line
		elseif string.sub(line, 1, 1) == "\t" then
			out[index] = string.sub(line, 2)
		else
			out[index] = (string.gsub(line, "^ ? ? ? ?", ""))
		end
	end

	local replaced = table.concat(out, "\n")

	self.TextBox:ReplaceRange(blockStart, blockEnd, replaced)
	self:setSelection(blockStart, blockStart + #replaced)
end

function CodeEditor:jumpToMatchingBracket()
	if not self:hasDocument() then
		return
	end

	local box = self.TextBox
	local cursor = math.max(box.CursorPosition or 1, 1)
	local map = bracketPairs(box.Text)

	local index = map[cursor] ~= nil and cursor or (map[cursor - 1] ~= nil and cursor - 1 or nil)

	if index == nil then
		self:notify("No matching bracket")

		return
	end

	local partner = map[index]

	box.CursorPosition = partner > index and (partner + 1) or partner
end

function CodeEditor:autoEnd(text, cursor)
	local box = self.TextBox
	local lineStart = lineBounds(text, cursor - 1)
	local prevLine = string.sub(text, lineStart, cursor - 2)
	local _, lineEnd = lineBounds(text, cursor)

	if string.match(string.sub(text, cursor, lineEnd - 1), "%S") ~= nil then
		return
	end

	local trimmed = string.match(prevLine, "^%s*(.-)%s*$")
	local closer = "end"

	if string.match(trimmed, "%f[%w_]then$") ~= nil then
		if string.match(trimmed, "^elseif%f[^%w_]") ~= nil then
			return
		end
	elseif string.match(trimmed, "%f[%w_]do$") ~= nil then
	elseif string.match(trimmed, "%f[%w_]function%f[^%w_].*%)$") ~= nil then
		local _, openCount = string.gsub(trimmed, "%(", "")
		local _, closeCount = string.gsub(trimmed, "%)", "")

		if openCount > closeCount then
			closer = "end)"
		end
	else
		return
	end

	if blockBalance(text) <= 0 then
		return
	end

	local indent = string.match(prevLine, "^[ \t]*") or ""

	box:ReplaceRange(cursor, cursor, "\n" .. indent .. closer)
	box.CursorPosition = cursor
	self.lastText = box.Text
end

function CodeEditor:autoEdit()
	if self.applyingSuggestion or not (AUTO_CLOSE_PAIRS or AUTO_END_BLOCKS) then
		return
	end

	local box = self.TextBox
	local old = self.lastText or ""
	local text = box.Text
	local cursor = math.max(box.CursorPosition or 1, 1)
	local _, _, hasSelection = self:getSelection()

	if hasSelection then
		self.pendingCloser = nil

		return
	end

	if #text == #old + 1 and cursor >= 2 then
		if
			string.sub(text, 1, cursor - 2) ~= string.sub(old, 1, cursor - 2)
			or string.sub(text, cursor) ~= string.sub(old, cursor - 1)
		then
			self.pendingCloser = nil

			return
		end

		local typed = string.sub(text, cursor - 1, cursor - 1)
		local before = string.sub(text, cursor - 2, cursor - 2)
		local after = string.sub(text, cursor, cursor)

		if AUTO_CLOSE_PAIRS and self.pendingCloser == cursor - 1 and after == typed then
			if CLOSE_BRACKETS[typed] ~= nil or QUOTES[typed] then
				self.pendingCloser = nil
				box:ReplaceRange(cursor, cursor + 1, "")
				self.lastText = box.Text

				return
			end
		end

		self.pendingCloser = nil

		if typed == "\n" then
			if AUTO_END_BLOCKS then
				self:autoEnd(text, cursor)
			end

			return
		end

		if not AUTO_CLOSE_PAIRS or not (OPEN_BRACKETS[typed] ~= nil or QUOTES[typed]) then
			return
		end

		if insideCommentOrString(old, cursor - 1) then
			return
		end

		if QUOTES[typed] and (string.match(before, "[%w_]") ~= nil or string.match(after, "[%w_]") ~= nil) then
			return
		end

		if after ~= "" and string.match(after, "[%s%)%]%},;]") == nil then
			return
		end

		box:ReplaceRange(cursor, cursor, OPEN_BRACKETS[typed] or typed)
		box.CursorPosition = cursor
		self.pendingCloser = cursor
		self.lastText = box.Text
	elseif #text == #old - 1 then
		self.pendingCloser = nil

		if not AUTO_CLOSE_PAIRS then
			return
		end

		if
			string.sub(text, 1, cursor - 1) ~= string.sub(old, 1, cursor - 1)
			or string.sub(text, cursor) ~= string.sub(old, cursor + 1)
		then
			return
		end

		local removed = string.sub(old, cursor, cursor)
		local after = string.sub(text, cursor, cursor)

		if after ~= "" and (OPEN_BRACKETS[removed] == after or (QUOTES[removed] and removed == after)) then
			box:ReplaceRange(cursor, cursor + 1, "")
			self.lastText = box.Text
		end
	else
		self.pendingCloser = nil
	end
end

function CodeEditor:selectEnclosing()
	if not self:hasDocument() then
		return
	end

	local first, finish = self:getSelection()
	local map = bracketPairs(self.TextBox.Text)
	local bestStart, bestFinish, bestSize

	for open, close in pairs(map) do
		if open < close then
			for _, range in ipairs({ { open + 1, close }, { open, close + 1 } }) do
				local rangeStart, rangeFinish = range[1], range[2]

				if
					rangeFinish > rangeStart
					and rangeStart <= first
					and rangeFinish >= finish
					and (rangeStart < first or rangeFinish > finish)
				then
					local size = rangeFinish - rangeStart

					if bestSize == nil or size < bestSize then
						bestStart, bestFinish, bestSize = rangeStart, rangeFinish, size
					end
				end
			end
		end
	end

	if bestStart == nil then
		self:notify("No enclosing brackets")

		return
	end

	self:setSelection(bestStart, bestFinish)
end

function CodeEditor:sortLines(descending)
	if not self:hasDocument() then
		return
	end

	local text, blockStart, blockEnd = self:selectedBlock()
	local lines = string.split(string.sub(text, blockStart, blockEnd - 1), "\n")

	if #lines < 2 then
		self:notify("Select multiple lines to sort")

		return
	end

	table.sort(lines, function(a, b)
		if descending then
			return a > b
		end

		return a < b
	end)

	local replaced = table.concat(lines, "\n")

	self.TextBox:ReplaceRange(blockStart, blockEnd, replaced)
	self:setSelection(blockStart, blockStart + #replaced)
end

function CodeEditor:toggleCase()
	if not self:hasDocument() then
		return
	end

	local text = self.TextBox.Text
	local first, finish, hasSelection = self:getSelection()

	if not hasSelection then
		first, finish = identifierAt(text, first)

		if first == nil then
			return
		end
	end

	local selected = string.sub(text, first, finish - 1)
	local converted = selected == string.upper(selected) and string.lower(selected) or string.upper(selected)

	if converted == selected then
		return
	end

	self.TextBox:ReplaceRange(first, finish, converted)
	self:setSelection(first, finish)
end

function CodeEditor:findWordUnderCursor()
	if not self:hasDocument() then
		return
	end

	local first, _, hasSelection = self:getSelection()

	if not hasSelection then
		local start, finish = identifierAt(self.TextBox.Text, first)

		if start ~= nil then
			self:setSelection(start, finish)
		end
	end

	self:openFind(false)
end

function CodeEditor:showSymbols()
	if not self:hasDocument() then
		return
	end

	local ranked = {}
	local lineNumber = 0

	for line in string.gmatch(self.TextBox.Text .. "\n", "([^\n]*)\n") do
		lineNumber += 1

		local name = string.match(line, "^%s*local%s+function%s+([%w_%.:]+)")
			or string.match(line, "^%s*function%s+([%w_%.:]+)")
			or string.match(line, "^%s*local%s+([%w_]+)%s*=%s*function")
			or string.match(line, "^%s*([%w_%.:]+)%s*=%s*function")

		if name ~= nil then
			table.insert(ranked, {
				name = name,
				kind = "Function",
				detail = "Ln " .. lineNumber,
				score = lineNumber,
				jumpLine = lineNumber,
				quote = false,
			})
		end
	end

	if #ranked == 0 then
		self:notify("No functions found")

		return
	end

	self:showRanked(ranked, "", { start = 1, finish = 1 })
end

function CodeEditor:hideDiagnosticPopup()
	self.diagnosticShown = nil
	self.diagnosticPinned = false

	if UI.isAlive(self.DiagnosticPopup) then
		self.DiagnosticPopup.Visible = false
	end
end

function CodeEditor:diagnosticAnchor(diagnostic)
	local box = self.TextBox
	local caret = box.CaretScreenPosition

	if caret == nil then
		return self.lastMouse
	end

	local caretLine, caretColumn = lineColumn(box.Text, math.max(box.CursorPosition or 1, 1))

	return Vector2.new(
		caret.X + (diagnostic.Column - caretColumn) * CODE_CHAR_WIDTH,
		caret.Y + (diagnostic.Line - caretLine) * SUGGEST_LINE_HEIGHT
	)
end

function CodeEditor:placeDiagnosticPopup()
	local diagnostic = self.diagnosticShown

	if diagnostic == nil or diagnostic.Column == nil or not UI.isAlive(self.DiagnosticPopup) then
		return
	end

	local box = self.TextBox
	local anchor = self:diagnosticAnchor(diagnostic)
	local top = box.AbsolutePosition.Y
	local bottom = top + box.AbsoluteSize.Y

	if anchor.Y < top - SUGGEST_LINE_HEIGHT or anchor.Y > bottom then
		self.DiagnosticPopup.Visible = false

		return
	end

	local camera = workspace.CurrentCamera
	local screen = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local height = self.DiagnosticPopup.Size.Y.Offset

	local x = math.clamp(anchor.X, 8, math.max(8, screen.X - DIAGNOSTIC_WIDTH - 8))
	local y = anchor.Y + SUGGEST_LINE_HEIGHT + 2

	if y + height > screen.Y - 8 then
		y = math.max(8, anchor.Y - height - 4)
	end

	self.DiagnosticPopup.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
	self.DiagnosticPopup.Visible = true
end

function CodeEditor:showDiagnosticPopup(diagnostic)
	if not UI.isAlive(self.DiagnosticPopup) then
		return
	end

	if self.diagnosticShown == diagnostic and self.DiagnosticPopup.Visible then
		return
	end

	local line = math.max(1, math.floor(tonumber(diagnostic.Line) or 1))
	local message = tostring(diagnostic.Message or "Syntax error")

	self.DiagnosticTitle.Text = "Syntax error · line " .. line
	self.DiagnosticText.Text = message

	local measured =
		TextService:GetTextSize(message, fontSize("small"), TAB_FONT, Vector2.new(DIAGNOSTIC_WIDTH - 20, 2000))

	self.DiagnosticPopup.Size = UDim2.fromOffset(DIAGNOSTIC_WIDTH, math.max(54, math.ceil(measured.Y) + 34))
	self.diagnosticShown = diagnostic
	self:placeDiagnosticPopup()
end

function CodeEditor:refreshDiagnostics()
	if not UI.isAlive(self.TextBox) then
		return
	end

	local source = self.TextBox.Text

	if not UI.shared().scriptDiagnostics or self.activeDocument == nil or source == "" then
		self.TextBox:ClearDiagnostics()
		self.currentDiagnostic = nil
		self:hideDiagnosticPopup()

		return
	end

	self.diagnosticSerial += 1

	local serial = self.diagnosticSerial

	task.delay(DIAGNOSTIC_DELAY, function()
		if self.destroyed or serial ~= self.diagnosticSerial or not UI.isAlive(self.TextBox) then
			return
		end

		local ok, result = pcall(function()
			return LuauService:Diagnose(source)
		end)

		if not ok or type(result) ~= "table" or serial ~= self.diagnosticSerial then
			return
		end

		if result.Ok then
			self.TextBox:ClearDiagnostics()
			self.currentDiagnostic = nil
			self:hideDiagnosticPopup()

			return
		end

		local line = math.max(1, math.floor(tonumber(result.Line) or 1))
		local message = tostring(result.Message or "Syntax error")
		local column, endColumn = diagnosticSpan(source, line, message)

		self.currentDiagnostic = { Line = line, Column = column, EndColumn = endColumn, Message = message }

		self.TextBox:SetDiagnostics({
			{
				Line = line,
				Column = column,
				EndColumn = endColumn,
				Message = message,
			},
		})

		self:hideDiagnosticPopup()

		if self:suggestionsBlocked() then
			self:hideSuggestionList()
		end
	end)
end

function CodeEditor:handleShortcut(keyCode)
	local K = Enum.KeyCode

	if keyCode == K.F then
		self:openFind(false)
	elseif keyCode == K.H then
		self:openFind(true)
	elseif keyCode == K.G then
		self:openGoTo()
	elseif keyCode == K.D then
		self:duplicateLines()
	elseif keyCode == K.K and shiftHeld() then
		self:deleteLines()
	elseif keyCode == K.Slash then
		self:toggleComment()
	elseif keyCode == K.S and altHeld() then
		self:sortLines(shiftHeld())
	elseif keyCode == K.S then
		self:saveActive()
	elseif keyCode == K.W then
		self:closeDocument(self.activeDocument)
	elseif keyCode == K.T and shiftHeld() then
		self:reopenClosed()
	elseif keyCode == K.Tab then
		self:cycleDocument(shiftHeld() and -1 or 1)
	elseif keyCode == K.Space and shiftHeld() then
		self:selectEnclosing()
	elseif keyCode == K.Space then
		self:forceSuggestions()
	elseif keyCode == K.U and shiftHeld() then
		self:toggleCase()
	elseif keyCode == K.E then
		self:findWordUnderCursor()
	elseif keyCode == K.O and shiftHeld() then
		self:showSymbols()
	elseif keyCode == K.L then
		self:selectLine()
	elseif keyCode == K.J then
		self:joinLines()
	elseif keyCode == K.Return or keyCode == K.KeypadEnter then
		self:dismissSuggestions()
		self:insertLine(shiftHeld())
	elseif keyCode == K.RightBracket then
		self:shiftIndent(1)
	elseif keyCode == K.LeftBracket then
		self:shiftIndent(-1)
	elseif keyCode == K.BackSlash and shiftHeld() then
		self:jumpToMatchingBracket()
	else
		return false
	end

	return true
end

function CodeEditor:wireEditor()
	self:connect(self.TextBox.TextChanged, function()
		if self.suppressTextSync then
			self.lastText = self.TextBox.Text

			return
		end

		self:autoEdit()

		if self.activeDocument ~= nil then
			self.activeDocument.source = self.TextBox.Text

			self:scheduleCommit(self.activeDocument)
		end

		self:refreshDiagnostics()

		if self.applyingSuggestion then
			self:renderArgumentHint()
		else
			self:refreshSuggestions()
		end

		if self.findVisible then
			self:scanFindMatches()
			self:updateFindCount()
		end

		if self.goToVisible then
			self:updateGoToHint()
		end

		self.lastText = self.TextBox.Text
	end)

	self:connect(self.findInput.TextChanged, function()
		self:runFind(0)
	end)

	self:connect(self.findInput.KeyDown, function(input)
		local keyCode = input and input.KeyCode

		if keyCode == Enum.KeyCode.Escape then
			self:closeFind()
			self.findInput.KeyHandled = true
		elseif keyCode == Enum.KeyCode.Return or keyCode == Enum.KeyCode.KeypadEnter then
			self:runFind(shiftHeld() and -1 or 1)
			self.findInput.KeyHandled = true
		elseif keyCode == Enum.KeyCode.H and modifierHeld() then
			self:setReplaceMode(true)
			self.replaceInput:CaptureFocus()
			self.findInput.KeyHandled = true
		end
	end)

	self:connect(self.replaceInput.KeyDown, function(input)
		local keyCode = input and input.KeyCode

		if keyCode == Enum.KeyCode.Escape then
			self:closeFind()
			self.replaceInput.KeyHandled = true
		elseif keyCode == Enum.KeyCode.Return or keyCode == Enum.KeyCode.KeypadEnter then
			if modifierHeld() then
				self:replaceAll()
			else
				self:replaceCurrent()
			end

			self.replaceInput.KeyHandled = true
		end
	end)

	self:connect(self.goToInput.TextChanged, function()
		self:updateGoToHint()
	end)

	self:connect(self.goToInput.KeyDown, function(input)
		local keyCode = input and input.KeyCode

		if keyCode == Enum.KeyCode.Escape then
			self:closeGoTo()
			self.goToInput.KeyHandled = true
		elseif keyCode == Enum.KeyCode.Return or keyCode == Enum.KeyCode.KeypadEnter then
			local requested = tonumber(self.goToInput.Text)

			self:closeGoTo(true)

			if requested ~= nil then
				self:GoToLine(requested)
			else
				self.TextBox:CaptureFocus()
			end

			self.goToInput.KeyHandled = true
		end
	end)

	self:connect(self.TextBox.FocusLost, function()
		task.defer(function()
			if not self.destroyed and UI.isAlive(self.TextBox) and not self.TextBox:IsFocused() then
				self:dismissSuggestions()
			end
		end)
	end)

	self:connect(self.TextBox.MouseMoved, function(x, y)
		self.lastMouse = Vector2.new(x, y)

		local absolute = self.TextBox.AbsolutePosition
		local hit = self.TextBox:DiagnosticAtPoint(x - absolute.X, y - absolute.Y)
		local current = self.currentDiagnostic

		if hit ~= nil and current ~= nil and UI.shared().scriptDiagnostics then
			self:showDiagnosticPopup(current)
		elseif not self.diagnosticPinned then
			self:hideDiagnosticPopup()
		end
	end)

	self:connect(self.TextBox.MouseLeave, function()
		if not self.diagnosticPinned then
			self:hideDiagnosticPopup()
		end
	end)

	self:connect(self.TextBox.KeyDown, function(input)
		local keyCode = input and input.KeyCode

		if keyCode == nil then
			return
		end

		if modifierHeld() and self:handleShortcut(keyCode) then
			self.TextBox.KeyHandled = true

			return
		end

		if keyCode == Enum.KeyCode.F3 then
			if self.findVisible then
				self:runFind(shiftHeld() and -1 or 1)
			else
				self:openFind(false)
			end

			self.TextBox.KeyHandled = true

			return
		end

		if keyCode == Enum.KeyCode.F8 then
			self:goToDiagnostic()
			self.TextBox.KeyHandled = true

			return
		end

		if altHeld() and (keyCode == Enum.KeyCode.Up or keyCode == Enum.KeyCode.Down) then
			self:dismissSuggestions()
			self:moveLines(keyCode == Enum.KeyCode.Up and -1 or 1)
			self.TextBox.KeyHandled = true

			return
		end

		if keyCode == Enum.KeyCode.Escape then
			if self.goToVisible then
				self:closeGoTo()
				self.TextBox.KeyHandled = true

				return
			end

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
