#include "emulation_core.h"
#include "audio_output.h"
#include "emulation_callbacks.h"
#include "renderer.h"

#include <algorithm>
#include <fstream>
#include <vector>
#include <windows.h>

// These are the public libretro entry points implemented by the DOSBox Pure
// sources compiled into this same Visual Studio project.  Keeping the narrow C
// ABI here avoids leaking the large third-party headers into the host code.
extern "C" {
unsigned __cdecl retro_api_version();
void __cdecl retro_init();
void __cdecl retro_deinit();
void __cdecl retro_set_environment(libretro::EnvironmentCallback);
void __cdecl retro_set_video_refresh(libretro::VideoCallback);
void __cdecl retro_set_audio_sample(libretro::AudioSampleCallback);
void __cdecl retro_set_audio_sample_batch(libretro::AudioBatchCallback);
void __cdecl retro_set_input_poll(libretro::InputPollCallback);
void __cdecl retro_set_input_state(libretro::InputStateCallback);
void __cdecl retro_set_controller_port_device(unsigned, unsigned);
bool __cdecl retro_load_game(const libretro::GameInfo *);
void __cdecl retro_unload_game();
void __cdecl retro_run();
void __cdecl retro_get_system_av_info(libretro::AvInfo *);
std::size_t __cdecl retro_serialize_size();
bool __cdecl retro_serialize(void *, std::size_t);
bool __cdecl retro_unserialize(const void *, std::size_t);
bool themepark_guest_game_is_running();
bool themepark_guest_main_is_running();
bool themepark_guest_frame_is_renderable();
}

namespace {
EmulationCore *gActiveCore = nullptr;

std::string toUtf8(const std::filesystem::path &path) {
  const std::wstring wide = path.wstring();
  const int size = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), -1, nullptr, 0,
                                       nullptr, nullptr);
  std::string utf8(static_cast<std::size_t>(size), '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), -1, utf8.data(), size, nullptr,
                      nullptr);
  utf8.pop_back(); // libretro expects a regular null-terminated std::string.
  return utf8;
}

} // namespace

struct EmulationCore::Functions {
  unsigned(__cdecl *apiVersion)() = nullptr;
  void(__cdecl *initialize)() = nullptr;
  void(__cdecl *deinitialize)() = nullptr;
  void(__cdecl *setEnvironment)(libretro::EnvironmentCallback) = nullptr;
  void(__cdecl *setVideo)(libretro::VideoCallback) = nullptr;
  void(__cdecl *setAudioSample)(libretro::AudioSampleCallback) = nullptr;
  void(__cdecl *setAudioBatch)(libretro::AudioBatchCallback) = nullptr;
  void(__cdecl *setInputPoll)(libretro::InputPollCallback) = nullptr;
  void(__cdecl *setInputState)(libretro::InputStateCallback) = nullptr;
  void(__cdecl *setController)(unsigned, unsigned) = nullptr;
  bool(__cdecl *loadGame)(const libretro::GameInfo *) = nullptr;
  void(__cdecl *unloadGame)() = nullptr;
  void(__cdecl *run)() = nullptr;
  void(__cdecl *getAvInfo)(libretro::AvInfo *) = nullptr;
  std::size_t(__cdecl *serializationSize)() = nullptr;
  bool(__cdecl *serialize)(void *, std::size_t) = nullptr;
  bool(__cdecl *unserialize)(const void *, std::size_t) = nullptr;
};

EmulationCore::EmulationCore()
    : functions_(std::make_unique<Functions>()),
      audio_(std::make_unique<AudioOutput>()) {
  // The table preserves the host/core boundary while using direct, statically
  // linked calls.  There is no DLL to locate, load, ship, or update separately.
  *functions_ = {retro_api_version,
                 retro_init,
                 retro_deinit,
                 retro_set_environment,
                 retro_set_video_refresh,
                 retro_set_audio_sample,
                 retro_set_audio_sample_batch,
                 retro_set_input_poll,
                 retro_set_input_state,
                 retro_set_controller_port_device,
                 retro_load_game,
                 retro_unload_game,
                 retro_run,
                 retro_get_system_av_info,
                 retro_serialize_size,
                 retro_serialize,
                 retro_unserialize};
}
EmulationCore::~EmulationCore() { shutdown(); }
EmulationCore *EmulationCore::active() { return gActiveCore; }

