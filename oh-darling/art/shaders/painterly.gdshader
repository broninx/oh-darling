// ==============================================================================
//  PAINTERLY FILTER  (task T05)
// ==============================================================================
//  TASK
//    Paint the screen with visible brush strokes, in the style of
//    expressionism and Van Gogh: strokes that follow the shapes and swirl
//    in flat areas, thick paint (impasto), strong colour, broken outlines.
//    It replaces the old Kuwahara filter (kuwahara_clear.gdshader).
//
//  HOW TO USE
//    Put it on a full-screen ColorRect (mouse_filter = Ignore) in a
//    CanvasLayer. mood_filter.tscn uses it for clear, overcast and bright.
//    Each mood has its own ShaderMaterial with its own values.
//
//  HOW IT WORKS (one pass, no extra viewport)
//    1. Underpainting: the image is smeared along the stroke direction.
//    2. Strokes: 3 layers of single brush strokes on a jittered grid
//       (2 large layers, 1 small layer only where there is detail).
//       Each stroke takes ONE colour from its centre, and turns with the
//       edges of the image and with a swirl field.
//    3. Outlines, colour (saturation, value steps, warm lights and cool
//       shadows), then light on the paint relief and the canvas grain.
//
//  SIZES DO NOT DEPEND ON THE RESOLUTION OR THE ZOOM
//    All sizes are a part of the SCREEN HEIGHT (brush_size 0.01 = 1% of the
//    screen height). The strokes have the same size on screen at 720p, at
//    1080p and at 4K, and when the camera zooms in or out. The direction of
//    a stroke comes from a mipmap level that matches the stroke size, so the
//    strokes do not flicker when the camera moves or zooms.
//    Tested in town_hills at zoom 0.45, 1.0 and 1.4, at 720p and 1080p.
//
//  RULES
//    - It ends with COLOR = vec4(..., COLOR.a), so the mood fade works.
//    - The loops have a fixed size: at most about 125 texture reads for each
//      pixel, usually fewer.
//      (The old Kuwahara with radius 9 used 400.)
// ==============================================================================
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;

// 0 = no effect, 1 = full effect.
uniform float intensity : hint_range(0.0, 1.0) = 1.0;

group_uniforms brush;
// The width of a large stroke, as a part of the screen height.
uniform float brush_size : hint_range(0.003, 0.03, 0.0005) = 0.011;
// The length of a stroke, as a multiple of its width.
uniform float stroke_length : hint_range(1.5, 5.0, 0.1) = 3.8;
// Random position and size of the strokes. 0 = a regular grid.
uniform float stroke_jitter : hint_range(0.0, 1.0) = 0.8;
// Random turn of each stroke (radians).
uniform float angle_jitter : hint_range(0.0, 0.8) = 0.2;
// Small strokes: 0 = none, 1 = many. They go mostly where there is detail.
uniform float fine_strokes : hint_range(0.0, 1.0) = 0.6;
// How much the underpainting (the paint between the strokes) is smeared.
uniform float underpaint_smear : hint_range(0.0, 1.0) = 0.8;
group_uniforms;

group_uniforms flow;
// The strokes follow the edges of the shapes.
uniform float follow_edges : hint_range(0.0, 1.0) = 0.85;
// The strokes swirl in flat areas (Van Gogh). 0 = straight hatching.
uniform float swirl : hint_range(0.0, 1.0) = 0.5;
// The number of swirls in one screen height.
uniform float swirl_scale : hint_range(0.5, 12.0) = 3.0;
// The swirls move slowly. 0 = still.
uniform float swirl_speed : hint_range(0.0, 0.2) = 0.0;
// The direction of the hatching where there is no edge and no swirl (degrees).
uniform float hatch_angle : hint_range(-90.0, 90.0) = 35.0;
group_uniforms;

group_uniforms detail;
// Strokes stop where the colour changes much. Higher keeps the shapes clean.
uniform float edge_respect : hint_range(0.0, 1.0) = 0.65;
// Large strokes do not cover small things (people, lamp posts). Only small
// strokes paint there.
uniform float detail_keep : hint_range(0.0, 1.0) = 0.8;
group_uniforms;

group_uniforms impasto;
// The height of the paint relief.
uniform float impasto : hint_range(0.0, 1.0) = 0.55;
// The lines of the bristles in the strokes, and the dry end of the strokes.
uniform float bristles : hint_range(0.0, 1.0) = 0.5;
// The direction of the light on the paint (degrees, 225 = from the top left).
uniform float light_angle : hint_range(0.0, 360.0) = 225.0;
// The weave of the canvas.
uniform float canvas_grain : hint_range(0.0, 1.0) = 0.2;
group_uniforms;

