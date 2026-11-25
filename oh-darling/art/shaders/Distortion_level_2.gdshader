// Screen warping: Distortion level 2 (the room sways).
// Original: "Screen Warping" by AivanWorld, godotshaders.com (CC0 / public domain)
// https://godotshaders.com/?p=10214
shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture;
uniform float warp_intensity : hint_range(0.0, 0.1) = 0.01; 
uniform float time_scale : hint_range(0.1, 10.0) = 0.4;
uniform float center_amount : hint_range(0.0, 1.0) = 1.0;

uniform float wave_count : hint_range(1.0, 40.0) = 5.0;

void fragment() {
    vec2 uv = SCREEN_UV;
    
        float warp = sin(uv.y * wave_count + TIME * time_scale) * warp_intensity;
    
    uv.x += warp * mix(smoothstep(0.2, 0.5, abs(uv.x - 0.5)), 1.0, center_amount);
    
    COLOR = texture(SCREEN_TEXTURE, uv);
}