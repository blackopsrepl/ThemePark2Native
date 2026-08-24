#include "app.h"
#include "cursor_visibility.h"
#include "emulation_core.h"
#include "game_install.h"
#include "input_mapper.h"
#include "renderer.h"
#include "resource.h"

#include <algorithm>
#include <chrono>
#include <filesystem>
#include <shellapi.h>
#include <windowsx.h>
namespace {
constexpr wchar_t kWindowClass[] = L"ThemePark2NativeWindow";
Renderer *gRenderer = nullptr; // Win32 callbacks cannot capture a C++ object.
EmulationCore *gCore = nullptr;
std::filesystem::path gQuickState;
bool gMouseCaptured = false;
InputMapper *gInput = nullptr;

void updateMouseClip(HWND window) {
  if (!gMouseCaptured)
    return;
  RECT area{};
  GetClientRect(window, &area);
  POINT topLeft{area.left, area.top}, bottomRight{area.right, area.bottom};
  ClientToScreen(window, &topLeft);
  ClientToScreen(window, &bottomRight);
  RECT screenArea{topLeft.x, topLeft.y, bottomRight.x, bottomRight.y};
  ClipCursor(&screenArea);
}

void captureMouse(HWND window, bool capture) {
  if (gMouseCaptured == capture)
    return;
  gMouseCaptured = capture;
  if (capture) {
    SetCapture(window);
    updateMouseClip(window);
  } else {
    ReleaseCapture();
    ClipCursor(nullptr);
    if (gCore)
      for (unsigned button = 0; button != 3; ++button)
        gCore->mouseButton(button, false);
  }
}

void showError(HWND owner, const wchar_t *text) {
  MessageBoxW(owner, text, L"Theme Park Native", MB_OK | MB_ICONERROR);
}

LRESULT CALLBACK windowProcedure(HWND window, UINT message, WPARAM key,
                                 LPARAM data) {
  if (handleGameCursorMessage(window, message, data))
    return TRUE;
  switch (message) {
  case WM_SIZE:
    if (gRenderer && key != SIZE_MINIMIZED) {
      gRenderer->resize(LOWORD(data), HIWORD(data));
      updateMouseClip(window);
    }
    return 0;
  case WM_MOVE:
    updateMouseClip(window);
    return 0;
  case WM_SYSKEYDOWN:
    // Alt+Enter is the conventional PC fullscreen shortcut.
    if (gRenderer && key == VK_RETURN && (data & (1LL << 29)) &&
        !(data & (1LL << 30))) {
      gRenderer->toggleFullscreen();
      if (gRenderer->isFullscreen())
        captureMouse(window, true);
      else
        captureMouse(window, false);
      updateMouseClip(window);
      return 0;
    }
    if (gCore)
      gCore->keyEvent(gInput ? gInput->remapKeyboard(static_cast<unsigned>(key))
                             : static_cast<unsigned>(key),
                      true);
    break;
  case WM_KEYDOWN:
    if (GetKeyState(VK_CONTROL) < 0 && key == VK_F10) {
      captureMouse(window, false);
    } else if (gCore && GetKeyState(VK_CONTROL) < 0 && key == VK_F5) {
      gCore->saveState(gQuickState);
    } else if (gCore && GetKeyState(VK_CONTROL) < 0 && key == VK_F9) {
      gCore->loadState(gQuickState);
    } else if (gCore) {
      gCore->keyEvent(gInput ? gInput->remapKeyboard(static_cast<unsigned>(key))
                             : static_cast<unsigned>(key),
                      true);
    }
    return 0;
  case WM_MOUSEMOVE:
    // Absolute mapping keeps the DOS pointer exactly under the Windows cursor
    // in a resized window. It remains useful before capture, so the first click
    // lands on the item the user actually pointed at.
    if (gCore && gRenderer) {
      const auto [x, y] =
          gRenderer->mapPointer(GET_X_LPARAM(data), GET_Y_LPARAM(data));
      gCore->pointerPosition(x, y);
    }
    return 0;
  case WM_LBUTTONDOWN:
  case WM_RBUTTONDOWN:
  case WM_MBUTTONDOWN: {
    if (!gMouseCaptured)
      captureMouse(window, true);
    if (gCore) {
      const unsigned button = message == WM_LBUTTONDOWN
                                  ? 0
                                  : (message == WM_RBUTTONDOWN ? 1 : 2);
      gCore->mouseButton(button, true);
    }
    return 0;
  }
  case WM_LBUTTONUP:
  case WM_RBUTTONUP:
  case WM_MBUTTONUP:
    if (gCore) {
      const unsigned button = message == WM_LBUTTONUP
                                  ? 0
                                  : (message == WM_RBUTTONUP ? 1 : 2);
      gCore->mouseButton(button, false);
    }
    return 0;
  case WM_ACTIVATEAPP:
    if (!key)
      captureMouse(window, false);
    if (key)
      hideGameCursor();
    else
      restoreSystemCursor();
    return 0;
  case WM_KEYUP:
  case WM_SYSKEYUP:
    if (gCore)
      gCore->keyEvent(gInput ? gInput->remapKeyboard(static_cast<unsigned>(key))
                             : static_cast<unsigned>(key),
                      false);
    if (message == WM_KEYUP)
      return 0;
    break;
  case WM_DROPFILES: {
    // Dragging an image onto the window is useful while the real resource
    // decoder is under construction.
    const HDROP drop = reinterpret_cast<HDROP>(key);
    wchar_t file[MAX_PATH]{};
    if (gRenderer && DragQueryFileW(drop, 0, file, MAX_PATH) > 0 &&
        !gRenderer->loadImage(file))
      showError(window, L"Could not decode that image.");
    DragFinish(drop);
    return 0;
  }
  case WM_DESTROY:
    restoreSystemCursor();
    PostQuitMessage(0);
    return 0;
  default:
    break;
  }
  return DefWindowProcW(window, message, key, data);
}
} // namespace

