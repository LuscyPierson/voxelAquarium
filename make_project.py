#!/usr/bin/env python3
"""Writes VoxelAquarium.xcodeproj/project.pbxproj. Source folders are synchronized groups,
so new .swift files are picked up by Xcode without re-running this."""
import hashlib, os

def oid(name):
    return hashlib.md5(name.encode()).hexdigest()[:24].upper()

TEAM = "4BD53JYD4T"
objs = {}

def add(name, body):
    objs[oid(name)] = body
    return oid(name)

def q(v):
    s = str(v)
    return s if s.replace("_", "").replace(".", "").replace("/", "").isalnum() and s else '"' + s.replace('"', '\\"') + '"'

def fmt(d, indent=2):
    pad = "\t" * indent
    out = "{\n"
    for k, v in d.items():
        if isinstance(v, dict):
            out += f"{pad}{k} = {fmt(v, indent + 1)};\n"
        elif isinstance(v, list):
            out += f"{pad}{k} = (\n" + "".join(f"{pad}\t{q(x)},\n" for x in v) + f"{pad});\n"
        else:
            out += f"{pad}{k} = {q(v)};\n"
    return out + "\t" * (indent - 1) + "}"

# Files and groups
app_group = add("group.App", {"isa": "PBXFileSystemSynchronizedRootGroup", "path": "App", "sourceTree": "<group>"})
shared_group = add("group.Shared", {"isa": "PBXFileSystemSynchronizedRootGroup", "path": "Shared", "sourceTree": "<group>"})
widget_group = add("group.Widget", {"isa": "PBXFileSystemSynchronizedRootGroup", "path": "Widget", "sourceTree": "<group>"})
config_files = [add(f"file.{n}", {"isa": "PBXFileReference", "lastKnownFileType": t, "path": n, "sourceTree": "<group>"})
                for n, t in [("App-Info.plist", "text.plist.xml"), ("Widget-Info.plist", "text.plist.xml"),
                             ("App.entitlements", "text.plist.entitlements"), ("Widget.entitlements", "text.plist.entitlements")]]
config_group = add("group.Config", {"isa": "PBXGroup", "children": config_files, "path": "Config", "sourceTree": "<group>"})
app_product = add("product.app", {"isa": "PBXFileReference", "explicitFileType": "wrapper.application", "includeInIndex": 0,
                                  "path": "Voxel Aquarium.app", "sourceTree": "BUILT_PRODUCTS_DIR"})
widget_product = add("product.appex", {"isa": "PBXFileReference", "explicitFileType": "wrapper.app-extension", "includeInIndex": 0,
                                       "path": "AquariumWidget.appex", "sourceTree": "BUILT_PRODUCTS_DIR"})
products = add("group.Products", {"isa": "PBXGroup", "children": [app_product, widget_product], "name": "Products", "sourceTree": "<group>"})
main_group = add("group.main", {"isa": "PBXGroup", "children": [app_group, shared_group, widget_group, config_group, products],
                                "sourceTree": "<group>"})

def configs(prefix, common, debug=None, release=None):
    d = add(f"{prefix}.Debug", {"isa": "XCBuildConfiguration", "buildSettings": {**common, **(debug or {})}, "name": "Debug"})
    r = add(f"{prefix}.Release", {"isa": "XCBuildConfiguration", "buildSettings": {**common, **(release or {})}, "name": "Release"})
    return add(f"{prefix}.list", {"isa": "XCConfigurationList", "buildConfigurations": [d, r],
                                  "defaultConfigurationIsVisible": 0, "defaultConfigurationName": "Release"})

signing = {"CODE_SIGN_STYLE": "Manual", "CODE_SIGN_IDENTITY": "Apple Development", "DEVELOPMENT_TEAM": TEAM,
           "PROVISIONING_PROFILE_SPECIFIER": "", "ENABLE_HARDENED_RUNTIME": "YES"}
version = {"MARKETING_VERSION": "2.0", "CURRENT_PROJECT_VERSION": "1"}

# Widget extension target
w_sources = add("phase.widget.sources", {"isa": "PBXSourcesBuildPhase", "buildActionMask": 2147483647, "files": [],
                                         "runOnlyForDeploymentPostprocessing": 0})
w_frameworks = add("phase.widget.frameworks", {"isa": "PBXFrameworksBuildPhase", "buildActionMask": 2147483647, "files": [],
                                               "runOnlyForDeploymentPostprocessing": 0})
w_resources = add("phase.widget.resources", {"isa": "PBXResourcesBuildPhase", "buildActionMask": 2147483647, "files": [],
                                             "runOnlyForDeploymentPostprocessing": 0})
