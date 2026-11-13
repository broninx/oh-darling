
shader_type canvas_item;
render_mode unshaded;

// Mania: post-impressionism (Van Gogh).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float intensity : hint_range(0.0, 1.0) = 1.0; // 0 = off, 1 = full effect

group_uniforms shapes; // nothing is straight
uniform float wave_strength : hint_range(0.0, 20.0) = 1.143; //
uniform float wave_size : hint_range(1.0, 20.0) = 6.0; // waves across the screen
uniform float sway : hint_range(0.0, 10.0) = 2.0; // whole image slowly sways (not sure if it conflicts with echoes)
group_uniforms;

group_uniforms swirl;
uniform float swirl_strength : hint_range(0.0, 40.0) = 4.0; 
uniform float swirl_scale : hint_range(0.5, 20.0) = 4.0;
uniform float swirl_speed : hint_range(0.0, 2.0) = 0.15;
uniform float follow_forms : hint_range(0.0, 1.0) = 0.6;
uniform float stroke_length : hint_range(0.0, 30.0) = 6.0;
uniform int stroke_samples : hint_range(1, 12) = 6;
uniform float impasto : hint_range(0.0, 1.0) = 0.45;
uniform float stroke_width : hint_range(1.0, 10.0) = 4.0;
group_uniforms;

group_uniforms outlines; // thick lines
uniform float outline_strength : hint_range(0.0, 1.0) = 0.58;
uniform float outline_thickness : hint_range(0.5, 4.0) = 2.212;
uniform float outline_threshold : hint_range(0.01, 0.5) = 0.15;
uniform vec3 outline_color : source_color = vec3(0.04, 0.05, 0.12);
group_uniforms;

group_uniforms light;
uniform float halo_strength : hint_range(0.0, 2.0) = 0.966;
uniform float halo_threshold : hint_range(0.01, 1.0) = 0.427;
uniform float halo_radius : hint_range(10.0, 200.0) = 60.0;
uniform float lamp_brightness : hint_range(0.0, 1.0) = 0.228;
uniform float ring_count : hint_range(0.0, 20.0) = 7.919;
uniform float ring_speed : hint_range(0.0, 5.0) = 2.566;
uniform vec3 halo_tint : source_color = vec3(1.0, 0.69, 0.0);
group_uniforms;

group_uniforms color;
uniform float saturation : hint_range(0.0, 3.0) = 3.0;
uniform float contrast : hint_range(0.5, 2.0) = 0.854;
uniform float brightness : hint_range(0.5, 2.0) = 1.275;
uniform float gamma : hint_range(0.4, 1.5) = 0.7;
uniform float shadow_lift : hint_range(0.0, 1.0) = 0.7; // darks turn blue instead of black
uniform vec3 ultramarine : source_color = vec3(0.18, 0.26, 0.72); // darks
uniform vec3 deep_blue : source_color = vec3(0.025, 0.025, 0.12); // darkest areas, instead of black
uniform vec3 orange : source_color = vec3(1.0, 0.49, 0.12); // mid tones
uniform vec3 chrome_yellow : source_color = vec3(1.0, 0.79, 0.11); // lights
uniform float tint_amount : hint_range(0.0, 3.0) = 1.47;
uniform float yellow_strength : hint_range(0.0, 1.0) = 1.0; // stronger chrome yellow in the lights
uniform float yellow_threshold : hint_range(0.0, 1.0) = 0.708;
uniform float pulse : hint_range(0.0, 0.3) = 0.082;
uniform float pulse_speed : hint_range(0.0, 10.0) = 1.011;
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
	return luma(textureLod(screen_tex, uv, 1.0).rgb);
}

