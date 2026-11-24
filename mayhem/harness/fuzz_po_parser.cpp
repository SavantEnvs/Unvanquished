// Fuzzes the vendored tinygettext .po parser (libs/tinygettext), which loads translation
// catalogs from paks: PO lexer/parser, Plural-Forms header parsing and dictionary insertion.
#include <cstddef>
#include <cstdint>
#include <sstream>
#include <string>
#include "tinygettext/dictionary.hpp"
#include "tinygettext/log.hpp"
#include "tinygettext/po_parser.hpp"

namespace {
void Quiet(const std::string&) {}
struct Init { Init() {
	tinygettext::Log::set_log_info_callback(Quiet);
	tinygettext::Log::set_log_warning_callback(Quiet);
	tinygettext::Log::set_log_error_callback(Quiet);
} } init;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
	std::istringstream in(std::string(reinterpret_cast<const char*>(data), size));
	tinygettext::Dictionary dict("UTF-8");
	try {
		tinygettext::POParser::parse("fuzz.po", in, dict);
	} catch (std::exception&) {
		// POParser reports malformed catalogs by throwing parser_exception.
		return 0;
	}
	dict.translate("Humans");
	dict.translate_plural("%d kill", "%d kills", 3);
	dict.translate_ctxt("menu", "Quit");
	return 0;
}
