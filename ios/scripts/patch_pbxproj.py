"""Insert ShareExtension target into Runner.xcodeproj/project.pbxproj.

We hand-edit the pbxproj because Flutter projects don't ship with
a workable Ruby/Xcodeproj toolchain in this repo. The script is
idempotent — running twice does nothing the second time.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

PROJ = Path(__file__).resolve().parent.parent / "Runner.xcodeproj/project.pbxproj"

# Stable, hand-picked 24-char hex IDs (ASCII-safe). Must not collide with existing IDs.
IDS = {
    # File references
    "share_swift_fileref": "AA10000000000000000000A1",
    "share_storyboard_fileref": "AA10000000000000000000A2",
    "share_info_fileref": "AA10000000000000000000A3",
    "share_entitlements_fileref": "AA10000000000000000000A4",
    "runner_entitlements_fileref": "AA10000000000000000000A5",
    "share_appex_fileref": "AA10000000000000000000A6",
    # Storyboard variant group
    "share_storyboard_variant": "AA10000000000000000000A7",
    # Build files
    "share_swift_buildfile": "AA10000000000000000000B1",
    "share_storyboard_buildfile": "AA10000000000000000000B2",
    "share_appex_embed_buildfile": "AA10000000000000000000B3",
    # Groups
    "share_group": "AA10000000000000000000C1",
    # Build phases
    "share_sources_phase": "AA10000000000000000000D1",
    "share_resources_phase": "AA10000000000000000000D2",
    "share_frameworks_phase": "AA10000000000000000000D3",
    "embed_appex_phase": "AA10000000000000000000D4",
    # Configurations
    "share_debug_config": "AA10000000000000000000E1",
    "share_release_config": "AA10000000000000000000E2",
    "share_profile_config": "AA10000000000000000000E3",
    "share_config_list": "AA10000000000000000000E4",
    # Native target + dependency
    "share_native_target": "AA10000000000000000000F1",
    "share_dep_proxy": "AA10000000000000000000F2",
    "share_target_dep": "AA10000000000000000000F3",
}


def already_patched(text: str) -> bool:
    return IDS["share_native_target"] in text


def insert_after(text: str, marker: str, payload: str) -> str:
    idx = text.find(marker)
    if idx < 0:
        raise SystemExit(f"marker not found: {marker[:60]!r}")
    end = idx + len(marker)
    return text[:end] + payload + text[end:]


def replace_once(text: str, old: str, new: str) -> str:
    if old not in text:
        raise SystemExit(f"old not found: {old[:80]!r}")
    if text.count(old) > 1:
        raise SystemExit(f"old not unique: {old[:80]!r}")
    return text.replace(old, new, 1)


def main() -> int:
    text = PROJ.read_text()
    if already_patched(text):
        print("pbxproj already contains ShareExtension target — nothing to do.")
        return 0

    # 1) PBXBuildFile entries
    build_files = (
        f"\n\t\t{IDS['share_swift_buildfile']} /* ShareViewController.swift in Sources */ = "
        f"{{isa = PBXBuildFile; fileRef = {IDS['share_swift_fileref']} /* ShareViewController.swift */; }};"
        f"\n\t\t{IDS['share_storyboard_buildfile']} /* MainInterface.storyboard in Resources */ = "
        f"{{isa = PBXBuildFile; fileRef = {IDS['share_storyboard_variant']} /* MainInterface.storyboard */; }};"
        f"\n\t\t{IDS['share_appex_embed_buildfile']} /* ShareExtension.appex in Embed Foundation Extensions */ = "
        f"{{isa = PBXBuildFile; fileRef = {IDS['share_appex_fileref']} /* ShareExtension.appex */; "
        f"settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};"
    )
    text = insert_after(text, "/* Begin PBXBuildFile section */", build_files)

    # 2) PBXFileReference entries
    file_refs = (
        f"\n\t\t{IDS['share_swift_fileref']} /* ShareViewController.swift */ = "
        f"{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ShareViewController.swift; sourceTree = \"<group>\"; }};"
        f"\n\t\t{IDS['share_storyboard_fileref']} /* Base */ = "
        f"{{isa = PBXFileReference; lastKnownFileType = file.storyboard; name = Base; path = Base.lproj/MainInterface.storyboard; sourceTree = \"<group>\"; }};"
        f"\n\t\t{IDS['share_info_fileref']} /* Info.plist */ = "
        f"{{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};"
        f"\n\t\t{IDS['share_entitlements_fileref']} /* ShareExtension.entitlements */ = "
        f"{{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = ShareExtension.entitlements; sourceTree = \"<group>\"; }};"
        f"\n\t\t{IDS['runner_entitlements_fileref']} /* Runner.entitlements */ = "
        f"{{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = Runner.entitlements; sourceTree = \"<group>\"; }};"
        f"\n\t\t{IDS['share_appex_fileref']} /* ShareExtension.appex */ = "
        f"{{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = ShareExtension.appex; sourceTree = BUILT_PRODUCTS_DIR; }};"
    )
    text = insert_after(text, "/* Begin PBXFileReference section */", file_refs)

    # 3) PBXVariantGroup for the storyboard
    variant_group = (
        f"\n\t\t{IDS['share_storyboard_variant']} /* MainInterface.storyboard */ = {{\n"
        f"\t\t\tisa = PBXVariantGroup;\n"
        f"\t\t\tchildren = (\n"
        f"\t\t\t\t{IDS['share_storyboard_fileref']} /* Base */,\n"
        f"\t\t\t);\n"
        f"\t\t\tname = MainInterface.storyboard;\n"
        f"\t\t\tsourceTree = \"<group>\";\n"
        f"\t\t}};"
    )
    text = insert_after(text, "/* Begin PBXVariantGroup section */", variant_group)

    # 4) ShareExtension PBXGroup, plus reference inside the main group
    share_group = (
        f"\n\t\t{IDS['share_group']} /* ShareExtension */ = {{\n"
        f"\t\t\tisa = PBXGroup;\n"
        f"\t\t\tchildren = (\n"
        f"\t\t\t\t{IDS['share_swift_fileref']} /* ShareViewController.swift */,\n"
        f"\t\t\t\t{IDS['share_storyboard_variant']} /* MainInterface.storyboard */,\n"
        f"\t\t\t\t{IDS['share_info_fileref']} /* Info.plist */,\n"
        f"\t\t\t\t{IDS['share_entitlements_fileref']} /* ShareExtension.entitlements */,\n"
        f"\t\t\t);\n"
        f"\t\t\tpath = ShareExtension;\n"
        f"\t\t\tsourceTree = \"<group>\";\n"
        f"\t\t}};"
    )
    text = insert_after(text, "/* Begin PBXGroup section */", share_group)

    # Reference ShareExtension folder inside the project root group (right after RunnerTests entry)
    text = replace_once(
        text,
        "\t\t\t\t331C8082294A63A400263BE5 /* RunnerTests */,\n"
        "\t\t\t\t4EE520AC2392B957B0458E8A /* Pods */,\n"
        "\t\t\t\t5EB7249C74FFA3D7E40C96CA /* Frameworks */,\n",
        "\t\t\t\t331C8082294A63A400263BE5 /* RunnerTests */,\n"
        f"\t\t\t\t{IDS['share_group']} /* ShareExtension */,\n"
        "\t\t\t\t4EE520AC2392B957B0458E8A /* Pods */,\n"
        "\t\t\t\t5EB7249C74FFA3D7E40C96CA /* Frameworks */,\n",
    )

    # Reference Runner.entitlements inside the Runner group
    text = replace_once(
        text,
        "\t\t\t\t74858FAE1ED2DC5600515810 /* AppDelegate.swift */,\n"
        "\t\t\t\t74858FAD1ED2DC5600515810 /* Runner-Bridging-Header.h */,\n"
        "\t\t\t);\n"
        "\t\t\tpath = Runner;\n",
        "\t\t\t\t74858FAE1ED2DC5600515810 /* AppDelegate.swift */,\n"
        "\t\t\t\t74858FAD1ED2DC5600515810 /* Runner-Bridging-Header.h */,\n"
        f"\t\t\t\t{IDS['runner_entitlements_fileref']} /* Runner.entitlements */,\n"
        "\t\t\t);\n"
        "\t\t\tpath = Runner;\n",
    )

    # Reference the .appex inside Products group
    text = replace_once(
        text,
        "\t\t\t\t97C146EE1CF9000F007C117D /* Runner.app */,\n"
        "\t\t\t\t331C8081294A63A400263BE5 /* RunnerTests.xctest */,\n",
        "\t\t\t\t97C146EE1CF9000F007C117D /* Runner.app */,\n"
        "\t\t\t\t331C8081294A63A400263BE5 /* RunnerTests.xctest */,\n"
        f"\t\t\t\t{IDS['share_appex_fileref']} /* ShareExtension.appex */,\n",
    )

    # 5) Build phases for the new target
    sources_phase = (
        f"\n\t\t{IDS['share_sources_phase']} /* Sources */ = {{\n"
        f"\t\t\tisa = PBXSourcesBuildPhase;\n"
        f"\t\t\tbuildActionMask = 2147483647;\n"
        f"\t\t\tfiles = (\n"
        f"\t\t\t\t{IDS['share_swift_buildfile']} /* ShareViewController.swift in Sources */,\n"
        f"\t\t\t);\n"
        f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        f"\t\t}};"
    )
    text = insert_after(text, "/* Begin PBXSourcesBuildPhase section */", sources_phase)

    resources_phase = (
        f"\n\t\t{IDS['share_resources_phase']} /* Resources */ = {{\n"
        f"\t\t\tisa = PBXResourcesBuildPhase;\n"
        f"\t\t\tbuildActionMask = 2147483647;\n"
        f"\t\t\tfiles = (\n"
        f"\t\t\t\t{IDS['share_storyboard_buildfile']} /* MainInterface.storyboard in Resources */,\n"
        f"\t\t\t);\n"
        f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        f"\t\t}};"
    )
    text = insert_after(text, "/* Begin PBXResourcesBuildPhase section */", resources_phase)

    frameworks_phase = (
        f"\n\t\t{IDS['share_frameworks_phase']} /* Frameworks */ = {{\n"
        f"\t\t\tisa = PBXFrameworksBuildPhase;\n"
        f"\t\t\tbuildActionMask = 2147483647;\n"
        f"\t\t\tfiles = (\n"
        f"\t\t\t);\n"
        f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        f"\t\t}};"
    )
    text = insert_after(text, "/* Begin PBXFrameworksBuildPhase section */", frameworks_phase)

    # 6) Embed Foundation Extensions copy phase, attached to the Runner target
    embed_phase = (
        f"\n\t\t{IDS['embed_appex_phase']} /* Embed Foundation Extensions */ = {{\n"
        f"\t\t\tisa = PBXCopyFilesBuildPhase;\n"
        f"\t\t\tbuildActionMask = 2147483647;\n"
        f"\t\t\tdstPath = \"\";\n"
        f"\t\t\tdstSubfolderSpec = 13;\n"
        f"\t\t\tfiles = (\n"
        f"\t\t\t\t{IDS['share_appex_embed_buildfile']} /* ShareExtension.appex in Embed Foundation Extensions */,\n"
        f"\t\t\t);\n"
        f"\t\t\tname = \"Embed Foundation Extensions\";\n"
        f"\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        f"\t\t}};"
    )
    text = insert_after(text, "/* Begin PBXCopyFilesBuildPhase section */", embed_phase)

    # Wire the embed phase into Runner's buildPhases list (after [CP] Copy Pods Resources)
    text = replace_once(
        text,
        "\t\t\t\t3516E4619D20759FC95D5547 /* [CP] Copy Pods Resources */,\n"
        "\t\t\t);\n"
        "\t\t\tbuildRules = (\n"
        "\t\t\t);\n"
        "\t\t\tdependencies = (\n"
        "\t\t\t);\n"
        "\t\t\tname = Runner;\n",
        "\t\t\t\t3516E4619D20759FC95D5547 /* [CP] Copy Pods Resources */,\n"
        f"\t\t\t\t{IDS['embed_appex_phase']} /* Embed Foundation Extensions */,\n"
        "\t\t\t);\n"
        "\t\t\tbuildRules = (\n"
        "\t\t\t);\n"
        "\t\t\tdependencies = (\n"
        f"\t\t\t\t{IDS['share_target_dep']} /* PBXTargetDependency */,\n"
        "\t\t\t);\n"
        "\t\t\tname = Runner;\n",
    )

    # 7) PBXContainerItemProxy + PBXTargetDependency
    container_proxy = (
        f"\n\t\t{IDS['share_dep_proxy']} /* PBXContainerItemProxy */ = {{\n"
        f"\t\t\tisa = PBXContainerItemProxy;\n"
        f"\t\t\tcontainerPortal = 97C146E61CF9000F007C117D /* Project object */;\n"
        f"\t\t\tproxyType = 1;\n"
        f"\t\t\tremoteGlobalIDString = {IDS['share_native_target']};\n"
        f"\t\t\tremoteInfo = ShareExtension;\n"
        f"\t\t}};"
    )
    text = insert_after(text, "/* Begin PBXContainerItemProxy section */", container_proxy)

    target_dep = (
        f"\n\t\t{IDS['share_target_dep']} /* PBXTargetDependency */ = {{\n"
        f"\t\t\tisa = PBXTargetDependency;\n"
        f"\t\t\ttarget = {IDS['share_native_target']} /* ShareExtension */;\n"
        f"\t\t\ttargetProxy = {IDS['share_dep_proxy']} /* PBXContainerItemProxy */;\n"
        f"\t\t}};"
    )
    text = insert_after(text, "/* Begin PBXTargetDependency section */", target_dep)

    # 8) Native target itself
    native_target = (
        f"\n\t\t{IDS['share_native_target']} /* ShareExtension */ = {{\n"
        f"\t\t\tisa = PBXNativeTarget;\n"
        f"\t\t\tbuildConfigurationList = {IDS['share_config_list']} /* Build configuration list for PBXNativeTarget \"ShareExtension\" */;\n"
        f"\t\t\tbuildPhases = (\n"
        f"\t\t\t\t{IDS['share_sources_phase']} /* Sources */,\n"
        f"\t\t\t\t{IDS['share_frameworks_phase']} /* Frameworks */,\n"
        f"\t\t\t\t{IDS['share_resources_phase']} /* Resources */,\n"
        f"\t\t\t);\n"
        f"\t\t\tbuildRules = (\n"
        f"\t\t\t);\n"
        f"\t\t\tdependencies = (\n"
        f"\t\t\t);\n"
        f"\t\t\tname = ShareExtension;\n"
        f"\t\t\tproductName = ShareExtension;\n"
        f"\t\t\tproductReference = {IDS['share_appex_fileref']} /* ShareExtension.appex */;\n"
        f"\t\t\tproductType = \"com.apple.product-type.app-extension\";\n"
        f"\t\t}};"
    )
    text = insert_after(text, "/* Begin PBXNativeTarget section */", native_target)

    # Add target to the project's targets list
    text = replace_once(
        text,
        "\t\t\ttargets = (\n"
        "\t\t\t\t97C146ED1CF9000F007C117D /* Runner */,\n"
        "\t\t\t\t331C8080294A63A400263BE5 /* RunnerTests */,\n"
        "\t\t\t);\n",
        "\t\t\ttargets = (\n"
        "\t\t\t\t97C146ED1CF9000F007C117D /* Runner */,\n"
        "\t\t\t\t331C8080294A63A400263BE5 /* RunnerTests */,\n"
        f"\t\t\t\t{IDS['share_native_target']} /* ShareExtension */,\n"
        "\t\t\t);\n",
    )

    # 9) XCBuildConfiguration entries for the new target
    common_bs = (
        "ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES = YES;\n"
        "\t\t\t\tCLANG_ENABLE_MODULES = YES;\n"
        "\t\t\t\tCODE_SIGN_ENTITLEMENTS = ShareExtension/ShareExtension.entitlements;\n"
        "\t\t\t\tCODE_SIGN_STYLE = Automatic;\n"
        "\t\t\t\tCURRENT_PROJECT_VERSION = 1;\n"
        "\t\t\t\tDEVELOPMENT_TEAM = JSD9P85VHL;\n"
        "\t\t\t\tGENERATE_INFOPLIST_FILE = NO;\n"
        "\t\t\t\tINFOPLIST_FILE = ShareExtension/Info.plist;\n"
        "\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 14.0;\n"
        "\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (\n"
        "\t\t\t\t\t\"$(inherited)\",\n"
        "\t\t\t\t\t\"@executable_path/Frameworks\",\n"
        "\t\t\t\t\t\"@executable_path/../../Frameworks\",\n"
        "\t\t\t\t);\n"
        "\t\t\t\tMARKETING_VERSION = 1.0;\n"
        "\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.xiaosui.xiaosui.ShareExtension;\n"
        "\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";\n"
        "\t\t\t\tSKIP_INSTALL = YES;\n"
        "\t\t\t\tSWIFT_VERSION = 5.0;\n"
        "\t\t\t\tTARGETED_DEVICE_FAMILY = \"1,2\";\n"
    )

    share_configs = (
        f"\n\t\t{IDS['share_debug_config']} /* Debug */ = {{\n"
        f"\t\t\tisa = XCBuildConfiguration;\n"
        f"\t\t\tbuildSettings = {{\n"
        f"\t\t\t\t{common_bs}"
        f"\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;\n"
        f"\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";\n"
        f"\t\t\t}};\n"
        f"\t\t\tname = Debug;\n"
        f"\t\t}};"
        f"\n\t\t{IDS['share_release_config']} /* Release */ = {{\n"
        f"\t\t\tisa = XCBuildConfiguration;\n"
        f"\t\t\tbuildSettings = {{\n"
        f"\t\t\t\t{common_bs}"
        f"\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-O\";\n"
        f"\t\t\t}};\n"
        f"\t\t\tname = Release;\n"
        f"\t\t}};"
        f"\n\t\t{IDS['share_profile_config']} /* Profile */ = {{\n"
        f"\t\t\tisa = XCBuildConfiguration;\n"
        f"\t\t\tbuildSettings = {{\n"
        f"\t\t\t\t{common_bs}"
        f"\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-O\";\n"
        f"\t\t\t}};\n"
        f"\t\t\tname = Profile;\n"
        f"\t\t}};"
    )
    text = insert_after(text, "/* Begin XCBuildConfiguration section */", share_configs)

    # 10) XCConfigurationList for the new target
    share_config_list = (
        f"\n\t\t{IDS['share_config_list']} /* Build configuration list for PBXNativeTarget \"ShareExtension\" */ = {{\n"
        f"\t\t\tisa = XCConfigurationList;\n"
        f"\t\t\tbuildConfigurations = (\n"
        f"\t\t\t\t{IDS['share_debug_config']} /* Debug */,\n"
        f"\t\t\t\t{IDS['share_release_config']} /* Release */,\n"
        f"\t\t\t\t{IDS['share_profile_config']} /* Profile */,\n"
        f"\t\t\t);\n"
        f"\t\t\tdefaultConfigurationIsVisible = 0;\n"
        f"\t\t\tdefaultConfigurationName = Release;\n"
        f"\t\t}};"
    )
    text = insert_after(text, "/* Begin XCConfigurationList section */", share_config_list)

    # 11) Wire CODE_SIGN_ENTITLEMENTS for Runner Debug/Release/Profile
    runner_entitlement_line = "\t\t\t\tCODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;\n"

    runner_config_marker_pattern = re.compile(
        r"(/\* (?:Debug|Release) \*/ = \{\n"
        r"\t\t\tisa = XCBuildConfiguration;\n"
        r"\t\t\tbaseConfigurationReference = (?:9740EEB21CF90195004384FC|7AFA3C8E1D35360C0083082E) /\* (?:Debug|Release)\.xcconfig \*/;\n"
        r"\t\t\tbuildSettings = \{\n)"
        r"(\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;\n)"
    )
    text, n = runner_config_marker_pattern.subn(
        r"\1" + runner_entitlement_line + r"\2",
        text,
    )
    if n != 2:
        raise SystemExit(f"runner Debug/Release entitlement wiring matched {n} times, expected 2")

    # Profile config has slightly different shape
    profile_pattern = re.compile(
        r"(249021D4217E4FDB00AE95B9 /\* Profile \*/ = \{\n"
        r"\t\t\tisa = XCBuildConfiguration;\n"
        r"\t\t\tbaseConfigurationReference = 7AFA3C8E1D35360C0083082E /\* Release\.xcconfig \*/;\n"
        r"\t\t\tbuildSettings = \{\n)"
        r"(\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;\n)"
    )
    text, n = profile_pattern.subn(
        r"\1" + runner_entitlement_line + r"\2",
        text,
    )
    if n != 1:
        raise SystemExit(f"runner Profile entitlement wiring matched {n} times, expected 1")

    PROJ.write_text(text)
    print("Patched pbxproj with ShareExtension target.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
