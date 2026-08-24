#pragma once

#include "libretro_api.h"

#include <filesystem>
#include <memory>
#include <string>
#include <unordered_map>

class AudioOutput;
class Renderer;

// EmulationCore hosts the original executable through the stable libretro ABI.
// No renderer or application code depends on DOSBox-specific implementation.
class EmulationCore {
public:
  EmulationCore();
  ~EmulationCore();
  EmulationCore(const EmulationCore &) = delete;
  EmulationCore &operator=(const EmulationCore &) = delete;

  bool initialize(const std::filesystem::path &installation, Renderer &renderer,
                  std::wstring &error);
  void runFrame();
  void keyEvent(unsigned windowsKey, bool down);
  void mouseMotion(int horizontal, int vertical);
  void pointerPosition(std::int16_t horizontal, std::int16_t vertical);
  void mouseButton(unsigned button, bool down);
  void pollInput();
  bool saveState(const std::filesystem::path &path) const;
  bool loadState(const std::filesystem::path &path);
  void shutdown();

  bool handleEnvironment(unsigned command, void *data);
  void receiveVideo(const void *pixels, unsigned width, unsigned height,
                    std::size_t pitch);
  std::size_t receiveAudio(const std::int16_t *samples, std::size_t frames);
  std::int16_t readInput(unsigned port, unsigned device, unsigned index,
                         unsigned id) const;
  static EmulationCore *active();
  std::uint64_t submittedAudioFrames() const { return submittedAudioFrames_; }
  std::uint16_t audioPeak() const { return audioPeak_; }
  std::int64_t simulationStepMicroseconds() const {
    return frameTimeMicroseconds_;
  }
  bool shutdownRequested() const { return shutdownRequested_; }

private:
  struct Functions;
  std::unique_ptr<Functions> functions_;
  std::unique_ptr<AudioOutput> audio_;
  Renderer *renderer_ = nullptr;
  // DOSBox Pure is linked into this executable.  This flag records whether
  // retro_init completed so shutdown can unwind the static core exactly once.
  bool coreInitialized_ = false;
  libretro::KeyboardEvent keyboardEvent_ = nullptr;
  libretro::FrameTimeEvent frameTimeEvent_ = nullptr;
  std::int64_t frameTimeMicroseconds_ = 16667;
  std::unordered_map<std::string, std::string> options_;
  std::string systemDirectory_;
  std::string saveDirectory_;
  std::string gamePath_;
  bool loaded_ = false;
  bool shutdownRequested_ = false;
  bool gameProgramSeen_ = false;
  unsigned missingGameFrames_ = 0;
  int pendingMouseX_ = 0;
  int pendingMouseY_ = 0;
  int frameMouseX_ = 0;
  int frameMouseY_ = 0;
  bool mouseButtons_[3]{};
  std::int16_t pointerX_ = 0;
  std::int16_t pointerY_ = 0;
  std::uint64_t submittedAudioFrames_ = 0;
  std::uint16_t audioPeak_ = 0;
};
