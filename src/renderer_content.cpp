#include "renderer.h"
#include <algorithm>
#include <array>
#include <chrono>
#include <cstdint>
#include <fstream>
#include <vector>
#include <wincodec.h>
using Microsoft::WRL::ComPtr;

namespace {
constexpr UINT kWidth = 320, kHeight = 200;

bool resemblesDosText(const void *pixels, UINT width, UINT height,
                      size_t pitch) {
  // DOS and DOS/4GW screens are almost entirely black with a small amount of
  // neutral white text. Sample sparsely so this guard is effectively free.
  // Black transition frames are covered as well. During startup, retaining
  // the branded loading image is preferable to flashing either a DOS console
  // or an unexplained black frame between INTRO.EXE and MAIN.EXE.
  const auto source = static_cast<const std::uint8_t *>(pixels);
  std::size_t samples = 0, dark = 0, bright = 0, colourful = 0;
  for (UINT y = 0; y < height; y += 4) {
    const auto row = reinterpret_cast<const std::uint32_t *>(source + y * pitch);
    for (UINT x = 0; x < width; x += 4) {
      const auto value = row[x];
      const int blue = value & 255;
      const int green = (value >> 8) & 255;
      const int red = (value >> 16) & 255;
      const int highest = std::max(red, std::max(green, blue));
      const int lowest = std::min(red, std::min(green, blue));
      ++samples;
      dark += highest < 20;
      bright += lowest > 100;
      colourful += highest - lowest > 24;
    }
  }
  const bool blackTransition = samples && dark * 100 >= samples * 98;
  const bool textConsole = samples && dark * 100 >= samples * 84 &&
                           bright * 1000 >= samples &&
                           bright * 10 <= samples &&
                           colourful * 200 <= samples;
  return blackTransition || textConsole;
}

void drawLoadingGlyph(std::vector<std::uint8_t> &pixels, char glyph, int left,
                      int top, int scale) {
  // Five-bit rows form a deliberately chunky DOS-era font. The surrounding
  // screen is native artwork, so this evokes the original without exposing
  // an emulator console or depending on an installed Windows font.
  struct Letter { char name; std::array<std::uint8_t, 7> rows; };
  constexpr std::array<Letter, 8> letters{{
      {'L', {16, 16, 16, 16, 16, 16, 31}},
      {'O', {14, 17, 17, 17, 17, 17, 14}},
      {'A', {14, 17, 17, 31, 17, 17, 17}},
      {'D', {30, 17, 17, 17, 17, 17, 30}},
      {'I', {31, 4, 4, 4, 4, 4, 31}},
      {'N', {17, 25, 21, 19, 17, 17, 17}},
      {'G', {14, 17, 16, 23, 17, 17, 14}},
      {'.', {0, 0, 0, 0, 0, 12, 12}},
  }};
  const auto found = std::find_if(letters.begin(), letters.end(),
                                  [glyph](const Letter &l) {
                                    return l.name == glyph;
                                  });
  if (found == letters.end())
    return;
  for (int y = 0; y < 7; ++y)
    for (int x = 0; x < 5; ++x)
      if (found->rows[y] & (16 >> x))
        for (int py = 0; py < scale; ++py)
          for (int px = 0; px < scale; ++px) {
            const auto i = (static_cast<size_t>(top + y * scale + py) * kWidth +
                            left + x * scale + px) * 4;
            pixels[i] = 42; pixels[i + 1] = 212;
            pixels[i + 2] = 238; pixels[i + 3] = 255;
          }
}

bool upload(ID3D11Device *device, ID3D11DeviceContext *context,
            const void *pixels, UINT width, UINT height, UINT pitch,
            ComPtr<ID3D11Texture2D> &texture,
            ComPtr<ID3D11ShaderResourceView> &view) {
  D3D11_TEXTURE2D_DESC existing{};
  if (texture)
    texture->GetDesc(&existing);
  if (!texture || existing.Width != width || existing.Height != height) {
    // The core may switch resolution for menus or cinematics. Recreate only at
    // that boundary; ordinary frames use the inexpensive UpdateSubresource
    // path.
    D3D11_TEXTURE2D_DESC description{};
    description.Width = width;
    description.Height = height;
    description.MipLevels = 1;
    description.ArraySize = 1;
    description.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    description.SampleDesc.Count = 1;
    description.Usage = D3D11_USAGE_DEFAULT;
    description.BindFlags = D3D11_BIND_SHADER_RESOURCE;
    ComPtr<ID3D11Texture2D> replacement;
    ComPtr<ID3D11ShaderResourceView> replacementView;
    if (FAILED(device->CreateTexture2D(&description, nullptr, &replacement)) ||
        FAILED(device->CreateShaderResourceView(replacement.Get(), nullptr,
                                                &replacementView)))
      return false;
    texture = std::move(replacement);
    view = std::move(replacementView);
  }
  context->UpdateSubresource(texture.Get(), 0, nullptr, pixels, pitch, 0);
  return true;
}
} // namespace

