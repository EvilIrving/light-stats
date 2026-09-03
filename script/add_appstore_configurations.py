#!/usr/bin/env python3
"""Add AppStore / AppStoreDebug build configurations to the Xcode project.

Idempotent: refuses to run if AppStore configurations already exist.
"""

from __future__ import annotations

import re
import sys
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "Light Stats.xcodeproj" / "project.pbxproj"

SOURCES = {
    ("proj", "Debug"): "A4163D542EFBC3DC0013ED8C",
    ("proj", "Release"): "A4163D552EFBC3DC0013ED8C",
    ("app", "Debug"): "A4163D572EFBC3DC0013ED8C",
    ("app", "Release"): "A4163D582EFBC3DC0013ED8C",
    ("ext", "Debug"): "48FB5A129531D001F3D4B192",
    ("ext", "Release"): "27C0BFF43610AFB60B4565C6",
    ("test", "Debug"): "48499D521F5C0518AC36073E",
    ("test", "Release"): "27B86FB89AFD7271A602A7AD",
}


def nid() -> str:
    return uuid.uuid4().hex[:24].upper()


def extract_block(text: str, block_id: str) -> str:
    marker = f"\t\t{block_id} /*"
    start = text.find(marker)
    if start < 0:
        raise SystemExit(f"missing config block {block_id}")
    brace = text.find("{", start)
    depth = 0
    index = brace
    while index < len(text):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                end = index + 1
                if end < len(text) and text[end] == ";":
                    end += 1
                if end < len(text) and text[end] == "\n":
                    end += 1
                return text[start:end]
        index += 1
    raise SystemExit(f"unbalanced braces for {block_id}")


def rename_config(block: str, old_name: str, new_name: str, new_id: str) -> str:
    block = re.sub(
        rf"^\t\t[A-F0-9]+ /\* {re.escape(old_name)} \*/",
        f"\t\t{new_id} /* {new_name} */",
        block,
        count=1,
    )
    block = re.sub(
        rf"name = {re.escape(old_name)};",
        f"name = {new_name};",
        block,
        count=1,
    )
    return block


def apply_app_store_overrides(block: str) -> str:
    block = re.sub(
        r"\t\t\t\tFRAMEWORK_SEARCH_PATHS = \(\n"
        r"\t\t\t\t\t\"\$\(inherited\)\",\n"
        r"\t\t\t\t\t/System/Library/PrivateFrameworks,\n"
        r"\t\t\t\t\);\n",
        "",
        block,
        count=1,
    )
    block = re.sub(
        r"\t\t\t\tOTHER_LDFLAGS = \(\n"
        r"\t\t\t\t\t\"\$\(inherited\)\",\n"
        r"\t\t\t\t\t\"-framework\",\n"
        r"\t\t\t\t\tCoreDisplay,\n"
        r"\t\t\t\t\t\"-framework\",\n"
        r"\t\t\t\t\tDisplayServices,\n"
        r"\t\t\t\t\);\n",
        "",
        block,
        count=1,
    )
    block = block.replace(
        'SWIFT_OBJC_BRIDGING_HEADER = "Light Stats/Services/DisplayControl/DisplayPrivateAPI.h";\n',
        "",
    )
    block = block.replace(
        'CODE_SIGN_ENTITLEMENTS = "Light Stats/LightStats.entitlements";',
        'CODE_SIGN_ENTITLEMENTS = "Light Stats/LightStats-AppStore.entitlements";',
    )
    block = block.replace("ENABLE_APP_SANDBOX = NO;", "ENABLE_APP_SANDBOX = YES;")
    block = block.replace(
        "ENABLE_OUTGOING_NETWORK_CONNECTIONS = NO;",
        "ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES;",
    )
    block = block.replace(
        "ENABLE_USER_SELECTED_FILES = readonly;",
        "ENABLE_USER_SELECTED_FILES = readwrite;",
    )
    insert = (
        '\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "$(inherited) APP_STORE";\n'
        "\t\t\t\tEXCLUDED_SOURCE_FILE_NAMES = (\n"
        '\t\t\t\t\t"DisplayControl/*",\n'
        "\t\t\t\t\tDisplayPrivateAPI.h,\n"
        "\t\t\t\t);\n"
    )
    if "SWIFT_ACTIVE_COMPILATION_CONDITIONS" in block:
        block = re.sub(
            r"\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = .*?;\n",
            insert,
            block,
            count=1,
        )
    else:
        block = block.replace(
            "\t\t\t\tSWIFT_VERSION = 5.0;\n",
            insert + "\t\t\t\tSWIFT_VERSION = 5.0;\n",
            1,
        )
    return block


def apply_project_store_flag(block: str, is_debug: bool) -> str:
    if is_debug:
        return block.replace(
            'SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";',
            'SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG APP_STORE $(inherited)";',
        )
    if "SWIFT_ACTIVE_COMPILATION_CONDITIONS" not in block:
        return block.replace(
            "\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;\n",
            '\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "APP_STORE $(inherited)";\n'
            "\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;\n",
            1,
        )
    return block


