// ==============================================================================
//  HOVER OUTLINE  (task T06)
// ==============================================================================
//  TASK
//    The bright outline around an object under the mouse (outline.tres,
//    hover_material of InteractionComponent).
//
//  HOW IT WORKS
//    Inverted hull: the mesh is drawn again with only its back faces, pushed
//    out along the normals. Unlike "grow" of StandardMaterial3D, the push is
//    in SCREEN PIXELS, not in metres. So the outline has the same thickness
//    at every zoom and at every resolution (width = a part of the screen
//    height), and it is thick enough to stay visible under the painterly
//    mood filter (art/shaders/painterly.gdshader).
//
//  TWO PASSES (outline.tres: the material and its next_pass)
//    1. radial = false: push along the normal. Good thickness, but meshes
//       with hard edges (boxes, CSG, flat-shaded props) have split normals,
//       so the hull opens small gaps at the corners.
//    2. radial = true: push away from the origin of the object on screen.
//       All the copies of a corner vertex go the same way, so this hull has
//       no gaps. Together the two hulls give a thick outline without gaps.
//
//  RULES
//    - Unshaded and without fog: the colour does not change with the light,
//      the time of day or the fog of the mood.
//    - Skinned meshes (NPCs) work: Godot skins VERTEX before vertex().
// ==============================================================================
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

// The outline thickness, as a part of the screen height (0.006 = 0.6%,
// about 6.5 px at 1080p).
uniform float width : hint_range(0.0, 0.03, 0.0005) = 0.006;
uniform vec4 color : source_color = vec4(1.0, 1.0, 0.0, 1.0);
// false: push along the normal. true: push away from the object origin.
uniform bool radial = false;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	// The push direction on screen, in pixels.
	vec2 dir;
	if (radial) {
		vec4 origin = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0));
		dir = (clip.xy / clip.w - origin.xy / origin.w) * VIEWPORT_SIZE;
	} else {
		vec3 n_view = mat3(MODELVIEW_MATRIX) * NORMAL;
		dir = (PROJECTION_MATRIX * vec4(n_view, 0.0)).xy * VIEWPORT_SIZE;
	}
	float len = length(dir);
	dir = len > 1e-6 ? dir / len : vec2(0.0);
	// "width" of the screen height, in clip space (x clip.w: the same size
	// near and far).
	clip.xy += dir * (width * VIEWPORT_SIZE.y) * 2.0 / VIEWPORT_SIZE * clip.w;
	POSITION = clip;
}

void fragment() {
	ALBEDO = color.rgb;
}