void Renderer::updateFrame(const void *pixels, UINT width, UINT height,
                           size_t pitch) {
  if (!pixels || !width || !height || pitch < static_cast<size_t>(width) * 4)
    return;
  if (resemblesDosText(pixels, width, height, pitch)) {
    if (!loadingVisible_)
      loadLoadingScreen();
    return;
  }
  D3D11_TEXTURE2D_DESC oldDescription{};
  if (source_)
    source_->GetDesc(&oldDescription);
  const bool sameSize = receivedFrame_ && oldDescription.Width == width &&
                        oldDescription.Height == height;
  if (sameSize && previousSource_)
    context_->CopyResource(previousSource_.Get(), source_.Get());

  if (upload(device_.Get(), context_.Get(), pixels, width, height,
             static_cast<UINT>(pitch), source_, sourceView_)) {
    // The first frame and resolution changes initialize both textures. Later
    // updates retain the prior completed image for presentation-only blending.
    if (!sameSize)
      upload(device_.Get(), context_.Get(), pixels, width, height,
             static_cast<UINT>(pitch), previousSource_, previousSourceView_);
    sourceWidth_ = width;
    sourceHeight_ = height;
    const auto now = std::chrono::steady_clock::now();
    if (receivedFrame_) {
      const auto measured = std::chrono::duration_cast<std::chrono::microseconds>(
          now - lastFrameTime_);
      if (measured >= std::chrono::milliseconds(8) &&
          measured <= std::chrono::milliseconds(50))
        framePeriod_ = measured;
    }
    lastFrameTime_ = now;
    receivedFrame_ = true;
    loadingVisible_ = false;
  }
}

bool Renderer::loadImage(const std::filesystem::path &path) {
  // WIC supplies GIF/PNG/JPEG/BMP decoding without another library. Preview
  // images are always reduced to the game's future 320x200 framebuffer size.
  ComPtr<IWICImagingFactory> factory;
  ComPtr<IWICBitmapDecoder> decoder;
  ComPtr<IWICBitmapFrameDecode> frame;
  ComPtr<IWICFormatConverter> converter;
  ComPtr<IWICBitmapScaler> scaler;
  if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                              CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory))))
    return false;
  if (FAILED(factory->CreateDecoderFromFilename(
          path.c_str(), nullptr, GENERIC_READ, WICDecodeMetadataCacheOnLoad,
          &decoder)))
    return false;
  if (FAILED(decoder->GetFrame(0, &frame)) ||
      FAILED(factory->CreateFormatConverter(&converter)))
    return false;
  if (FAILED(converter->Initialize(frame.Get(), GUID_WICPixelFormat32bppBGRA,
                                   WICBitmapDitherTypeNone, nullptr, 0,
                                   WICBitmapPaletteTypeCustom)))
    return false;
  if (FAILED(factory->CreateBitmapScaler(&scaler)) ||
      FAILED(scaler->Initialize(converter.Get(), kWidth, kHeight,
                                WICBitmapInterpolationModeNearestNeighbor)))
    return false;
  std::vector<std::uint8_t> pixels(kWidth * kHeight * 4);
  if (FAILED(scaler->CopyPixels(nullptr, kWidth * 4,
                                static_cast<UINT>(pixels.size()),
                                pixels.data())))
    return false;
  if (!upload(device_.Get(), context_.Get(), pixels.data(), kWidth, kHeight,
              kWidth * 4, source_, sourceView_))
    return false;
  sourceWidth_ = kWidth;
  sourceHeight_ = kHeight;
  return true;
}

