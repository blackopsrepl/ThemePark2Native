#pragma once
#include <filesystem>
#include <string>
struct StartupOptions {
  std::filesystem::path preview;
};
StartupOptions parseStartupOptions();
std::filesystem::path executableDirectory();
void runImportWizardIfNeeded(const std::filesystem::path &install);
std::wstring validateGameInstallation(const std::filesystem::path &install);
