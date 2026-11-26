// ==============================================================================
//  GLASS RAIN  (the Distortion of the storm mood: rain on the screen itself)
// ==============================================================================
//  TASK
//    The storm breaks the fourth wall: it rains on the glass of the screen,
//    under the painting: the painterly mood filter repaints the drops, so
//    they become brush strokes too. Nothing here adds its own colour. Every part is
//    an adjustment of the image under it (like an adjustment layer in
//    Photoshop):
//      - Condensation: the glass is misty. The image is blurred, less
//        saturated and a little lighter. It is stronger near the screen edges.
//      - Splats: drops hit the glass, then dry. Each drop is a lens: the
//        image in it is upside down and magnified, much more saturated, with
//        chromatic aberration at the edge, darker at the rim and lighter at
//        the bottom (where a real drop focuses the light).
//      - Runners: big drops slide down in jerks. They wipe the mist away and
//        leave a clear, saturated trail with small droplets.
//    "amount" (0 to 1) sets how much of all this there is.
//
//  RULES
//    - It reads the 3D image (before the mood filter), so it needs the
//      BackBufferCopy in glass_rain.tscn before it.
//    - amount = 0 gives the image back unchanged. The script hides the layer
//      then, so it costs nothing.
// ==============================================================================
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;

// How much rain is on the glass (set by glass_rain.gd from the Distortion).
uniform float amount : hint_range(0.0, 1.0) = 1.0;

group_uniforms condensation;
// How misty the glass is at amount 1.
uniform float mist : hint_range(0.0, 1.0) = 0.55;
// How blurred the mist is (mipmap level of the screen).
uniform float mist_blur : hint_range(0.0, 6.0) = 2.2;
// The saturation of the image under the mist (1 = no change).
uniform float mist_saturation : hint_range(0.0, 2.0) = 0.45;
// How much the mist lifts the darks (like the output levels in Photoshop).
uniform float mist_lift : hint_range(0.0, 0.5) = 0.07;

group_uniforms drops;
// The saturation in the drops and trails (1 = no change).
uniform float drop_saturation : hint_range(0.0, 4.0) = 2.4;
uniform float drop_contrast : hint_range(0.5, 2.0) = 1.35;
// How far the lens bends the image (in drop radii). Above 1, the image flips.
uniform float refraction : hint_range(0.0, 4.0) = 2.0;
// Colour split at the edge of the drops (part of the screen).
uniform float chroma : hint_range(0.0, 0.02) = 0.005;
// How dark the rim of a drop is (multiply).
uniform float rim_dark : hint_range(0.0, 1.0) = 0.6;
// How much lighter the bottom of a drop is (dodge).
uniform float focus_light : hint_range(0.0, 2.0) = 1.1;

group_uniforms rain;
// Splats: cells per screen height, and the part of the cells with a drop at amount 1.
uniform float splat_cells : hint_range(4.0, 80.0) = 8.0;
uniform float splat_density : hint_range(0.0, 1.0) = 0.35;
// Runners: columns per screen height, and the part of the columns with a drop at amount 1.
uniform float runner_columns : hint_range(2.0, 60.0) = 10.0;
uniform float runner_density : hint_range(0.0, 1.0) = 0.6;
// Screen heights per second (average).
uniform float runner_speed : hint_range(0.0, 1.0) = 0.12;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

// A round lens. d = from the centre, r = radius (both in screen heights).
// Returns xy = d / r (-1 to 1 in the drop) times the mask, z = mask.
vec3 lens(vec2 d, float r, float aa) {
	float dist = length(d);
	float m = 1.0 - smoothstep(r - aa, r + aa, dist);
	return vec3(d / max(r, 1e-4) * m, m);
}

// Drops that hit the glass, stay, and dry. p is in screen heights.
// Returns the lens (xy, mask) and the radius in w.
vec4 splats(vec2 p, float cells, float density, float t, float aa) {
	vec2 g = p * cells;
	vec2 id = floor(g);
	float period = 5.0 + 7.0 * hash12(id + 7.1);
	float life = t / period + hash12(id + 3.3);
	float cycle = floor(life);
	float phase = fract(life);
	vec2 key = id + cycle * 17.31;
	if (hash12(key) > density) {
		return vec4(0.0);
	}
	vec2 centre = (id + 0.25 + 0.5 * hash22(key + 1.7)) / cells;
	// It hits fast, stays, then dries (shrinks) at the end of its life.
	float r = (0.1 + 0.15 * hash12(key + 9.2)) / cells; // Stays in its cell.
	r *= smoothstep(0.0, 0.015, phase) * (1.0 - smoothstep(0.6, 1.0, phase));
	return vec4(lens(p - centre, r, aa), r);
}