void Renderer::loadLoadingScreen() {
  // The host owns startup presentation. Never reveal a DOS prompt, DOSBox
  // menu, extender banner, or installer while the original programs change.
  std::vector<std::uint8_t> pixels(kWidth * kHeight * 4);
  for (UINT y = 0; y < kHeight; ++y)
    for (UINT x = 0; x < kWidth; ++x) {
      const size_t i = (static_cast<size_t>(y) * kWidth + x) * 4;
      pixels[i] = static_cast<std::uint8_t>(86 + y * 40 / kHeight);
      pixels[i + 1] = static_cast<std::uint8_t>(26 + y * 18 / kHeight);
      pixels[i + 2] = 4;
      pixels[i + 3] = 255;
    }
  constexpr char message[] = "LOADING...";
  constexpr int scale = 4;
  constexpr int advance = 6 * scale;
  const int left = (static_cast<int>(kWidth) -
                    static_cast<int>(std::size(message) - 1) * advance) / 2;
  for (int index = 0; message[index]; ++index)
    drawLoadingGlyph(pixels, message[index], left + index * advance, 84, scale);
  upload(device_.Get(), context_.Get(), pixels.data(), kWidth, kHeight,
         kWidth * 4, source_, sourceView_);
  upload(device_.Get(), context_.Get(), pixels.data(), kWidth, kHeight,
         kWidth * 4, previousSource_, previousSourceView_);
  sourceWidth_ = kWidth;
  sourceHeight_ = kHeight;
  loadingVisible_ = true;
}

bool Renderer::loadThemeParkLoadingScreen(
    const std::filesystem::path &dataDirectory) {
  // MMENU-0 is the actual 320x200 Theme Park menu background. Reading it from
  // the player's imported CD keeps copyrighted artwork out of the public
  // repository while giving every supported release authentic loading art.
  std::ifstream image(dataDirectory / L"MMENU-0.DAT", std::ios::binary);
  std::ifstream palette(dataDirectory / L"MPALETTE.DAT", std::ios::binary);
  std::vector<std::uint8_t> indices(kWidth * kHeight), colours(256 * 3);
  if (!image.read(reinterpret_cast<char *>(indices.data()), indices.size()) ||
      !palette.read(reinterpret_cast<char *>(colours.data()), colours.size()))
    return false;

  std::vector<std::uint8_t> pixels(kWidth * kHeight * 4);
  for (std::size_t position = 0; position < indices.size(); ++position) {
    const auto index = static_cast<std::size_t>(indices[position]) * 3;
    // Theme Park stores six-bit VGA components. Replicating their high bits
    // expands 0..63 to the full 0..255 display range without banding gaps.
    for (unsigned component = 0; component < 3; ++component) {
      const auto sixBit = colours[index + (2 - component)];
      pixels[position * 4 + component] =
          static_cast<std::uint8_t>((sixBit << 2) | (sixBit >> 4));
    }
    pixels[position * 4 + 3] = 255;
  }

  // Keep the title and Bullfrog logo unobstructed. The caption sits in a small
  // strip at the bottom, where it cannot be mistaken for replacement artwork.
  for (int y = 172; y < 193; ++y)
    for (int x = 96; x < 224; ++x) {
      const auto position = (static_cast<std::size_t>(y) * kWidth + x) * 4;
      for (unsigned component = 0; component < 3; ++component)
        pixels[position + component] /= 2;
    }
  constexpr char message[] = "LOADING...";
  constexpr int scale = 2, advance = 6 * scale;
  const int left = (static_cast<int>(kWidth) -
                    static_cast<int>(std::size(message) - 1) * advance) / 2;
  for (int index = 0; message[index]; ++index)
    drawLoadingGlyph(pixels, message[index], left + index * advance, 175, scale);

  if (!upload(device_.Get(), context_.Get(), pixels.data(), kWidth, kHeight,
              kWidth * 4, source_, sourceView_) ||
      !upload(device_.Get(), context_.Get(), pixels.data(), kWidth, kHeight,
              kWidth * 4, previousSource_, previousSourceView_))
    return false;
  sourceWidth_ = kWidth;
  sourceHeight_ = kHeight;
  loadingVisible_ = true;
  return true;
}
