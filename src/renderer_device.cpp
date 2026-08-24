#include "renderer.h"
#include "presentation_shader.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <d3dcompiler.h>
#include <dxgi1_3.h>
using Microsoft::WRL::ComPtr;

bool Renderer::initialize(HWND window) {
  window_ = window;
  RECT client{};
  GetClientRect(window_, &client);
  width_ = std::max<LONG>(1, client.right);
  height_ = std::max<LONG>(1, client.bottom);
  DXGI_SWAP_CHAIN_DESC swap{};
  swap.BufferCount = 2;
  swap.BufferDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
  swap.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
  swap.OutputWindow = window_;
  swap.SampleDesc.Count = 1;
  swap.Windowed = TRUE;
  swap.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
  // A waitable flip-model chain gives Windows explicit ownership of frame
  // pacing. Limiting queued frames to one prevents latency and uneven bursts
  // when a 60 Hz simulation is presented on 90/120/144 Hz displays.
  swap.Flags = DXGI_SWAP_CHAIN_FLAG_FRAME_LATENCY_WAITABLE_OBJECT;
  const D3D_FEATURE_LEVEL levels[] = {D3D_FEATURE_LEVEL_11_1,
                                      D3D_FEATURE_LEVEL_11_0};
  D3D_FEATURE_LEVEL selected{};
  if (FAILED(D3D11CreateDeviceAndSwapChain(
          nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0, levels,
          static_cast<UINT>(std::size(levels)), D3D11_SDK_VERSION, &swap,
          &swapChain_, &device_, &selected, &context_)))
    return false;
  ComPtr<IDXGISwapChain2> pacedSwapChain;
  if (FAILED(swapChain_.As(&pacedSwapChain)) ||
      FAILED(pacedSwapChain->SetMaximumFrameLatency(1)))
    return false;
  frameLatencyWaitable_ = pacedSwapChain->GetFrameLatencyWaitableObject();
  if (!frameLatencyWaitable_)
    return false;
  // DXGI normally implements Alt+Enter itself. The host owns this transition,
  // so disable the automatic mode switch to prevent two competing fullscreen
  // operations from destroying the restored non-client frame.
  ComPtr<IDXGIDevice> dxgiDevice;
  ComPtr<IDXGIAdapter> adapter;
  ComPtr<IDXGIFactory> factory;
  if (SUCCEEDED(device_.As(&dxgiDevice)) &&
      SUCCEEDED(dxgiDevice->GetAdapter(&adapter)) &&
      SUCCEEDED(adapter->GetParent(IID_PPV_ARGS(&factory))))
    factory->MakeWindowAssociation(window_, DXGI_MWA_NO_ALT_ENTER);

  ComPtr<ID3DBlob> vs, ps, errors;
  if (FAILED(D3DCompile(kPresentationShader, sizeof(kPresentationShader),
                        nullptr, nullptr, nullptr,
                        "VSMain", "vs_5_0", D3DCOMPILE_ENABLE_STRICTNESS, 0,
                        &vs, &errors)))
    return false;
  if (FAILED(D3DCompile(kPresentationShader, sizeof(kPresentationShader),
                        nullptr, nullptr, nullptr,
                        "PSMain", "ps_5_0", D3DCOMPILE_ENABLE_STRICTNESS, 0,
                        &ps, &errors)))
    return false;
  if (FAILED(device_->CreateVertexShader(vs->GetBufferPointer(),
                                         vs->GetBufferSize(), nullptr,
                                         &vertexShader_)))
    return false;
  if (FAILED(device_->CreatePixelShader(
          ps->GetBufferPointer(), ps->GetBufferSize(), nullptr, &pixelShader_)))
    return false;
  D3D11_SAMPLER_DESC sampler{};
  sampler.AddressU = sampler.AddressV = sampler.AddressW =
      D3D11_TEXTURE_ADDRESS_CLAMP;
  sampler.MaxLOD = D3D11_FLOAT32_MAX;
  sampler.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR;
  if (FAILED(device_->CreateSamplerState(&sampler, &linearSampler_)))
    return false;
  D3D11_BUFFER_DESC constants{};
  constants.ByteWidth = 16;
  constants.Usage = D3D11_USAGE_DEFAULT;
  constants.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
  if (FAILED(device_->CreateBuffer(&constants, nullptr,
                                   &presentationConstants_)))
    return false;
  resize(width_, height_);
  loadLoadingScreen();
  return true;
}

void Renderer::resize(UINT width, UINT height) {
  if (!swapChain_ || !width || !height)
    return;
  width_ = width;
  height_ = height;
  context_->OMSetRenderTargets(0, nullptr, nullptr);
  backbuffer_.Reset();
  if (FAILED(swapChain_->ResizeBuffers(0, width_, height_, DXGI_FORMAT_UNKNOWN,
                     DXGI_SWAP_CHAIN_FLAG_FRAME_LATENCY_WAITABLE_OBJECT)))
    return;
  ComPtr<ID3D11Texture2D> buffer;
  if (SUCCEEDED(swapChain_->GetBuffer(0, IID_PPV_ARGS(&buffer))))
    device_->CreateRenderTargetView(buffer.Get(), nullptr, &backbuffer_);
}

