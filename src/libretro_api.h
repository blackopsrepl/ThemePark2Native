#pragma once

#include <cstddef>
#include <cstdint>

// This is the deliberately small portion of libretro's stable C ABI used by
// our host. Keeping it local makes the emulator boundary readable without
// vendoring the several-thousand-line upstream documentation header.
namespace libretro {
constexpr unsigned kApiVersion = 1;
constexpr unsigned kExperimental = 0x10000;

enum Environment : unsigned {
  EnvGetCanDuplicate = 3,
  EnvShutdown = 7,
  EnvGetSystemDirectory = 9,
  EnvSetPixelFormat = 10,
  EnvSetKeyboardCallback = 12,
  EnvGetVariable = 15,
  EnvSetVariables = 16,
  EnvGetVariableUpdate = 17,
  EnvSetSupportNoGame = 18,
  EnvGetLibraryPath = 19,
  EnvSetFrameTimeCallback = 21,
  EnvGetLogInterface = 27,
  EnvGetSaveDirectory = 31,
  EnvSetSystemAvInfo = 32,
  EnvSetGeometry = 37,
  EnvGetCoreOptionsVersion = 52,
  EnvGetInputBitmasks = 51 | kExperimental,
};

enum class PixelFormat : unsigned {
  Xrgb1555 = 0,
  Xrgb8888 = 1,
  Rgb565 = 2,
};

enum Device : unsigned {
  None = 0,
  Joypad = 1,
  Mouse = 2,
  Keyboard = 3,
  Analog = 5,
  Pointer = 6,
};

struct SystemInfo {
  const char *libraryName;
  const char *libraryVersion;
  const char *validExtensions;
  bool needsFullPath;
  bool blocksExtraction;
};

struct Geometry {
  unsigned baseWidth;
  unsigned baseHeight;
  unsigned maximumWidth;
  unsigned maximumHeight;
  float aspectRatio;
};

struct Timing {
  double framesPerSecond;
  double sampleRate;
};

struct AvInfo {
  Geometry geometry;
  Timing timing;
};

struct GameInfo {
  const char *path;
  const void *data;
  std::size_t size;
  const char *metadata;
};

struct Variable {
  const char *key;
  const char *value;
};

using KeyboardEvent = void(__cdecl *)(bool, unsigned, std::uint32_t,
                                      std::uint16_t);
struct KeyboardCallback {
  KeyboardEvent callback;
};

using FrameTimeEvent = void(__cdecl *)(std::int64_t);
struct FrameTimeCallback {
  FrameTimeEvent callback;
  std::int64_t referenceMicroseconds;
};

using LogFunction = void(__cdecl *)(int, const char *, ...);
struct LogCallback {
  LogFunction log;
};

using EnvironmentCallback = bool(__cdecl *)(unsigned, void *);
using VideoCallback = void(__cdecl *)(const void *, unsigned, unsigned,
                                      std::size_t);
using AudioSampleCallback = void(__cdecl *)(std::int16_t, std::int16_t);
using AudioBatchCallback = std::size_t(__cdecl *)(const std::int16_t *,
                                                  std::size_t);
using InputPollCallback = void(__cdecl *)();
using InputStateCallback = std::int16_t(__cdecl *)(unsigned, unsigned, unsigned,
                                                   unsigned);
} // namespace libretro
