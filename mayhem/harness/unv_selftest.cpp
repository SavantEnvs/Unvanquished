// Functional self-test for mayhem/test.sh, built with the project's normal flags. Each mode
// runs one real parser on repo data and prints a value test.sh compares to a known answer:
//   unv_selftest bt <bots dir> <name>    load bots/<name>.bt (with every .bt in the dir available)
//   unv_selftest upgrade <attr.cfg>      BG_ParseUpgradeAttributeFile
//   unv_selftest weapon <attr.cfg>       BG_ParseWeaponAttributeFile
#include "sgame/sg_local.h"
#include "sgame/sg_bot_parse.h"
#include "engine_shim.h"

#include <dirent.h>
#include <fstream>
#include <iostream>
#include <sstream>

static std::string Slurp(const std::string& path) {
	std::ifstream f(path, std::ios::binary);
	std::stringstream s; s << f.rdbuf(); return s.str();
}

int main(int argc, char** argv) {
	if (argc < 3) { std::cerr << "usage\n"; return 2; }
	std::string mode = argv[1];
	if (mode == "bt" && argc == 4) {
		DIR* d = opendir(argv[2]);
		if (!d) return 2;
		while (dirent* e = readdir(d)) {
			std::string n = e->d_name;
			if (n.size() > 3 && n.compare(n.size() - 3, 3, ".bt") == 0)
				FuzzEngine::SetFile("bots/" + n, Slurp(std::string(argv[2]) + "/" + n));
		}
		closedir(d);
		AITreeList_t list;
		AIBehaviorTree_t* t = ReadBehaviorTree(argv[3], &list);
		std::cout << "bt " << argv[3] << " " << (t && t->root ? "loaded" : "failed")
		          << " trees=" << list.size() << "\n";
		FreeTreeList(&list);
		return 0;
	}
	FuzzEngine::SetFile("configs/test.cfg", Slurp(argv[2]));
	if (mode == "upgrade") {
		upgradeAttributes_t a{};
		BG_ParseUpgradeAttributeFile("configs/test.cfg", &a);
		std::cout << "upgrade name=" << (a.humanName ? a.humanName : "(null)") << " price=" << a.price
		          << " slots=" << a.slots << "\n";
		return 0;
	}
	if (mode == "weapon") {
		weaponAttributes_t a{};
		BG_ParseWeaponAttributeFile("configs/test.cfg", &a);
		std::cout << "weapon name=" << (a.humanName ? a.humanName : "(null)") << " price=" << a.price
		          << " ammo=" << a.maxAmmo << "\n";
		return 0;
	}
	return 2;
}
