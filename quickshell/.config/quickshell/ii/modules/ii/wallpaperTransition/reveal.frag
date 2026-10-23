#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 center;    // circle centre, in window pixels
    vec2 size;      // window size, in pixels
    float radius;   // current circle radius, in pixels
    float feather;  // width of the soft edge, in pixels
};
layout(binding = 1) uniform sampler2D src;

void main() {
    float d = distance(qt_TexCoord0 * size, center);
    // 0 inside the circle (hole: live screen shows through), 1 outside (frozen old screen stays)
    float a = smoothstep(radius - feather, radius, d);
    fragColor = texture(src, qt_TexCoord0) * (a * qt_Opacity);
}
