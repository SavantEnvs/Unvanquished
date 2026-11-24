// Leaks are not the defect class fuzzed here (SPEC §6.2 item 15).
extern "C" int __lsan_is_turned_off() { return 1; }
