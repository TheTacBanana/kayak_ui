struct View {
    view_proj: mat4x4<f32>,
    world_position: vec3<f32>,
};
@group(0) @binding(0)
var<uniform> view: View;

struct QuadType {
    t: i32,
    _padding_1: i32,
    _padding_2: i32,
    _padding_3: i32,
};

@group(2) @binding(0)
var<uniform> quad_type: QuadType;

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) color: vec4<f32>,
    @location(1) uv: vec3<f32>,
    @location(2) pos: vec2<f32>,
    @location(3) size: vec2<f32>,
    @location(4) border_radius: f32,
    @location(5) pixel_position: vec2<f32>,
};

@vertex
fn vertex(
    @location(0) vertex_position: vec3<f32>,
    @location(1) vertex_color: vec4<f32>,
    @location(2) vertex_uv: vec4<f32>,
    @location(3) vertex_pos_size: vec4<f32>,
) -> VertexOutput {
    var out: VertexOutput;
    out.color = vertex_color;
    out.pos = (vertex_position.xy - vertex_pos_size.xy);
    out.position = view.view_proj * vec4<f32>(vertex_position, 1.0);
    out.pixel_position = out.position.xy;
    out.uv = vertex_uv.xyz;
    out.size = vertex_pos_size.zw;
    out.border_radius = vertex_uv.w;
    return out;
}

@group(1) @binding(0)
var font_texture: texture_2d_array<f32>;
@group(1) @binding(1)
var font_sampler: sampler;

@group(3) @binding(0)
var image_texture: texture_2d<f32>;
@group(3) @binding(1)
var image_sampler: sampler;

const RADIUS: f32 = 0.1;

// Where P is the position in pixel space, B is the size of the box adn R is the radius of the current corner.
fn sdRoundBox(p: vec2<f32>, b: vec2<f32>, r: f32) -> f32 {
    var q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, vec2<f32>(0.0))) - r;
}

fn median3(v: vec3<f32>) -> f32 {
    return max(min(v.x, v.y), min(max(v.x, v.y), v.z));
}

fn sample_sdf(coords: vec2<f32>, arr: i32, scale: f32) -> f32 {
    let sample = textureSample(font_texture, font_sampler, vec2(coords.xy), arr);
    return median3(sample.rgb);
}

fn range_curve(font_size: f32) -> f32 {
    return (5.128 - 6.428 * font_size + 3.428 * pow(font_size, 2.0)) + 1.0;
}

@fragment
fn fragment(in: VertexOutput) -> @location(0) vec4<f32> {
    var output_color = vec4<f32>(0.0);
    if quad_type.t == 0 {
        var size = in.size;
        var pos = in.pos.xy * 2.0;
        // Lock border to max size. This is similar to how HTML/CSS handles border radius.
        var bs = min(in.border_radius * 2.0, min(size.x, size.y));
        var rect_dist = sdRoundBox(
            pos - size,
            size,
            bs,
        );
        rect_dist = 1.0 - smoothstep(0.0, fwidth(rect_dist), rect_dist);
        output_color = vec4<f32>(in.color.rgb, rect_dist * in.color.a);
    }
    if quad_type.t == 1 {
        var px_range = 8.0;
        var tex_dimensions = textureDimensions(font_texture);
        let dxdy = fwidth(in.uv.xy) * vec2(f32(tex_dimensions.x), f32(tex_dimensions.y));
        let subpixel_width = fwidth(in.uv.x) / 3.;
        // RGB stripe sub-pixel arrangement
        var red = sample_sdf(vec2(in.uv.x - subpixel_width, 1. - in.uv.y), i32(in.uv.z), 0.0) + min(0.001, 0.5 - 1.0 / px_range) - 0.5;
        var green = sample_sdf(vec2(in.uv.x, 1. - in.uv.y), i32(in.uv.z), 0.0) + min(0.001, 0.5 - 1.0 / px_range) - 0.5;
        var blue = sample_sdf(vec2(in.uv.x + subpixel_width, 1. - in.uv.y), i32(in.uv.z), 0.0) + min(0.001, 0.5 - 1.0 / px_range) - 0.5;
        red = clamp(red * px_range / length(dxdy) + 0.5, 0.0, 1.0);
        green = clamp(green * px_range / length(dxdy) + 0.5, 0.0, 1.0);
        blue = clamp(blue * px_range / length(dxdy) + 0.5, 0.0, 1.0);
        // fudge: this really should be somehow blended per-channel, using alpha here is a nasty hack
        let alpha = clamp(0.4 * (red + green + blue), 0., 1.);
        output_color = vec4(red * in.color.r, green * in.color.g, blue * in.color.b, in.color.a * alpha);
    }
    if quad_type.t == 2 {
        var px_range = 8.0;
        var tex_dimensions = textureDimensions(font_texture);
        let sd = sample_sdf(vec2(in.uv.x, 1.0 - in.uv.y), i32(in.uv.z), 0.0);
        let dxdy = fwidth(in.uv.xy) * vec2(f32(tex_dimensions.x), f32(tex_dimensions.y));
        let dist = sd + min(0.001, 0.5 - 1.0 / px_range) - 0.5;
        let alpha = clamp(dist * px_range / length(dxdy) + 0.5, 0.0, 1.0);
        output_color = vec4(in.color.rgb, in.color.a * alpha);
    }
    if quad_type.t == 3 {
        var bs = min(in.border_radius, min(in.size.x, in.size.y));
        var mask = sdRoundBox(
            in.pos.xy * 2.0 - (in.size.xy),
            in.size.xy,
            bs,
        );
        mask = 1.0 - smoothstep(0.0, fwidth(mask), mask);
        var color = textureSample(image_texture, image_sampler, vec2<f32>(in.uv.x, 1.0 - in.uv.y));
        output_color = vec4<f32>(color.rgb * in.color.rgb, color.a * in.color.a * mask);
    }
    return vec4(output_color.rgb, output_color.a);
}
