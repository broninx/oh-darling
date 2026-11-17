shader_type canvas_item;
render_mode unshaded;

// Painting cut into pieces: Distortion level 3 (the scene breaks into fragments).
// The image is cut into big irregular pieces. Each piece floats slowly on its own
// (moves and turns), carrying its part of the picture with it.
// Between the pieces there are dark gaps.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;

uniform float amount : hint_range(0.0, 1.0) = 1.0; // set by distortion_filter.gd
uniform float shard_size : hint_range(40.0, 600.0) = 220.0; // size of the pieces (px)
uniform float shard_shift : hint_range(0.0, 60.0) = 14.0; // how far pieces float (px)
uniform float shard_turn : hint_range(0.0, 15.0) = 3.0; // how much pieces turn (degrees)
uniform float move_speed : hint_range(0.0, 3.0) = 0.6; // how fast pieces float, 0 = still
uniform float gap_width : hint_range(0.0, 20.0) = 4.0; // dark space between pieces (px)
uniform vec3 gap_color : source_color = vec3(0.06, 0.05, 0.07);
uniform float edge_shade : hint_range(0.0, 1.0) = 0.35; // darker border on each piece

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 hash2(vec2 p) {
	return vec2(hash(p), hash(p + vec2(17.31, 5.17)));
}

mat2 rot(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

vec3 nearest_piece(vec2 g) {
	vec2 ip = floor(g);
	vec2 fp = fract(g);
	float d1 = 10.0;
	float d2 = 10.0;
	vec2 best = ip;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			float d = length(o + hash2(ip + o) - fp);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				best = ip + o;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec3(best, d2 - d1);
}

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 p = (SCREEN_UV - 0.5) * res;
	float t = TIME * move_speed;
	float gap = gap_width / shard_size * amount;

	vec3 col = gap_color;
	float best_margin = -1.0;

	vec2 ip = floor(p / shard_size);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 id = ip + vec2(float(x), float(y));
			vec2 center = (id + hash2(id)) * shard_size;

			vec2 r = hash2(id + vec2(3.7, 9.1)) * 6.2831;
			vec2 move = vec2(sin(t + r.x), sin(t * 0.83 + r.y)) * shard_shift * amount;
			float turn = radians(shard_turn) * sin(t * 0.71 + r.x + r.y) * amount;

			vec2 q = center + rot(-turn) * (p - move - center);

			vec3 hit = nearest_piece(q / shard_size);
			float margin = hit.z - gap;
			if (length(hit.xy - id) < 0.5 && margin >= 0.0 && margin > best_margin) {
				best_margin = margin;
				col = textureLod(screen_tex, q / res + 0.5, 0.0).rgb;
				// darker border, so every piece reads as a cut piece
				float edge = 1.0 - smoothstep(0.0, 0.06, margin);
				col *= 1.0 - edge * edge_shade * amount;
			}
		}
	}

	COLOR = vec4(col, COLOR.a);
}