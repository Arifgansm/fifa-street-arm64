#!/usr/bin/env python3
"""Writes a stand-in for the code `rexglue codegen` generates from the game,
so the port can be compiled and linked without the game (in CI).

    scripts/placeholder-codegen.py PROJECT SDK

PROJECT is ReStreet's recomp project (Installer/recomp-template, made by
prepare.sh), SDK the SDK's source tree (for its codegen templates). It writes
PROJECT/generated/{default,fifadllzf_xex,FootballCompEngzf_xex} the way
codegen lays them out: the executable's module and the two guest DLL
modules, each built as its own shared library.

Every module declares and defines (with empty bodies) only the recompiled
functions ReStreet's own sources name, with made-up image addresses. The
result builds and links like the real thing but does nothing: it holds no
code or data of the game, and nothing built from it may be run.

Needs jinja2 (the codegen templates are inja, which jinja2 reads).
"""
import re
import sys
from pathlib import Path

import jinja2

project_dir, sdk = (Path(p) for p in sys.argv[1:3])
project = "fifastreet"
generated = project_dir / "generated"


class CBool:
    """A flag that tests like a bool and prints as C++ (false/true)."""

    def __init__(self, value: bool):
        self.value = value

    def __bool__(self):
        return self.value

    def __str__(self):
        return "true" if self.value else "false"


env = jinja2.Environment(
    loader=jinja2.FileSystemLoader(str(sdk / "resources" / "templates")),
    keep_trailing_newline=True)
env.globals["cmake_var"] = lambda name: "${" + name + "}"


def render(name: str, values: dict) -> str:
    return env.get_template(f"codegen/{name}.inja").render(**values)


def named_functions(sources):
    """The sub_XXXXXXXX functions the given sources hook or call."""
    names = set()
    for path in sources:
        text = path.read_text(encoding="utf-8-sig", errors="replace")
        text = re.sub(r"//[^\n]*|/\*.*?\*/", "", text, flags=re.S)
        names.update(re.findall(r"(?<![0-9A-Za-z])sub_[0-9A-F]{8}(?!\w)", text))
    return sorted(names)


src = project_dir / "src"
modules = [
    # (output folder, is a DLL, image base, sources that name its functions)
    ("default", False, 0x82000000, [src / "main.cpp", src / f"{project}_app.h", src / "startup_race_hooks.cpp"]),
    ("fifadllzf_xex", True, 0x86000000, [src / "stubs.cpp", src / "native_libc_hooks.cpp"]),
    ("FootballCompEngzf_xex", True, 0x8A000000, []),
]
dll_modules = [m for m in modules if m[1]]

for out_name, is_dll, image_base, sources in modules:
    out = generated / out_name
    out.mkdir(parents=True, exist_ok=True)
    names = named_functions(sources)
    code_base = image_base + 0x100000
    values = {
        "project": project,
        "is_dll": is_dll,
        "has_dll_modules": True,
        "image_base": f"0x{image_base:08X}", "image_size": "0x2000000",
        "code_base": f"0x{code_base:08X}", "code_size": "0x1000000",
        "thunk_reserve_size": "0x10000",
        "rexcrt_heap": CBool(False),
        "config_flags": {k: CBool(False) for k in (
            "skip_lr", "ctr_as_local", "xer_as_local", "reserved_as_local",
            "skip_msr", "cr_as_local", "non_argument_as_local", "non_volatile_as_local")},
        "functions": [{"name": n, "address": f"0x{n[4:]}", "below_code_base": False,
                       "is_import": False} for n in names],
        "recomp_files": [f"{project}_recomp.0.cpp"],
        "dll_modules": [
            {"pe_name": name.replace("_xex", ".xex.dll"),
             "guest_path": "game:/" + name.replace("_xex", ".xex.dll"),
             "shared_lib_name": f"{project}_{name}",
             "target_name": name, "lib_name": f"{project}_{name}",
             "output_dir": f"generated/{name}"}
            for name, _, _, _ in dll_modules],
    }
    files = {
        f"{project}_pch.h": render("pch_h", values),
        f"{project}_funcs.h": render("funcs_h", values),
        f"{project}_init.h": render("init_h", values),
        f"{project}_init.cpp": "// Placeholder (scripts/placeholder-codegen.py): not the game.\n"
                               + render("init_cpp", values),
        f"{project}_register.cpp": render("register_cpp", values),
        f"{project}_recomp.0.cpp": f'#include "{project}_init.h"\n\n'
                                   + "".join(f"DEFINE_REX_FUNC({n}) {{ (void)base; }}\n"
                                             for n in names),
        "sources.cmake": render("sources_cmake", values),
    }
    if not is_dll:
        files["module_registry.cpp"] = render("module_registry_cpp", values)
        files["dll_targets.cmake"] = render("dll_targets_cmake", values)
    for name, text in files.items():
        (out / name).write_text(text)
    print(f"Placeholder {out_name}: {len(names)} functions")
