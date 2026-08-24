#include "engine_frame.h"
#include "widescreen_policy.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cstdio>
#include <fstream>
#include <windows.h>

extern "C" unsigned char *themepark_guest_memory();
extern "C" unsigned short themepark_guest_psp();
extern "C" unsigned int themepark_guest_palette_rgb(unsigned int index);

namespace {
constexpr std::uint16_t kWidth = 0x8468;
constexpr std::uint16_t kLength = 0x846A;
constexpr std::uint16_t kSegmentsPerLine = 0x846C;
constexpr std::uint16_t kTopLeftX = 0x846E;
constexpr std::uint16_t kTopLeftY = 0x8470;
constexpr std::uint16_t kHudHeight = 0x847A;
constexpr std::uint16_t kExtraLines = 0x847C;
constexpr std::uint16_t kRoomToken = 0xC756;
constexpr std::uint16_t kBackingSegment = 0x0F40;
constexpr int kOriginalWidth = 320;

std::atomic<int> gWideStart{};
std::atomic<int> gOriginalStart{};
std::atomic<int> gHudStart{};
std::atomic<int> gHudEnd{};

void logFrameLayout(unsigned width, unsigned height, int backingWidth,
                    int backingLength, int segmentsPerLine, int originalStart,
                    int top, int hudHeight, int extraLines,
                    std::uint16_t roomToken, bool accepted) {
  const std::array<int, 11> state{
      static_cast<int>(width), static_cast<int>(height), backingWidth,
      backingLength, segmentsPerLine, originalStart, top, hudHeight,
      extraLines, roomToken, accepted};
  static std::array<int, 11> previous{};
  static bool written = false;
  if (written && state == previous)
    return;
  wchar_t path[32768]{};
  const DWORD length = GetEnvironmentVariableW(
      L"THEMEPARK_ENGINE_LOG", path, static_cast<DWORD>(std::size(path)));
  if (!length || length >= std::size(path))
    return;
  written = true;
  previous = state;
  std::ofstream file(path, std::ios::app);
  file << "[Expanded frame] accepted=" << accepted << " source=" << width
       << 'x' << height
       << " backing=" << backingWidth << 'x' << backingLength
       << " strideSegments=" << segmentsPerLine << " camera=("
       << originalStart << ',' << top << ") hud=" << hudHeight
       << " extra=" << extraLines << " roomToken=0x" << std::hex << roomToken
       << std::dec << '\n';
}

std::size_t physical(std::uint16_t segment, std::uint16_t offset) {
  // The 8086 wraps addresses at 20 bits. Normal game buffers do not cross the
  // boundary, but applying the mask documents and preserves DOS semantics.
  return (static_cast<std::size_t>(segment) * 16 + offset) & 0xFFFFF;
}

std::uint16_t word(const unsigned char *memory, std::uint16_t segment,
                   std::uint16_t offset) {
  const auto address = physical(segment, offset);
  return static_cast<std::uint16_t>(memory[address] |
                                    (memory[(address + 1) & 0xFFFFF] << 8));
}

bool backingMatchesOriginal(const unsigned char *memory,
                            std::uint16_t loadSegment, const void *original,
                            unsigned sourceScale, std::size_t pitch,
                            int originalStart, int top, int extraLines,
                            int hudHeight, int sceneRows) {
  // A layout can become visible just before its backing pixels are ready. A
  // sparse comparison against the completed VGA frame proves that both views
  // describe the same scene before the native host reveals additional pixels.
  const auto source = static_cast<const unsigned char *>(original);
  int compared = 0, matching = 0, nonBlack = 0;
  for (int y = 0; y < sceneRows; y += 7) {
    const auto segment = static_cast<std::uint16_t>(
        loadSegment + kBackingSegment + (top + extraLines + y) * 32);
    const auto line = physical(segment,
                               static_cast<std::uint16_t>(originalStart));
    const auto sourceRow = reinterpret_cast<const std::uint32_t *>(
        source + (hudHeight + extraLines + y) * sourceScale * pitch);
    for (int x = 0; x < kOriginalWidth; x += 11) {
      const auto backing = themepark_guest_palette_rgb(
                               memory[(line + x) & 0xFFFFF]) &
                           0x00FFFFFFu;
      const auto displayed = sourceRow[x * sourceScale] & 0x00FFFFFFu;
      ++compared;
      nonBlack += displayed != 0;
      matching += backing == displayed;
    }
  }
  return nonBlack >= 10 && matching * 100 >= compared * 85;
}
} // namespace

