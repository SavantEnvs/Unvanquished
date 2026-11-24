// Functional self-test for the tinygettext .po parser: po_selftest <file.po> <msgid> prints the
// translation (mayhem/test.sh compares it to the catalog's known msgstr).
#include <fstream>
#include <iostream>
#include "tinygettext/dictionary.hpp"
#include "tinygettext/po_parser.hpp"

int main(int argc, char** argv) {
	if (argc != 3) return 2;
	std::ifstream in(argv[1]);
	tinygettext::Dictionary dict("UTF-8");
	tinygettext::POParser::parse(argv[1], in, dict);
	std::cout << "po " << argv[2] << "=" << dict.translate(argv[2]) << "\n";
	return 0;
}
