#include "windows_app_services.h"

#include <flutter/standard_method_codec.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <winternl.h>
#include <wrl.h>

#include <atomic>
#include <deque>
#include <filesystem>
#include <mutex>
#include <system_error>
#include <utility>

using flutter::EncodableMap;
using flutter::EncodableValue;
using NativeResult = flutter::MethodResult<EncodableValue>;
using Microsoft::WRL::ComPtr;

struct WindowsServiceOutcome {
  HRESULT status = S_OK;
  EncodableValue value;
};

struct WindowsServicesState {
  std::mutex mutex;
  HWND owner = nullptr;
  bool stopping = false;
  bool dialog_pending = false;
  DWORD dialog_thread = 0;
  struct Completion {
    std::unique_ptr<NativeResult> result;
    WindowsServiceOutcome outcome;
  };
  std::deque<Completion> completions;
};

namespace {
constexpr char kChannel[] = "com.xichengyang.smart_walker/windows";

std::string Utf8(const std::wstring &text) {
  if (text.empty()) return {};
  const int length = WideCharToMultiByte(CP_UTF8, 0, text.c_str(), -1, nullptr,
                                         0, nullptr, nullptr);
  if (length <= 0) return {};
  std::string buffer(static_cast<size_t>(length), '\0');
  WideCharToMultiByte(CP_UTF8, 0, text.c_str(), -1, buffer.data(), length,
                      nullptr, nullptr);
  buffer.pop_back();
  return buffer;
}

std::wstring Wide(const std::string &text) {
  if (text.empty()) return {};
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                         text.c_str(), -1, nullptr, 0);
  if (length <= 0) return {};
  std::wstring buffer(static_cast<size_t>(length), L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.c_str(), -1,
                      buffer.data(), length);
  buffer.pop_back();
  return buffer;
}

std::string ErrorText(HRESULT status) {
  wchar_t *buffer = nullptr;
  const DWORD length = FormatMessageW(
      FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
          FORMAT_MESSAGE_IGNORE_INSERTS,
      nullptr, static_cast<DWORD>(status), 0,
      reinterpret_cast<wchar_t *>(&buffer), 0, nullptr);
  std::string message = length ? Utf8(std::wstring(buffer, length))
                               : "Windows could not complete the operation.";
  if (buffer) LocalFree(buffer);
  return message;
}

const std::string *Argument(const flutter::MethodCall<EncodableValue> &call,
                            const char *key) {
  const auto *map =
      call.arguments() ? std::get_if<EncodableMap>(call.arguments()) : nullptr;
  if (!map) return nullptr;
  const auto found = map->find(EncodableValue(key));
  return found == map->end() ? nullptr
                             : std::get_if<std::string>(&found->second);
}

// Initial dialog events also cover the race where shutdown starts just before
// Show creates its window. Close is always called on the dialog's STA thread.
class SaveDialogEvents final
    : public Microsoft::WRL::RuntimeClass<
          Microsoft::WRL::RuntimeClassFlags<Microsoft::WRL::ClassicCom>,
          IFileDialogEvents> {
 public:
  explicit SaveDialogEvents(std::shared_ptr<WindowsServicesState> state)
      : state_(std::move(state)) {}
  IFACEMETHODIMP OnFileOk(IFileDialog *dialog) override {
    return Check(dialog);
  }
  IFACEMETHODIMP OnFolderChanging(IFileDialog *dialog, IShellItem *) override {
    return Check(dialog);
  }
  IFACEMETHODIMP OnFolderChange(IFileDialog *dialog) override {
    return Check(dialog);
  }
  IFACEMETHODIMP OnSelectionChange(IFileDialog *dialog) override {
    return Check(dialog);
  }
  IFACEMETHODIMP
  OnShareViolation(IFileDialog *, IShellItem *,
                   FDE_SHAREVIOLATION_RESPONSE *response) override {
    *response = FDESVR_DEFAULT;
    return S_OK;
  }
  IFACEMETHODIMP OnTypeChange(IFileDialog *dialog) override {
    return Check(dialog);
  }
  IFACEMETHODIMP OnOverwrite(IFileDialog *, IShellItem *,
                             FDE_OVERWRITE_RESPONSE *response) override {
    *response = FDEOR_DEFAULT;
    return S_OK;
  }

 private:
  HRESULT Check(IFileDialog *dialog) {
    bool stopping;
    {
      std::lock_guard<std::mutex> guard(state_->mutex);
      stopping = state_->stopping;
    }
    if (stopping) dialog->Close(HRESULT_FROM_WIN32(ERROR_CANCELLED));
    return S_OK;
  }
  std::shared_ptr<WindowsServicesState> state_;
};

