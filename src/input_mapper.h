#pragma once

#include <array>
#include <cstdint>

class EmulationCore;

// Converts modern Windows inputs into the deliberately small keyboard/mouse
// vocabulary understood by the 1994 engine. Keeping this policy outside the
// emulator and window code makes the bindings easy for a new contributor to
// find and change.
class InputMapper {
public:
  unsigned remapKeyboard(unsigned windowsKey) const;
  void pollController(EmulationCore &core);

private:
  void setKey(EmulationCore &core, unsigned slot, unsigned windowsKey,
              bool down);
  void releaseController(EmulationCore &core);

  std::array<bool, 10> keyDown_{};
  std::array<bool, 2> mouseDown_{};
  bool controllerConnected_ = false;
};