// Big drops that slide down in jerks and leave a wet trail.
// Returns the lens (xy, mask) and the radius in w; trail = the clear trail.
vec4 runners(vec2 p, float columns, float density, float t, float aa, out float trail) {
	trail = 0.0;
	float col = floor(p.x * columns);
	float s = hash12(vec2(col, 4.7));
	if (s > density) {
		return vec4(0.0);
	}
	// Stop and go: the time runs faster and slower, but never back.
	float jerk = t + 0.28 * sin(t * 2.3 + s * 20.0) + 0.05 * sin(t * 5.1 + s * 7.0);
	float speed = runner_speed * (0.6 + 0.8 * hash12(vec2(col, 9.1)));
	float lap = s * 5.3 + jerk * speed / 1.4;
	float y = fract(lap) * 1.4 - 0.2; // From above the screen to below it.
	float lap_id = floor(lap);
	float r = (0.25 + 0.15 * hash12(vec2(col, lap_id))) / columns;
	float cx = (col + 0.5 + 0.22 * sin(y * 11.0 + s * 30.0)) / columns;
	vec2 d = p - vec2(cx, y);
	// The top of the drop is pointed: stretch the upper half.
	d.y *= d.y < 0.0 ? 0.65 : 1.0;
	vec4 drop = vec4(lens(d, r, aa), r);
	// The trail above the drop: clear glass that closes again with time.
	float above = y - p.y;
	float side = abs(p.x - (col + 0.5 + 0.22 * sin(p.y * 11.0 + s * 30.0)) / columns);
	float width = r * 0.55 * (1.0 - smoothstep(0.0, 0.5, above));
	trail = step(0.0, above) * (1.0 - smoothstep(width * 0.6, width + aa, side)) * exp(-above * 3.0);
	// Small droplets left in the trail.
	float row = floor(p.y * columns * 4.0);
	vec2 dot_c = vec2(cx, (row + 0.5) / (columns * 4.0)) + (hash22(vec2(col, row)) - 0.5) * vec2(r * 0.6, 0.0);
	float dot_r = r * 0.28 * step(0.45, hash12(vec2(row, col + lap_id))) * step(0.0, above) * exp(-above * 2.0);
	vec4 droplet = vec4(lens(p - dot_c, dot_r, aa), dot_r);
	return drop.z >= droplet.z ? drop : droplet;
}

vec3 saturate_color(vec3 c, float s) {
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	return max(mix(vec3(l), c, s), 0.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 original = textureLod(screen_tex, uv, 0.0).rgb;
	if (amount <= 0.0) {
		COLOR = vec4(original, 1.0);
	} else {
		float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
		vec2 p = vec2(uv.x * aspect, uv.y); // Screen heights, y goes down.
		float aa = 1.5 * SCREEN_PIXEL_SIZE.y;
		float t = TIME;

		// The drops: two sizes of splats, and the runners.
		vec4 a = splats(p, splat_cells, splat_density * amount, t, aa);
		vec4 b = splats(p + 0.37, splat_cells * 2.5, splat_density * 0.35 * amount, t * 1.3, aa);
		float trail;
		vec4 c = runners(p, runner_columns, runner_density * amount, t, aa, trail);
		vec4 drop = a;
		if (b.z > drop.z) { drop = b; }
		if (c.z > drop.z) { drop = c; }

		// The mist, stronger near the edges of the screen.
		float edge = smoothstep(0.25, 0.75, length((uv - 0.5) * vec2(1.0, 1.15)));
		float mist_here = mist * amount * mix(0.55, 1.0, edge) * (1.0 - trail);
		vec3 misty = textureLod(screen_tex, uv, mist_blur * mist_here).rgb;
		misty = saturate_color(misty, mix(1.0, mist_saturation, mist_here));
		misty = misty + mist_lift * mist_here * (1.0 - misty);
		vec3 col = mix(original, misty, smoothstep(0.0, 0.3, mist_here));

		// The trails: clear glass, a little more saturated.
		col = mix(col, saturate_color(original, mix(1.0, drop_saturation, 0.4)), trail);

		// The drops: lenses that flip and magnify the image.
		if (drop.z > 0.0) {
			vec2 n = drop.xy / max(drop.z, 1e-4); // -1 to 1 in the drop.
			vec2 bend = -n * drop.w * refraction;
			bend.x /= aspect;
			vec2 split = n * chroma;
			vec3 seen;
			seen.r = textureLod(screen_tex, uv + bend + split, 0.0).r;
			seen.g = textureLod(screen_tex, uv + bend, 0.0).g;
			seen.b = textureLod(screen_tex, uv + bend - split, 0.0).b;
			seen = saturate_color(seen, drop_saturation);
			seen = max((seen - 0.5) * drop_contrast + 0.5, 0.0);
			float rim = smoothstep(0.65, 1.0, length(n));
			seen *= 1.0 - rim_dark * rim;
			float focus = smoothstep(0.2, 0.9, n.y) * (1.0 - rim);
			seen *= 1.0 + focus_light * focus;
			col = mix(col, seen, drop.z);
		}
		COLOR = vec4(col, 1.0);
	}
}
