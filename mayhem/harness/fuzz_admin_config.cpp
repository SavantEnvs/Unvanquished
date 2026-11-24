// Fuzzes the server admin database loader (admin.dat, src/sgame/sg_admin.cpp
// G_admin_readconfig): [level]/[admin]/[ban]/[command] blocks and their fields, then the
// cleanup that frees every list. The input is served as admin.dat (the g_admin default).
#include "sgame/sg_local.h"
#include "engine_shim.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
	FuzzEngine::ResetFiles();
	FuzzEngine::SetFile("admin.dat", std::string(reinterpret_cast<const char*>(data), size));
	try {
		G_admin_readconfig(nullptr);
	} catch (Sys::DropErr&) {
		// Sys::Drop is the engine's "reject this data" path, not a defect.
	}
	G_admin_cleanup();
	FuzzEngine::ResetFiles();
	return 0;
}
