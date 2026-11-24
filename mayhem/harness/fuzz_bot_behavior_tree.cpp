// Fuzzes bot behavior tree loading (bots/<name>.bt from map/mod paks): the parse.cpp
// preprocessor/tokenizer, the behavior-tree parser in sg_bot_parse.cpp and its free paths.
// The input is served as bots/fuzz.bt by the in-memory engine shim.
#include "sgame/sg_local.h"
#include "sgame/sg_bot_parse.h"
#include "engine_shim.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
	FuzzEngine::ResetFiles();
	FuzzEngine::SetFile("bots/fuzz.bt", std::string(reinterpret_cast<const char*>(data), size));
	AITreeList_t list;
	try {
		ReadBehaviorTree("fuzz", &list);
	} catch (Sys::DropErr&) {
		// Sys::Drop is the engine's "reject this data" path, not a defect.
	}
	FreeTreeList(&list);
	FuzzEngine::ResetFiles();
	return 0;
}
