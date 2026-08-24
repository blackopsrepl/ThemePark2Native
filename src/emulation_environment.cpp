#include "emulation_core.h"

#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <mutex>
#include <windows.h>

namespace {
void __cdecl writeCoreLog(int, const char *format, ...) {
  char line[2048]{};
  va_list arguments;
  va_start(arguments, format);
  vsnprintf_s(line, sizeof(line), _TRUNCATE, format, arguments);
  va_end(arguments);
  OutputDebugStringA("[DOS runtime] ");
  OutputDebugStringA(line);
  // Developers can opt into a core trace without making normal installations
  // accumulate logs. Set THEMEPARK_LOG to an absolute file before launching.
  static std::mutex logMutex;
  static std::ofstream log = [] {
    wchar_t destination[32768]{};
    const DWORD length = GetEnvironmentVariableW(
        L"THEMEPARK_LOG", destination, static_cast<DWORD>(std::size(destination)));
    return length && length < std::size(destination)
               ? std::ofstream(destination, std::ios::app)
               : std::ofstream{};
  }();
  if (log) {
    const std::lock_guard lock(logMutex);
    log << line;
    log.flush();
  }
}

std::string firstOptionValue(const char *description) {
  if (!description)
    return {};
  const char *separator = std::strchr(description, ';');
  if (!separator)
    return {};
  separator += separator[1] == ' ' ? 2 : 1;
  const char *end = std::strchr(separator, '|');
  return std::string(separator, end ? end : separator + std::strlen(separator));
}
} // namespace

bool EmulationCore::handleEnvironment(unsigned command, void *data) {
  switch (command) {
  case libretro::EnvGetCanDuplicate:
    *static_cast<bool *>(data) = true;
    return true;
  case libretro::EnvShutdown:
    shutdownRequested_ = true;
    return true;
  case libretro::EnvGetSystemDirectory:
    *static_cast<const char **>(data) = systemDirectory_.c_str();
    return true;
  case libretro::EnvGetSaveDirectory:
    *static_cast<const char **>(data) = saveDirectory_.c_str();
    return true;
  case libretro::EnvGetLibraryPath:
    // A statically linked core has no DLL path.  Some libretro code still asks
    // for a stable identity, so expose the monolithic executable's filename.
    *static_cast<const char **>(data) = "ThemePark2Native.exe";
    return true;
  case libretro::EnvSetPixelFormat:
    return *static_cast<libretro::PixelFormat *>(data) ==
           libretro::PixelFormat::Xrgb8888;
  case libretro::EnvSetKeyboardCallback:
    keyboardEvent_ = static_cast<libretro::KeyboardCallback *>(data)->callback;
    return true;
  case libretro::EnvSetFrameTimeCallback: {
    const auto callback = static_cast<libretro::FrameTimeCallback *>(data);
    frameTimeEvent_ = callback->callback;
    frameTimeMicroseconds_ = callback->referenceMicroseconds;
    return true;
  }
  case libretro::EnvGetLogInterface:
    static_cast<libretro::LogCallback *>(data)->log = writeCoreLog;
    return true;
  case libretro::EnvGetCoreOptionsVersion:
    // Version zero asks the core for the compact key/default-value API. The
    // modern option schema is UI metadata that this dedicated host does not
    // use.
    *static_cast<unsigned *>(data) = 0;
    return true;
  case libretro::EnvSetVariables: {
    const auto variables = static_cast<const libretro::Variable *>(data);
    for (std::size_t index = 0; variables && variables[index].key; ++index)
      options_.try_emplace(variables[index].key,
                           firstOptionValue(variables[index].value));
    return true;
  }
  case libretro::EnvGetVariable: {
    auto variable = static_cast<libretro::Variable *>(data);
    static const std::unordered_map<std::string, std::string> overrides{
        // Theme Park is unusually CPU-speed-sensitive: DOSBox's protected-mode
        // AUTO policy becomes MAX and makes days race by on a modern PC. The
        // fixed 3000-cycle budget preserves the widely verified original game
        // pace. Camera smoothness must be solved by native presentation, not by
        // allowing extra instructions to accelerate the authoritative game.
        {"dosbox_pure_cycles", "3000"},
        {"dosbox_pure_cycles_scale", "1.0"},
        {"dosbox_pure_cpu_type", "386"},
        // Pure advances the emulated VGA clock at its real rate but emits an
        // even 60-frame stream. This removes 70-to-60 Hz cadence judder without
        // changing Theme Park's timers, sound clock, or authoritative speed.
        {"dosbox_pure_force60fps", "true"},
        {"dosbox_pure_savestate", "on"},
        {"dosbox_pure_on_screen_keyboard", "false"},
        // Direct mode keeps the game's pointer exactly under the native one.
        // Theme Park's separate VESA freeze is repaired in its imported copy;
        // using relative emulation here adds acceleration and perceptible lag.
        {"dosbox_pure_mouse_input", "direct"},
        {"dosbox_pure_aspect_correction", "false"},
        {"dosbox_pure_audiorate", "48000"},
        // Expose the hardware selected by Theme Park's setup data.  Keep both
        // mixer paths at unity gain: raising a silent channel cannot repair an
        // incorrect setup selection, and would clip once playback is fixed.
        {"dosbox_pure_sblaster_type", "sb16"},
        {"dosbox_pure_sblaster_conf", "A220 I5 D1 H5"},
        {"dosbox_pure_sblaster_adlib_mode", "opl2"},
        {"dosbox_pure_sblaster_adlib_emu", "nuked"},
        {"dosbox_pure_volume_adlib", "1.0"},
        {"dosbox_pure_volume_sb", "1.0"},
        {"dosbox_pure_menu_time", "0"},
    };
    if (const auto selected = overrides.find(variable->key);
        selected != overrides.end()) {
      variable->value = selected->second.c_str();
    } else if (const auto found = options_.find(variable->key);
               found != options_.end()) {
      variable->value = found->second.c_str();
    } else {
      variable->value = nullptr;
    }
    return true;
  }
  case libretro::EnvGetVariableUpdate:
    *static_cast<bool *>(data) = false;
    return true;
  case libretro::EnvSetSystemAvInfo: {
    // VGA/VESA switches can change the cadence after startup. The old host
    // acknowledged this notification but kept its initial timing forever,
    // starving the high-resolution mode of emulation calls.
    const auto information = static_cast<const libretro::AvInfo *>(data);
    if (information && information->timing.framesPerSecond > 1.0)
      frameTimeMicroseconds_ = static_cast<std::int64_t>(
          1000000.0 / information->timing.framesPerSecond + 0.5);
    return true;
  }
  case libretro::EnvSetSupportNoGame:
  case libretro::EnvSetGeometry:
    return true;
  case libretro::EnvGetInputBitmasks:
    return false;
  default:
    return false;
  }
}
