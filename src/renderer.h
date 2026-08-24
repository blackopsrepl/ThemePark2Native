#pragma once
#include <d3d11.h>
#include <chrono>
#include <filesystem>
#include <utility>
#include <windows.h>
#include <wrl/client.h>

class Renderer {
public:
  bool initialize(HWND window);
  void resize(UINT width, UINT height);
  void render();
  void updateFrame(const void *pixels, UINT width, UINT height, size_t pitch);
  bool loadImage(const std::filesystem::path &path);
  void loadLoadingScreen();
  bool loadThemeParkLoadingScreen(const std::filesystem::path &dataDirectory);
  void toggleFullscreen();
  bool isFullscreen() const { return fullscreen_; }
  RECT contentRectangle() const;
  std::pair<std::int16_t, std::int16_t> mapPointer(LONG x, LONG y) const;

private:
  HWND window_{};
  Microsoft::WRL::ComPtr<ID3D11Device> device_;
  Microsoft::WRL::ComPtr<ID3D11DeviceContext> context_;
  Microsoft::WRL::ComPtr<IDXGISwapChain> swapChain_;
  Microsoft::WRL::ComPtr<ID3D11RenderTargetView> backbuffer_;
  Microsoft::WRL::ComPtr<ID3D11Texture2D> source_;
  Microsoft::WRL::ComPtr<ID3D11ShaderResourceView> sourceView_;
  Microsoft::WRL::ComPtr<ID3D11Texture2D> previousSource_;
  Microsoft::WRL::ComPtr<ID3D11ShaderResourceView> previousSourceView_;
  Microsoft::WRL::ComPtr<ID3D11VertexShader> vertexShader_;
  Microsoft::WRL::ComPtr<ID3D11PixelShader> pixelShader_;
  Microsoft::WRL::ComPtr<ID3D11SamplerState> linearSampler_;
  Microsoft::WRL::ComPtr<ID3D11Buffer> presentationConstants_;
  HANDLE frameLatencyWaitable_{};
  UINT width_ = 1280, height_ = 720;
  UINT sourceWidth_ = 320, sourceHeight_ = 200;
  bool fullscreen_ = false;
  bool receivedFrame_ = false;
  bool loadingVisible_ = false;
  std::chrono::steady_clock::time_point lastFrameTime_{};
  std::chrono::microseconds framePeriod_{16667};
  RECT savedWindowRect_{};
  DWORD savedWindowStyle_{};
  DWORD savedWindowExStyle_{};
};
