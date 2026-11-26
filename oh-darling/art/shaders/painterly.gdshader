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
//    painterly_camera.gd (in mood_filter.tscn) sets the "camera" uniforms
//    every frame. Do not set them by hand.
//
//  HOW IT WORKS (one pass, no extra viewport)
//    1. Underpainting: the image is smeared along the stroke direction.
//    2. Strokes: layers of single brush strokes on a jittered grid
//       (2 large layers, 1 small layer only where there is detail).
//       Each stroke takes ONE colour from its centre, and turns with the
//       edges of the image and with a swirl field.
//    3. Outlines, colour (saturation, value steps, warm lights and cool
//       shadows), then light on the paint relief and the canvas grain.
//
//  THE STROKES STAY ON THE WORLD (like the dithering of Obra Dinn)
//    The grid of the strokes, the swirls, the bristle lines and the canvas
//    are not in screen space. They are on the ground plane at the height of
//    the player, in metres ("anchor space"). When the camera moves, the
//    strokes move with the ground.
//    - The ground is exact. Things above the ground (walls, people) drift a
//      little (about 10% of the camera movement for a 3 m wall), because
//      the shader has no depth buffer.
//    - Zoom: strokes come in two sizes (octaves), 2x apart. When the camera
//      zooms, one octave fades out and the other fades in, stroke by
//      stroke. So the strokes stay on the world, and their size on screen
//      stays near brush_size (0.78x to 1.27x).
//    - Without camera data (cam_valid = false, for example a 2D test scene)
//      the pattern is in screen space.
//
//  SIZES DO NOT DEPEND ON THE RESOLUTION
//    brush_size is a part of the SCREEN HEIGHT (0.01 = 1%). The direction
//    of a stroke comes from a mipmap level that matches the stroke size, so
//    the strokes do not flicker. Tested in town_hills at zoom 0.45, 1.0 and
//    1.4, at 720p and 1080p.
//
//  QUALITY (uniform "quality", set by painterly_camera.gd, auto by FPS)
//    GPU time of the filter at 1080p on an RTX 5060 Ti (zoom 1.0 / during
//    the octave fade). A GTX 750 Ti is about 20x slower.
//      2 high:   2.6 / 3.3 ms. Each stroke finds its own direction.
//      1 medium: 2.1 / 2.7 ms. All strokes take the flow of the pixel
//                ("fast" mode: they bend along the flow), short fade.
//      0 low:    1.2 / 1.2 ms. Fast mode, 1 layer of large strokes, no small
//                strokes, no ragged edges, no fade (instant octave switch).
//    The base (screen copy + mipmaps, underpainting, relief) is ~0.5 ms.
//
//  RULES
//    - It ends with COLOR = vec4(..., COLOR.a), so the mood fade works.
//    - The loops have a fixed size. Strokes that cannot touch the pixel are
//      skipped before any texture read.
//    - Compute the second octave only when weight_b > 0 (it is 0 most of
//      the time): mix(a, b, 0.0) still pays for b.
// ==============================================================================
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;

// 0 = no effect, 1 = full effect.
uniform float intensity : hint_range(0.0, 1.0) = 1.0;

group_uniforms brush;
// The width of a large stroke on screen, as a part of the screen height.
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
// The size of one swirl on the ground, in metres.
uniform float swirl_size : hint_range(1.0, 30.0, 0.1) = 4.5;
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

// Set every frame by painterly_camera.gd. Do not set them by hand.
group_uniforms camera;
uniform bool cam_valid = false;
uniform vec3 cam_origin = vec3(0.0);
uniform vec3 cam_right = vec3(1.0, 0.0, 0.0);
uniform vec3 cam_up = vec3(0.0, 1.0, 0.0);
// Camera +Z (the camera looks along -Z). Its y must be > 0 (looks down).
uniform vec3 cam_back = vec3(0.0, 0.0, 1.0);
// tan(vertical field of view / 2).
uniform float cam_tan_half_fov = 0.2;
// The height (world y) of the ground plane where the pattern lives.
uniform float plane_height = 0.0;
// 0 = low, 1 = medium, 2 = high. See QUALITY in the banner.
uniform int quality = 2;
group_uniforms;

