#include "engine_probe.h"

#include <array>
#include <cstdint>
#include <fstream>
#include <windows.h>

extern "C" unsigned char *themepark_guest_memory();
extern "C" unsigned short themepark_guest_psp();
extern "C" unsigned short themepark_guest_code_segment();
extern "C" unsigned short themepark_guest_data_segment();

namespace {
// These offsets are not reverse-engineered guesses. They come from the v3
// Turbo Debugger symbol records retained in the retail H2PC.EXE. The public
// inspection script reproduces the lookup from a user's own copy.
constexpr std::uint16_t kWidth = 0x8468;
constexpr std::uint16_t kLength = 0x846A;
constexpr std::uint16_t kTopLeftX = 0x846E;
constexpr std::uint16_t kTopLeftY = 0x8470;
constexpr std::uint16_t kMaxTopLeftX = 0x8476;
constexpr std::uint16_t kMaxTopLeftY = 0x8478;
constexpr std::uint16_t kHudHeight = 0x847A;

std::uint16_t readWord(const unsigned char *memory, std::uint16_t segment,
                       std::uint16_t offset) {
  const std::size_t physical = static_cast<std::size_t>(segment) * 16 + offset;
  return static_cast<std::uint16_t>(memory[physical] |
                                    (memory[physical + 1] << 8));
}

void appendDiagnostic(const char *line) {
  OutputDebugStringA(line);
  wchar_t path[32768]{};
  const DWORD length = GetEnvironmentVariableW(
      L"THEMEPARK_ENGINE_LOG", path, static_cast<DWORD>(std::size(path)));
  if (length && length < std::size(path)) {
    std::ofstream file(path, std::ios::app);
    file << line;
  }
}
} // namespace

void inspectHeimdallEngine() {
  // Do not include CS in change detection. DOSBox switches code segments as
  // ordinary functions execute, which otherwise turns this useful camera log
  // into thousands of duplicate lines per second.
  static std::array<std::uint16_t, 8> previous{};
  static bool recorded = false;
  const auto memory = themepark_guest_memory();
  const auto dataSegment = themepark_guest_data_segment();
  const auto psp = themepark_guest_psp();
  if (!memory || !dataSegment || !psp)
    return;

  const std::array<std::uint16_t, 8> state{
      psp,
      dataSegment,
      readWord(memory, dataSegment, kWidth),
      readWord(memory, dataSegment, kLength),
      readWord(memory, dataSegment, kTopLeftX),
      readWord(memory, dataSegment, kTopLeftY),
      readWord(memory, dataSegment, kMaxTopLeftX),
      readWord(memory, dataSegment, kMaxTopLeftY)};
  // DOS and the setup utility run before H2PC. Reject their arbitrary words;
  // the game reports a plausible pixel width and buffer length together.
  if (state[2] < 160 || state[2] > 640 || state[3] < 100 || state[3] > 400)
    return;
  if (recorded && state == previous)
    return;
  previous = state;
  recorded = true;

  char line[512]{};
  const auto hud = readWord(memory, dataSegment, kHudHeight);
  sprintf_s(line,
            "[Heimdall engine] PSP=%04X CS=%04X DS=%04X viewport=%ux%u "
            "camera=(%u,%u) max=(%u,%u) hud=%u\n",
            state[0], themepark_guest_code_segment(), state[1], state[2],
            state[3], state[4], state[5], state[6], state[7], hud);
  appendDiagnostic(line);
}
