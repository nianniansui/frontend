"""Insert XiaosuiWidget WidgetKit extension target into Runner.xcodeproj/project.pbxproj.

模板参照 patch_pbxproj.py（ShareExtension 的）。脚本幂等。

Widget 与 ShareExtension 的区别：
- Widget 没有 Storyboard
- Widget 需要 SwiftUI / WidgetKit 框架（隐式 link，无需手动加）
- ProductType 不同：com.apple.product-type.app-extension（同 ShareExtension）
- entitlements 文件名不同
"""
from __future__ import annotations

import sys
from pathlib import Path

PROJ = Path(__file__).resolve().parent.parent / "Runner.xcodeproj/project.pbxproj"

# 24-char hex IDs，前缀用 AA20 区分 ShareExtension（AA10）
IDS = {
    "widget_swift_fileref":     "AA20000000000000000000A1",
    "widget_info_fileref":      "AA20000000000000000000A2",
    "widget_entitlements_fileref": "AA20000000000000000000A3",
    "widget_appex_fileref":     "AA20000000000000000000A4",
    "widget_swift_buildfile":   "AA20000000000000000000B1",
    "widget_appex_embed_buildfile": "AA20000000000000000000B2",
    "widget_group":             "AA20000000000000000000C1",
    "widget_sources_phase":     "AA20000000000000000000D1",
    "widget_resources_phase":   "AA20000000000000000000D2",
    "widget_frameworks_phase":  "AA20000000000000000000D3",
    "widget_debug_config":      "AA20000000000000000000E1",
    "widget_release_config":    "AA20000000000000000000E2",
    "widget_profile_config":    "AA20000000000000000000E3",
    "widget_config_list":       "AA20000000000000000000E4",
    "widget_native_target":     "AA20000000000000000000F1",
    "widget_dep_proxy":         "AA20000000000000000000F2",
    "widget_target_dep":        "AA20000000000000000000F3",
}


def already_patched(text: str) -> bool:
    return IDS["widget_native_target"] in text


def insert_after(text: str, marker: str, payload: str) -> str:
    if marker not in text:
        raise SystemExit(f"marker not found in pbxproj: {marker!r}")
    return text.replace(marker, marker + payload, 1)


def replace_once(text: str, old: str, new: str) -> str:
    if old not in text:
        raise SystemExit(f"old not found: {old[:80]!r}")
    if text.count(old) > 1:
        raise SystemExit(f"old not unique: {old[:80]!r}")
    return text.replace(old, new, 1)


