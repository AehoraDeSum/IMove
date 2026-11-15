#!/usr/bin/env python3
"""Generate the small, dependency-free IMove iOS/iPadOS Xcode project."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FILES = [
    "Models.swift", "IMoveAPI.swift", "DeviceLocation.swift", "AppStore.swift",
    "MapCanvas.swift", "IMoveMobileApp.swift", "DashboardView.swift", "PlacesView.swift",
    "RoutesView.swift", "SettingsView.swift",
]


def oid(number):
    return f"B2{number:022X}"


refs = {name: oid(index + 1) for index, name in enumerate(FILES)}
builds = {name: oid(index + 101) for index, name in enumerate(FILES)}
assets_ref, assets_build, plist_ref, app_ref = [oid(i) for i in (201, 202, 203, 204)]
root_group, source_group, products_group = [oid(i) for i in (301, 302, 303)]
sources_phase, resources_phase, framework_phase = [oid(i) for i in (401, 402, 403)]
target, project = oid(501), oid(502)
target_configs, project_configs = oid(601), oid(602)
debug_target, release_target, debug_project, release_project = [oid(i) for i in (701, 702, 703, 704)]

objects = []


def add(identifier, value):
    objects.append(f"\t\t{identifier} = {value};")


for name in FILES:
    add(refs[name], f'{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = "<group>"; }}')
    add(builds[name], f'{{isa = PBXBuildFile; fileRef = {refs[name]}; }}')

add(assets_ref, '{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }')
add(assets_build, f'{{isa = PBXBuildFile; fileRef = {assets_ref}; }}')
add(plist_ref, '{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }')
add(app_ref, '{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = IMoveMobile.app; sourceTree = BUILT_PRODUCTS_DIR; }')
add(root_group, f'{{isa = PBXGroup; children = ({source_group}, {products_group},); sourceTree = "<group>"; }}')
add(source_group, '{isa = PBXGroup; children = (' + ', '.join(refs.values()) + f', {assets_ref}, {plist_ref},); path = IMoveMobile; sourceTree = "<group>"; }}')
add(products_group, f'{{isa = PBXGroup; children = ({app_ref},); name = Products; sourceTree = "<group>"; }}')
add(sources_phase, '{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (' + ', '.join(builds.values()) + ',); runOnlyForDeploymentPostprocessing = 0; }')
add(resources_phase, f'{{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({assets_build},); runOnlyForDeploymentPostprocessing = 0; }}')
add(framework_phase, '{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }')
add(target, '{isa = PBXNativeTarget; buildConfigurationList = ' + target_configs + '; buildPhases = (' + ', '.join((sources_phase, framework_phase, resources_phase)) + ',); buildRules = (); dependencies = (); name = IMoveMobile; productName = IMoveMobile; productReference = ' + app_ref + '; productType = "com.apple.product-type.application"; }')
add(project, '{isa = PBXProject; attributes = {BuildIndependentTargetsInParallel = 1; LastUpgradeCheck = 1500; TargetAttributes = {' + target + ' = {CreatedOnToolsVersion = 15.0; }; }; }; buildConfigurationList = ' + project_configs + '; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base,); mainGroup = ' + root_group + '; productRefGroup = ' + products_group + '; projectDirPath = ""; projectRoot = ""; targets = (' + target + ',); }')
add(target_configs, f'{{isa = XCConfigurationList; buildConfigurations = ({debug_target}, {release_target},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }}')
add(project_configs, f'{{isa = XCConfigurationList; buildConfigurations = ({debug_project}, {release_project},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }}')

base_target = 'ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon; CODE_SIGN_STYLE = Automatic; DEVELOPMENT_TEAM = ""; GENERATE_INFOPLIST_FILE = NO; INFOPLIST_FILE = IMoveMobile/Info.plist; IPHONEOS_DEPLOYMENT_TARGET = 15.0; PRODUCT_BUNDLE_IDENTIFIER = local.imove.mobile; PRODUCT_NAME = "$(TARGET_NAME)"; SDKROOT = iphoneos; SWIFT_VERSION = 5.0; TARGETED_DEVICE_FAMILY = "1,2";'
for ident, name in ((debug_target, 'Debug'), (release_target, 'Release')):
    add(ident, f'{{isa = XCBuildConfiguration; buildSettings = {{{base_target}}}; name = {name}; }}')
for ident, name, optimization in ((debug_project, 'Debug', '-Onone'), (release_project, 'Release', '-O')):
    add(ident, '{isa = XCBuildConfiguration; buildSettings = {ALWAYS_SEARCH_USER_PATHS = NO; CLANG_ENABLE_MODULES = YES; CLANG_ENABLE_OBJC_ARC = YES; IPHONEOS_DEPLOYMENT_TARGET = 15.0; SDKROOT = iphoneos; SWIFT_OPTIMIZATION_LEVEL = "' + optimization + '"; }; name = ' + name + '; }')

text = '// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n' + '\n'.join(objects) + '\n\t};\n\trootObject = ' + project + ';\n}\n'
(ROOT / 'IMoveMobile.xcodeproj' / 'project.pbxproj').write_text(text)
