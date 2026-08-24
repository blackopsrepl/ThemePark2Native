#include "emulation_core.h"

#include <algorithm>
#include <iterator>
#include <windows.h>

namespace {
unsigned translateKey(unsigned key) {
  if ((key >= 'A' && key <= 'Z') || (key >= '0' && key <= '9'))
    return key >= 'A' ? key + ('a' - 'A') : key;
  if (key >= VK_F1 && key <= VK_F12)
    return 282 + key - VK_F1;
  if (key >= VK_NUMPAD0 && key <= VK_NUMPAD9)
    return 256 + key - VK_NUMPAD0;
  switch (key) {
  case VK_BACK:
    return 8;
  case VK_TAB:
    return 9;
  case VK_RETURN:
    return 13;
  case VK_ESCAPE:
    return 27;
  case VK_SPACE:
    return 32;
  case VK_DELETE:
    return 127;
  case VK_UP:
    return 273;
  case VK_DOWN:
    return 274;
  case VK_RIGHT:
    return 275;
  case VK_LEFT:
    return 276;
  case VK_INSERT:
    return 277;
  case VK_HOME:
    return 278;
  case VK_END:
    return 279;
  case VK_PRIOR:
    return 280;
  case VK_NEXT:
    return 281;
  case VK_NUMLOCK:
    return 300;
  case VK_CAPITAL:
    return 301;
  case VK_SCROLL:
    return 302;
  case VK_RSHIFT:
    return 303;
  case VK_LSHIFT:
  case VK_SHIFT:
    return 304;
  case VK_RCONTROL:
    return 305;
  case VK_LCONTROL:
  case VK_CONTROL:
    return 306;
  case VK_RMENU:
    return 307;
  case VK_LMENU:
  case VK_MENU:
    return 308;
  case VK_DECIMAL:
    return 266;
  case VK_DIVIDE:
    return 267;
  case VK_MULTIPLY:
    return 268;
  case VK_SUBTRACT:
    return 269;
  case VK_ADD:
    return 270;
  case VK_OEM_MINUS:
    return '-';
  case VK_OEM_PLUS:
    return '=';
  case VK_OEM_4:
    return '[';
  case VK_OEM_6:
    return ']';
  case VK_OEM_5:
    return '\\';
  case VK_OEM_1:
    return ';';
  case VK_OEM_7:
    return '\'';
  case VK_OEM_COMMA:
    return ',';
  case VK_OEM_PERIOD:
    return '.';
  case VK_OEM_2:
    return '/';
  case VK_OEM_3:
    return '`';
  default:
    return 0;
  }
}

std::uint16_t modifiers() {
  std::uint16_t value = 0;
  if (GetKeyState(VK_SHIFT) < 0)
    value |= 0x01;
  if (GetKeyState(VK_CONTROL) < 0)
    value |= 0x02;
  if (GetKeyState(VK_MENU) < 0)
    value |= 0x04;
  if (GetKeyState(VK_NUMLOCK) & 1)
    value |= 0x1000;
  if (GetKeyState(VK_CAPITAL) & 1)
    value |= 0x2000;
  if (GetKeyState(VK_SCROLL) & 1)
    value |= 0x4000;
  return value;
}
} // namespace

void EmulationCore::keyEvent(unsigned windowsKey, bool down) {
  if (keyboardEvent_) {
    const unsigned key = translateKey(windowsKey);
    if (key)
      keyboardEvent_(down, key, 0, modifiers());
  }
}

std::int16_t EmulationCore::readInput(unsigned, unsigned device, unsigned,
                                      unsigned id) const {
  // Pure asks separately for absolute pointer state and relative mouse state.
  const unsigned kind = device & 0xff;
  if (kind == libretro::Pointer) {
    if (id == 0)
      return pointerX_;
    if (id == 1)
      return pointerY_;
    if (id == 2)
      return mouseButtons_[0] ? 1 : 0;
    return id == 3 ? 1 : 0; // Exactly one native pointer is available.
  }
  if (kind != libretro::Mouse)
    return 0;
  if (id == 0)
    return static_cast<std::int16_t>(std::clamp(frameMouseX_, -32768, 32767));
  if (id == 1)
    return static_cast<std::int16_t>(std::clamp(frameMouseY_, -32768, 32767));
  return id >= 2 && id <= 4 ? (mouseButtons_[id - 2] ? 1 : 0) : 0;
}

void EmulationCore::mouseMotion(int horizontal, int vertical) {
  // Controller motion updates the same absolute pointer used by the mouse.
  pointerX_ = static_cast<std::int16_t>(std::clamp(
      static_cast<int>(pointerX_) + horizontal * 192, -32767, 32767));
  pointerY_ = static_cast<std::int16_t>(std::clamp(
      static_cast<int>(pointerY_) + vertical * 256, -32767, 32767));
  pendingMouseX_ += horizontal;
  pendingMouseY_ += vertical;
}

void EmulationCore::pointerPosition(std::int16_t horizontal,
                                    std::int16_t vertical) {
  pointerX_ = horizontal;
  pointerY_ = vertical;
}

void EmulationCore::mouseButton(unsigned button, bool down) {
  if (button < std::size(mouseButtons_))
    mouseButtons_[button] = down;
}

void EmulationCore::pollInput() {
  frameMouseX_ = pendingMouseX_;
  frameMouseY_ = pendingMouseY_;
  pendingMouseX_ = pendingMouseY_ = 0;
}