group_uniforms color;
uniform float saturation : hint_range(0.0, 3.0) = 1.5;
// The number of value (light) steps. 0 = no steps. Steps can merge a dark
// object with a dark background, so use them with care.
uniform float value_steps : hint_range(0.0, 12.0, 1.0) = 0.0;
// 0 = hard steps, 1 = very soft steps.
uniform float step_softness : hint_range(0.0, 1.0) = 0.45;
// Each stroke gets a slightly different value and temperature.
uniform float color_jitter : hint_range(0.0, 0.3) = 0.1;
// Shadows go to this colour.
uniform vec3 shadow_color : source_color = vec3(0.13, 0.17, 0.45);
// Lights go to this colour.
uniform vec3 light_color : source_color = vec3(1.0, 0.85, 0.42);
// How much the shadows and the lights go to these colours.
uniform float complement : hint_range(0.0, 1.0) = 0.45;
// Dark, broken outlines at the edges of the shapes.
uniform float outline : hint_range(0.0, 1.0) = 0.3;
// The edge strength where outlines start.
uniform float outline_threshold : hint_range(0.02, 1.0) = 0.25;
uniform vec3 outline_color : source_color = vec3(0.06, 0.07, 0.16);
group_uniforms;

group_uniforms motion;
// The strokes change this many times per second (hand-drawn "boil"). 0 = still.
uniform float boil_fps : hint_range(0.0, 12.0) = 0.0;
group_uniforms;

// A stroke moves at most this part of its grid cell from the cell centre.
const float CELL_JITTER = 0.3;

// --- Hash and noise ---------------------------------------------------------
// Hashes without sin(), so they give the same result on all GPUs.

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec4 hash42(vec2 p) {
	vec4 p4 = fract(vec4(p.xyxy) * vec4(0.1031, 0.1030, 0.0973, 0.1099));
	p4 += dot(p4, p4.wzxy + 33.33);
	return fract((p4.xxyz + p4.yzzw) * p4.zywx);
}

float vnoise1(float x) {
	float i = floor(x);
	float f = fract(x);
	float u = f * f * (3.0 - 2.0 * f);
	return mix(hash12(vec2(i, 0.0)), hash12(vec2(i + 1.0, 0.0)), u);
}

float vnoise2(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Value noise with its derivatives: (value, d/dx, d/dy).
vec3 vnoise2_d(vec2 x) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	vec2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	float k1 = b - a;
	float k2 = c - a;
	float k4 = a - b - c + d;
	return vec3(a + k1 * u.x + k2 * u.y + k4 * u.x * u.y,
			du * vec2(k1 + k4 * u.y, k2 + k4 * u.x));
}

// --- Helpers ----------------------------------------------------------------