int App::run(HINSTANCE instance, int showCommand) {
  // WIC and the file picker use COM on this UI thread.
  if (FAILED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)))
    return 1;
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);

  WNDCLASSEXW type{sizeof(type)};
  type.style = CS_HREDRAW | CS_VREDRAW;
  type.lpfnWndProc = windowProcedure;
  type.hInstance = instance;
  // Use the icon embedded by ThemePark2Native.rc.  The large icon appears in
  // Alt+Tab while the small one is used by the title bar and taskbar.
  type.hIcon = LoadIconW(instance, MAKEINTRESOURCEW(IDI_THEMEPARK_NATIVE));
  type.hIconSm =
      LoadIconW(instance, MAKEINTRESOURCEW(IDI_THEMEPARK_NATIVE));
  type.hCursor = nullptr;
  type.hbrBackground = static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
  type.lpszClassName = kWindowClass;
  if (!RegisterClassExW(&type))
    return 1;

  // The window is 16:9; the original picture remains aspect-correct inside it.
  RECT desired{0, 0, 1280, 720};
  AdjustWindowRectExForDpi(&desired, WS_OVERLAPPEDWINDOW, FALSE, 0, 96);
  HWND window = CreateWindowExW(
      WS_EX_ACCEPTFILES, kWindowClass,
      L"Theme Park Native", WS_OVERLAPPEDWINDOW,
      CW_USEDEFAULT, CW_USEDEFAULT, desired.right - desired.left,
      desired.bottom - desired.top, nullptr, nullptr, instance, nullptr);
  if (!window)
    return 1;
  DragAcceptFiles(window, TRUE);
  Renderer renderer;
  gRenderer = &renderer;
  if (!renderer.initialize(window)) {
    showError(window, L"Direct3D 11 initialization failed.");
    return 1;
  }

  const auto options = parseStartupOptions();
  const auto install = executableDirectory();
  runImportWizardIfNeeded(install);
  // The CD supplies the official menu background used while the private DOS
  // machine boots. If a regional release lacks it, retain the generated
  // loading screen already uploaded by Renderer::initialize().
  renderer.loadThemeParkLoadingScreen(install / L"data" / L"DATA");
  // A developer may explicitly supply a reference capture, but release builds
  // never expect or distribute one. With no --preview argument the renderer
  // displays its generated test pattern, which contains no game artwork.
  if (!options.preview.empty() && !renderer.loadImage(options.preview))
    showError(window, L"The preview image could not be loaded.");

  EmulationCore core;
  InputMapper input;
  gCore = &core;
  gInput = &input;
  gQuickState = install / L"saves" / L"quick.tpstate";
  std::wstring coreError;
  if (!core.initialize(install, renderer, coreError))
    showError(window, coreError.c_str());

  SetWindowTextW(window, L"Theme Park Native");
  ShowWindow(window, showCommand);
  // Present at the monitor's cadence while the original engine advances only
  // at the rate reported by its compatibility core. Repeating the most recent
  // completed frame is intentional: presentation refresh must never speed up
  // scripts, combat, CD commands, audio generation, or save-state evolution.
  using Clock = std::chrono::steady_clock;
  auto simulationStep = std::chrono::microseconds(
      std::max<std::int64_t>(1, core.simulationStepMicroseconds()));
  auto nextSimulation = Clock::now();
  MSG event{};
  while (event.message != WM_QUIT) {
    while (PeekMessageW(&event, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&event);
      DispatchMessageW(&event);
      if (event.message == WM_QUIT)
        break;
    }
    if (event.message != WM_QUIT) {
      // Controller and pointer sampling happen once per native presentation,
      // then the core consumes the latest state on its next simulation tick.
      input.pollController(core);
      const auto now = Clock::now();
      const auto reportedStep = std::chrono::microseconds(
          std::max<std::int64_t>(1, core.simulationStepMicroseconds()));
      if (reportedStep != simulationStep) {
        simulationStep = reportedStep;
        nextSimulation = now;
      }
      unsigned catchUpSteps = 0;
      while (now >= nextSimulation && catchUpSteps++ != 4) {
        core.runFrame();
        nextSimulation += simulationStep;
      }
      // Returning from MAIN.EXE now exits the private DOS machine. Close the
      // native window as a normal game exit; never expose an emulator menu.
      if (core.shutdownRequested()) {
        DestroyWindow(window);
        continue;
      }
      // Do not create an unbounded fast-forward after a breakpoint or suspend.
      if (now - nextSimulation > simulationStep * 4)
        nextSimulation = now + simulationStep;
      renderer.render();
    }
  }
  gCore = nullptr;
  gInput = nullptr;
  gRenderer = nullptr;
  captureMouse(window, false);
  CoUninitialize();
  return static_cast<int>(event.wParam);
}