// A stroke moves at most this part of its grid cell from the cell centre.
const float CELL_JITTER = 0.3;
// Without camera data, the screen is this many "metres" high.
const float FALLBACK_SCREEN_M = 10.0;

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

// --- Anchor space ------------------------------------------------------------
// A point of anchor space (metres) is a point of the ground plane, given by
// its position along cam_right and cam_up. The camera never turns, so a
// ground point keeps the same anchor coordinates when the camera moves.
// On screen, anchor x goes right and anchor y goes UP (screen y goes down).

// The depth of the ground point at the screen centre.
float ref_depth() {
	return max((cam_origin.y - plane_height) / max(cam_back.y, 0.05), 0.5);
}

// Pixels per metre at this depth.
float ppm_at(float depth, vec2 res) {
	if (!cam_valid) {
		return res.y / FALLBACK_SCREEN_M;
	}
	return res.y * 0.5 / (cam_tan_half_fov * depth);
}

// Screen pixel -> anchor space. depth = the depth of the ground point.
vec2 pix_to_anchor(vec2 pix, vec2 res, out float depth) {
	if (!cam_valid) {
		depth = 1.0;
		return vec2(pix.x, -pix.y) * (FALLBACK_SCREEN_M / res.y);
	}
	vec2 ndc = vec2(pix.x / res.x * 2.0 - 1.0, 1.0 - pix.y / res.y * 2.0);
	// One unit of t along this ray is one metre of depth.
	vec3 d = cam_right * (ndc.x * cam_tan_half_fov * res.x / res.y)
			+ cam_up * (ndc.y * cam_tan_half_fov) - cam_back;
	float t = (plane_height - cam_origin.y) / min(d.y, -1e-4);
	t = clamp(t, 0.1, ref_depth() * 4.0); // Rays near the horizon.
	depth = t;
	vec3 p = cam_origin + d * t;
	return vec2(dot(p, cam_right), dot(p, cam_up));
}