bool buildExpandedHeimdallFrame(const void *original, unsigned width,
                                unsigned height, std::size_t pitch,
                                ExpandedFrame &result) {
  // DOSBox Pure may report either the logical 320x200 image or an exact 2x
  // 640x400 copy. Treat the latter as doubled source pixels, not as a larger
  // logical viewport.
  const unsigned sourceScale =
      width == 320 && height == 200 ? 1 : (width == 640 && height == 400 ? 2 : 0);
  if (!original || !sourceScale || pitch < width * 4)
    return false;
  const auto memory = themepark_guest_memory();
  const auto loadSegment = static_cast<std::uint16_t>(themepark_guest_psp() + 16);
  if (!memory || !loadSegment)
    return false;

  const int backingWidth = word(memory, loadSegment, kWidth);
  const int backingLength = word(memory, loadSegment, kLength);
  int segmentsPerLine = word(memory, loadSegment, kSegmentsPerLine);
  const int originalStart = word(memory, loadSegment, kTopLeftX);
  const int top = word(memory, loadSegment, kTopLeftY);
  int hudHeight = word(memory, loadSegment, kHudHeight);
  const int extraLines = word(memory, loadSegment, kExtraLines);
  // The copy routine temporarily describes its 320-pixel VGA destination
  // after finishing a frame. Reuse only the two stable gameplay properties;
  // the pixel comparison below still has to prove that the backing is current.
  static int stableHudHeight = 0;
  if (segmentsPerLine == 32 && hudHeight > 0) {
    stableHudHeight = hudHeight;
  } else if (backingWidth >= static_cast<int>(ExpandedFrame::Width) &&
             backingLength >= 200 && stableHudHeight > 0) {
    segmentsPerLine = 32;
    hudHeight = stableHudHeight;
  }
  // VidUpdateScreen places the map below the top control bar. Consequently,
  // the backing buffer only needs to contain the visible map rows, not another
  // full 200 rows in addition to the HUD. At the lowest camera position this
  // distinction is exact: 144 + (200 - 24) == the 320-row backing height.
  const int sceneRows = 200 - hudHeight - extraLines;
  const auto roomToken = word(memory, loadSegment, kRoomToken);
  const bool accepted =
      backingWidth >= static_cast<int>(ExpandedFrame::Width) &&
      backingWidth <= 512 && backingLength >= 200 && backingLength <= 400 &&
      segmentsPerLine == 32 && originalStart >= 0 &&
      originalStart + kOriginalWidth <= backingWidth && top >= 0 &&
      hudHeight >= 0 && hudHeight <= 80 && extraLines >= 0 &&
      extraLines <= 40 && sceneRows > 0 &&
      top + extraLines + sceneRows <= backingLength &&
      widescreenAllowedForRoom(roomToken) &&
      backingMatchesOriginal(memory, loadSegment, original, sourceScale, pitch,
                             originalStart, top, extraLines, hudHeight,
                             sceneRows);
  logFrameLayout(width, height, backingWidth, backingLength, segmentsPerLine,
                 originalStart, top, hudHeight, extraLines, roomToken,
                 accepted);
  if (!accepted)
    return false;

  const int halfGrowth =
      (static_cast<int>(ExpandedFrame::Width) - kOriginalWidth) / 2;
  const int wideStart = std::clamp(originalStart - halfGrowth, 0,
                                   backingWidth - (int)ExpandedFrame::Width);
  result.pixels.assign(ExpandedFrame::Width * ExpandedFrame::Height,
                       0xFF000000u);
  for (int y = 0; y < sceneRows; ++y) {
    const auto lineSegment = static_cast<std::uint16_t>(
        loadSegment + kBackingSegment + (top + extraLines + y) * 32);
    const auto line = physical(lineSegment, static_cast<std::uint16_t>(wideStart));
    for (unsigned x = 0; x < ExpandedFrame::Width; ++x)
      result.pixels[(hudHeight + extraLines + y) * ExpandedFrame::Width + x] =
          themepark_guest_palette_rgb(memory[(line + x) & 0xFFFFF]);
  }

  // The HUD is the top `hudHeight` rows of the ordinary 320-pixel image. Keep
  // its artwork at the original size and center it over the wider room. Only
  // its outermost background colors are extended into the two new margins.
  const int hudStart = 0;
  const int hudEnd = hudHeight;
  const int hudLeft = halfGrowth;
  const auto source = static_cast<const unsigned char *>(original);
  for (int y = hudStart; y < hudEnd; ++y) {
    const auto row = reinterpret_cast<const std::uint32_t *>(
        source + y * sourceScale * pitch);
    auto destination = result.pixels.begin() + y * ExpandedFrame::Width;
    std::fill(destination, destination + hudLeft, row[0]);
    std::fill(destination + hudLeft + kOriginalWidth,
              destination + ExpandedFrame::Width,
              row[(kOriginalWidth - 1) * sourceScale]);
    for (int x = 0; x < kOriginalWidth; ++x)
      destination[hudLeft + x] = row[x * sourceScale];
  }
  gWideStart = wideStart;
  gOriginalStart = originalStart;
  gHudStart = hudStart;
  gHudEnd = hudEnd;
  return true;
}

int expandedPointerToOriginal(int horizontal, int vertical) {
  if (vertical >= gHudStart.load() && vertical < gHudEnd.load())
    return std::clamp(horizontal - 53, 0, 319);
  return std::clamp(horizontal + gWideStart.load() - gOriginalStart.load(),
                    0, 319);
}

float expandedHudStart() { return gHudStart.load() / 200.0f; }

float expandedHudEnd() { return gHudEnd.load() / 200.0f; }