void Renderer::render() {
  if (!backbuffer_ || !sourceView_)
    return;
  // Wait before writing the next back buffer instead of allowing Present calls
  // to bunch up. The timeout only protects shutdown/device-loss paths.
  WaitForSingleObjectEx(frameLatencyWaitable_, 1000, TRUE);
  constexpr float black[4] = {.004f, .002f, .006f, 1};
  context_->ClearRenderTargetView(backbuffer_.Get(), black);
  const RECT content = contentRectangle();
  const float w = static_cast<float>(content.right - content.left);
  const float h = static_cast<float>(content.bottom - content.top);
  D3D11_VIEWPORT view{};
  view.TopLeftX = static_cast<float>(content.left);
  view.TopLeftY = static_cast<float>(content.top);
  view.Width = w;
  view.Height = h;
  view.MaxDepth = 1;
  context_->RSSetViewports(1, &view);
  context_->OMSetRenderTargets(1, backbuffer_.GetAddressOf(), nullptr);
  context_->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
  context_->VSSetShader(vertexShader_.Get(), nullptr, 0);
  context_->PSSetShader(pixelShader_.Get(), nullptr, 0);
  ID3D11ShaderResourceView *frames[]{sourceView_.Get(),
                                    previousSourceView_.Get()};
  context_->PSSetShaderResources(0, 2, frames);
  // Never blend complete frames. Theme Park draws its pointer and interface
  // into that image, so blending also blends yesterday's cursor position and
  // makes direct mouse input feel delayed. Camera-only interpolation will use
  // separately identified world pixels; until then the newest frame wins.
  const float presentation[4]{1.0f, 1.0f, 1.0f, 0.0f};
  context_->UpdateSubresource(presentationConstants_.Get(), 0, nullptr,
                              presentation, 0, 0);
  context_->PSSetConstantBuffers(0, 1,
                                 presentationConstants_.GetAddressOf());
  ID3D11SamplerState *sampler = linearSampler_.Get();
  context_->PSSetSamplers(0, 1, &sampler);
  context_->Draw(3, 0);
  ID3D11ShaderResourceView *empty[]{nullptr, nullptr};
  context_->PSSetShaderResources(0, 2, empty);
  swapChain_->Present(1, 0); // V-sync avoids tearing and needless GPU load.
}

RECT Renderer::contentRectangle() const {
  // VGA 320x200 uses non-square DOS pixels and should appear as 4:3. Theme
  // Park's optional 640x480 VESA mode already uses square pixels.
  // A 320x200 mode fills a 4:3 CRT: each source pixel is 5/6 as wide as it is
  // tall. The previous reciprocal (6/5) stretched low resolution to 16:9.
  const float pixelAspect = sourceHeight_ == 200 ? (5.0f / 6.0f) : 1.0f;
  const float pictureAspect = sourceWidth_ * pixelAspect / sourceHeight_;
  float h = static_cast<float>(height_);
  float w = h * pictureAspect;
  if (w > width_) {
    w = static_cast<float>(width_);
    h = w / pictureAspect;
  }
  const LONG left = static_cast<LONG>(std::floor((width_ - w) / 2));
  const LONG top = static_cast<LONG>(std::floor((height_ - h) / 2));
  return {left, top, left + static_cast<LONG>(w), top + static_cast<LONG>(h)};
}

std::pair<std::int16_t, std::int16_t> Renderer::mapPointer(LONG x,
                                                           LONG y) const {
  const RECT area = contentRectangle();
  const double nx = std::clamp((x - area.left) /
                                   static_cast<double>(area.right - area.left),
                               0.0, 1.0);
  const double ny = std::clamp((y - area.top) /
                                   static_cast<double>(area.bottom - area.top),
                               0.0, 1.0);
  return {static_cast<std::int16_t>(nx * 65534.0 - 32767.0),
          static_cast<std::int16_t>(ny * 65534.0 - 32767.0)};
}

void Renderer::toggleFullscreen() {
  fullscreen_ = !fullscreen_;
  if (fullscreen_) {
    savedWindowStyle_ =
        static_cast<DWORD>(GetWindowLongPtrW(window_, GWL_STYLE));
    savedWindowExStyle_ =
        static_cast<DWORD>(GetWindowLongPtrW(window_, GWL_EXSTYLE));
    GetWindowRect(window_, &savedWindowRect_);
    MONITORINFO monitor{sizeof(monitor)};
    GetMonitorInfoW(MonitorFromWindow(window_, MONITOR_DEFAULTTONEAREST),
                    &monitor);
    SetWindowLongPtrW(window_, GWL_STYLE,
                      savedWindowStyle_ & ~WS_OVERLAPPEDWINDOW);
    SetWindowPos(window_, HWND_TOP, monitor.rcMonitor.left,
                 monitor.rcMonitor.top,
                 monitor.rcMonitor.right - monitor.rcMonitor.left,
                 monitor.rcMonitor.bottom - monitor.rcMonitor.top,
                 SWP_FRAMECHANGED | SWP_NOOWNERZORDER);
  } else {
    SetWindowLongPtrW(window_, GWL_STYLE, savedWindowStyle_);
    SetWindowLongPtrW(window_, GWL_EXSTYLE, savedWindowExStyle_);
    SetWindowPos(window_, nullptr, savedWindowRect_.left, savedWindowRect_.top,
                 savedWindowRect_.right - savedWindowRect_.left,
                 savedWindowRect_.bottom - savedWindowRect_.top,
                 SWP_FRAMECHANGED | SWP_NOZORDER | SWP_NOOWNERZORDER);
    // Windows sometimes defers non-client recalculation across a borderless
    // transition. Force both frame and menu metrics to be recomputed now.
    RedrawWindow(window_, nullptr, nullptr,
                 RDW_FRAME | RDW_INVALIDATE | RDW_UPDATENOW);
  }
}
