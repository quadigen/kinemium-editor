local RunService = game:GetService("RunService")

-- ===== Settings =====
local MAX = 12 -- footprints alive at once (shader is generated for this count)
local STRIDE = 1.8 -- studs travelled between prints
local SIDE_OFFSET = 0.45 -- left/right foot offset from the path
local HALF_LENGTH = 0.9 -- half the print length, studs
local HALF_WIDTH = 0.4 -- half the print width, studs
local REFILL_TIME = 25 -- seconds for a print to fill back in
local FEET_OFFSET = 3 -- studs from the tracked part's center down to the ground

local tracked = workspace.Player -- the part whose position follows the character
local snowSurface = workspace.SnowGround -- any part (or Terrain) using this variant

-- ===== Shader (generated for MAX prints) =====
local template = [==[
material {
    name : "FootprintSnow",
    shadingModel : lit,
    instanced : true,
    requires : [ tangents ],
    parameters : [
        { type : float4[64], name : instanceColors },
        { type : float4, name : baseColor },
        { type : float, name : roughness },
        { type : float, name : metallic },
        { type : float, name : stepDepth },
        { type : float, name : grain },
        { type : float, name : sparkle },
        { type : float, name : tintStrength },
        { type : float3, name : compactColor },
@PARAMS@
    ]
}
vertex {
    void materialVertex(inout MaterialVertexInputs material) {
        // MATERIAL_VARIANT_VERTEX_HOOK
    }
}
fragment {
    float hash21(vec2 p) {
        p = fract(p * vec2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    float hash31(vec3 p) {
        return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
    }

    float vnoise(vec2 p) {
        vec2 i = floor(p);
        vec2 f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
                   mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
    }

    // a = (x, y, z, strength), b = (dirX, dirZ, halfLength, halfWidth)
    // Returns (pit amount, rim amount), both already scaled by strength.
    vec2 foot(vec3 pos, vec4 a, vec4 b) {
        if (a.w <= 0.001 || abs(pos.y - a.y) > 1.0) { return vec2(0.0); }
        vec2 r = pos.xz - a.xz;
        float L = b.z;
        float W = b.w;
        if (dot(r, r) > 4.0 * L * L) { return vec2(0.0); }
        vec2 d = b.xy;
        vec2 loc = vec2(dot(r, d), dot(r, vec2(-d.y, d.x)));
        // Forefoot and heel ellipses; the union reads as a boot sole.
        float e1 = length((loc - vec2(0.18 * L, 0.0)) / vec2(0.62 * L, W));
        float e2 = length((loc - vec2(-0.62 * L, 0.0)) / vec2(0.34 * L, 0.75 * W));
        float s = min(e1, e2);
        float pit = 1.0 - smoothstep(0.55, 1.0, s);
        float k = (s - 1.2) / 0.22;
        float rim = exp(-k * k);
        return vec2(pit, rim) * a.w;
    }

    // Snow height offset in studs (negative = pressed down).
    float heightAt(vec3 pos) {
        float pit = 0.0;
        float rim = 0.0;
        vec2 v;
@ACCUM@
        return (-pit + 0.22 * rim) * materialParams.stepDepth;
    }

    void material(inout MaterialInputs material) {
        prepareMaterial(material);

        vec3 pos = getUserWorldPosition();
        vec3 n = normalize(getWorldGeometricNormalVector());
        vec3 toEye = getWorldCameraPosition() - getWorldPosition();
        float dist = length(toEye);
        vec3 v = toEye / max(dist, 1e-4);

        // Footprint relief: normal from the height gradient.
        float e = 0.04;
        float h0 = heightAt(pos);
        float gx = (heightAt(pos + vec3(e, 0.0, 0.0)) - heightAt(pos - vec3(e, 0.0, 0.0))) / (2.0 * e);
        float gz = (heightAt(pos + vec3(0.0, 0.0, e)) - heightAt(pos - vec3(0.0, 0.0, e))) / (2.0 * e);
        float pitAmt = clamp(-h0 / max(materialParams.stepDepth, 1e-3), 0.0, 1.0);

        // Fine snow grain, faded with distance to avoid shimmering.
        float fade = 1.0 - smoothstep(20.0, 60.0, dist);
        vec2 gp = pos.xz * 22.0;
        vec2 gg = vec2(vnoise(gp + vec2(0.5, 0.0)) - vnoise(gp - vec2(0.5, 0.0)),
                       vnoise(gp + vec2(0.0, 0.5)) - vnoise(gp - vec2(0.0, 0.5)));
        gg *= materialParams.grain * fade * 0.25;

        vec3 nw = normalize(n + vec3(-gx - gg.x, 0.0, -gz - gg.y));
        material.normal = normalize(transpose(getWorldTangentFrame()) * nw);

        // Color: cool white snow, compacted and bluer inside prints.
        vec3 col = materialParams.baseColor.rgb * (0.96 + 0.06 * vnoise(pos.xz * 0.7));
        vec4 inst = materialParams.instanceColors[getInstanceIndex()];
        col *= mix(vec3(1.0), inst.rgb, materialParams.tintStrength);
        col = mix(col, materialParams.compactColor, pitAmt * 0.55);

        // Sparkle glints, suppressed inside compacted prints.
        vec3 cell = floor(pos * 45.0);
        float hh = hash31(cell);
        float flicker = fract(hh * 91.0 + dot(v, vec3(3.1, 5.7, 2.3)) * 4.0);
        float glint = step(0.985, hh) * smoothstep(0.9, 1.0, flicker) * (1.0 - pitAmt) * fade;

        material.baseColor = vec4(col, 1.0);
        material.roughness = clamp(materialParams.roughness - 0.25 * pitAmt - 0.5 * glint, 0.04, 1.0);
        material.metallic = materialParams.metallic;
        material.ambientOcclusion = 1.0 - 0.55 * pitAmt;
        material.emissive = vec4(vec3(glint * materialParams.sparkle), 0.0);

        // MATERIAL_VARIANT_FRAGMENT_HOOK
    }
}
]==]

local params, accum = {}, {}
for i = 0, MAX - 1 do
	table.insert(params, string.format("        { type : float4, name : printA%d },", i))
	table.insert(params, string.format("        { type : float4, name : printB%d }%s", i, i < MAX - 1 and "," or ""))
	table.insert(
		accum,
		string.format(
			"        v = foot(pos, materialParams.printA%d, materialParams.printB%d); pit = max(pit, v.x); rim = max(rim, v.y);",
			i,
			i
		)
	)
end
local source = template:gsub("@PARAMS@", table.concat(params, "\n")):gsub("@ACCUM@", table.concat(accum, "\n"))

-- ===== Material =====
local snow = Instance.new("MaterialVariant", game:GetService("ReplicatedStorage"))
snow.Name = "FootprintSnow"
snow.Source = source

snow.Color = Color3.fromRGB(240, 246, 255)
snow.Roughness = 0.85
snow.Metalness = 0

snow:SetUniform("stepDepth", 0.3) -- print depth in studs
snow:SetUniform("grain", 1)
snow:SetUniform("sparkle", 0.5)
snow:SetUniform("tintStrength", 0)
snow:SetUniform("compactColor", { 0.74, 0.83, 0.95 })

local function writePrint(i, e)
	snow:SetUniform("printA" .. i, { e.x, e.y, e.z, e.s })
	snow:SetUniform("printB" .. i, { e.dx, e.dz, HALF_LENGTH, HALF_WIDTH })
end

local prints = {}
for i = 1, MAX do
	prints[i] = { x = 0, y = 0, z = 0, s = 0, dx = 0, dz = 1 }
	writePrint(i - 1, prints[i])
end

snowSurface.MaterialVariant = "FootprintSnow"
-- game:GetService("Terrain").MaterialVariant = "FootprintSnow"

-- ===== Footstep logic =====
local nextSlot, side = 1, 1
local last = nil
local timer, wasActive = 0, false

RunService.Heartbeat:Connect(function(dt)
	local p = tracked.Position
	local feet = Vector3.new(p.X, p.Y - FEET_OFFSET, p.Z)
	last = last or feet

	local delta = Vector3.new(feet.X - last.X, 0, feet.Z - last.Z)
	if delta.Magnitude >= STRIDE then
		local dir = delta.Unit
		local perp = Vector3.new(-dir.Z, 0, dir.X)
		local spot = feet + perp * (side * SIDE_OFFSET)
		prints[nextSlot] = { x = spot.X, y = feet.Y, z = spot.Z, s = 1, dx = dir.X, dz = dir.Z }
		nextSlot = nextSlot % MAX + 1
		side = -side
		last = feet
	end

	local active = false
	for _, e in ipairs(prints) do
		if e.s > 0 then
			e.s = math.max(0, e.s - dt / REFILL_TIME)
			active = true
		end
	end

	-- Push uniforms at ~15 Hz, plus one final push after the last print fades out.
	timer += dt
	if (active or wasActive) and timer >= 1 / 15 then
		timer = 0
		for i = 1, MAX do
			writePrint(i - 1, prints[i])
		end
	end
	wasActive = active
end)

print(snow.Compiled, snow.LastError) -- compiles on first draw, so check again after a frame

local part = Instance.new("Part")
part.Size = Vector3.new(4, 1, 4)
part.Position = Vector3.new(0, 0.5, 0)
part.MaterialVariant = "FootprintSnow"
part.Parent = workspace
