#include "audio_output.h"

#include <cstring>
#include <xaudio2.h>

#include <wrl/client.h>

using Microsoft::WRL::ComPtr;

struct AudioOutput::Implementation final : IXAudio2VoiceCallback {
  ComPtr<IXAudio2> engine;
  IXAudio2MasteringVoice *mastering = nullptr;
  IXAudio2SourceVoice *source = nullptr;

  // XAudio2 returns pContext after it has finished reading a buffer. Each
  // callback therefore owns and releases exactly one copied sample array.
  void __stdcall OnBufferEnd(void *context) override {
    delete[] static_cast<std::int16_t *>(context);
  }
  void __stdcall OnVoiceProcessingPassStart(UINT32) override {}
  void __stdcall OnVoiceProcessingPassEnd() override {}
  void __stdcall OnStreamEnd() override {}
  void __stdcall OnBufferStart(void *) override {}
  void __stdcall OnLoopEnd(void *) override {}
  void __stdcall OnVoiceError(void *, HRESULT) override {}
};

AudioOutput::AudioOutput()
    : implementation_(std::make_unique<Implementation>()) {}
AudioOutput::~AudioOutput() { stop(); }

bool AudioOutput::initialize(unsigned sampleRate) {
  stop();
  if (FAILED(XAudio2Create(&implementation_->engine)))
    return false;
  if (FAILED(implementation_->engine->CreateMasteringVoice(
          &implementation_->mastering)))
    return false;

  WAVEFORMATEX format{};
  format.wFormatTag = WAVE_FORMAT_PCM;
  format.nChannels = 2;
  format.nSamplesPerSec = sampleRate;
  format.wBitsPerSample = 16;
  format.nBlockAlign = format.nChannels * format.wBitsPerSample / 8;
  format.nAvgBytesPerSec = format.nSamplesPerSec * format.nBlockAlign;
  if (FAILED(implementation_->engine->CreateSourceVoice(
          &implementation_->source, &format, 0, XAUDIO2_DEFAULT_FREQ_RATIO,
          implementation_.get())))
    return false;
  return SUCCEEDED(implementation_->source->Start());
}

std::size_t AudioOutput::submit(const std::int16_t *samples,
                                std::size_t frames) {
  if (!implementation_->source || !samples || !frames)
    return 0;
  XAUDIO2_VOICE_STATE state{};
  implementation_->source->GetState(&state);
  if (state.BuffersQueued > 8)
    return frames; // Drop stale audio instead of adding perceptible latency.

  const std::size_t sampleCount = frames * 2;
  auto *copy = new std::int16_t[sampleCount];
  std::memcpy(copy, samples, sampleCount * sizeof(*copy));
  XAUDIO2_BUFFER buffer{};
  buffer.AudioBytes = static_cast<UINT32>(sampleCount * sizeof(*copy));
  buffer.pAudioData = reinterpret_cast<const BYTE *>(copy);
  buffer.pContext = copy;
  if (FAILED(implementation_->source->SubmitSourceBuffer(&buffer))) {
    delete[] copy;
    return 0;
  }
  return frames;
}

void AudioOutput::stop() {
  if (implementation_->source) {
    implementation_->source->Stop();
    implementation_->source->FlushSourceBuffers();
    implementation_->source->DestroyVoice();
    implementation_->source = nullptr;
  }
  if (implementation_->mastering) {
    implementation_->mastering->DestroyVoice();
    implementation_->mastering = nullptr;
  }
  implementation_->engine.Reset();
}