def main() -> int:
    text = PROJECT.read_text()
    if "/* AppStoreDebug */" in text or "name = AppStoreDebug;" in text:
        print("AppStore configurations already present; nothing to do.")
        return 0

    new_ids = {key: nid() for key in SOURCES}
    new_blocks: list[str] = []
    for (kind, name), old_id in SOURCES.items():
        block = extract_block(text, old_id)
        new_name = "AppStoreDebug" if name == "Debug" else "AppStore"
        block = rename_config(block, name, new_name, new_ids[(kind, name)])
        if kind == "app":
            block = apply_app_store_overrides(block)
        elif kind == "proj":
            block = apply_project_store_flag(block, name == "Debug")
        new_blocks.append(block)

    end_marker = "/* End XCBuildConfiguration section */"
    insert_at = text.find(end_marker)
    if insert_at < 0:
        raise SystemExit("end marker missing")
    text = text[:insert_at] + "".join(new_blocks) + text[insert_at:]

    replacements = [
        (
            'A4163D442EFBC3DB0013ED8C /* Build configuration list for PBXProject "Light Stats" */ = {\n'
            "\t\t\tisa = XCConfigurationList;\n"
            "\t\t\tbuildConfigurations = (\n"
            "\t\t\t\tA4163D542EFBC3DC0013ED8C /* Debug */,\n"
            "\t\t\t\tA4163D552EFBC3DC0013ED8C /* Release */,\n"
            "\t\t\t);",
            'A4163D442EFBC3DB0013ED8C /* Build configuration list for PBXProject "Light Stats" */ = {\n'
            "\t\t\tisa = XCConfigurationList;\n"
            "\t\t\tbuildConfigurations = (\n"
            "\t\t\t\tA4163D542EFBC3DC0013ED8C /* Debug */,\n"
            "\t\t\t\tA4163D552EFBC3DC0013ED8C /* Release */,\n"
            f'\t\t\t\t{new_ids[("proj", "Debug")]} /* AppStoreDebug */,\n'
            f'\t\t\t\t{new_ids[("proj", "Release")]} /* AppStore */,\n'
            "\t\t\t);",
        ),
        (
            'A4163D562EFBC3DC0013ED8C /* Build configuration list for PBXNativeTarget "Light Stats" */ = {\n'
            "\t\t\tisa = XCConfigurationList;\n"
            "\t\t\tbuildConfigurations = (\n"
            "\t\t\t\tA4163D572EFBC3DC0013ED8C /* Debug */,\n"
            "\t\t\t\tA4163D582EFBC3DC0013ED8C /* Release */,\n"
            "\t\t\t);",
            'A4163D562EFBC3DC0013ED8C /* Build configuration list for PBXNativeTarget "Light Stats" */ = {\n'
            "\t\t\tisa = XCConfigurationList;\n"
            "\t\t\tbuildConfigurations = (\n"
            "\t\t\t\tA4163D572EFBC3DC0013ED8C /* Debug */,\n"
            "\t\t\t\tA4163D582EFBC3DC0013ED8C /* Release */,\n"
            f'\t\t\t\t{new_ids[("app", "Debug")]} /* AppStoreDebug */,\n'
            f'\t\t\t\t{new_ids[("app", "Release")]} /* AppStore */,\n'
            "\t\t\t);",
        ),
        (
            '27D40924EAEBE9AC8CB8E011 /* Build configuration list for PBXNativeTarget "FinderMenuExtension" */ = {\n'
            "\t\t\tisa = XCConfigurationList;\n"
            "\t\t\tbuildConfigurations = (\n"
            "\t\t\t\t27C0BFF43610AFB60B4565C6 /* Release */,\n"
            "\t\t\t\t48FB5A129531D001F3D4B192 /* Debug */,\n"
            "\t\t\t);",
            '27D40924EAEBE9AC8CB8E011 /* Build configuration list for PBXNativeTarget "FinderMenuExtension" */ = {\n'
            "\t\t\tisa = XCConfigurationList;\n"
            "\t\t\tbuildConfigurations = (\n"
            "\t\t\t\t27C0BFF43610AFB60B4565C6 /* Release */,\n"
            "\t\t\t\t48FB5A129531D001F3D4B192 /* Debug */,\n"
            f'\t\t\t\t{new_ids[("ext", "Release")]} /* AppStore */,\n'
            f'\t\t\t\t{new_ids[("ext", "Debug")]} /* AppStoreDebug */,\n'
            "\t\t\t);",
        ),
        (
            'E980368FEF4F8D93349110B7 /* Build configuration list for PBXNativeTarget "LightStatsTests" */ = {\n'
            "\t\t\tisa = XCConfigurationList;\n"
            "\t\t\tbuildConfigurations = (\n"
            "\t\t\t\t27B86FB89AFD7271A602A7AD /* Release */,\n"
            "\t\t\t\t48499D521F5C0518AC36073E /* Debug */,\n"
            "\t\t\t);",
            'E980368FEF4F8D93349110B7 /* Build configuration list for PBXNativeTarget "LightStatsTests" */ = {\n'
            "\t\t\tisa = XCConfigurationList;\n"
            "\t\t\tbuildConfigurations = (\n"
            "\t\t\t\t27B86FB89AFD7271A602A7AD /* Release */,\n"
            "\t\t\t\t48499D521F5C0518AC36073E /* Debug */,\n"
            f'\t\t\t\t{new_ids[("test", "Release")]} /* AppStore */,\n'
            f'\t\t\t\t{new_ids[("test", "Debug")]} /* AppStoreDebug */,\n'
            "\t\t\t);",
        ),
    ]

    for old, new in replacements:
        if old not in text:
            raise SystemExit("replacement target missing:\n" + old[:160])
        text = text.replace(old, new, 1)

    PROJECT.write_text(text)
    print("Added AppStore / AppStoreDebug configurations.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
