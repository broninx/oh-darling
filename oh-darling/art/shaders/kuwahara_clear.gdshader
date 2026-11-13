// Original: "Kuwahara" by innerdev, godotshaders.com (CC0 / public domain)
// https://godotshaders.com/shader/kuwahara-shader-godot-4/

shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform int radius : hint_range(1, 20) = 5;
uniform vec3 offset = vec3(0.0);

// Peso decrescente com a distância; troque a função de peso se quiser outra curva.
float weight_for_dist(float dist) {
    return 1.0 / (1.0 + dist); // leve decaimento
}

void fragment() {
    vec2 uv = SCREEN_UV;
    vec3 m0 = offset; vec3 m1 = offset; vec3 m2 = offset; vec3 m3 = offset;
    vec3 s0 = offset; vec3 s1 = offset; vec3 s2 = offset; vec3 s3 = offset;
    float n0 = 0.0; float n1 = 0.0; float n2 = 0.0; float n3 = 0.0;
    vec3 c;

    // Quadrante superior-esquerdo
    for (int j = -radius; j <= 0; ++j) {
        for (int i = -radius; i <= 0; ++i) {
            vec2 ofs = vec2(float(i), float(j)) * SCREEN_PIXEL_SIZE;
            c = texture(SCREEN_TEXTURE, uv + ofs).rgb;
            float dist = length(vec2(float(i), float(j)));
            float w = weight_for_dist(dist);
            m0 += c * w;
            s0 += c * c * w;
            n0 += w;
        }
    }

    // Quadrante superior-direito
    for (int j = -radius; j <= 0; ++j) {
        for (int i = 0; i <= radius; ++i) {
            vec2 ofs = vec2(float(i), float(j)) * SCREEN_PIXEL_SIZE;
            c = texture(SCREEN_TEXTURE, uv + ofs).rgb;
            float dist = length(vec2(float(i), float(j)));
            float w = weight_for_dist(dist);
            m1 += c * w;
            s1 += c * c * w;
            n1 += w;
        }
    }

    // Quadrante inferior-direito
    for (int j = 0; j <= radius; ++j) {
        for (int i = 0; i <= radius; ++i) {
            vec2 ofs = vec2(float(i), float(j)) * SCREEN_PIXEL_SIZE;
            c = texture(SCREEN_TEXTURE, uv + ofs).rgb;
            float dist = length(vec2(float(i), float(j)));
            float w = weight_for_dist(dist);
            m2 += c * w;
            s2 += c * c * w;
            n2 += w;
        }
    }

    // Quadrante inferior-esquerdo
    for (int j = 0; j <= radius; ++j) {
        for (int i = -radius; i <= 0; ++i) {
            vec2 ofs = vec2(float(i), float(j)) * SCREEN_PIXEL_SIZE;
            c = texture(SCREEN_TEXTURE, uv + ofs).rgb;
            float dist = length(vec2(float(i), float(j)));
            float w = weight_for_dist(dist);
            m3 += c * w;
            s3 += c * c * w;
            n3 += w;
        }
    }

    float min_sigma2 = 1e+20;
    vec3 best_color = texture(SCREEN_TEXTURE, uv).rgb;

    if (n0 > 0.0) {
        m0 /= n0;
        s0 = abs(s0 / n0 - m0 * m0);
        float sigma2 = s0.r + s0.g + s0.b;
        if (sigma2 < min_sigma2) { min_sigma2 = sigma2; best_color = m0; }
    }

    if (n1 > 0.0) {
        m1 /= n1;
        s1 = abs(s1 / n1 - m1 * m1);
        float sigma2 = s1.r + s1.g + s1.b;
        if (sigma2 < min_sigma2) { min_sigma2 = sigma2; best_color = m1; }
    }

    if (n2 > 0.0) {
        m2 /= n2;
        s2 = abs(s2 / n2 - m2 * m2);
        float sigma2 = s2.r + s2.g + s2.b;
        if (sigma2 < min_sigma2) { min_sigma2 = sigma2; best_color = m2; }
    }

    if (n3 > 0.0) {
        m3 /= n3;
        s3 = abs(s3 / n3 - m3 * m3);
        float sigma2 = s3.r + s3.g + s3.b;
        if (sigma2 < min_sigma2) { min_sigma2 = sigma2; best_color = m3; }
    }

    COLOR = vec4(best_color, 1.0);
}