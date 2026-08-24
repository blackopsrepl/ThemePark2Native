#pragma once
#include <windows.h>

// Owns the window and top-level event loop. Rendering and installation are
// separate modules so a new contributor can study one concern at a time.
class App {
public:
  int run(HINSTANCE instance, int showCommand);
};
