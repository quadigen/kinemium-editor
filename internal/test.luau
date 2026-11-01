local part = Instance.new("Part", workspace)
part.Name = "MyPart"

local brick = Instance.new("MaterialVariant", game:GetService("ReplicatedStorage"))
brick.Name = "ProceduralBrick"

brick.Source = [==[
material {
    name : "ProceduralBrickPOM",
    shadingModel : lit,
    instanced : true,
    requires : [ tangents ],
    parameters : [
        { type : float4[64], name : instanceColors },
        { type : float4, name : baseColor },
        { type : float, name : roughness },
        { type : float, name : metallic },
        { type : float2, name : brickSize },
        { type : float, name : mortarWidth },
        { type : float, name : bevel },
        { type : float3, name : brickColorA },
        { type : float3, name : brickColorB },
        { type : float3, name : mortarColor },
        { type : float, name : tintStrength },
        { type : float, name : fadeDistance },
        { type : float, name : parallaxDepth },
        { type : float, name : parallaxSteps },
        { type : float, name : normalStrength },
        { type : float, name : aoStrength }
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

    float vnoise(vec2 p) {
        vec2 i = floor(p);
        vec2 f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
                   mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
    }

    // Running bond: every other row is shifted by half a brick.
    vec2 brickCoord(vec2 p) {
        vec2 size = materialParams.brickSize;
        float row = floor(p.y / size.y);
        return vec2(p.x + mod(row, 2.0) * 0.5 * size.x, p.y);
    }

    // 0 in the mortar, 1 on the brick face, with a soft bevel between.
    float brickMask(vec2 q) {
        vec2 size = materialParams.brickSize;
        vec2 local = q - floor(q / size) * size;
        vec2 d2 = min(local, size - local);
        float d = min(d2.x, d2.y);
        float m = materialParams.mortarWidth * 0.5;
        return smoothstep(m, m + max(materialParams.bevel, 0.002), d);
    }

    // 0 = bottom of the mortar, 1 = top of the brick.
    float brickHeight(vec2 p) {
        vec2 q = brickCoord(p);
        float t = brickMask(q);
        float n = vnoise(q * 14.0);
        return mix(0.05 * n, 0.82 + 0.18 * n, t);
    }

    // Ray-march the height field. Offsets are in studs, in the projection plane.
    vec2 pom(vec2 p, vec2 viewXY, float viewN, float depth) {
        float steps = clamp(materialParams.parallaxSteps, 8.0, 64.0);
        float layer = 1.0 / steps;
        vec2 delta = viewXY / max(viewN, 0.2) * depth * layer;

        vec2 cur = p;
        float curDepth = 0.0;
        float surf = 1.0 - brickHeight(cur);
        vec2 prev = cur;
        float prevDepth = 0.0;
        float prevSurf = surf;

        for (int i = 0; i < 64; i++) {
            if (float(i) >= steps || curDepth >= surf) break;
            prev = cur;
            prevDepth = curDepth;
            prevSurf = surf;
            cur -= delta;
            curDepth += layer;
            surf = 1.0 - brickHeight(cur);
        }
        float after = surf - curDepth;
        float before = prevSurf - prevDepth;
        float t = after / (after - before - 1e-5);
        return mix(cur, prev, clamp(t, 0.0, 1.0));
    }

    void material(inout MaterialInputs material) {
        prepareMaterial(material);

        vec3 pos = getUserWorldPosition();
        vec3 n = normalize(getWorldGeometricNormalVector());
        vec3 toEye = getWorldCameraPosition() - getWorldPosition();
        float dist = length(toEye);
        vec3 v = toEye / max(dist, 1e-4);

        // Pick the projection plane from the dominant normal axis.
        vec3 an = abs(n);
        vec3 ua; vec3 va; vec3 wa;
        if (an.y >= an.x && an.y >= an.z) {
            ua = vec3(1.0, 0.0, 0.0);
            va = vec3(0.0, 0.0, 1.0);
            wa = vec3(0.0, n.y >= 0.0 ? 1.0 : -1.0, 0.0);
        } else if (an.x >= an.z) {
            ua = vec3(0.0, 0.0, 1.0);
            va = vec3(0.0, 1.0, 0.0);
            wa = vec3(n.x >= 0.0 ? 1.0 : -1.0, 0.0, 0.0);
        } else {
            ua = vec3(1.0, 0.0, 0.0);
            va = vec3(0.0, 1.0, 0.0);
            wa = vec3(0.0, 0.0, n.z >= 0.0 ? 1.0 : -1.0);
        }
        vec2 uv = vec2(dot(pos, ua), dot(pos, va));
        vec2 viewXY = vec2(dot(v, ua), dot(v, va));
        float viewN = abs(dot(v, wa));

        // Fade detail with distance to avoid aliasing on far walls.
        float fd = max(materialParams.fadeDistance, 1.0);
        float fade = 1.0 - smoothstep(0.5 * fd, fd, dist);

        vec2 q = pom(uv, viewXY, viewN, materialParams.parallaxDepth * fade);

        // Normal from the height gradient at the parallax-shifted point.
        float e = 0.015;
        float gx = brickHeight(q + vec2(e, 0.0)) - brickHeight(q - vec2(e, 0.0));
        float gy = brickHeight(q + vec2(0.0, e)) - brickHeight(q - vec2(0.0, e));
        float relief = max(materialParams.parallaxDepth, 0.05);
        vec2 g = vec2(gx, gy) / (2.0 * e) * relief * materialParams.normalStrength * fade;
        vec3 nw = normalize(wa - g.x * ua - g.y * va);
        material.normal = normalize(transpose(getWorldTangentFrame()) * nw);

        // Color: per-brick variation, grain, and mortar.
        vec2 bq = brickCoord(q);
        float mask = brickMask(bq);
        float h = brickHeight(q);
        float id = hash21(floor(bq / materialParams.brickSize));
        vec3 brickCol = mix(materialParams.brickColorA, materialParams.brickColorB, id);
        brickCol *= 0.88 + 0.24 * vnoise(bq * 9.0);
        vec3 mortarCol = materialParams.mortarColor * (0.85 + 0.3 * vnoise(bq * 25.0));
        vec3 col = mix(mortarCol, brickCol, mask);

        vec4 inst = materialParams.instanceColors[getInstanceIndex()];
        col *= mix(vec3(1.0), inst.rgb, materialParams.tintStrength);
        col *= materialParams.baseColor.rgb;

        float cavity = 0.35 + 0.65 * smoothstep(0.0, 0.6, h);

        material.baseColor = vec4(col, 1.0);
        material.roughness = clamp(mix(materialParams.roughness + 0.1, materialParams.roughness, mask), 0.04, 1.0);
        material.metallic = materialParams.metallic;
        material.ambientOcclusion = mix(1.0, cavity, materialParams.aoStrength);

        // MATERIAL_VARIANT_FRAGMENT_HOOK
    }
}
]==]

-- Custom uniforms (set these after assigning Source; ResetShader clears them)
brick:SetUniform("brickSize", { 2.0, 0.667 }) -- studs: width, height
brick:SetUniform("mortarWidth", 0.09)
brick:SetUniform("bevel", 0.06)
brick:SetUniform("brickColorA", { 0.55, 0.20, 0.14 })
brick:SetUniform("brickColorB", { 0.42, 0.16, 0.12 })
brick:SetUniform("mortarColor", { 0.62, 0.60, 0.55 })
brick:SetUniform("tintStrength", 0) -- 1 = multiply by part color
brick:SetUniform("fadeDistance", 60)

-- Built-in properties that feed the shader's declared parameters
brick.Color = Color3.new(1, 1, 1)
brick.Roughness = 0.85
brick.Metalness = 0
brick.ParallaxDepth = 0.1
brick.ParallaxSteps = 32
brick.NormalStrength = 1
brick.AOStrength = 1

print(brick.Compiled, brick.LastError) -- compiles on first draw, so check again after a frame

part.MaterialVariant = "ProceduralBrick"

game:GetService("Terrain").MaterialVariant = "ProceduralBrick"
