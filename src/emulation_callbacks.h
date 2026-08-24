#pragma once

#include "libretro_api.h"

namespace emulation_callbacks {
bool __cdecl environment(unsigned command, void *data);
void __cdecl video(const void *pixels, unsigned width, unsigned height,
                   std::size_t pitch);
void __cdecl audioSample(std::int16_t left, std::int16_t right);
std::size_t __cdecl audioBatch(const std::int16_t *samples, std::size_t frames);
void __cdecl inputPoll();
std::int16_t __cdecl inputState(unsigned port, unsigned device, unsigned index,
                                unsigned id);
} // namespace emulation_callbacks