bool EmulationCore::initialize(const std::filesystem::path &installation,
                               Renderer &renderer, std::wstring &error) {
  shutdown();
  renderer_ = &renderer;
  // Maintainers can boot another executable from the imported data directory
  // while diagnosing the retail setup program.  The value is deliberately
  // restricted to a filename, so it cannot escape into arbitrary host paths.
  wchar_t diagnosticProgram[260]{};
  const DWORD diagnosticLength = GetEnvironmentVariableW(
      L"THEMEPARK_PROGRAM", diagnosticProgram,
      static_cast<DWORD>(std::size(diagnosticProgram)));
  std::filesystem::path program = L"INTRO.EXE";
  if (diagnosticLength && diagnosticLength < std::size(diagnosticProgram)) {
    const std::filesystem::path requested = diagnosticProgram;
    if (requested == requested.filename())
      program = requested;
  }
  const auto gamePath = installation / L"data" / program;
  if (!std::filesystem::exists(gamePath)) {
    error = L"The original Theme Park program is missing.";
    return false;
  }

  const auto system = installation / L"system";
  const auto saves = installation / L"saves";
  std::error_code filesystemError;
  std::filesystem::create_directories(system, filesystemError);
  std::filesystem::create_directories(saves, filesystemError);
  systemDirectory_ = toUtf8(system);
  saveDirectory_ = toUtf8(saves);
  gamePath_ = toUtf8(gamePath);
  if (!functions_->apiVersion ||
      functions_->apiVersion() != libretro::kApiVersion ||
      !functions_->loadGame || !functions_->run) {
    error = L"The DOS runtime exposes an incompatible libretro ABI.";
    shutdown();
    return false;
  }

  gActiveCore = this;
  functions_->setEnvironment(emulation_callbacks::environment);
  functions_->setVideo(emulation_callbacks::video);
  functions_->setAudioSample(emulation_callbacks::audioSample);
  functions_->setAudioBatch(emulation_callbacks::audioBatch);
  functions_->setInputPoll(emulation_callbacks::inputPoll);
  functions_->setInputState(emulation_callbacks::inputState);
  functions_->initialize();
  coreInitialized_ = true;
  functions_->setController(0, libretro::Keyboard);

  const libretro::GameInfo game{gamePath_.c_str(), nullptr, 0, nullptr};
  if (!functions_->loadGame(&game)) {
    error = L"The original Theme Park executable could not be started.";
    shutdown();
    return false;
  }
  loaded_ = true;
  libretro::AvInfo av{};
  functions_->getAvInfo(&av);
  frameTimeMicroseconds_ =
      av.timing.framesPerSecond > 0
          ? static_cast<std::int64_t>(1000000.0 / av.timing.framesPerSecond)
          : 16667;
  if (!audio_->initialize(static_cast<unsigned>(av.timing.sampleRate))) {
    error = L"Windows could not initialize the audio output device.";
    shutdown();
    return false;
  }
  return true;
}

void EmulationCore::runFrame() {
  if (!loaded_ || shutdownRequested_)
    return;
  if (frameTimeEvent_)
    frameTimeEvent_(frameTimeMicroseconds_);
  functions_->run();
  // Pure may keep its machine alive after the DOS shell exits, so a libretro
  // shutdown callback alone cannot define native application lifetime. Once
  // Once MAIN.EXE has genuinely run, several consecutive shell frames mean
  // the original game returned to DOS and the Windows host should close.
  if (themepark_guest_main_is_running()) {
    gameProgramSeen_ = true;
    missingGameFrames_ = 0;
  } else if (gameProgramSeen_ && ++missingGameFrames_ >= 6) {
    shutdownRequested_ = true;
  }
}

void EmulationCore::receiveVideo(const void *pixels, unsigned width,
                                 unsigned height, std::size_t pitch) {
  if (!renderer_ || !pixels || pixels == reinterpret_cast<const void *>(-1))
    return;
  // Theme Park can switch between VGA and its built-in high-resolution VESA
  // mode. Preserve the dimensions reported by the original engine; the native
  // renderer handles either without game-specific framebuffer assumptions.
  // Frames produced before INTRO.EXE/MAIN.EXE belong to the private
  // DOS machine.  They must never replace the native loading artwork: doing
  // so would briefly expose the DOSBox or DOS/4GW startup screen.
  if (!themepark_guest_frame_is_renderable())
    return;
  // The stable branch preserves Theme Park's authoritative 4:3 framebuffer.
  // The renderer scales that complete image without modifying engine memory.
  renderer_->updateFrame(pixels, width, height, pitch);
}

std::size_t EmulationCore::receiveAudio(const std::int16_t *samples,
                                        std::size_t frames) {
  submittedAudioFrames_ += frames;
  for (std::size_t index = 0; index != frames * 2; ++index) {
    const int magnitude = std::abs(static_cast<int>(samples[index]));
    audioPeak_ = std::max(audioPeak_, static_cast<std::uint16_t>(magnitude));
  }
  return audio_->submit(samples, frames);
}

bool EmulationCore::saveState(const std::filesystem::path &path) const {
  if (!loaded_ || !functions_->serializationSize || !functions_->serialize)
    return false;
  std::vector<std::uint8_t> state(functions_->serializationSize());
  if (state.empty() || !functions_->serialize(state.data(), state.size()))
    return false;
  std::ofstream output(path, std::ios::binary);
  output.write(reinterpret_cast<const char *>(state.data()), state.size());
  return output.good();
}

bool EmulationCore::loadState(const std::filesystem::path &path) {
  std::ifstream input(path, std::ios::binary | std::ios::ate);
  if (!loaded_ || !input || !functions_->unserialize)
    return false;
  const auto length = input.tellg();
  if (length <= 0)
    return false;
  std::vector<std::uint8_t> state(static_cast<std::size_t>(length));
  input.seekg(0);
  input.read(reinterpret_cast<char *>(state.data()), state.size());
  return input.good() && functions_->unserialize(state.data(), state.size());
}

void EmulationCore::shutdown() {
  audio_->stop();
  if (functions_ && loaded_ && functions_->unloadGame)
    functions_->unloadGame();
  loaded_ = false;
  if (coreInitialized_ && functions_ && functions_->deinitialize)
    functions_->deinitialize();
  coreInitialized_ = false;
  keyboardEvent_ = nullptr;
  frameTimeEvent_ = nullptr;
  shutdownRequested_ = false;
  gameProgramSeen_ = false;
  missingGameFrames_ = 0;
  if (gActiveCore == this)
    gActiveCore = nullptr;
}