// Anchor space -> screen pixel. depth = the depth of the ground point.
vec2 anchor_to_pix(vec2 a, vec2 res, out float depth) {
	if (!cam_valid) {
		depth = 1.0;
		return vec2(a.x, -a.y) * (res.y / FALLBACK_SCREEN_M);
	}
	// The ground point with these anchor coordinates.
	float s = (plane_height - a.x * cam_right.y - a.y * cam_up.y) / max(cam_back.y, 0.05);
	vec3 rel = a.x * cam_right + a.y * cam_up + s * cam_back - cam_origin;
	depth = max(-dot(rel, cam_back), 0.1);
	vec2 ndc = vec2(dot(rel, cam_right) / (res.x / res.y), dot(rel, cam_up))
			/ (depth * cam_tan_half_fov);
	return vec2((ndc.x + 1.0) * 0.5 * res.x, (1.0 - ndc.y) * 0.5 * res.y);
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

// The swirl direction ON SCREEN at the anchor point a. The direction goes
// along the contour lines of a noise, so it turns around in closed loops.
vec2 swirl_dir(vec2 a, float t) {
	vec2 p = a / swirl_size + vec2(t, -0.7 * t);
	vec3 n1 = vnoise2_d(p);
	vec3 n2 = vnoise2_d(p * 2.03 + vec2(5.2, 1.3));
	vec2 grad = n1.yz + n2.yz;
	vec2 d = vec2(-grad.y, grad.x);
	d = vec2(d.x, -d.y); // Anchor y goes up, screen y goes down.
	return d / max(length(d), 1e-5);
}

// The direction of the swirl and the hatching at the anchor point a, as a
// "doubled angle" (a stroke that goes left is the same as a stroke that goes
// right). It changes over metres, so the shader computes it once for each
// pixel, not once for each stroke (a large saving).
vec2 flow2_at(vec2 a, float t) {
	vec2 s = swirl_dir(a, t);
	vec2 swirl2 = vec2(s.x * s.x - s.y * s.y, 2.0 * s.x * s.y);
	float h = radians(hatch_angle) * 2.0;
	return mix(vec2(cos(h), sin(h)), swirl2, swirl);
}

// The stroke direction on screen. flow2 comes from flow2_at(). gx and gy
// are the colour changes along screen x and y: the stroke turns along the
// edges of the image.
vec2 stroke_dir(vec2 flow2, vec3 gx, vec3 gy) {
	float e = dot(gx, gx);
	float f = dot(gx, gy);
	float g = dot(gy, gy);
	// Along the edge (perpendicular to the colour gradient).
	vec2 edge2 = vec2(g - e, -2.0 * f);
	float edge_len = length(edge2);
	float edge_w = follow_edges * smoothstep(0.0004, 0.006, edge_len);
	vec2 d2 = mix(flow2, edge2 / max(edge_len, 1e-6), edge_w);
	float ang = 0.5 * atan(d2.y, d2.x + 1e-6);
	return vec2(cos(ang), sin(ang));
}

// The canvas weave and bumps at the anchor point a, for a weave cell of
// "cell" metres.
float canvas_at(vec2 a, float cell) {
	vec2 gp = a / cell;
	return sin(gp.x * PI) * sin(gp.y * PI) + vnoise2(gp * 1.4) - 0.5;
}

// Paints one layer of strokes of width sm (metres). The grid is in anchor
// space, so the strokes stay on the world. The shape is tested on screen.
// weight: 1 = all strokes of the layer, 0 = none (octave fade).
// It keeps the two strokes with the highest priority that touch this
// pixel: top_* and sec_* (colour + alpha, and priority + paint height).
// fast = false (high quality): each stroke reads the image at its centre to
//   find its own direction (3 texture reads for each nearby stroke).
// fast = true (medium, low): each stroke uses the direction of the flow at
//   this pixel (dir_pix), and the projection is linear near the pixel (jac,
//   pix0). Only strokes that touch the pixel read the image (1 read). The
//   strokes bend along the flow.
void paint_layer(vec2 pix, vec2 a_pix, vec2 px, vec2 res, float ppm_ref, float sm,
		float weight, vec2 seed, vec2 shift, float prio_add, float density_flat,
		float density_detail, float layer_alpha, vec3 local, vec2 flow2,
		bool fast, vec2 dir_pix, mat2 jac, vec2 pix0, float ppm_pix, float pix_detail,
		inout vec4 top_c, inout vec2 top_ph, inout vec4 sec_c, inout vec2 sec_ph) {
	// The farthest that any stroke can reach from its centre (half length +
	// ragged edge + antialiasing), with a margin for the perspective.
	float reach_m = (0.5 * sm * stroke_length * (1.0 + 0.2 * stroke_jitter) + 0.125 * sm) * 1.05
			+ 1.5 / ppm_ref;
	// The cell is large enough that only the 3 x 3 cells around the pixel
	// can have a stroke that touches it.
	float cell = reach_m / (1.5 - CELL_JITTER);
	vec2 base = floor((a_pix + shift) / cell);
	float clip = mix(1.2, 0.15, edge_respect);

	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 id = base + vec2(float(i), float(j));
			vec4 r1 = hash42(id + seed);
			float r_fade = hash12(id + seed + vec2(77.7, 13.1));
			// Skip strokes that do not exist before any other work.
			if (r1.z >= density_detail || r_fade >= weight) {
				continue;
			}
			vec2 center_a = (id + 0.5 + (r1.xy - 0.5) * 2.0 * CELL_JITTER * stroke_jitter) * cell - shift;
			vec2 center;
			float w; // Stroke width on screen (pixels).
			if (fast) {
				center = pix0 + jac * (center_a - a_pix);
				w = sm * ppm_pix;
			} else {
				float depth_c;
				center = anchor_to_pix(center_a, res, depth_c);
				w = sm * ppm_at(depth_c, res);
			}
			float len = w * stroke_length;
			// Skip strokes that cannot touch this pixel, before any texture read.
			if (distance(pix, center) > 0.5 * len * (1.0 + 0.2 * stroke_jitter) + 0.125 * w + 1.0) {
				continue;
			}
			vec4 r2 = hash42(id + seed + vec2(19.19, 7.31));
			vec4 r3 = hash42(id + seed + vec2(3.71, 41.3));

			vec2 dir;
			float detail;
			if (fast) {
				dir = dir_pix;
				detail = pix_detail;
			} else {
				// The direction comes from a blurred image (stable).
				float lod = log2(max(w * 0.5, 1.0));
				float step_px = w * 0.6;
				vec3 c0 = screen_at(center, px, lod);
				vec3 gx = screen_at(center + vec2(step_px, 0.0), px, lod) - c0;
				vec3 gy = screen_at(center + vec2(0.0, step_px), px, lod) - c0;
				detail = smoothstep(0.05, 0.22, length(gx) + length(gy));
				dir = stroke_dir(flow2, gx, gy);
			}

			// Small strokes: few in flat areas, many where there is detail.
			// In fast mode "detail" is the detail at this pixel, so the
			// stroke fades softly (a hard test would cut the stroke).
			float density = mix(density_flat, density_detail, detail);
			float density_alpha = 1.0;
			if (density < 1.0) {
				if (fast) {
					density_alpha = smoothstep(-0.08, 0.08, density - r1.z);
					if (density_alpha <= 0.0) {
						continue;
					}
				} else if (r1.z >= density) {
					continue;
				}
			}

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
			// Ragged edge (not in low quality).
			float rag = quality > 0 ? (vnoise1(u / w * 2.5 + r2.w * 31.0) - 0.5) * 0.25 * w : 0.0;
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
			// Octave fade: each stroke fades in over a short part of the zoom.
			if (weight < 0.999) {
				a *= smoothstep(0.0, 0.08, weight - r_fade);
			}
			// The colour of the stroke (from a nearly sharp image: clean colours,
			// thin things keep theirs). Read only for strokes that touch the pixel.
			vec3 c_stroke = screen_at(center, px, log2(max(w * 0.2, 1.0)));
			// The stroke does not paint over a very different colour.
			a *= layer_alpha * density_alpha * (1.0 - smoothstep(clip * 0.5, clip, color_diff(c_stroke, local)));
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

// Paints one octave: 1 or 2 layers of large strokes (quality), and a layer
// of small ones with the alpha fine_alpha (skipped when it is 0).
void paint_octave(vec2 pix, vec2 a_pix, vec2 px, vec2 res, float ppm_ref, float sm,
		float weight, vec2 seed, float coarse_alpha, float fine_alpha, vec3 local, vec2 flow2,
		bool fast, vec2 dir_pix, mat2 jac, vec2 pix0, float ppm_pix, float pix_detail,
		inout vec4 top_c, inout vec2 top_ph, inout vec4 sec_c, inout vec2 sec_ph) {
	paint_layer(pix, a_pix, px, res, ppm_ref, sm, weight, seed, vec2(0.0),
			0.0, 1.0, 1.0, coarse_alpha, local, flow2,
			fast, dir_pix, jac, pix0, ppm_pix, pix_detail, top_c, top_ph, sec_c, sec_ph);
	if (quality > 0) {
		paint_layer(pix, a_pix, px, res, ppm_ref, sm, weight, seed + vec2(113.0, 71.0),
				vec2(0.5, 0.37) * sm * stroke_length, 0.0, 1.0, 1.0, coarse_alpha, local, flow2,
				fast, dir_pix, jac, pix0, ppm_pix, pix_detail, top_c, top_ph, sec_c, sec_ph);
	}
	if (fine_alpha > 0.0) {
		paint_layer(pix, a_pix, px, res, ppm_ref, sm * 0.55, weight, seed + vec2(37.0, 191.0), vec2(0.0),
				1.0, fine_strokes * 0.25, fine_strokes, fine_alpha, local, flow2,
				fast, dir_pix, jac, pix0, ppm_pix, pix_detail, top_c, top_ph, sec_c, sec_ph);
	}
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec2 res = 1.0 / px;
	vec2 pix = SCREEN_UV * res; // This pixel, in pixels.
	vec3 original = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;

	float t = TIME * swirl_speed;
	float boil = boil_fps > 0.0 ? mod(floor(TIME * boil_fps), 61.0) : 0.0;
	vec2 seed = vec2(boil * 7.31, boil * 3.17);

	// --- Anchor space and the two octaves ---
	float depth_p;
	vec2 a_pix = pix_to_anchor(pix, res, depth_p);
	float ppm_pix = ppm_at(depth_p, res);
	float ppm_ref = cam_valid ? ppm_at(ref_depth(), res) : res.y / FALLBACK_SCREEN_M;
	// The stroke width (metres) that gives brush_size on screen at the centre.
	float s_want = brush_size * res.y / ppm_ref;
	float level = log2(s_want);
	float s_a = exp2(floor(level));
	float s_b = s_a * 2.0;
	// The octave fade: during the fade, both octaves are painted (2x work).
	// Lower quality: a shorter fade (low: an instant switch).
	float fade_half = quality == 2 ? 0.15 : (quality == 1 ? 0.05 : 0.0);
	float weight_b = fade_half > 0.0
			? smoothstep(0.5 - fade_half, 0.5 + fade_half, fract(level))
			: step(0.5, fract(level));
	if (!cam_valid) {
		// No zoom in screen space: one octave with the exact size.
		s_a = s_want;
		weight_b = 0.0;
	}
	float weight_a = 1.0 - weight_b;

	float w = max(s_want * ppm_pix, 2.0); // Large stroke width here, in pixels.
	// The "nearly sharp" mip level: 0 at 1080p, 1 at 4K (the same part of the
	// screen). Not more: Godot blurs the 2D screen mipmaps with a Gaussian, so
	// level 1 at 1080p already mixes a bright outline into a thin dark body.
	float lod_fine = log2(max(res.y / 1080.0, 1.0));

	// --- Direction and edges at this pixel ---
	float lod_c = log2(max(w * 0.5, 1.0));
	float sp = w * 0.6;
	// The nearly sharp colour of this pixel. Strokes of a very different
	// colour do not paint here, so thin things (lamp posts, people) stay.
	vec3 local = screen_at(pix, px, lod_fine);
	vec3 gx = screen_at(pix + vec2(sp, 0.0), px, lod_c) - screen_at(pix - vec2(sp, 0.0), px, lod_c);
	vec3 gy = screen_at(pix + vec2(0.0, sp), px, lod_c) - screen_at(pix - vec2(0.0, sp), px, lod_c);
	float edge_mag = length(gx) + length(gy);
	vec2 flow2 = flow2_at(a_pix, t);
	vec2 dir_p = stroke_dir(flow2, gx * 0.5, gy * 0.5);
	// Small detail: the sharp colour is far from the blurred colour.
	float small_detail = smoothstep(0.08, 0.25, color_diff(local, screen_at(pix, px, lod_c)));
	float coarse_alpha = 1.0 - detail_keep * small_detail;
	// Small strokes only near detail or edges (not on flat ground), and not
	// in low quality. They fade out softly toward flat ground.
	float fine_alpha = (fine_strokes > 0.0 && quality > 0)
			? max(smoothstep(0.02, 0.06, edge_mag), small_detail) : 0.0;
	// Fast mode (medium, low): the direction of all strokes comes from this
	// pixel, and the projection is linear near this pixel.
	bool fast = quality < 2;
	float pix_detail = max(smoothstep(0.1, 0.44, edge_mag), small_detail);
	mat2 jac = mat2(1.0);
	vec2 pix0 = pix;
	if (fast) {
		float dd;
		pix0 = anchor_to_pix(a_pix, res, dd);
		jac = mat2((anchor_to_pix(a_pix + vec2(0.05, 0.0), res, dd) - pix0) / 0.05,
				(anchor_to_pix(a_pix + vec2(0.0, 0.05), res, dd) - pix0) / 0.05);
	}

	// --- 1. Underpainting: smear along the stroke direction ---
	// Colour weights fall off with the colour difference, so the smear
	// does not cross edges. The streak lines are in anchor space.
	vec3 under = local;
	float wsum = 1.0;
	float len_u = w * stroke_length * 0.5 * underpaint_smear;
	vec2 sa = vec2(1.0 / (s_a * 0.3));
	vec2 sb = vec2(1.0 / (s_b * 0.3));
	// The second octave only when it is visible (it is 0 most of the time).
	bool two = weight_b > 0.0;
	float streak = two ? mix(vnoise2(a_pix * sa), vnoise2(a_pix * sb), weight_b) : vnoise2(a_pix * sa);
	// Samples on each side: high 3, medium 2, low 1.
	int steps = quality + 1;
	for (int k = 1; k <= steps; k++) {
		float o = float(k) / float(steps) * len_u;
		float kw = 1.0 - float(k) / float(steps) * 0.6;
		vec2 off = dir_p * o;
		vec3 ca = screen_at(pix + off, px, lod_fine);
		vec3 cb = screen_at(pix - off, px, lod_fine);
		float wa = kw * exp(-dot(ca - local, ca - local) * 12.0);
		float wb = kw * exp(-dot(cb - local, cb - local) * 12.0);
		under += ca * wa + cb * wb;
		wsum += wa + wb;
		vec2 off_a = vec2(off.x, -off.y) / ppm_pix;
		float s_oct_a = vnoise2((a_pix + off_a) * sa) + vnoise2((a_pix - off_a) * sa);
		streak += !two ? s_oct_a : mix(s_oct_a,
				vnoise2((a_pix + off_a) * sb) + vnoise2((a_pix - off_a) * sb), weight_b);
	}
	under /= wsum;
	// Lines along the smear. The average of fewer samples has more contrast,
	// so the gain goes with sqrt(samples): the same look as 7 samples.
	float n_streak = float(1 + 2 * steps);
	streak = clamp((streak / n_streak - 0.5) * 2.5 * sqrt(n_streak / 7.0) + 0.5, 0.0, 1.0);
	float under_h = 0.25 + 0.35 * streak;

	// --- 2. Strokes ---
	vec4 top_c = vec4(0.0);
	vec2 top_ph = vec2(-1.0, 0.0);
	vec4 sec_c = vec4(0.0);
	vec2 sec_ph = vec2(-1.0, 0.0);
	if (weight_a > 0.0) {
		paint_octave(pix, a_pix, px, res, ppm_ref, s_a, weight_a, seed, coarse_alpha, fine_alpha,
				local, flow2, fast, dir_p, jac, pix0, ppm_pix, pix_detail, top_c, top_ph, sec_c, sec_ph);
	}
	if (weight_b > 0.0) {
		paint_octave(pix, a_pix, px, res, ppm_ref, s_b, weight_b, seed + vec2(503.0, 307.0), coarse_alpha,
				fine_alpha, local, flow2, fast, dir_p, jac, pix0, ppm_pix, pix_detail,
				top_c, top_ph, sec_c, sec_ph);
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

	// --- Light on the paint relief, and the canvas (on the world too) ---
	float grain = canvas_at(a_pix, s_a * 0.25);
	if (two) {
		grain = mix(grain, canvas_at(a_pix, s_b * 0.25), weight_b);
	}
	height += canvas_grain * 0.04 * grain;
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
	if (quality > 0) {
		float tint = vnoise2(a_pix / (s_a * 0.36));
		if (two) {
			tint = mix(tint, vnoise2(a_pix / (s_b * 0.36)), weight_b);
		}
		col *= 1.0 + canvas_grain * 0.08 * (tint - 0.5);
	}

	COLOR = vec4(mix(original, clamp(col, 0.0, 1.0), intensity), COLOR.a);
}
