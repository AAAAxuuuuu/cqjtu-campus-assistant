#version 460 core
#include <flutter/runtime_effect.glsl>

// 液态玻璃 —— 边缘高光 + 厚度渐变 + 镜面拉伸
//
// 本 shader 只绘制玻璃体**自身的光学层**（半透明白 + 边缘高光 + 上下缘），
// 叠加在已经被 BackdropFilter 模糊过的背景之上。
//
// 为什么不在 shader 里做折射采样：折射需要读取背景纹理，而 CustomPaint 的
// Paint.shader 路径没有可用的 backdrop sampler（ImageFilter.shader 倒是有
// 输入纹理，但它不注入控件尺寸，uSize 会是 0，SDF 全部算错——表现就是胶囊被
// 横向切成两半）。所以这里的分工是：模糊交给 BackdropFilter，本 shader 负责
// 玻璃体的厚度感与高光。
//
// 三个可见现象：
// 1. 厚度渐变：顶部薄（更透）、底部厚（更实），模拟光穿过玻璃体的衰减。
// 2. 镜面拉伸：沿边缘法线的一道高光，随光源角度变化，在圆角处收窄。
// 3. 上下缘：顶面亮边（反射）+ 底面暗线（内反射），让玻璃有实体边界。

uniform vec2 uSize;         // 玻璃体尺寸（逻辑像素）
uniform float uRadius;      // 圆角半径
uniform float uThickness;   // 厚度：高光与渐变强度总控
uniform float uLightAngle;  // 主光源角度（弧度）

out vec4 fragColor;

// 圆角矩形的有符号距离场。负 = 内部，0 = 边界，正 = 外部。
float roundedBoxSDF(vec2 p, vec2 halfSize, float radius) {
    vec2 q = abs(p) - halfSize + radius;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - radius;
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 uv = fragCoord / uSize;
    vec2 centered = fragCoord - uSize * 0.5;
    vec2 halfSize = uSize * 0.5;

    float dist = roundedBoxSDF(centered, halfSize, uRadius);

    // 边缘带：折射/高光集中的区域。
    float edgeBand = mix(8.0, 20.0, clamp(uThickness, 0.0, 1.0));
    float edgeFactor = 1.0 - clamp(-dist / edgeBand, 0.0, 1.0);
    edgeFactor = edgeFactor * edgeFactor;

    // SDF 梯度即边缘法线。
    vec2 grad = vec2(
        roundedBoxSDF(centered + vec2(1.0, 0.0), halfSize, uRadius) -
        roundedBoxSDF(centered - vec2(1.0, 0.0), halfSize, uRadius),
        roundedBoxSDF(centered + vec2(0.0, 1.0), halfSize, uRadius) -
        roundedBoxSDF(centered - vec2(0.0, 1.0), halfSize, uRadius)
    );
    vec2 normal = normalize(grad + vec2(1e-5));

    // ── 1. 厚度渐变：顶透底实 ─────────────────────────────────
    float body = mix(0.40, 0.68, uv.y) * clamp(uThickness, 0.3, 1.0);

    // ── 2. 镜面拉伸 ──────────────────────────────────────────
    vec2 lightDir = vec2(cos(uLightAngle), sin(uLightAngle));
    float facing = max(dot(normal, lightDir), 0.0);
    float specular = pow(facing, 4.0) * edgeFactor * 0.45;

    // 顶部内侧的体高光，让玻璃显得通透而非塑料。
    float bodyGlow = pow(1.0 - uv.y, 3.0) * 0.12 * uThickness;

    // ── 3. 上下缘 ────────────────────────────────────────────
    // 顶面亮边：只在朝上的边缘出现。
    float topRim = smoothstep(0.0, 2.0, -dist) - smoothstep(2.0, 4.0, -dist);
    topRim *= max(-normal.y, 0.0);

    // 底面暗线：内反射。
    float bottomRim = smoothstep(0.0, 1.5, -dist) - smoothstep(1.5, 3.5, -dist);
    bottomRim *= max(normal.y, 0.0);

    float alphaTotal = clamp(body + specular + bodyGlow + topRim * 0.5, 0.0, 0.92);
    vec3 tint = vec3(1.0);
    tint -= vec3(bottomRim * 0.10);

    // 圆角外抗锯齿裁切。
    float shape = 1.0 - smoothstep(-1.0, 0.5, dist);
    float a = alphaTotal * shape;

    // 预乘 alpha。
    fragColor = vec4(tint * a, a);
}