w_configs = configs("config.widget", {
    **signing, **version,
    "PRODUCT_NAME": "AquariumWidget", "PRODUCT_BUNDLE_IDENTIFIER": "com.piersonluscy.voxelaquarium.widget",
    "INFOPLIST_FILE": "Config/Widget-Info.plist", "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_KEY_CFBundleDisplayName": "Voxel Aquarium", "INFOPLIST_KEY_NSHumanReadableCopyright": "",
    "CODE_SIGN_ENTITLEMENTS": "Config/Widget.entitlements", "SKIP_INSTALL": "YES",
    "APPLICATION_EXTENSION_API_ONLY": "YES",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks @executable_path/../../../../Frameworks",
})
widget_target = add("target.widget", {
    "isa": "PBXNativeTarget", "buildConfigurationList": w_configs,
    "buildPhases": [w_sources, w_frameworks, w_resources], "buildRules": [], "dependencies": [],
    "fileSystemSynchronizedGroups": [shared_group, widget_group],
    "name": "AquariumWidget", "productName": "AquariumWidget", "productReference": widget_product,
    "productType": "com.apple.product-type.app-extension",
})

# App target
embed_file = add("buildfile.embed", {"isa": "PBXBuildFile", "fileRef": widget_product,
                                     "settings": {"ATTRIBUTES": ["RemoveHeadersOnCopy"]}})
a_sources = add("phase.app.sources", {"isa": "PBXSourcesBuildPhase", "buildActionMask": 2147483647, "files": [],
                                      "runOnlyForDeploymentPostprocessing": 0})
a_frameworks = add("phase.app.frameworks", {"isa": "PBXFrameworksBuildPhase", "buildActionMask": 2147483647, "files": [],
                                            "runOnlyForDeploymentPostprocessing": 0})
a_resources = add("phase.app.resources", {"isa": "PBXResourcesBuildPhase", "buildActionMask": 2147483647, "files": [],
                                          "runOnlyForDeploymentPostprocessing": 0})
a_embed = add("phase.app.embed", {"isa": "PBXCopyFilesBuildPhase", "buildActionMask": 2147483647, "dstPath": "",
                                  "dstSubfolderSpec": 13, "files": [embed_file], "name": "Embed Foundation Extensions",
                                  "runOnlyForDeploymentPostprocessing": 0})
proxy = add("proxy.widget", {"isa": "PBXContainerItemProxy", "containerPortal": oid("project"), "proxyType": 1,
                             "remoteGlobalIDString": widget_target, "remoteInfo": "AquariumWidget"})
dependency = add("dep.widget", {"isa": "PBXTargetDependency", "target": widget_target, "targetProxy": proxy})
a_configs = configs("config.app", {
    **signing, **version,
    "PRODUCT_NAME": "Voxel Aquarium", "PRODUCT_BUNDLE_IDENTIFIER": "com.piersonluscy.voxelaquarium",
    "INFOPLIST_FILE": "Config/App-Info.plist", "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_KEY_CFBundleDisplayName": "Voxel Aquarium",
    "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.entertainment",
    "INFOPLIST_KEY_NSHumanReadableCopyright": "",
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "CODE_SIGN_ENTITLEMENTS": "Config/App.entitlements", "COMBINE_HIDPI_IMAGES": "YES",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/../Frameworks",
})
app_target = add("target.app", {
    "isa": "PBXNativeTarget", "buildConfigurationList": a_configs,
    "buildPhases": [a_sources, a_frameworks, a_resources, a_embed], "buildRules": [], "dependencies": [dependency],
    "fileSystemSynchronizedGroups": [app_group, shared_group],
    "name": "VoxelAquarium", "productName": "VoxelAquarium", "productReference": app_product,
    "productType": "com.apple.product-type.application",
})

# Project
common = {
    "ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES", "ENABLE_USER_SCRIPT_SANDBOXING": "YES", "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "MACOSX_DEPLOYMENT_TARGET": "15.0", "SDKROOT": "macosx", "SWIFT_VERSION": "5.0",
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
}
p_configs = configs("config.project", common,
                    debug={"DEBUG_INFORMATION_FORMAT": "dwarf", "ENABLE_TESTABILITY": "YES", "ONLY_ACTIVE_ARCH": "YES",
                           "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)", "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
                           "GCC_OPTIMIZATION_LEVEL": "0"},
                    release={"DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym", "SWIFT_COMPILATION_MODE": "wholemodule",
                             "ENABLE_NS_ASSERTIONS": "NO"})
objs[oid("project")] = {
    "isa": "PBXProject", "attributes": {"BuildIndependentTargetsInParallel": 1, "LastSwiftUpdateCheck": 2700,
                                        "LastUpgradeCheck": 2700},
    "buildConfigurationList": p_configs, "developmentRegion": "en", "hasScannedForEncodings": 0,
    "knownRegions": ["en", "Base"], "mainGroup": main_group, "minimizedProjectReferenceProxies": 1,
    "preferredProjectObjectVersion": 77, "productRefGroup": products, "projectDirPath": "", "projectRoot": "",
    "targets": [app_target, widget_target],
}

text = "// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 77;\n\tobjects = {\n"
for k in sorted(objs, key=lambda k: (objs[k]["isa"], k)):
    text += f"\t\t{k} = {fmt(objs[k], 3)};\n"
text += f"\t}};\n\trootObject = {oid('project')};\n}}\n"
here = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(here, "VoxelAquarium.xcodeproj", "project.pbxproj"), "w") as f:
    f.write(text)
print("wrote project.pbxproj with", len(objs), "objects")
