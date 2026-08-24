#include "game_install.h"

#include <algorithm>
#include <array>
#include <fstream>
#include <iterator>
#include <span>
#include <vector>
#include <windows.h>
#include <shellapi.h>

namespace {
bool repairMouseFreeze(const std::filesystem::path &executable) {
  // Theme Park's retail executable contains a known one-byte branch error in
  // its VGA/VESA transition. Patching the imported copy is safer and more
  // responsive than routing every movement through an accelerated DOS mouse.
  constexpr std::array<std::uint8_t, 4> original{0x0F, 0x84, 0x4D, 0x05};
  constexpr std::array<std::uint8_t, 4> repaired{0x0F, 0x84, 0x43, 0x05};
  std::ifstream input(executable, std::ios::binary);
  std::vector<std::uint8_t> bytes{std::istreambuf_iterator<char>(input),
                                  std::istreambuf_iterator<char>()};
  if (!input.eof() || bytes.empty())
    return false;

  const auto firstOriginal =
      std::search(bytes.begin(), bytes.end(), original.begin(), original.end());
  const auto firstRepaired =
      std::search(bytes.begin(), bytes.end(), repaired.begin(), repaired.end());
  const auto noOriginalDuplicate =
      firstOriginal == bytes.end() ||
      std::search(firstOriginal + original.size(), bytes.end(), original.begin(),
                  original.end()) == bytes.end();
  const auto noRepairedDuplicate =
      firstRepaired == bytes.end() ||
      std::search(firstRepaired + repaired.size(), bytes.end(), repaired.begin(),
                  repaired.end()) == bytes.end();
  if (!noOriginalDuplicate || !noRepairedDuplicate)
    return false; // Refuse an ambiguous executable rather than guessing.
  if (firstRepaired != bytes.end() && firstOriginal == bytes.end())
    return true;
  if (firstOriginal == bytes.end() || firstRepaired != bytes.end())
    return false;

  bytes[static_cast<std::size_t>(firstOriginal - bytes.begin()) + 2] = 0x43;
  std::ofstream output(executable, std::ios::binary | std::ios::trunc);
  output.write(reinterpret_cast<const char *>(bytes.data()), bytes.size());
  output.close();
  return output.good();
}

void writeNativeConfiguration(const std::filesystem::path &data) {
  // These tiny text files are host configuration, not original game data.
  // Recreate them when repairing an early import so users never need the DOS
  // setup utility and its machine-specific installation paths.
  if (!std::filesystem::exists(data / L"SNDSETUP.INF")) {
    std::ofstream sound(data / L"SNDSETUP.INF", std::ios::binary);
    sound << "SOUNDFX = SB16 220 5 1\r\n"
             "MUSIC = ADLIB 388 0 0\r\n";
  }
}

bool hasHeader(const std::filesystem::path &file,
               std::span<const std::uint8_t> expected) {
  HANDLE handle = CreateFileW(file.c_str(), GENERIC_READ, FILE_SHARE_READ,
                              nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL,
                              nullptr);
  if (handle == INVALID_HANDLE_VALUE)
    return false;
  std::array<std::uint8_t, 8> bytes{};
  DWORD read = 0;
  const BOOL ok = ReadFile(handle, bytes.data(),
                           static_cast<DWORD>(expected.size()), &read, nullptr);
  CloseHandle(handle);
  return ok && read == expected.size() &&
         std::equal(expected.begin(), expected.end(), bytes.begin());
}
} // namespace

StartupOptions parseStartupOptions() {
  // Normal players need no arguments; --preview remains a renderer test aid.
  int count = 0;
  wchar_t **arguments = CommandLineToArgvW(GetCommandLineW(), &count);
  StartupOptions options;
  if (arguments) {
    for (int index = 1; index + 1 < count; ++index)
      if (std::wstring_view(arguments[index]) == L"--preview")
        options.preview = arguments[++index];
    LocalFree(arguments);
  }
  return options;
}

std::filesystem::path executableDirectory() {
  // Shortcuts may choose any working directory, so resolve beside the EXE.
  std::wstring path(32768, L'\0');
  const DWORD length =
      GetModuleFileNameW(nullptr, path.data(), static_cast<DWORD>(path.size()));
  if (!length || length == path.size())
    return std::filesystem::current_path();
  path.resize(length);
  return std::filesystem::path(path).parent_path();
}

void runImportWizardIfNeeded(const std::filesystem::path &install) {
  const auto data = install / L"data";
  if (std::filesystem::exists(data / L"MAIN.EXE")) {
    repairMouseFreeze(data / L"MAIN.EXE");
    writeNativeConfiguration(data);
    return;
  }
  const auto script = install / L"tools" / L"Import-ThemePark.ps1";
  if (!std::filesystem::exists(script))
    return;
  std::wstring command =
      L"powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File \"" +
      script.wstring() + L"\" -InstallDirectory \"" + install.wstring() +
      L"\"";
  STARTUPINFOW startup{sizeof(startup)};
  PROCESS_INFORMATION process{};
  if (CreateProcessW(nullptr, command.data(), nullptr, nullptr, FALSE,
                     CREATE_NO_WINDOW, nullptr, install.c_str(), &startup,
                     &process)) {
    WaitForSingleObject(process.hProcess, INFINITE);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
  }
}

std::wstring validateGameInstallation(const std::filesystem::path &install) {
  const auto data = install / L"data";
  constexpr std::array<std::uint8_t, 2> mz{'M', 'Z'};
  const bool programs = hasHeader(data / L"MAIN.EXE", mz) &&
                        hasHeader(data / L"INTRO.EXE", mz);
  const bool graphics =
      std::filesystem::exists(data / L"DATA" / L"INTRO.DAT") &&
      std::filesystem::exists(data / L"DATA" / L"MSPR-0.DAT");
  const bool audio =
      std::filesystem::exists(data / L"DATA" / L"MUSIC0-0.DAT") &&
      std::filesystem::exists(data / L"DATA" / L"SNDS0-0.DAT");
  const bool configuration =
      std::filesystem::exists(data / L"SNDSETUP.INF");
  const bool mouseCompatibility = repairMouseFreeze(data / L"MAIN.EXE");
  if (programs && graphics && audio && configuration && mouseCompatibility)
    return L"Theme Park PC CD data and file-based audio verified";
  return L"game data incomplete or unsupported";
}
