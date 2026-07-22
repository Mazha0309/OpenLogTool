#include "crash_handler.h"

#include <dbghelp.h>
#include <windows.h>

#include <cwchar>

namespace {

LONG WINAPI WriteUnhandledExceptionDump(EXCEPTION_POINTERS* exception) {
  static LONG writing_dump = 0;
  if (InterlockedCompareExchange(&writing_dump, 1, 0) != 0) {
    return EXCEPTION_CONTINUE_SEARCH;
  }

  wchar_t local_app_data[MAX_PATH] = {};
  const DWORD length = GetEnvironmentVariableW(
      L"LOCALAPPDATA", local_app_data, static_cast<DWORD>(MAX_PATH));
  if (length == 0 || length >= MAX_PATH) {
    return EXCEPTION_CONTINUE_SEARCH;
  }

  wchar_t app_directory[MAX_PATH] = {};
  wchar_t dump_directory[MAX_PATH] = {};
  swprintf_s(app_directory, L"%ls\\OpenLogTool", local_app_data);
  swprintf_s(dump_directory, L"%ls\\CrashDumps", app_directory);
  CreateDirectoryW(app_directory, nullptr);
  CreateDirectoryW(dump_directory, nullptr);

  SYSTEMTIME time = {};
  GetLocalTime(&time);
  wchar_t dump_path[MAX_PATH] = {};
  swprintf_s(
      dump_path,
      L"%ls\\openlogtool-%04u%02u%02u-%02u%02u%02u-%lu.dmp",
      dump_directory, time.wYear, time.wMonth, time.wDay, time.wHour,
      time.wMinute, time.wSecond, GetCurrentProcessId());

  HANDLE file = CreateFileW(dump_path, GENERIC_WRITE, FILE_SHARE_READ, nullptr,
                            CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file != INVALID_HANDLE_VALUE) {
    MINIDUMP_EXCEPTION_INFORMATION exception_information = {};
    exception_information.ThreadId = GetCurrentThreadId();
    exception_information.ExceptionPointers = exception;
    exception_information.ClientPointers = FALSE;
    const auto dump_type = static_cast<MINIDUMP_TYPE>(
        MiniDumpNormal | MiniDumpWithThreadInfo | MiniDumpWithUnloadedModules |
        MiniDumpWithProcessThreadData);
    MiniDumpWriteDump(GetCurrentProcess(), GetCurrentProcessId(), file,
                      dump_type, &exception_information, nullptr, nullptr);
    CloseHandle(file);
  }

  // Preserve the normal Windows Error Reporting path after capturing the
  // application-local dump.
  return EXCEPTION_CONTINUE_SEARCH;
}

}  // namespace

void InstallCrashHandler() {
  SetUnhandledExceptionFilter(WriteUnhandledExceptionDump);
}
