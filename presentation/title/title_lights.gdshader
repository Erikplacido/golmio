// Luzes vivas da abertura, somadas por cima da arte (blend_add): dois feixes saindo dos refletores
// que varrem devagar e pulsam, mais o brilho central pulsando. Coordenadas em fração da arte.
shader_type canvas_item;
render_mode blend_add;

uniform vec2 lamp_left = vec2(0.17, 0.065);
uniform vec2 lamp_right = vec2(0.83, 0.065);
uniform vec2 target = vec2(0.5, 0.30);        // para onde os feixes apontam
uniform vec2 sun = vec2(0.5, 0.25);
uniform float aspect = 0.5628;                  // largura / altura da arte
uniform float cone_half_angle = 0.16;           // rad
uniform float sweep = 0.05;                     // rad de varredura
uniform float intensity = 0.10;
uniform float sun_intensity = 0.12;
uniform vec4 beam_color : source_color = vec4(1.0, 0.93, 0.7, 1.0);
uniform vec4 sun_color : source_color = vec4(1.0, 0.78, 0.3, 1.0);

float beam(vec2 p, vec2 lamp, float phase) {
	vec2 d = p - lamp;
	d.x *= aspect;
	vec2 aim = target - lamp;
	aim.x *= aspect;
	float a = atan(d.x, d.y) - atan(aim.x, aim.y) - sin(TIME * 0.45 + phase) * sweep;
	float inside = 1.0 - smoothstep(cone_half_angle * 0.55, cone_half_angle, abs(a));
	float dist = length(d);
	float falloff = smoothstep(0.75, 0.05, dist) * smoothstep(0.0, 0.04, dist);
	float pulse = 0.75 + 0.25 * sin(TIME * 1.7 + phase * 3.0);
	return inside * falloff * pulse;
}

void fragment() {
	vec2 p = UV;
	float b = beam(p, lamp_left, 0.0) + beam(p, lamp_right, 2.4);
	vec2 s = p - sun;
	s.x *= aspect;
	float glow = smoothstep(0.32, 0.0, length(s)) * (0.7 + 0.3 * sin(TIME * 1.1));
	vec3 col = beam_color.rgb * b * intensity + sun_color.rgb * glow * sun_intensity;
	COLOR = vec4(col, 1.0);
}
