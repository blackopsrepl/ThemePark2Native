#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

struct ExpandedFrame {
  static constexpr unsigned Width = 426;
  static constexpr unsigned Height = 200;
  std::vector<std::uint32_t> pixels;
};

// Builds a genuinely wider scene from Theme Park's own 464-pixel backing
// surface. Menus and modes that do not expose a valid gameplay HUD return
// false, which gives them an automatic and safe 4:3 compatibility fallback.
bool buildExpandedHeimdallFrame(const void *original, unsigned width,
                                unsigned height, std::size_t pitch,
                                ExpandedFrame &result);

// Converts a pointer on the 426-pixel scene back to the 320-pixel coordinate
// system expected by the authoritative DOS input and script code.
int expandedPointerToOriginal(int horizontal, int vertical);

// Normalized UI bounds let the presentation interpolator keep text and icons
// on the newest completed frame instead of blending two interface states.
float expandedHudStart();
float expandedHudEnd();
