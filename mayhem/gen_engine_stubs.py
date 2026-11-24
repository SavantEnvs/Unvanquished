#!/usr/bin/env python3
"""Emit an assembly file defining every global symbol of the replaced engine-proxy objects
(daemon CommonProxies.cpp, server/sg_api.cpp) that the harness shim does not define itself.
Functions become an abort() naming the symbol; data becomes zeroed storage of the same size.
usage: gen_engine_stubs.py OUT.S --replaced OBJ... --provided OBJ..."""
import subprocess, sys

def syms(objs):
    out = subprocess.run(["nm", "-S", "--defined-only", "-g", *objs], check=True,
                         capture_output=True, text=True).stdout
    res = {}
    for line in out.splitlines():
        p = line.split()
        if len(p) == 4:
            _, size, kind, name = p
        elif len(p) == 3 and len(p[1]) == 1:
            size, kind, name = "0", p[1], p[2]
        else:
            continue
        if kind in "TDBR":  # strong definitions only; weak (W/V) are emitted by users too
            res[name] = (kind, int(size, 16))
    return res

args = sys.argv[1:]
out = args[0]
i_r, i_p = args.index("--replaced"), args.index("--provided")
replaced = syms(args[i_r + 1:i_p])
provided = syms(args[i_p + 1:])
lines = ["\t.text"]
data = []
for n, (kind, size) in sorted(replaced.items()):
    if n in provided:
        continue
    if kind == "T":
        lbl = f".Lname_{len(lines)}"
        lines += [f"\t.globl {n}", f"\t.type {n},@function", f"{n}:",
                  f"\tleaq {lbl}(%rip), %rdi", "\tjmp unv_fuzz_engine_stub_called",
                  "\t.section .rodata", f"{lbl}:", f"\t.asciz \"{n}\"", "\t.text"]
    else:
        data += [f"\t.globl {n}", f"\t.type {n},@object", f"\t.size {n}, {max(size,1)}",
                 "\t.balign 16", f"{n}:", f"\t.zero {max(size,1)}"]
lines += ["\t.bss"] + data + ['\t.section .note.GNU-stack,"",@progbits']
open(out, "w").write("\n".join(lines) + "\n")
