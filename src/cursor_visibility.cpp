#include "cursor_visibility.h"

namespace {
bool gCursorHidden = false;
}

void hideGameCursor() {
  // SetCursor alone can be undone when Windows synthesizes WM_SETCURSOR after
  // capture or a fullscreen transition.  Normalize this UI thread's display
  // counter once, then also clear the active handle for immediate feedback.
  // The matching restore function returns the counter to the visible state.
  if (!gCursorHidden) {
    while (ShowCursor(FALSE) >= 0) {
    }
    gCursorHidden = true;
  }
  SetCursor(nullptr);
}

void restoreSystemCursor() {
  if (gCursorHidden) {
    while (ShowCursor(TRUE) < 0) {
    }
    gCursorHidden = false;
  }
  SetCursor(LoadCursorW(nullptr, IDC_ARROW));
}

bool handleGameCursorMessage(HWND window, UINT message, LPARAM data) {
  if (message == WM_SETCURSOR) {
    if (LOWORD(data) == HTCLIENT) {
      hideGameCursor();
      return true;
    }
    restoreSystemCursor();
    return false;
  }
  if (message == WM_MOUSEMOVE) {
    hideGameCursor();
    TRACKMOUSEEVENT tracking{sizeof(tracking), TME_LEAVE, window, 0};
    TrackMouseEvent(&tracking);
  } else if (message == WM_MOUSELEAVE || message == WM_NCMOUSEMOVE) {
    restoreSystemCursor();
  }
  return false;
}
