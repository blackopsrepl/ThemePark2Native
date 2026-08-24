// Theme Park Native starts here. Windows GUI programs use wWinMain instead of
// console `main`. Keeping this file tiny gives readers an obvious entry point.
#include "app.h"
#include <windows.h>

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int showCommand) {
  App app;
  return app.run(instance, showCommand);
}
