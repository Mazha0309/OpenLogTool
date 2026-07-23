#ifndef RUNNER_CRASH_HANDLER_H_
#define RUNNER_CRASH_HANDLER_H_

// Installs an unhandled-exception filter that writes a native minidump under
// %LOCALAPPDATA%\OpenLogTool\CrashDumps before Windows Error Reporting runs.
void InstallCrashHandler();

#endif  // RUNNER_CRASH_HANDLER_H_
