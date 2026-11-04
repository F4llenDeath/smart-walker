#ifndef RUNNER_WINDOWS_APP_SERVICES_H_
#define RUNNER_WINDOWS_APP_SERVICES_H_

#include <flutter/method_channel.h>
#include <windows.h>

#include <atomic>
#include <functional>
#include <memory>
#include <string>
#include <thread>
#include <vector>

struct WindowsServicesState;
struct WindowsServiceOutcome;

// Thin native boundary; all method results are delivered on the platform
// thread.
class WindowsAppServices {
 public:
  static constexpr UINT kCompletionMessage = WM_APP + 51;
  static bool IsSupportedWindows();
  static HRESULT PrepareDataDirectory(std::wstring *path, HANDLE *lock);

  WindowsAppServices(flutter::BinaryMessenger *messenger, HWND owner,
                     const std::wstring &data_directory);
  ~WindowsAppServices();
  WindowsAppServices(const WindowsAppServices &) = delete;
  WindowsAppServices &operator=(const WindowsAppServices &) = delete;

  void CompletePending();

 private:
  void HandleMethod(
      const flutter::MethodCall<flutter::EncodableValue> &call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void Launch(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result,
      std::function<WindowsServiceOutcome()> operation);

  std::shared_ptr<WindowsServicesState> state_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::string data_directory_;
  // Finished threads are joined on subsequent completions, not accumulated for
  // the lifetime of a long-running clinic session.
  struct Worker {
    std::thread thread;
    std::shared_ptr<std::atomic<bool>> done;
  };
  std::vector<Worker> workers_;
};

#endif  // RUNNER_WINDOWS_APP_SERVICES_H_