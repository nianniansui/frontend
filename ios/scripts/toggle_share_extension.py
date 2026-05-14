"""Toggle the ShareExtension target in Runner's build dependencies.

Signing a Share Extension on a free Apple ID requires an extra App ID,
an extra provisioning profile, and a matching App Group capability. When
you just want to install the main app on device, it's easiest to skip
the extension entirely. This script flips a comment block inside
Runner.xcodeproj/project.pbxproj so that:

- `disable` removes the Runner -> ShareExtension target dependency
  and removes the .appex from the Embed phase.
- `enable` restores both.

It's idempotent — running the same mode twice is a no-op.
"""
from __future__ import annotations

import sys
from pathlib import Path

PROJ = Path(__file__).resolve().parent.parent / "Runner.xcodeproj/project.pbxproj"

SHARE_DEP_LINE = "\t\t\t\tAA10000000000000000000F3 /* PBXTargetDependency */,\n"
SHARE_EMBED_LINE = "\t\t\t\tAA10000000000000000000B3 /* ShareExtension.appex in Embed Foundation Extensions */,\n"


def disable(text: str) -> str:
    if SHARE_DEP_LINE in text:
        text = text.replace(SHARE_DEP_LINE, "")
    if SHARE_EMBED_LINE in text:
        text = text.replace(SHARE_EMBED_LINE, "")
    return text


def enable(text: str) -> str:
    if SHARE_DEP_LINE not in text:
        text = text.replace(
            "\t\t\tdependencies = (\n"
            "\t\t\t);\n"
            "\t\t\tname = Runner;\n",
            "\t\t\tdependencies = (\n"
            + SHARE_DEP_LINE
            + "\t\t\t);\n"
            + "\t\t\tname = Runner;\n",
        )
    if SHARE_EMBED_LINE not in text:
        text = text.replace(
            "\t\tAA10000000000000000000D4 /* Embed Foundation Extensions */ = {\n"
            "\t\t\tisa = PBXCopyFilesBuildPhase;\n"
            "\t\t\tbuildActionMask = 2147483647;\n"
            "\t\t\tdstPath = \"\";\n"
            "\t\t\tdstSubfolderSpec = 13;\n"
            "\t\t\tfiles = (\n"
            "\t\t\t);\n",
            "\t\tAA10000000000000000000D4 /* Embed Foundation Extensions */ = {\n"
            "\t\t\tisa = PBXCopyFilesBuildPhase;\n"
            "\t\t\tbuildActionMask = 2147483647;\n"
            "\t\t\tdstPath = \"\";\n"
            "\t\t\tdstSubfolderSpec = 13;\n"
            "\t\t\tfiles = (\n"
            + SHARE_EMBED_LINE,
        )
    return text


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in {"disable", "enable"}:
        print("usage: toggle_share_extension.py <disable|enable>")
        return 2
    mode = sys.argv[1]
    text = PROJ.read_text()
    new_text = disable(text) if mode == "disable" else enable(text)
    if new_text == text:
        print(f"ShareExtension is already {mode}d — no changes.")
        return 0
    PROJ.write_text(new_text)
    print(f"ShareExtension {mode}d in Runner target.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
