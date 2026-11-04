#include <metal_stdlib>
using namespace metal;

struct GlyphVertex {
    float2 position;
    float2 texCoord;
    float4 color;
};

struct TextCell {
    float2 position;
    float2 size;
    float2 texOrigin;
    float2 texSize;
    float4 color;
};

struct ColorCell {
    float2 position;
    float2 size;
    float4 color;
};

// Every vertex function takes `viewport`. `geometry` is (drawable width,
// drawable height, x offset, y offset), all in pixels: rows are laid out from
// the view's top-left corner and the offset moves them by the view's content
// insets. `fade` is (alpha, top inset, fade length, unused), the last two in
// pixels: what is drawn inside the top inset is drawn at `alpha`, ramping up
// to full opacity over the fade length just above row 0. `background` is the
// premultiplied default background, which the pipeline without blending fades
// towards.
struct Viewport {
    float4 geometry;
    float4 fade;
    float4 background;
};

struct GlyphOut {
    float4 position [[position]];
    float2 texCoord;
    float4 color;
    float4 fade [[flat]];
};

// The opacity of a fragment `y` pixels from the drawable's top edge.
static float top_inset_opacity(float4 fade, float y) {
    float alpha = fade.x;
    if (alpha >= 1.0) {
        return 1.0;
    }
    float above = fade.y - y;
    if (above <= 0.0) {
        return 1.0;
    }
    if (above < fade.z) {
        return mix(1.0, alpha, above / fade.z);
    }
    return alpha;
}

constant float2 kQuadCorners[6] = {
    float2(0.0, 0.0),
    float2(1.0, 0.0),
    float2(0.0, 1.0),
    float2(1.0, 0.0),
    float2(1.0, 1.0),
    float2(0.0, 1.0),
};

vertex GlyphOut terminal_text_vertex(uint vid [[vertex_id]],
                                     const device GlyphVertex *vertices [[buffer(0)]],
                                     constant Viewport &viewport [[buffer(1)]]) {
    GlyphVertex v = vertices[vid];
    float4 geometry = viewport.geometry;
    float2 ndc = float2(((v.position.x + geometry.z) / geometry.x) * 2.0 - 1.0,
                        ((v.position.y + geometry.w) / geometry.y) * 2.0 - 1.0);
    GlyphOut out;
    out.position = float4(ndc, 0.0, 1.0);
    out.texCoord = v.texCoord;
    out.color = v.color;
    out.fade = viewport.fade;
    return out;
}

vertex GlyphOut terminal_cell_text_vertex(uint vid [[vertex_id]],
                                          const device TextCell *cells [[buffer(0)]],
                                          constant Viewport &viewport [[buffer(1)]]) {
    uint cellIndex = vid / 6;
    uint cornerIndex = vid % 6;
    TextCell cell = cells[cellIndex];
    float2 corner = kQuadCorners[cornerIndex];
    float2 position = cell.position + cell.size * corner;
    float4 geometry = viewport.geometry;
    float2 ndc = float2(((position.x + geometry.z) / geometry.x) * 2.0 - 1.0,
                        ((position.y + geometry.w) / geometry.y) * 2.0 - 1.0);
    GlyphOut out;
    out.position = float4(ndc, 0.0, 1.0);
    out.texCoord = cell.texOrigin + cell.texSize * corner;
    out.color = cell.color;
    out.fade = viewport.fade;
    return out;
}

fragment float4 terminal_text_fragment(GlyphOut in [[stage_in]],
                                       texture2d<float> atlas [[texture(0)]],
                                       sampler samp [[sampler(0)]]) {
    float4 tex = atlas.sample(samp, in.texCoord);
    float4 color = float4(tex.rgb * in.color.rgb, tex.a * in.color.a);
    return color * top_inset_opacity(in.fade, in.position.y);
}

fragment float4 terminal_text_fragment_gray(GlyphOut in [[stage_in]],
                                            texture2d<float> atlas [[texture(0)]],
                                            sampler samp [[sampler(0)]]) {
    float coverage = atlas.sample(samp, in.texCoord).r
        * top_inset_opacity(in.fade, in.position.y);
    return float4(in.color.rgb * coverage, in.color.a * coverage);
}

struct ColorVertex {
    float2 position;
    float4 color;
};

struct ColorOut {
    float4 position [[position]];
    float4 color;
    float4 fade [[flat]];
    float4 background [[flat]];
};

vertex ColorOut terminal_color_vertex(uint vid [[vertex_id]],
                                      const device ColorVertex *vertices [[buffer(0)]],
                                      constant Viewport &viewport [[buffer(1)]]) {
    ColorVertex v = vertices[vid];
    float4 geometry = viewport.geometry;
    float2 ndc = float2(((v.position.x + geometry.z) / geometry.x) * 2.0 - 1.0,
                        ((v.position.y + geometry.w) / geometry.y) * 2.0 - 1.0);
    ColorOut out;
    out.background = viewport.background;
    out.position = float4(ndc, 0.0, 1.0);
    out.color = v.color;
    out.fade = viewport.fade;
    return out;
}

vertex ColorOut terminal_cell_color_vertex(uint vid [[vertex_id]],
                                           const device ColorCell *cells [[buffer(0)]],
                                           constant Viewport &viewport [[buffer(1)]]) {
    uint cellIndex = vid / 6;
    uint cornerIndex = vid % 6;
    ColorCell cell = cells[cellIndex];
    float2 corner = kQuadCorners[cornerIndex];
    float2 position = cell.position + cell.size * corner;
    float4 geometry = viewport.geometry;
    float2 ndc = float2(((position.x + geometry.z) / geometry.x) * 2.0 - 1.0,
                        ((position.y + geometry.w) / geometry.y) * 2.0 - 1.0);
    ColorOut out;
    out.background = viewport.background;
    out.position = float4(ndc, 0.0, 1.0);
    out.color = cell.color;
    out.fade = viewport.fade;
    return out;
}

// For the blending pipelines, which take straight (unpremultiplied) color.
fragment float4 terminal_color_fragment(ColorOut in [[stage_in]]) {
    return float4(in.color.rgb, in.color.a * top_inset_opacity(in.fade, in.position.y));
}

// For the pipeline without blending, which writes premultiplied color as is,
// replacing the default background: a faded cell mixes back towards it.
fragment float4 terminal_color_fragment_premultiplied(ColorOut in [[stage_in]]) {
    float opacity = top_inset_opacity(in.fade, in.position.y);
    return opacity >= 1.0 ? in.color : mix(in.background, in.color, opacity);
}

// Never called. Its name says which uniform and buffer layout these shaders
// use (here: `viewport` is the Viewport struct, with the fade). The renderer
// requires it, so a default library built from an older copy of these
// shaders is passed over for the embedded source. When a layout changes,
// change the number here, in `requiredShaderFunctions` (MetalTerminalRenderer)
// and in `ContentInsetsMetalTests.aStaleShaderLibraryIsRejected`.
kernel void swiftterm_viewport_layout_3() {}
