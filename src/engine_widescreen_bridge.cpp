#include "engine_widescreen_bridge.h"
#include "renderer.h"

#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <memory>
#include <vector>

extern "C" {
bool themepark_guest_apply_widescreen();
unsigned int themepark_guest_widescreen_status();
bool themepark_guest_copy_widescreen(unsigned int *, unsigned int,
                                     unsigned int *, unsigned int *);
unsigned int themepark_guest_widescreen_diagnostics(unsigned int *,
                                                     unsigned int *);
}

namespace {
void logWidescreenDecision(unsigned width) {
  char *rawPath = nullptr;
  std::size_t pathLength = 0;
  if (_dupenv_s(&rawPath, &pathLength, "THEMEPARK_WIDE_LOG") != 0 ||
      !rawPath || pathLength <= 1)
    return;
  const std::unique_ptr<char, decltype(&std::free)> path(rawPath, &std::free);
  unsigned legacy = 0, wide = 0;
  const unsigned state = themepark_guest_widescreen_diagnostics(&legacy, &wide);
  static unsigned previousState = ~0u, previousWidth = ~0u;
  if (state == previousState && width == previousWidth)
    return;
  std::ofstream output(path.get(), std::ios::app);
  output << "state=" << state << " presentedWidth=" << width
         << " bridgeStatus=" << themepark_guest_widescreen_status()
         << " legacyMatches=" << legacy << " wideMatches=" << wide << '\n';
  previousState = state;
  previousWidth = width;
}
} // namespace

bool applyThemeParkWidescreen() {
  // The core exposes its trustworthy program identity while delivering video.
  // Wait for two consecutive successful callbacks: the first changes stride,
  // while the second proves a complete frame was rendered with that stride.
  static bool previousCallbackWasWide = false;
  const bool active = themepark_guest_apply_widescreen();
  const bool completedWideFrame = active && previousCallbackWasWide;
  previousCallbackWasWide = active;
  // Width zero means that the native host intentionally used the core's
  // ordinary VGA/VESA frame. It is written only when diagnostics are enabled.
  logWidescreenDecision(active ? 427u : 0u);
  return completedWideFrame;
}

bool presentThemeParkWidescreen(Renderer &renderer) {
  // 854x480 is the larger of the two exact 16:9 engine targets. Reusing one
  // vector avoids allocation churn while the bridge copies indexed pixels and
  // resolves Theme Park's live VGA palette inside the authoritative core.
  static std::vector<std::uint32_t> pixels(854u * 480u);
  unsigned width = 0, height = 0;
  if (!themepark_guest_copy_widescreen(
          pixels.data(), static_cast<unsigned>(pixels.size()), &width, &height))
    return false;
  logWidescreenDecision(width);
  renderer.updateFrame(pixels.data(), width, height,
                       static_cast<std::size_t>(width) * sizeof(pixels[0]));
  return true;
}
