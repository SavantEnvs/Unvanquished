// In-process stand-in for the Daemon engine side of the gamelogic VM boundary.
// The real gamelogic talks to the engine over IPC (daemon/src/shared/CommonProxies.cpp and the
// BUILD_VM branch of FS::PakPath::ReadFile). The fuzz harnesses link every sgame object except
// CommonProxies.cpp and serve those syscalls from an in-memory file table filled from the input.
#pragma once
#include <string>

namespace FuzzEngine {
// Replace the whole virtual file system with exactly these files.
void ResetFiles();
void SetFile(const std::string& path, const std::string& content);
}