WindowsServiceOutcome ChooseCsvPath(
    const std::shared_ptr<WindowsServicesState> &state,
    const std::wstring &filename) {
  WindowsServiceOutcome outcome;
  const HRESULT initialized = CoInitializeEx(
      nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
  if (FAILED(initialized)) {
    outcome.status = initialized;
    std::lock_guard<std::mutex> guard(state->mutex);
    state->dialog_pending = false;
    return outcome;
  }
  {
    ComPtr<IFileSaveDialog> dialog;
    outcome.status =
        CoCreateInstance(CLSID_FileSaveDialog, nullptr, CLSCTX_INPROC_SERVER,
                         IID_PPV_ARGS(&dialog));
    HWND owner = nullptr;
    {
      std::lock_guard<std::mutex> guard(state->mutex);
      state->dialog_thread = GetCurrentThreadId();
      if (!state->stopping) owner = state->owner;
    }
    if (!owner) outcome.status = HRESULT_FROM_WIN32(ERROR_CANCELLED);
    auto events = Microsoft::WRL::Make<SaveDialogEvents>(state);
    DWORD cookie = 0;
    bool advised = false;
    if (SUCCEEDED(outcome.status)) {
      const COMDLG_FILTERSPEC filters[] = {{L"CSV files (*.csv)", L"*.csv"}};
      FILEOPENDIALOGOPTIONS options = 0;
      outcome.status = dialog->GetOptions(&options);
      if (SUCCEEDED(outcome.status)) {
        outcome.status = dialog->SetOptions(
            options | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST |
            FOS_OVERWRITEPROMPT | FOS_NOCHANGEDIR);
      }
      if (SUCCEEDED(outcome.status))
        outcome.status = dialog->SetFileTypes(1, filters);
      if (SUCCEEDED(outcome.status))
        outcome.status = dialog->SetDefaultExtension(L"csv");
      if (SUCCEEDED(outcome.status))
        outcome.status = dialog->SetFileName(filename.c_str());
      if (SUCCEEDED(outcome.status))
        outcome.status = dialog->SetTitle(L"Export Smart Walker trial");
      if (SUCCEEDED(outcome.status)) {
        outcome.status = dialog->Advise(events.Get(), &cookie);
        advised = SUCCEEDED(outcome.status);
      }
      if (SUCCEEDED(outcome.status)) outcome.status = dialog->Show(owner);
      if (SUCCEEDED(outcome.status)) {
        ComPtr<IShellItem> item;
        outcome.status = dialog->GetResult(&item);
        PWSTR path = nullptr;
        if (SUCCEEDED(outcome.status))
          outcome.status = item->GetDisplayName(SIGDN_FILESYSPATH, &path);
        if (SUCCEEDED(outcome.status))
          outcome.value = EncodableValue(Utf8(path));
        CoTaskMemFree(path);
      }
      if (advised) dialog->Unadvise(cookie);
    }
    if (outcome.status == HRESULT_FROM_WIN32(ERROR_CANCELLED))
      outcome.status = S_OK;
    {
      std::lock_guard<std::mutex> guard(state->mutex);
      state->dialog_thread = 0;
      state->dialog_pending = false;
    }
  }
  CoUninitialize();
  return outcome;
}
}  // namespace

bool WindowsAppServices::IsSupportedWindows() {
  using RtlGetVersionFunction = LONG(WINAPI *)(PRTL_OSVERSIONINFOW);
  const auto version_function = reinterpret_cast<RtlGetVersionFunction>(
      GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "RtlGetVersion"));
  RTL_OSVERSIONINFOW version{};
  version.dwOSVersionInfoSize = sizeof(version);
  return version_function && version_function(&version) == 0 &&
         version.dwMajorVersion >= 10 && version.dwBuildNumber >= 19041;
}

HRESULT WindowsAppServices::PrepareDataDirectory(std::wstring *path,
                                                 HANDLE *lock) {
  PWSTR local = nullptr;
  const HRESULT status = SHGetKnownFolderPath(FOLDERID_LocalAppData,
                                              KF_FLAG_CREATE, nullptr, &local);
  if (FAILED(status)) return status;
  *path = std::wstring(local) + L"\\Smart Walker";
  CoTaskMemFree(local);
  std::error_code error;
  std::filesystem::create_directories(*path, error);
  if (error) return HRESULT_FROM_WIN32(static_cast<DWORD>(error.value()));
  *lock = CreateFileW((*path + L"\\.instance.lock").c_str(),
                      GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ, nullptr,
                      OPEN_ALWAYS, FILE_ATTRIBUTE_HIDDEN, nullptr);
  return *lock == INVALID_HANDLE_VALUE ? HRESULT_FROM_WIN32(GetLastError())
                                       : S_OK;
}

WindowsAppServices::WindowsAppServices(flutter::BinaryMessenger *messenger,
                                       HWND owner,
                                       const std::wstring &data_directory)
    : state_(std::make_shared<WindowsServicesState>()),
      data_directory_(Utf8(data_directory)) {
  state_->owner = owner;
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, kChannel, &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto &call, auto result) {
    HandleMethod(call, std::move(result));
  });
}

