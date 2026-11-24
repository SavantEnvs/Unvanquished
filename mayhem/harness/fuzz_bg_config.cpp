// Fuzzes the gameplay config parsers in src/shared/bg_parse.cpp (configs/**/*.cfg shipped in
// paks): buildable/class/weapon/upgrade/missile/beacon attribute and model files plus the
// shared COM_Parse tokenizer. The first input byte picks the parser, the rest is the file,
// served through FS::PakPath::ReadFile by the in-memory engine shim.
#include "sgame/sg_local.h"
#include "engine_shim.h"

namespace {
const char* kFile = "configs/fuzz.cfg";
// Parsers set some fields to an empty literal ("") and heap-copy every non-empty token.
template <typename T> void FreeStr(T*& p) { if (p && *p) { BG_Free(const_cast<char*>(p)); p = nullptr; } }
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
	if (size < 1) return -1;
	FuzzEngine::ResetFiles();
	FuzzEngine::SetFile(kFile, std::string(reinterpret_cast<const char*>(data) + 1, size - 1));
	try {
		switch (data[0] % 8) {
		case 0: { buildableAttributes_t a{}; BG_ParseBuildableAttributeFile(kFile, &a);
			FreeStr(a.humanName); FreeStr(a.info); FreeStr(a.icon); break; }
		case 1: { buildableModelConfig_t c{}; BG_ParseBuildableModelFile(kFile, &c); break; }
		case 2: { classAttributes_t a{}; BG_ParseClassAttributeFile(kFile, &a);
			FreeStr(a.info); FreeStr(a.icon); FreeStr(a.fovCvar); break; }
		case 3: { classModelConfig_t c{}; BG_ParseClassModelFile(kFile, &c); FreeStr(c.humanName); break; }
		case 4: { weaponAttributes_t a{}; BG_ParseWeaponAttributeFile(kFile, &a);
			FreeStr(a.humanName); FreeStr(a.info); break; }
		case 5: { upgradeAttributes_t a{}; BG_ParseUpgradeAttributeFile(kFile, &a); FreeStr(a.humanName); break; }
		case 6: { missileAttributes_t a{}; BG_ParseMissileAttributeFile(kFile, &a);
			BG_ParseMissileDisplayFile(kFile, &a); break; }
		case 7: { beaconAttributes_t a{}; BG_ParseBeaconAttributeFile(kFile, &a); break; }
		}
	} catch (Sys::DropErr&) {
		// Sys::Drop is the engine's "reject this data" path, not a defect.
	}
	FuzzEngine::ResetFiles();
	return 0;
}