vec3 soft_light(vec3 a, vec3 b) {
	return (1.0 - 2.0 * b) * a * a + 2.0 * b * a;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 original = textureLod(screen_tex, uv, 0.0).rgb;
	vec2 px = SCREEN_PIXEL_SIZE;
	float aspect = px.y / px.x;
	float t = TIME ;

	// shapes
	vec2 w = uv;
	w += vec2(sin(uv.y * wave_size * 6.2831 + t * 0.8),
			cos(uv.x * wave_size * 5.0265 + t * 0.6)) * wave_strength * px;
	w += vec2(sin(t * 0.5), cos(t * 0.4)) * sway * px;

	// edges of the wavy image
	vec2 o = outline_thickness * px;
	float tl = luma_at(w + vec2(-o.x, -o.y));
	float tc = luma_at(w + vec2(0.0, -o.y));
	float tr = luma_at(w + vec2(o.x, -o.y));
	float ml = luma_at(w + vec2(-o.x, 0.0));
	float mr = luma_at(w + vec2(o.x, 0.0));
	float bl = luma_at(w + vec2(-o.x, o.y));
	float bc = luma_at(w + vec2(0.0, o.y));
	float br = luma_at(w + vec2(o.x, o.y));
	float gx = (tr + 2.0 * mr + br) - (tl + 2.0 * ml + bl);
	float gy = (bl + 2.0 * bc + br) - (tl + 2.0 * tc + tr);
	float edge = length(vec2(gx, gy));
	vec2 tangent = normalize(vec2(-gy, gx) + vec2(0.00001));

	// flow
	vec2 p = vec2(w.x * aspect, w.y) * swirl_scale;
	float ts = t * swirl_speed;
	float angle = fbm(p + vec2(ts, -ts * 0.7)) * 12.566;
	vec2 dir = vec2(cos(angle), sin(angle));
	tangent *= dot(tangent, dir) < 0.0 ? -1.0 : 1.0;
	float follow = follow_forms * smoothstep(0.02, 0.2, edge);
	dir = normalize(mix(dir, tangent, follow));

	vec2 base = w + dir * swirl_strength * px;

	// strokes
	vec3 col = vec3(0.0);
	float n = float(stroke_samples);
	for (int i = 0; i < stroke_samples; i++) {
		float k = float(i) / max(n - 1.0, 1.0) - 0.5;
		col += textureLod(screen_tex, base + dir * k * stroke_length * px, 0.0).rgb;
	}
	col /= n;

	// brush marks
	vec2 fc = FRAGCOORD.xy;
	vec2 perp = vec2(-dir.y, dir.x);
	vec2 q = vec2(dot(fc, dir) / max(stroke_length, 1.0), dot(fc, perp) / stroke_width);
	float marks = noise(q + vec2(0.0, ts * 3.0)) - 0.5;
	col *= 1.0 + marks * impasto;

	// color
	col = (col - 0.5) * contrast + 0.5;
	col *= brightness;
	col = pow(max(col, vec3(0.0)), vec3(gamma));
	float l = clamp(luma(col), 0.0, 1.0);
	col = mix(vec3(l), col, saturation);
	vec3 tone = mix(deep_blue, ultramarine, smoothstep(0.1, 0.4, l));
	tone = mix(tone, orange, smoothstep(0.4, 0.6, l));
	tone = mix(tone, chrome_yellow, smoothstep(0.6, 0.85, l));
	col = mix(col, soft_light(clamp(col, 0.0, 1.0), tone), tint_amount);
	// no black
	col = mix(col, deep_blue, (1.0 - smoothstep(0.0, 0.25, l)) * shadow_lift);
	col = mix(col, chrome_yellow * (0.7 + 0.5 * l), smoothstep(yellow_threshold, yellow_threshold + 0.35, l) * yellow_strength);
	
	// light field
	float near = 0.0;
	float far = 0.0;
	float brightest = 0.0;
	for (int i = 0; i < 16; i++) {
		float fi = float(i) + 0.5;
		float r = sqrt(fi / 16.0);
		float a = fi * 2.39996;
		vec2 off = vec2(cos(a), sin(a)) * r * halo_radius * px;
		float b = luma(textureLod(screen_tex, w + off, 2.0).rgb);
		near += b;
		brightest = max(brightest, b);
		far += luma(textureLod(screen_tex, w + off * 3.0, 3.0).rgb);
	}
	float spot = max(near - far, 0.0) / 16.0;
	float glow = smoothstep(0.01, halo_threshold, spot);
	glow *= smoothstep(lamp_brightness - 0.1, lamp_brightness + 0.05, brightest);

	// outlines
	float line = smoothstep(outline_threshold, outline_threshold * 3.0, edge) * outline_strength;
	line *= 1.0 - glow;
	col = mix(col, outline_color, line);

	// halos with concentric rings
	float rings = 0.5 + 0.5 * sin(spot / halo_threshold * ring_count * 3.1416 - t * ring_speed);
	vec3 halo = clamp(halo_tint * glow * mix(1.0, rings, 0.7) * halo_strength, 0.0, 1.0);
	col = vec3(1.0) - (vec3(1.0) - clamp(col, 0.0, 1.0)) * (vec3(1.0) - halo);

	// pulse
	col *= 1.0 + sin(t * pulse_speed) * pulse;

	COLOR = vec4(mix(original, clamp(col, 0.0, 1.0), intensity), 1.0);
}
