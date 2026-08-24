#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>

// AudioOutput is intentionally unaware of DOS. It accepts ordinary interleaved
// stereo PCM frames, so native CD music can later use the same Windows device.
class AudioOutput {
public:
  AudioOutput();
  ~AudioOutput();
  AudioOutput(const AudioOutput &) = delete;
  AudioOutput &operator=(const AudioOutput &) = delete;

  bool initialize(unsigned sampleRate);
  std::size_t submit(const std::int16_t *samples, std::size_t frames);
  void stop();

private:
  struct Implementation;
  std::unique_ptr<Implementation> implementation_;
};
