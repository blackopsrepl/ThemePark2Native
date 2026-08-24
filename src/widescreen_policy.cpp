#include "widescreen_policy.h"

#include <algorithm>
#include <filesystem>
#include <string>
#include <vector>
#include <windows.h>

namespace {
std::filesystem::path policyPath() {
  std::vector<wchar_t> path(32768);
  const DWORD length = GetModuleFileNameW(nullptr, path.data(),
                                          static_cast<DWORD>(path.size()));
  if (!length || length == path.size())
    return L"ThemePark-Widescreen.ini";
  return std::filesystem::path(std::wstring(path.data(), length)).parent_path() /
         L"ThemePark-Widescreen.ini";
}

bool tokenAppearsInList(std::wstring list, std::uint16_t wanted) {
  std::replace(list.begin(), list.end(), L',', L' ');
  std::replace(list.begin(), list.end(), L';', L' ');
  const wchar_t *cursor = list.c_str();
  while (*cursor) {
    while (*cursor == L' ' || *cursor == L'\t')
      ++cursor;
    wchar_t *end = nullptr;
    const unsigned long value = wcstoul(cursor, &end, 0);
    if (end == cursor)
      break;
    if (value == wanted)
      return true;
    cursor = end;
  }
  return false;
}
} // namespace

bool widescreenAllowedForRoom(std::uint16_t roomToken) {
  const auto path = policyPath();
  if (!GetPrivateProfileIntW(L"widescreen", L"enabled", 1, path.c_str()))
    return false;
  wchar_t fallbacks[4096]{};
  GetPrivateProfileStringW(L"widescreen", L"fallbackRoomTokens", L"",
                           fallbacks, static_cast<DWORD>(std::size(fallbacks)),
                           path.c_str());
  return !tokenAppearsInList(fallbacks, roomToken);
}