def main() -> int:
    text = PROJ.read_text()
    if already_patched(text):
        print("pbxproj already contains XiaosuiWidget target — nothing to do.")
        return 0

    # 1) PBXBuildFile entries
    build_files = (
        f"\n\t\t{IDS['widget_swift_buildfile']} /* XiaosuiWidget.swift in Sources */ = "
        f"{{isa = PBXBuildFile; fileRef = {IDS['widget_swift_fileref']} /* XiaosuiWidget.swift */; }};"
        f"\n\t\t{IDS['widget_appex_embed_buildfile']} /* XiaosuiWidget.appex in Embed Foundation Extensions */ = "
        f"{{isa = PBXBuildFile; fileRef = {IDS['widget_appex_fileref']} /* XiaosuiWidget.appex */; "
        f"settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};"
    )
    text = insert_after(text, "/* Begin PBXBuildFile section */", build_files)

    # 2) PBXFileReference entries
    file_refs = (
        f"\n\t\t{IDS['widget_swift_fileref']} /* XiaosuiWidget.swift */ = "
        f"{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = XiaosuiWidget.swift; sourceTree = \"<group>\"; }};"
        f"\n\t\t{IDS['widget_info_fileref']} /* Info.plist */ = "
        f"{{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};"
        f"\n\t\t{IDS['widget_entitlements_fileref']} /* XiaosuiWidget.entitlements */ = "
        f"{{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = XiaosuiWidget.entitlements; sourceTree = \"<group>\"; }};"
        f"\n\t\t{IDS['widget_appex_fileref']} /* XiaosuiWidget.appex */ = "
        f"{{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = XiaosuiWidget.appex; sourceTree = BUILT_PRODUCTS_DIR; }};"
    )
    text = insert_after(text, "/* Begin PBXFileReference section */", file_refs)

    # 3) Group containing the Widget target's files
    widget_group = (
        f"\n\t\t{IDS['widget_group']} /* XiaosuiWidget */ = {{\n"
        f"\t\t\tisa = PBXGroup;\n"
        f"\t\t\tchildren = (\n"
        f"\t\t\t\t{IDS['widget_swift_fileref']} /* XiaosuiWidget.swift */,\n"
        f"\t\t\t\t{IDS['widget_info_fileref']} /* Info.plist */,\n"
        f"\t\t\t\t{IDS['widget_entitlements_fileref']} /* XiaosuiWidget.entitlements */,\n"
        f"\t\t\t);\n"
        f"\t\t\tpath = XiaosuiWidget;\n"
        f"\t\t\tsourceTree = \"<group>\";\n"
        f"\t\t}};"
    )
    text = insert_after(text, "/* Begin PBXGroup section */", widget_group)

    # 把 group 链入工程根 group。我们插在 ShareExtension 之后，但 ShareExtension 的
    # patch 用的 ID 是 AA10000000000000000000C1。如果 ShareExtension 还没 patch，
    # 我们就插到 RunnerTests 之后。
    if "AA10000000000000000000C1 /* ShareExtension */" in text:
        text = replace_once(
            text,
            "\t\t\t\tAA10000000000000000000C1 /* ShareExtension */,\n"
            "\t\t\t\t4EE520AC2392B957B0458E8A /* Pods */,\n",
            "\t\t\t\tAA10000000000000000000C1 /* ShareExtension */,\n"
            f"\t\t\t\t{IDS['widget_group']} /* XiaosuiWidget */,\n"
            "\t\t\t\t4EE520AC2392B957B0458E8A /* Pods */,\n",
        )
    else:
        text = replace_once(
            text,
            "\t\t\t\t331C8082294A63A400263BE5 /* RunnerTests */,\n"
            "\t\t\t\t4EE520AC2392B957B0458E8A /* Pods */,\n",
            "\t\t\t\t331C8082294A63A400263BE5 /* RunnerTests */,\n"
            f"\t\t\t\t{IDS['widget_group']} /* XiaosuiWidget */,\n"
            "\t\t\t\t4EE520AC2392B957B0458E8A /* Pods */,\n",
        )

    # 4) Add the .appex to Products group
    if "AA10000000000000000000A6 /* ShareExtension.appex */" in text:
        text = replace_once(
            text,
            "\t\t\t\tAA10000000000000000000A6 /* ShareExtension.appex */,\n",
            "\t\t\t\tAA10000000000000000000A6 /* ShareExtension.appex */,\n"
            f"\t\t\t\t{IDS['widget_appex_fileref']} /* XiaosuiWidget.appex */,\n",
        )
    else:
        text = replace_once(
            text,
            "\t\t\t\t97C146EE1CF9000F007C117D /* Runner.app */,\n"
            "\t\t\t\t331C8081294A63A400263BE5 /* RunnerTests.xctest */,\n",
            "\t\t\t\t97C146EE1CF9000F007C117D /* Runner.app */,\n"
            "\t\t\t\t331C8081294A63A400263BE5 /* RunnerTests.xctest */,\n"
            f"\t\t\t\t{IDS['widget_appex_fileref']} /* XiaosuiWidget.appex */,\n",
        )

    # 5) Build phases
    sources_phase = (
        f"\n\t\t{IDS['widget_sources_phase']} /* Sources */ = {{\n"
        f"\t\t\tisa = PBXSourcesBuildPhase;\n"
        f"\t\t\tbuildActionMask = 2147483647;\n"
        f"\t\t\tfiles = (\n"
        f"\t\t\t\t{IDS['widget_swift_buildfile']} /* XiaosuiWidget.swift in Sources */,\n"
        f"\t\t\t);\n"
        f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        f"\t\t}};"
    )
    text = insert_after(text, "/* Begin PBXSourcesBuildPhase section */", sources_phase)

    resources_phase = (
        f"\n\t\t{IDS['widget_resources_phase']} /* Resources */ = {{\n"
        f"\t\t\tisa = PBXResourcesBuildPhase;\n"
        f"\t\t\tbuildActionMask = 2147483647;\n"
        f"\t\t\tfiles = (\n"
        f"\t\t\t);\n"
        f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        f"\t\t}};"
    )
    text = insert_after(text, "/* Begin PBXResourcesBuildPhase section */", resources_phase)

    frameworks_phase = (
        f"\n\t\t{IDS['widget_frameworks_phase']} /* Frameworks */ = {{\n"
        f"\t\t\tisa = PBXFrameworksBuildPhase;\n"
        f"\t\t\tbuildActionMask = 2147483647;\n"
        f"\t\t\tfiles = (\n"
        f"\t\t\t);\n"
        f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        f"\t\t}};"
    )
    text = insert_after(text, "/* Begin PBXFrameworksBuildPhase section */", frameworks_phase)

    # 6) 把 .appex 嵌入 Runner.app。
    # 如果 ShareExtension 已 patch，沿用同一个 Embed Foundation Extensions phase；
    # 如果没有，就单独建一个。
    if "AA10000000000000000000D4 /* Embed Foundation Extensions */" in text:
        # 把 widget 的 build file 加入已有 phase 的 files 列表
        text = replace_once(
            text,
            "\t\t\tfiles = (\n"
            "\t\t\t\tAA10000000000000000000B3 /* ShareExtension.appex in Embed Foundation Extensions */,\n"
            "\t\t\t);\n"
            "\t\t\tname = \"Embed Foundation Extensions\";\n",
            "\t\t\tfiles = (\n"
            "\t\t\t\tAA10000000000000000000B3 /* ShareExtension.appex in Embed Foundation Extensions */,\n"
            f"\t\t\t\t{IDS['widget_appex_embed_buildfile']} /* XiaosuiWidget.appex in Embed Foundation Extensions */,\n"
            "\t\t\t);\n"
            "\t\t\tname = \"Embed Foundation Extensions\";\n",
        )
        # Runner 的 dependencies 加上 widget
        text = replace_once(
            text,
            "\t\t\tdependencies = (\n"
            "\t\t\t\tAA10000000000000000000F3 /* PBXTargetDependency */,\n"
            "\t\t\t);\n"
            "\t\t\tname = Runner;\n",
            "\t\t\tdependencies = (\n"
            "\t\t\t\tAA10000000000000000000F3 /* PBXTargetDependency */,\n"
            f"\t\t\t\t{IDS['widget_target_dep']} /* PBXTargetDependency */,\n"
            "\t\t\t);\n"
            "\t\t\tname = Runner;\n",
        )
    else:
        raise SystemExit(
            "Widget patcher requires ShareExtension to be patched first "
            "(it sets up the Embed Foundation Extensions phase). "
            "Run patch_pbxproj.py before this script."
        )

    # 7) PBXContainerItemProxy + PBXTargetDependency
    container_proxy = (
        f"\n\t\t{IDS['widget_dep_proxy']} /* PBXContainerItemProxy */ = {{\n"
        f"\t\t\tisa = PBXContainerItemProxy;\n"
        f"\t\t\tcontainerPortal = 97C146E61CF9000F007C117D /* Project object */;\n"
        f"\t\t\tproxyType = 1;\n"
        f"\t\t\tremoteGlobalIDString = {IDS['widget_native_target']};\n"
        f"\t\t\tremoteInfo = XiaosuiWidget;\n"
        f"\t\t}};"
    )
    text = insert_after(text, "/* Begin PBXContainerItemProxy section */", container_proxy)

    target_dep = (
        f"\n\t\t{IDS['widget_target_dep']} /* PBXTargetDependency */ = {{\n"
        f"\t\t\tisa = PBXTargetDependency;\n"
        f"\t\t\ttarget = {IDS['widget_native_target']} /* XiaosuiWidget */;\n"
        f"\t\t\ttargetProxy = {IDS['widget_dep_proxy']} /* PBXContainerItemProxy */;\n"
        f"\t\t}};"
    )
    text = insert_after(text, "/* Begin PBXTargetDependency section */", target_dep)

    # 8) PBXNativeTarget
    native_target = (
        f"\n\t\t{IDS['widget_native_target']} /* XiaosuiWidget */ = {{\n"
        f"\t\t\tisa = PBXNativeTarget;\n"
        f"\t\t\tbuildConfigurationList = {IDS['widget_config_list']} /* Build configuration list for PBXNativeTarget \"XiaosuiWidget\" */;\n"
        f"\t\t\tbuildPhases = (\n"
        f"\t\t\t\t{IDS['widget_sources_phase']} /* Sources */,\n"
        f"\t\t\t\t{IDS['widget_resources_phase']} /* Resources */,\n"
        f"\t\t\t\t{IDS['widget_frameworks_phase']} /* Frameworks */,\n"
        f"\t\t\t);\n"
        f"\t\t\tbuildRules = (\n"
        f"\t\t\t);\n"
        f"\t\t\tdependencies = (\n"
        f"\t\t\t);\n"
        f"\t\t\tname = XiaosuiWidget;\n"
        f"\t\t\tproductName = XiaosuiWidget;\n"
        f"\t\t\tproductReference = {IDS['widget_appex_fileref']} /* XiaosuiWidget.appex */;\n"
        f"\t\t\tproductType = \"com.apple.product-type.app-extension\";\n"
        f"\t\t}};"
    )
    text = insert_after(text, "/* Begin PBXNativeTarget section */", native_target)

    # 加入项目 targets 列表（如果 ShareExtension 已存在则插在它后面）
    if "AA10000000000000000000F1 /* ShareExtension */" in text:
        text = replace_once(
            text,
            "\t\t\t\tAA10000000000000000000F1 /* ShareExtension */,\n"
            "\t\t\t);\n",
            "\t\t\t\tAA10000000000000000000F1 /* ShareExtension */,\n"
            f"\t\t\t\t{IDS['widget_native_target']} /* XiaosuiWidget */,\n"
            "\t\t\t);\n",
        )
    else:
        text = replace_once(
            text,
            "\t\t\ttargets = (\n"
            "\t\t\t\t97C146ED1CF9000F007C117D /* Runner */,\n"
            "\t\t\t\t331C8080294A63A400263BE5 /* RunnerTests */,\n"
            "\t\t\t);\n",
            "\t\t\ttargets = (\n"
            "\t\t\t\t97C146ED1CF9000F007C117D /* Runner */,\n"
            "\t\t\t\t331C8080294A63A400263BE5 /* RunnerTests */,\n"
            f"\t\t\t\t{IDS['widget_native_target']} /* XiaosuiWidget */,\n"
            "\t\t\t);\n",
        )

    # 9) XCBuildConfiguration entries
    common_bs = (
        "ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES = YES;\n"
        "\t\t\t\tCLANG_ENABLE_MODULES = YES;\n"
        "\t\t\t\tCODE_SIGN_ENTITLEMENTS = XiaosuiWidget/XiaosuiWidget.entitlements;\n"
        "\t\t\t\tCODE_SIGN_STYLE = Automatic;\n"
        "\t\t\t\tCURRENT_PROJECT_VERSION = 1;\n"
        "\t\t\t\tDEVELOPMENT_TEAM = JSD9P85VHL;\n"
        "\t\t\t\tGENERATE_INFOPLIST_FILE = NO;\n"
        "\t\t\t\tINFOPLIST_FILE = XiaosuiWidget/Info.plist;\n"
        "\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 16.0;\n"
        "\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (\n"
        "\t\t\t\t\t\"$(inherited)\",\n"
        "\t\t\t\t\t\"@executable_path/Frameworks\",\n"
        "\t\t\t\t\t\"@executable_path/../../Frameworks\",\n"
        "\t\t\t\t);\n"
        "\t\t\t\tMARKETING_VERSION = 1.0;\n"
        "\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.xiaosui.xiaosui.XiaosuiWidget;\n"
        "\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";\n"
        "\t\t\t\tSKIP_INSTALL = YES;\n"
        "\t\t\t\tSWIFT_VERSION = 5.0;\n"
        "\t\t\t\tTARGETED_DEVICE_FAMILY = \"1,2\";\n"
    )

    debug_config = (
        f"\n\t\t{IDS['widget_debug_config']} /* Debug */ = {{\n"
        f"\t\t\tisa = XCBuildConfiguration;\n"
        f"\t\t\tbuildSettings = {{\n"
        f"\t\t\t\t{common_bs}"
        f"\t\t\t}};\n"
        f"\t\t\tname = Debug;\n"
        f"\t\t}};"
    )
    release_config = (
        f"\n\t\t{IDS['widget_release_config']} /* Release */ = {{\n"
        f"\t\t\tisa = XCBuildConfiguration;\n"
        f"\t\t\tbuildSettings = {{\n"
        f"\t\t\t\t{common_bs}"
        f"\t\t\t}};\n"
        f"\t\t\tname = Release;\n"
        f"\t\t}};"
    )
    profile_config = (
        f"\n\t\t{IDS['widget_profile_config']} /* Profile */ = {{\n"
        f"\t\t\tisa = XCBuildConfiguration;\n"
        f"\t\t\tbuildSettings = {{\n"
        f"\t\t\t\t{common_bs}"
        f"\t\t\t}};\n"
        f"\t\t\tname = Profile;\n"
        f"\t\t}};"
    )
    text = insert_after(
        text,
        "/* Begin XCBuildConfiguration section */",
        debug_config + release_config + profile_config,
    )

    # 10) XCConfigurationList
    widget_config_list = (
        f"\n\t\t{IDS['widget_config_list']} /* Build configuration list for PBXNativeTarget \"XiaosuiWidget\" */ = {{\n"
        f"\t\t\tisa = XCConfigurationList;\n"
        f"\t\t\tbuildConfigurations = (\n"
        f"\t\t\t\t{IDS['widget_debug_config']} /* Debug */,\n"
        f"\t\t\t\t{IDS['widget_release_config']} /* Release */,\n"
        f"\t\t\t\t{IDS['widget_profile_config']} /* Profile */,\n"
        f"\t\t\t);\n"
        f"\t\t\tdefaultConfigurationIsVisible = 0;\n"
        f"\t\t\tdefaultConfigurationName = Release;\n"
        f"\t\t}};"
    )
    text = insert_after(text, "/* Begin XCConfigurationList section */", widget_config_list)

    PROJ.write_text(text)
    print("Patched pbxproj with XiaosuiWidget target.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
