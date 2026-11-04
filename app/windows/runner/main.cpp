#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"
#include "windows_app_services.h"

namespace {
int RunApplication(const std::wstring &data_directory) {
  flutter::DartProject project(L"data");
  project.set_dart_entrypoint_arguments(GetCommandLineArguments());
  FlutterWindow window(project, data_directory);
  const Win32Window::Point origin(0, 0);
  const Win32Window::Size size(1180, 820);
  if (!window.Create(L"Smart Walker", origin, size)) return EXIT_FAILURE;
  window.SetQuitOnClose(true);
  MSG message{};
  BOOL status;
  while ((status = GetMessageW(&message, nullptr, 0, 0)) > 0) {
    TranslateMessage(&message);
    DispatchMessageW(&message);
  }
  return status == -1 ? EXIT_FAILURE : EXIT_SUCCESS;
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  if (!WindowsAppServices::IsSupportedWindows()) {
    MessageBoxW(nullptr,
                L"Smart Walker requires 64-bit Windows 10 build 19041 or newer "
                L"(LTSC 2021 or Windows 11 LTSC 2024).",
                L"Smart Walker", MB_OK | MB_ICONERROR);
    return EXIT_FAILURE;
  }
  const HRESULT initialized = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  if (FAILED(initialized)) return EXIT_FAILURE;
  std::wstring data_directory;
  HANDLE data_lock = INVALID_HANDLE_VALUE;
  const HRESULT prepared =
      WindowsAppServices::PrepareDataDirectory(&data_directory, &data_lock);
  int exit_code = EXIT_FAILURE;
  if (FAILED(prepared)) {
    const bool in_use =
        prepared == HRESULT_FROM_WIN32(ERROR_SHARING_VIOLATION) ||
        prepared == HRESULT_FROM_WIN32(ERROR_LOCK_VIOLATION);
    MessageBoxW(
        nullptr,
        in_use ? L"Smart Walker is already using this Windows user's data. "
                 L"Close the other copy before opening another."
               : L"Smart Walker could not open its local data directory. "
                 L"Contact your clinic IT administrator.",
        L"Smart Walker", MB_OK | MB_ICONERROR);
  } else {
    // Keep the data lock until the window, engine, and native workers are gone.
    exit_code = RunApplication(data_directory);
    CloseHandle(data_lock);
  }
  CoUninitialize();
  return exit_code;
}
