#pragma once

#include <windows.h>

// Win32 maintains a display counter in addition to the current cursor handle.
// These helpers keep both mechanisms balanced around the game client.
bool handleGameCursorMessage(HWND window, UINT message, LPARAM data);
void hideGameCursor();
void restoreSystemCursor();
