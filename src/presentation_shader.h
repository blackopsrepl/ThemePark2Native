#pragma once

// This shader runs before the external CRT pass. It solves two different
// problems in a single native-resolution draw:
//
// 1. Sharp bilinear reconstruction keeps source-pixel boundaries stable at
//    arbitrary display scales such as 4.5x, while still antialiasing each edge
//    across one output pixel. Ordinary bilinear filtering blurs every boundary.
// 2. Contrast-limited sharpening restores local definition without allowing
//    bright or dark halos beyond the colours already present nearby.
//
// The CRT shader receives this clean reconstructed image and remains solely
// responsible for scanlines, beam shape, phosphor mask, glow, and halation.
constexpr char kPresentationShader[] = R"(
Texture2D Frame : register(t0);
Texture2D Previous : register(t1);
SamplerState LinearClamp : register(s0);
cbuffer Presentation : register(b0) { float4 P; }

struct VertexOutput { float4 position : SV_POSITION; float2 uv : TEXCOORD0; };

VertexOutput VSMain(uint id : SV_VertexID) {
  float2 positions[3] = {
    float2(-1.0, -1.0), float2(-1.0, 3.0), float2(3.0, -1.0)
  };
  float2 coordinates[3] = {
    float2(0.0, 1.0), float2(0.0, -1.0), float2(2.0, 1.0)
  };
  VertexOutput output;
  output.position = float4(positions[id], 0.0, 1.0);
  output.uv = coordinates[id];
  return output;
}

float4 completedFrame(float2 uv) {
  float alpha = uv.y >= P.y && uv.y < P.z ? 1.0 : P.x;
  return lerp(Previous.Sample(LinearClamp, uv),
              Frame.Sample(LinearClamp, uv), alpha);
}

float luma(float3 color) {
  return dot(color, float3(0.2126, 0.7152, 0.0722));
}

float2 sharpBilinearUv(float2 uv, float2 size) {
  float2 pixel = uv * size - 0.5;
  float2 fraction = frac(pixel);
  // fwidth measures how much of one source pixel this output fragment spans.
  // The transition therefore stays one physical display pixel wide at every
  // resolution instead of becoming blurrier as the scale increases.
  float2 transition = max(fwidth(pixel), 1.0 / size);
  float2 reconstructed = smoothstep(0.5 - transition * 0.5,
                                    0.5 + transition * 0.5, fraction);
  return (floor(pixel) + reconstructed + 0.5) / size;
}

float4 PSMain(VertexOutput input) : SV_TARGET {
  uint width, height;
  Frame.GetDimensions(width, height);
  float2 size = float2(width, height);
  float2 texel = 1.0 / size;
  float2 crispUv = sharpBilinearUv(input.uv, size);

  float4 ordinary = completedFrame(input.uv);
  float4 center = completedFrame(crispUv);
  float4 north = completedFrame(crispUv - float2(0.0, texel.y));
  float4 south = completedFrame(crispUv + float2(0.0, texel.y));
  float4 west = completedFrame(crispUv - float2(texel.x, 0.0));
  float4 east = completedFrame(crispUv + float2(texel.x, 0.0));

  float lowest = min(luma(center.rgb), min(min(luma(north.rgb), luma(south.rgb)),
                                           min(luma(west.rgb), luma(east.rgb))));
  float highest = max(luma(center.rgb), max(max(luma(north.rgb), luma(south.rgb)),
                                            max(luma(west.rgb), luma(east.rgb))));
  float edge = saturate((highest - lowest) * 6.0);
  float3 reconstructed = lerp(ordinary.rgb, center.rgb, edge);

  float3 neighbourhood = (north.rgb + south.rgb + west.rgb + east.rgb) * 0.25;
  float3 minimum = min(center.rgb, min(min(north.rgb, south.rgb),
                                      min(west.rgb, east.rgb)));
  float3 maximum = max(center.rgb, max(max(north.rgb, south.rgb),
                                      max(west.rgb, east.rgb)));
  // A restrained 0.22 gain restores definition lost during reconstruction.
  // Clamping to the local range prevents ringing and bright/dark outlines.
  float3 sharpened = reconstructed + (reconstructed - neighbourhood) * 0.22;
  sharpened = clamp(sharpened, minimum, maximum);
  return float4(saturate(sharpened), center.a);
}
)";
