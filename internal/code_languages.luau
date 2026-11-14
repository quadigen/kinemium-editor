local Languages = {}

local luau = { name = "Luau", lineComment = "--", luau = true }
local plain = { name = "Plain text" }

local shaderKeywords = [[
	break case const continue default discard do else false for if in inout out return
	struct switch true uniform void while flat smooth centroid invariant precision highp mediump lowp
]]

local shaderTypes = [[
	bool bvec2 bvec3 bvec4 int uint ivec2 ivec3 ivec4 uvec2 uvec3 uvec4 float
	vec2 vec3 vec4 mat2 mat3 mat4 mat2x2 mat3x3 mat4x4 sampler2D samplerCube sampler3D
]]

local sksl = {
	name = "SkSL", lineComment = "//", directives = true,
	keywords = shaderKeywords,
	types = shaderTypes .. [[
		half half2 half3 half4 half2x2 half3x3 half4x4 float2 float3 float4 float2x2 float3x3 float4x4
		int2 int3 int4 bool2 bool3 bool4 shader colorFilter blender
	]],
}

local glsl = {
	name = "GLSL", lineComment = "//", directives = true,
	keywords = shaderKeywords .. " attribute varying layout buffer shared coherent readonly writeonly",
	types = shaderTypes,
}

local filament = {
	name = "Filament Material", lineComment = "//", directives = true,
	keywords = glsl.keywords .. [[
		material vertex fragment shadingModel blending parameters requires culling
		depthWrite depthCulling colorWrite name domain featureLevel interpolation variables
	]],
	types = shaderTypes .. " MaterialInputs MaterialVertexInputs sampler2d samplerCubemap float2 float3 float4",
}

local c = {
	name = "C / C++", lineComment = "//", directives = true,
	keywords = [[
		alignas auto break case class const constexpr continue default delete do else enum extern
		false for if inline namespace new nullptr private protected public return sizeof static
		struct switch template true typedef union using volatile while
	]],
	types = "bool char double float int long short signed unsigned void size_t uint32_t int32_t",
}

local csharp = {
	name = "C#", lineComment = "//", directives = true,
	keywords = [[
		abstract as async await base break case catch checked class const continue default delegate do
		else enum event false finally fixed for foreach if in interface internal is lock namespace new
		null out override private protected public readonly ref return sealed static struct switch
		this throw true try typeof unchecked unsafe using var virtual while yield
	]],
	types = "bool byte char decimal double float int long object sbyte short string uint ulong ushort void",
}

local json = { name = "JSON", keywords = "true false null" }

local extensions = {
	lua = luau, luau = luau,
	sksl = sksl, mat = filament,
	glsl = glsl, vert = glsl, frag = glsl, geom = glsl, comp = glsl,
	c = c, h = c, cpp = c, hpp = c, cc = c, cxx = c, cs = csharp,
	json = json,
}

local classes = {
	Script = luau, LocalScript = luau, ModuleScript = luau,
	UIShader = sksl, PostProcess = filament, RuntimeShader = filament, MaterialVariant = filament,
}

function Languages.forInstance(instance)
	return classes[instance.ClassName]
end

function Languages.forFile(path)
	local extension = string.match(path, "%.([^./\\]+)$")
	return extension and extensions[string.lower(extension)] or plain
end

function Languages.apply(highlighter, language)
	highlighter:ClearRules()
	highlighter.Language = language.luau and "Luau" or "None"
	if language.luau or language == plain then return end

	local comment = Color3.fromRGB(108, 129, 146)
	local literal = Color3.fromRGB(96, 187, 126)
	if language.lineComment == "//" then
		highlighter:AddRule("Range", comment, "/*", "*/")
		highlighter:AddRule("Prefix", comment, "//")
		highlighter:AddRegex(literal, [['([^'\\]|\\.)*']])
	end
	highlighter:AddRegex(literal, [["([^"\\]|\\.)*"]])
	if language.directives then highlighter:AddRule("Prefix", Color3.fromRGB(175, 129, 219), "#") end
	highlighter:AddRegex(Color3.fromRGB(222, 146, 81), [[0[xX][0-9a-fA-F]+|\d+(\.\d*)?([eE][+-]?\d+)?]])
	for word in string.gmatch(language.keywords or "", "%S+") do
		highlighter:AddKeyword(Color3.fromRGB(222, 149, 80), word)
	end
	for word in string.gmatch(language.types or "", "%S+") do
		highlighter:AddKeyword(Color3.fromRGB(107, 181, 218), word)
	end
end

return Languages