float luma(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// Reads the screen at a position in pixels.
vec3 screen_at(vec2 pix, vec2 px, float lod) {
	vec2 uv = clamp(pix * px, vec2(0.0), vec2(1.0));
	return textureLod(screen_tex, uv, lod).rgb;
}

// The colour difference, relative to the light. In dark areas a small
// difference counts more (dark lamp post on a dark street).
float color_diff(vec3 a, vec3 b) {
	return distance(a, b) / (0.25 + max(luma(a), luma(b)));
}

vec3 soft_light(vec3 a, vec3 b) {
	return mix(2.0 * a * b + a * a * (1.0 - 2.0 * b),
			sqrt(a) * (2.0 * b - 1.0) + 2.0 * a * (1.0 - b),
			step(vec3(0.5), b));
}

// The swirl direction at q (q is in screen heights). The direction goes
// along the contour lines of a noise, so it turns around in closed loops.
vec2 swirl_dir(vec2 q, float t) {
	vec2 p = q * swirl_scale + vec2(t, -0.7 * t);
	vec3 n1 = vnoise2_d(p);
	vec3 n2 = vnoise2_d(p * 2.03 + vec2(5.2, 1.3));
	vec2 grad = n1.yz + n2.yz;
	vec2 d = vec2(-grad.y, grad.x);
	return d / max(length(d), 1e-5);
}

// The stroke direction at pix. gx and gy are the colour changes along x
// and y. The directions are mixed as "doubled angles", because a stroke
// that goes left is the same as a stroke that goes right.
vec2 stroke_dir(vec2 pix, float unit, vec3 gx, vec3 gy, float t) {
	float e = dot(gx, gx);
	float f = dot(gx, gy);
	float g = dot(gy, gy);
	// Along the edge (perpendicular to the colour gradient).
	vec2 edge2 = vec2(g - e, -2.0 * f);
	float edge_len = length(edge2);
	float edge_w = follow_edges * smoothstep(0.0004, 0.006, edge_len);

	vec2 s = swirl_dir(pix / unit, t);
	vec2 swirl2 = vec2(s.x * s.x - s.y * s.y, 2.0 * s.x * s.y);
	float h = radians(hatch_angle) * 2.0;
	vec2 hatch2 = vec2(cos(h), sin(h));

	vec2 d2 = mix(hatch2, swirl2, swirl);
	d2 = mix(d2, edge2 / max(edge_len, 1e-6), edge_w);
	float a = 0.5 * atan(d2.y, d2.x + 1e-6);
	return vec2(cos(a), sin(a));
}

// Paints one layer of strokes. It keeps the two strokes with the highest
// priority that touch this pixel: top_* and sec_* (colour + alpha, and
// priority + paint height).
void paint_layer(vec2 pix, vec2 px, float unit, float w, vec2 seed, vec2 shift,
		float prio_add, float density_flat, float density_detail, float layer_alpha, vec3 local,
		float t, inout vec4 top_c, inout vec2 top_ph, inout vec4 sec_c, inout vec2 sec_ph) {
	float len = w * stroke_length;
	// The cell is large enough that only the 3 x 3 cells around the pixel
	// can have a stroke that touches it (stroke radius <= 0.6 len + 0.15 w).
	float cell = (0.6 * len + 0.15 * w + 1.0) / (1.5 - CELL_JITTER);
	vec2 base = floor((pix + shift) / cell);
	// The direction comes from a blurred image (stable), the colour from a
	// nearly sharp one (clean colours, thin things keep their colour).
	float lod = log2(max(w * 0.5, 1.0));
	float lod_col = log2(max(w * 0.2, 1.0));
	float step_px = w * 0.6;
	float clip = mix(1.2, 0.15, edge_respect);
	// The farthest that any stroke can reach from its centre
	// (half length + ragged edge + antialiasing).
	float reach = 0.5 * len * (1.0 + 0.2 * stroke_jitter) + 0.125 * w + 1.0;

	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 id = base + vec2(float(i), float(j));
			vec4 r1 = hash42(id + seed);
			vec2 center = (id + 0.5 + (r1.xy - 0.5) * 2.0 * CELL_JITTER * stroke_jitter) * cell - shift;
			// Skip strokes that cannot touch this pixel, or that do not
			// exist, before any texture read. About half of them.
			if (distance(pix, center) > reach || r1.z >= density_detail) {
				continue;
			}
			vec4 r2 = hash42(id + seed + vec2(19.19, 7.31));
			vec4 r3 = hash42(id + seed + vec2(3.71, 41.3));

			vec3 c0 = screen_at(center, px, lod);
			vec3 gx = screen_at(center + vec2(step_px, 0.0), px, lod) - c0;
			vec3 gy = screen_at(center + vec2(0.0, step_px), px, lod) - c0;

			// Small strokes: few in flat areas, many where there is detail.
			float detail = smoothstep(0.05, 0.22, length(gx) + length(gy));
			if (r1.z >= mix(density_flat, density_detail, detail)) {
				continue;
			}

			vec2 dir = stroke_dir(center, unit, gx, gy, t);
			float ang = (r1.w - 0.5) * 2.0 * angle_jitter;
			dir = vec2(dir.x * cos(ang) - dir.y * sin(ang), dir.x * sin(ang) + dir.y * cos(ang));
			if (r2.x < 0.5) {
				dir = -dir; // The thick start of the stroke is on a random side.
			}
			vec2 perp = vec2(-dir.y, dir.x);
			vec2 d = pix - center;
			float u = dot(d, dir);
			float v = dot(d, perp);

			float half_len = 0.5 * len * (1.0 + (r2.y - 0.5) * 0.4 * stroke_jitter);
			float half_w = 0.5 * w * (1.0 + (r2.z - 0.5) * 0.4 * stroke_jitter);
			float t01 = clamp(u / half_len * 0.5 + 0.5, 0.0, 1.0); // 0 = start, 1 = end
			float hw = half_w * mix(1.0, 0.7, t01 * t01); // The stroke gets thinner at the end.
			float rag = (vnoise1(u / w * 2.5 + r2.w * 31.0) - 0.5) * 0.25 * w; // Ragged edge.
			float core = max(half_len - hw, 0.0);
			float dist = length(vec2(max(abs(u) - core, 0.0), v)) - hw - rag;
			float a = 1.0 - smoothstep(-0.75, 0.75, dist); // About 1.5 px of antialiasing.
			if (a <= 0.002) {
				continue;
			}

			// Bristles: lines along the stroke. At the dry end some leave gaps.
			float bristle = vnoise1(v / w * 4.5 + r3.w * 57.0);
			float dry = bristles * smoothstep(0.35, 1.0, t01);
			a *= 1.0 - dry * (1.0 - smoothstep(0.3, 0.55, bristle));
			// The colour of the stroke. Read only for strokes that touch the pixel.
			vec3 c_stroke = screen_at(center, px, lod_col);
			// The stroke does not paint over a very different colour.
			a *= layer_alpha * (1.0 - smoothstep(clip * 0.5, clip, color_diff(c_stroke, local)));
			if (a <= 0.002) {
				continue;
			}

			// Paint height: round across the stroke, a blob at the start.
			// It does not go down to 0 at the border, so the borders are
			// small steps, not deep grooves.
			float across = clamp(v / max(hw, 1e-3), -1.0, 1.0);
			float h = 0.5 + 0.5 * sqrt(1.0 - across * across);
			h *= 0.75 + 0.25 * mix(1.0, bristle, bristles);
			h += 0.3 * (1.0 - smoothstep(0.0, 0.25, t01));
			h *= 0.85 + 0.3 * r3.y;

			vec3 c = c_stroke * (1.0 + (r3.x - 0.5) * 2.0 * color_jitter);
			c += (r2.w - 0.5) * color_jitter * vec3(0.5, 0.0, -0.5); // Warmer or cooler.
			float p = r3.z + prio_add;

			if (p > top_ph.x) {
				sec_c = top_c;
				sec_ph = top_ph;
				top_c = vec4(c, a);
				top_ph = vec2(p, h);
			} else if (p > sec_ph.x) {
				sec_c = vec4(c, a);
				sec_ph = vec2(p, h);
			}
		}
	}
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec2 res = 1.0 / px;
	float unit = res.y; // Pixels in one screen height.
	vec2 pix = SCREEN_UV * res; // This pixel, in pixels.
	vec3 original = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;

	float w = max(brush_size * unit, 2.0); // Large stroke width in pixels.
	float t = TIME * swirl_speed;
	float boil = boil_fps > 0.0 ? mod(floor(TIME * boil_fps), 61.0) : 0.0;
	vec2 seed = vec2(boil * 7.31, boil * 3.17);

	// A blur of about 2 px at 1080p, the same part of the screen at all resolutions.
	float lod_fine = log2(max(unit / 540.0, 1.0));

	// --- Direction and edges at this pixel ---
	float lod_c = log2(max(w * 0.5, 1.0));
	float sp = w * 0.6;
	// The nearly sharp colour of this pixel. Strokes of a very different
	// colour do not paint here, so thin things (lamp posts, people) stay.
	vec3 local = screen_at(pix, px, lod_fine);
	vec3 gx = screen_at(pix + vec2(sp, 0.0), px, lod_c) - screen_at(pix - vec2(sp, 0.0), px, lod_c);
	vec3 gy = screen_at(pix + vec2(0.0, sp), px, lod_c) - screen_at(pix - vec2(0.0, sp), px, lod_c);
	float edge_mag = length(gx) + length(gy);
	vec2 dir_p = stroke_dir(pix, unit, gx * 0.5, gy * 0.5, t);
	// Small detail: the sharp colour is far from the blurred colour.
	float small_detail = smoothstep(0.08, 0.25, color_diff(local, screen_at(pix, px, lod_c)));
	float coarse_alpha = 1.0 - detail_keep * small_detail;

	// --- 1. Underpainting: smear along the stroke direction ---
	// Colour weights fall off with the colour difference, so the smear
	// does not cross edges.
	float lod_u = lod_fine;
	vec3 c_mid = local;
	vec3 under = c_mid;
	float wsum = 1.0;
	float len_u = w * stroke_length * 0.5 * underpaint_smear;
	float streak = vnoise2(pix / (w * 0.3));
	for (int k = 1; k <= 3; k++) {
		float o = float(k) / 3.0 * len_u;
		float kw = 1.0 - float(k) * 0.2;
		vec2 off = dir_p * o;
		vec3 ca = screen_at(pix + off, px, lod_u);
		vec3 cb = screen_at(pix - off, px, lod_u);
		float wa = kw * exp(-dot(ca - c_mid, ca - c_mid) * 12.0);
		float wb = kw * exp(-dot(cb - c_mid, cb - c_mid) * 12.0);
		under += ca * wa + cb * wb;
		wsum += wa + wb;
		streak += vnoise2((pix + off) / (w * 0.3)) + vnoise2((pix - off) / (w * 0.3));
	}
	under /= wsum;
	streak = clamp((streak / 7.0 - 0.5) * 2.5 + 0.5, 0.0, 1.0); // Lines along the smear.
	float under_h = 0.25 + 0.35 * streak;

	// --- 2. Strokes ---
	vec4 top_c = vec4(0.0);
	vec2 top_ph = vec2(-1.0, 0.0);
	vec4 sec_c = vec4(0.0);
	vec2 sec_ph = vec2(-1.0, 0.0);
	paint_layer(pix, px, unit, w, seed + vec2(0.0, 0.0), vec2(0.0),
			0.0, 1.0, 1.0, coarse_alpha, local, t, top_c, top_ph, sec_c, sec_ph);
	paint_layer(pix, px, unit, w, seed + vec2(113.0, 71.0), vec2(0.5 * w * stroke_length, 0.37 * w * stroke_length),
			0.0, 1.0, 1.0, coarse_alpha, local, t, top_c, top_ph, sec_c, sec_ph);
	if (fine_strokes > 0.0) {
		paint_layer(pix, px, unit, w * 0.55, seed + vec2(37.0, 191.0), vec2(0.0),
				1.0, fine_strokes * 0.25, fine_strokes, 1.0, local, t, top_c, top_ph, sec_c, sec_ph);
	}

	vec3 col = mix(under, sec_c.rgb, sec_c.a);
	float height = mix(under_h, sec_ph.y, sec_c.a);
	col = mix(col, top_c.rgb, top_c.a);
	height = mix(height, top_ph.y, top_c.a);

	// --- 3. Outlines, broken like a brush line ---
	float line = smoothstep(outline_threshold, outline_threshold * 2.5, edge_mag) * outline;
	line *= 0.55 + 0.45 * streak;
	col = mix(col, outline_color, line);

	// --- Colour ---
	col = clamp(col, 0.0, 1.0);
	float l = luma(col);
	col = clamp(mix(vec3(l), col, saturation), 0.0, 1.0);
	if (value_steps > 0.5) {
		// Soft steps around the centre of each band, so darks do not become black.
		float x = l * value_steps - 0.5;
		float s = 0.5 * max(step_softness, 0.01);
		float lq = (floor(x) + smoothstep(0.5 - s, 0.5 + s, fract(x)) + 0.5) / value_steps;
		col = clamp(col * min(lq / max(l, 1e-3), 3.0), 0.0, 1.0);
		l = luma(col);
	}
	vec3 tone = mix(shadow_color, light_color, smoothstep(0.15, 0.75, l));
	col = mix(col, soft_light(col, tone), complement);

	// --- Light on the paint relief, and the canvas ---
	float grain_px = max(unit * 0.0028, 1.0);
	vec2 gp = pix / grain_px;
	height += canvas_grain * 0.04 * (sin(gp.x * PI) * sin(gp.y * PI) + vnoise2(gp * 1.4) - 0.5);
	// Height change over half a stroke width, so the relief has the same
	// look at all resolutions.
	vec2 slope = vec2(dFdx(height), dFdy(height)) * w * 0.5;
	slope *= min(1.0, 1.2 / max(length(slope), 1e-4)); // No spikes at stroke borders.
	slope *= impasto;
	float la = radians(light_angle);
	vec3 ldir = normalize(vec3(cos(la), sin(la), 1.2));
	// Not normalized on purpose: the shade is linear in the slope, so on
	// average the image does not get darker. 1.0 on a flat surface.
	float diffuse = clamp(1.0 - dot(slope, ldir.xy) / ldir.z, 0.45, 1.6);
	vec3 n = normalize(vec3(-slope, 1.0));
	float spec = pow(max(dot(reflect(-ldir, n), vec3(0.0, 0.0, 1.0)), 0.0), 20.0);
	col = col * diffuse + vec3(spec * 0.12 * impasto);
	// Canvas colour: a little lighter and darker in the weave.
	col *= 1.0 + canvas_grain * 0.08 * (vnoise2(gp * 0.7) - 0.5);

	COLOR = vec4(mix(original, clamp(col, 0.0, 1.0), intensity), COLOR.a);
}