WindowsAppServices::~WindowsAppServices() {
  channel_->SetMethodCallHandler(nullptr);
  DWORD dialog_thread;
  {
    std::lock_guard<std::mutex> guard(state_->mutex);
    state_->stopping = true;
    state_->owner = nullptr;
    dialog_thread = state_->dialog_thread;
  }
  // A dialog on another STA can synchronously message its owner when it closes.
  // Pump messages while workers finish rather than deadlocking that STA in
  // join. Repeat enumeration to cover a window created just after shutdown
  // began.
  bool quit_seen = false;
  WPARAM quit_code = 0;
  while (true) {
    bool finished = true;
    for (const auto &worker : workers_)
      finished = finished && worker.done->load();
    if (finished) break;
    {
      std::lock_guard<std::mutex> guard(state_->mutex);
      dialog_thread = state_->dialog_thread;
    }
    if (dialog_thread) {
      EnumThreadWindows(
          dialog_thread,
          [](HWND window, LPARAM) -> BOOL {
            PostMessageW(window, WM_CLOSE, 0, 0);
            return TRUE;
          },
          0);
    }
    MSG message{};
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
      if (message.message == WM_QUIT) {
        quit_seen = true;
        quit_code = message.wParam;
      } else {
        TranslateMessage(&message);
        DispatchMessageW(&message);
      }
    }
    MsgWaitForMultipleObjectsEx(0, nullptr, 20, QS_ALLINPUT,
                                MWMO_INPUTAVAILABLE);
  }
  for (auto &worker : workers_) {
    if (worker.thread.joinable()) worker.thread.join();
  }
  state_->completions.clear();
  if (quit_seen) PostQuitMessage(static_cast<int>(quit_code));
}

void WindowsAppServices::Launch(
    std::unique_ptr<NativeResult> result,
    std::function<WindowsServiceOutcome()> operation) {
  auto done = std::make_shared<std::atomic<bool>>(false);
  auto state = state_;
  workers_.push_back({std::thread([state, done, result = std::move(result),
                                   operation = std::move(operation)]() mutable {
                        WindowsServiceOutcome outcome;
                        try {
                          outcome = operation();
                        } catch (...) {
                          outcome.status = E_FAIL;
                        }
                        {
                          std::lock_guard<std::mutex> guard(state->mutex);
                          if (!state->stopping) {
                            state->completions.push_back(
                                {std::move(result), std::move(outcome)});
                            done->store(true);
                            PostMessageW(state->owner, kCompletionMessage, 0,
                                         0);
                          }
                        }
                        done->store(true);
                      }),
                      done});
}

void WindowsAppServices::CompletePending() {
  std::deque<WindowsServicesState::Completion> completed;
  {
    std::lock_guard<std::mutex> guard(state_->mutex);
    completed.swap(state_->completions);
  }
  for (auto &completion : completed) {
    if (FAILED(completion.outcome.status)) {
      completion.result->Error("windows-operation-failed",
                               ErrorText(completion.outcome.status));
    } else {
      completion.result->Success(completion.outcome.value);
    }
  }
  for (auto worker = workers_.begin(); worker != workers_.end();) {
    if (worker->done->load()) {
      worker->thread.join();
      worker = workers_.erase(worker);
    } else {
      ++worker;
    }
  }
}

void WindowsAppServices::HandleMethod(
    const flutter::MethodCall<EncodableValue> &call,
    std::unique_ptr<NativeResult> result) {
  if (call.method_name() == "dataDirectory") {
    result->Success(EncodableValue(data_directory_));
  } else if (call.method_name() == "chooseCsvPath") {
    const auto *filename = Argument(call, "filename");
    if (!filename || filename->empty() ||
        filename->find_first_of("/\\:") != std::string::npos) {
      result->Error("invalid-argument", "A plain CSV filename is required.");
      return;
    }
    {
      std::lock_guard<std::mutex> guard(state_->mutex);
      if (state_->dialog_pending) {
        result->Error("export-busy", "Close the current Save As dialog first.");
        return;
      }
      state_->dialog_pending = true;
    }
    Launch(std::move(result), [state = state_, filename = Wide(*filename)] {
      return ChooseCsvPath(state, filename);
    });
  } else if (call.method_name() == "replaceFile") {
    const auto *source = Argument(call, "source");
    const auto *destination = Argument(call, "destination");
    if (!source || !destination || source->empty() || destination->empty()) {
      result->Error("invalid-argument",
                    "Source and destination paths are required.");
      return;
    }
    Launch(std::move(result),
           [source = Wide(*source), destination = Wide(*destination)] {
             WindowsServiceOutcome outcome;
             if (source.empty() || destination.empty()) {
               outcome.status = E_INVALIDARG;
             } else if (!MoveFileExW(source.c_str(), destination.c_str(),
                                     MOVEFILE_REPLACE_EXISTING |
                                         MOVEFILE_WRITE_THROUGH)) {
               outcome.status = HRESULT_FROM_WIN32(GetLastError());
             }
             return outcome;
           });
  } else {
    result->NotImplemented();
  }
}