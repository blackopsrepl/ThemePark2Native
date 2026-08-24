#include "emulation_callbacks.h"
#include "emulation_core.h"

namespace emulation_callbacks {
bool __cdecl environment(unsigned command, void *data) {
  const auto core = EmulationCore::active();
  return core && core->handleEnvironment(command, data);
}

void __cdecl video(const void *pixels, unsigned width, unsigned height,
                   std::size_t pitch) {
  if (const auto core = EmulationCore::active())
    core->receiveVideo(pixels, width, height, pitch);
}

void __cdecl audioSample(std::int16_t left, std::int16_t right) {
  const std::int16_t samples[]{left, right};
  if (const auto core = EmulationCore::active())
    core->receiveAudio(samples, 1);
}

std::size_t __cdecl audioBatch(const std::int16_t *samples,
                               std::size_t frames) {
  if (const auto core = EmulationCore::active())
    return core->receiveAudio(samples, frames);
  return 0;
}

void __cdecl inputPoll() {
  // libretro asks the frontend to take one coherent input snapshot before it
  // queries individual axes and buttons. This also ensures a relative mouse
  // delta is consumed only once even if the core queries it more than once.
  if (const auto core = EmulationCore::active())
    core->pollInput();
}

std::int16_t __cdecl inputState(unsigned port, unsigned device, unsigned index,
                                unsigned id) {
  if (const auto core = EmulationCore::active())
    return core->readInput(port, device, index, id);
  return 0;
}
} // namespace emulation_callbacks
