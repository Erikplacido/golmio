// Onda de choque da abertura: um anel que se expande do centro e some (blend_add).
// progress 0 → 1 leva o anel do centro até a borda do retângulo.
shader_type canvas_item;
render_mode blend_add;

uniform float progress = 1.0;
uniform vec4 color : source_color = vec4(1.0, 0.94, 0.72, 1.0);

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float width = 0.03 + 0.09 * progress;
	float ring = smoothstep(width, 0.0, abs(r - progress));
	float fade = 1.0 - progress;
	COLOR = vec4(color.rgb * ring * fade * fade * 1.4, 1.0);
}
