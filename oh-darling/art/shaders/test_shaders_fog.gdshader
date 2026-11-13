shader_type canvas_item;
render_mode unshaded;

// Fog: dull expressionism (Schiele, Picasso blue period).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;

uniform float intensity : hint_range(0.0, 1.0) = 1.0; // 0 = off, 1 = full effect

group_uniforms shapes;
uniform float thin : hint_range(0.0, 0.4) = 0.0;
uniform float stretch : hint_range(0.0, 0.3) = 0.0;
group_uniforms;

group_uniforms palette;
uniform float saturation : hint_range(0.0, 1.0) = 0.12;
uniform float contrast : hint_range(0.3, 1.5) = 0.7; // flat light
uniform float brightness : hint_range(0.5, 1.5) = 1.0;
uniform vec3 deep_blue : source_color = vec3(0.05, 0.08, 0.16); // darks
uniform vec3 grey_blue : source_color = vec3(0.3, 0.38, 0.47);
uniform vec3 dull_green : source_color = vec3(0.42, 0.47, 0.42);
uniform vec3 dirty_ochre : source_color = vec3(0.66, 0.6, 0.45); // lights
uniform float palette_amount : hint_range(0.0, 1.0) = 0.5;
group_uniforms;

group_uniforms lines; 
uniform float line_strength : hint_range(0.0, 1.0) = 0.567;
uniform float line_threshold : hint_range(0.01, 0.5) = 0.5;
uniform float line_gaps : hint_range(0.0, 1.0) = 0.209;
uniform float line_jitter : hint_range(0.0, 4.0) = 0.473;
uniform float jitter_fps : hint_range(0.0, 24.0) = 4.44;
uniform vec3 line_color : source_color = vec3(0.04, 0.05, 0.09);
group_uniforms;

group_uniforms canvas;
uniform vec3 canvas_color : source_color = vec3(0.78, 0.76, 0.7);
uniform float canvas_amount : hint_range(0.0, 1.0) = 0.162;
uniform float canvas_scale : hint_range(0.5, 10.0) = 1.805;
uniform float fade : hint_range(0.0, 1.0) = 0.06;
uniform float edge_canvas : hint_range(0.0, 1.0) = 0.062;
group_uniforms;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.0;
		a *= 0.5;
	}
	return v;
}

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

float luma_at(vec2 uv) {
	return luma(textureLod(screen_tex, uv, 0.0).rgb);
}

vec3 blue_period(float l) {
	vec3 c = mix(deep_blue, grey_blue, smoothstep(0.0, 0.35, l));
	c = mix(c, dull_green, smoothstep(0.35, 0.6, l));
	return mix(c, dirty_ochre, smoothstep(0.6, 1.0, l));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 original = textureLod(screen_tex, uv, 0.0).rgb;
	vec2 px = SCREEN_PIXEL_SIZE;
	float aspect = px.y / px.x; // width / height
	vec2 fc = FRAGCOORD.xy;

	// shapes
	vec2 suv = vec2(0.5 + (uv.x - 0.5) * (1.0 + thin), 0.5 + (uv.y - 0.5) * (1.0 - stretch));
	float inside = smoothstep(-0.02, 0.06, suv.x) * smoothstep(1.02, 0.94, suv.x)
			* smoothstep(-0.02, 0.06, suv.y) * smoothstep(1.02, 0.94, suv.y);
	vec3 col = textureLod(screen_tex, suv, 0.0).rgb;

	//palette:       blue period colors
	col = (col - 0.5) * contrast + 0.5;
	col *= brightness;
	float l = clamp(luma(col), 0.0, 1.0);
	col = mix(vec3(l), col, saturation);
	col = mix(col, blue_period(l), palette_amount);

	// 3. canvas: faded surfaces
	float patches = smoothstep(0.55, 0.75, fbm(vec2(uv.x * aspect, uv.y) * canvas_scale)) * canvas_amount;
	vec3 canvas = canvas_color + (hash(floor(fc / 2.0)) - 0.5) * 0.04; // canvas weave
	col = mix(col, canvas, patches);
	col = mix(col, canvas, fade);

	// lines: they twitch a few times per second
	float frame = floor(TIME * jitter_fps);
	vec2 jit = (vec2(hash(floor(fc / 8.0) + frame), hash(floor(fc / 8.0) - frame)) - 0.5) * line_jitter * px;
	vec2 luv = suv + jit;
	float tl = luma_at(luv + vec2(-px.x, -px.y));
	float tc = luma_at(luv + vec2(0.0, -px.y));
	float tr = luma_at(luv + vec2(px.x, -px.y));
	float ml = luma_at(luv + vec2(-px.x, 0.0));
	float mr = luma_at(luv + vec2(px.x, 0.0));
	float bl = luma_at(luv + vec2(-px.x, px.y));
	float bc = luma_at(luv + vec2(0.0, px.y));
	float br = luma_at(luv + vec2(px.x, px.y));
	float gx = (tr + 2.0 * mr + br) - (tl + 2.0 * ml + bl);
	float gy = (bl + 2.0 * bc + br) - (tl + 2.0 * tc + tr);
	float edge = length(vec2(gx, gy));
	float line = smoothstep(line_threshold, line_threshold * 2.0, edge);
	float gaps = smoothstep(line_gaps - 0.1, line_gaps + 0.1, noise(fc / 10.0 + frame * 0.37));
	col = mix(col, line_color, line * gaps * line_strength);

	// borders
	vec2 c = (uv - 0.5) * vec2(aspect, 1.0);
	float edge_mask = smoothstep(0.45, 0.85, length(c) + (fbm(fc / 60.0) - 0.5) * 0.2);
	col = mix(col, canvas, max(edge_mask * edge_canvas, 1.0 - inside));

	COLOR = vec4(mix(original, clamp(col, 0.0, 1.0), intensity), 1.0);
}
