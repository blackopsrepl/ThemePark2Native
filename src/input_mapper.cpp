#include "input_mapper.h"

#include "emulation_core.h"

#include <algorithm>
#include <cmath>
#include <windows.h>
#include <xinput.h>

namespace {
constexpr SHORT kStickDeadZone = 9000;

bool button(const XINPUT_STATE &state, WORD mask) {
  return (state.Gamepad.wButtons & mask) != 0;
}

int cursorDelta(SHORT axis) {
  // A small dead zone prevents an aging stick from drifting. The nonlinear
  // response keeps icon selection precise near center while still allowing a
  // fast sweep across the 320-pixel game screen.
  const int magnitude = std::abs(static_cast<int>(axis));
  if (magnitude <= kStickDeadZone)
    return 0;
  const float normalized = static_cast<float>(magnitude - kStickDeadZone) /
                           (32767 - kStickDeadZone);
  const int speed = 1 + static_cast<int>(normalized * normalized * 11.0f);
  return axis < 0 ? -speed : speed;
}
} // namespace

unsigned InputMapper::remapKeyboard(unsigned key) const {
  // Theme Park already has useful single-key management shortcuts. Preserve
  // them exactly; its primary interaction is the mouse, not avatar movement.
  return key;
}

void InputMapper::setKey(EmulationCore &core, unsigned slot,
                         unsigned windowsKey, bool down) {
  if (keyDown_[slot] == down)
    return;
  keyDown_[slot] = down;
  core.keyEvent(windowsKey, down);
}

void InputMapper::releaseController(EmulationCore &core) {
  constexpr unsigned keys[]{VK_UP, VK_DOWN, VK_LEFT, VK_RIGHT, 'F',
                            'O',   'P',     VK_ESCAPE, VK_RETURN, VK_SPACE};
  for (unsigned index = 0; index != std::size(keys); ++index)
    setKey(core, index, keys[index], false);
  for (unsigned buttonIndex = 0; buttonIndex != mouseDown_.size();
       ++buttonIndex) {
    if (mouseDown_[buttonIndex])
      core.mouseButton(buttonIndex, false);
    mouseDown_[buttonIndex] = false;
  }
}

void InputMapper::pollController(EmulationCore &core) {
  XINPUT_STATE state{};
  if (XInputGetState(0, &state) != ERROR_SUCCESS) {
    if (controllerConnected_)
      releaseController(core);
    controllerConnected_ = false;
    return;
  }
  controllerConnected_ = true;

  const auto &pad = state.Gamepad;
  // Menus accept the keyboard arrows, so the D-pad remains precise even when
  // the game changes screens. The right stick always controls the pointer.
  setKey(core, 0, VK_UP, button(state, XINPUT_GAMEPAD_DPAD_UP));
  setKey(core, 1, VK_DOWN, button(state, XINPUT_GAMEPAD_DPAD_DOWN));
  setKey(core, 2, VK_LEFT, button(state, XINPUT_GAMEPAD_DPAD_LEFT));
  setKey(core, 3, VK_RIGHT, button(state, XINPUT_GAMEPAD_DPAD_RIGHT));
  setKey(core, 4, 'F', button(state, XINPUT_GAMEPAD_X));
  setKey(core, 5, 'O', button(state, XINPUT_GAMEPAD_Y));
  setKey(core, 6, 'P', button(state, XINPUT_GAMEPAD_START));
  setKey(core, 7, VK_ESCAPE, button(state, XINPUT_GAMEPAD_BACK));
  setKey(core, 8, VK_RETURN, button(state, XINPUT_GAMEPAD_RIGHT_SHOULDER));
  setKey(core, 9, VK_SPACE, button(state, XINPUT_GAMEPAD_LEFT_SHOULDER));

  int mouseX = cursorDelta(pad.sThumbRX);
  int mouseY = -cursorDelta(pad.sThumbRY);
  core.mouseMotion(mouseX, mouseY);

  const bool clicks[]{button(state, XINPUT_GAMEPAD_A) ||
                          pad.bRightTrigger > XINPUT_GAMEPAD_TRIGGER_THRESHOLD,
                      button(state, XINPUT_GAMEPAD_B) ||
                          pad.bLeftTrigger > XINPUT_GAMEPAD_TRIGGER_THRESHOLD};
  for (unsigned index = 0; index != std::size(clicks); ++index) {
    if (clicks[index] != mouseDown_[index])
      core.mouseButton(index, clicks[index]);
    mouseDown_[index] = clicks[index];
  }
}
