#!/usr/bin/env python3
"""앱 프로젝트 변경 없이 실제 Entry 소스의 시뮬레이터 XCTest 호스트를 생성합니다."""

import argparse
import json
import shutil
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    project = args.output.resolve() / "EntryQA.xcodeproj"
    project.mkdir(parents=True, exist_ok=True)
    objects = {}

    def add(value):
        key = f"{len(objects) + 1:024X}"
        objects[key] = value
        return key

    def group(path):
        return add(dict(isa="PBXFileSystemSynchronizedRootGroup", path=str(path),
                        sourceTree="<group>"))

    def configs(settings):
        items = [add(dict(isa="XCBuildConfiguration", name=name, buildSettings=settings))
                 for name in ("Debug", "Release")]
        return add(dict(isa="XCConfigurationList", buildConfigurations=items,
                        defaultConfigurationIsVisible=0, defaultConfigurationName="Debug"))

    project_id = add({})
    local = add(dict(isa="XCLocalSwiftPackageReference",
                     relativePath=str(repo / "Packages/ResearchersModules")))
    remote = add(dict(isa="XCRemoteSwiftPackageReference",
                      repositoryURL="https://github.com/pointfreeco/swift-composable-architecture",
                      requirement=dict(kind="upToNextMajorVersion", minimumVersion="1.26.2")))
    products = [add(dict(isa="XCSwiftPackageProductDependency", package=package,
                         productName=name))
                for package, name in [(local, "LabcordKit"), (remote, "ComposableArchitecture")]]
    feature_group = group(repo / "Researchers/Features/ExperimentEntry")
    support_group = group(repo / "Tests/ExperimentEntry/Support")
    resources_group = group(repo / "Researchers/Resources")
    unit_group = group(repo / "Tests/ExperimentEntry/UnitTests")
    ui_group = group(repo / "Tests/ExperimentEntry/UITests")
    targets, references = [], []
    app_id = None
    target_ids = {}
    for name, kind, groups in [
        ("EntryQA", "application", [feature_group, support_group, resources_group]),
        ("EntryQATests", "bundle.unit-test", [unit_group]),
        ("EntryQAUITests", "bundle.ui-testing", [ui_group]),
    ]:
        is_app = kind == "application"
        is_ui = kind == "bundle.ui-testing"
        # 단위 테스트는 TEST_HOST를 통해 공유 심벌을 참조합니다.
        # 같은 패키지를 두 번 링크하면 Xcode 27에서 동적 변형을 강제합니다.
        links = products if is_app else []
        phases = [add(dict(isa="PBXSourcesBuildPhase", buildActionMask=2147483647,
                           files=[], runOnlyForDeploymentPostprocessing=0)),
                  add(dict(isa="PBXFrameworksBuildPhase", buildActionMask=2147483647,
                           files=[add(dict(isa="PBXBuildFile", productRef=p)) for p in links],
                           runOnlyForDeploymentPostprocessing=0)),
                  add(dict(isa="PBXResourcesBuildPhase", buildActionMask=2147483647,
                           files=[], runOnlyForDeploymentPostprocessing=0))]
        product = add(dict(isa="PBXFileReference", sourceTree="BUILT_PRODUCTS_DIR",
                           explicitFileType="wrapper.application" if is_app else "wrapper.cfbundle",
                           path=name + (".app" if is_app else ".xctest")))
        references.append(product)
        settings = dict(GENERATE_INFOPLIST_FILE="YES", PRODUCT_NAME="$(TARGET_NAME)",
                        PRODUCT_BUNDLE_IDENTIFIER="dev.labcord.entry-qa.5c6d" +
                        ("" if is_app else "." + name.lower()), TARGETED_DEVICE_FAMILY="1,2",
                        CODE_SIGNING_ALLOWED="NO", SWIFT_EMIT_LOC_STRINGS="NO")
        if is_app:
            settings.update(INFOPLIST_KEY_UILaunchScreen_Generation="YES",
                            INFOPLIST_KEY_UIApplicationSceneManifest_Generation="YES")
        elif is_ui:
            settings["TEST_TARGET_NAME"] = "EntryQA"
        else:
            settings.update(TEST_HOST="$(BUILT_PRODUCTS_DIR)/EntryQA.app/EntryQA",
                            BUNDLE_LOADER="$(TEST_HOST)")
        dependencies = []
        if app_id:
            proxy = add(dict(isa="PBXContainerItemProxy", containerPortal=project_id,
                             proxyType=1, remoteGlobalIDString=app_id, remoteInfo="EntryQA"))
            dependencies = [add(dict(isa="PBXTargetDependency", target=app_id,
                                     targetProxy=proxy))]
        target = add(dict(isa="PBXNativeTarget", name=name, productName=name,
                          productType="com.apple.product-type." + kind,
                          productReference=product, buildConfigurationList=configs(settings),
                          buildPhases=phases, buildRules=[], dependencies=dependencies,
                          fileSystemSynchronizedGroups=groups, packageProductDependencies=links))
        targets.append(target)
        target_ids[name] = target
        if is_app:
            app_id = target
    product_group = add(dict(isa="PBXGroup", name="Products", children=references,
                             sourceTree="<group>"))
    main_group = add(dict(isa="PBXGroup", sourceTree="<group>",
                          children=[feature_group, support_group, resources_group,
                                    unit_group, ui_group, product_group]))
    settings = dict(CLANG_ENABLE_MODULES="YES", SDKROOT="iphoneos",
                    IPHONEOS_DEPLOYMENT_TARGET="27.0", SWIFT_VERSION="5.0",
                    SWIFT_DEFAULT_ACTOR_ISOLATION="MainActor",
                    SWIFT_APPROACHABLE_CONCURRENCY="YES",
                    SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY="YES",
                    SWIFT_OPTIMIZATION_LEVEL="-Onone", GCC_OPTIMIZATION_LEVEL="0",
                    SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG", ENABLE_TESTABILITY="YES",
                    DEBUG_INFORMATION_FORMAT="dwarf", ONLY_ACTIVE_ARCH="YES")
    objects[project_id] = dict(
        isa="PBXProject", attributes=dict(BuildIndependentTargetsInParallel="YES",
                                         LastUpgradeCheck="2700"),
        buildConfigurationList=configs(settings), preferredProjectObjectVersion=77,
        developmentRegion="en", knownRegions=["en", "Base"], mainGroup=main_group,
        packageReferences=[local, remote], productRefGroup=product_group,
        projectDirPath="", projectRoot="", targets=targets)

    def serialize(value):
        if isinstance(value, dict):
            return "{\n" + "\n".join(f"{json.dumps(k)} = {serialize(v)};"
                                     for k, v in value.items()) + "\n}"
        if isinstance(value, list):
            return "(" + ",".join(serialize(v) for v in value) + ",)" if value else "()"
        return str(value) if isinstance(value, int) else json.dumps(value)

    (project / "project.pbxproj").write_text(
        "// !$*UTF8*$!\n" + serialize(dict(archiveVersion=1, classes={}, objectVersion=110,
                                           objects=objects, rootObject=project_id)))
    scheme = project / "xcshareddata/xcschemes/EntryQA.xcscheme"
    scheme.parent.mkdir(parents=True, exist_ok=True)

    def reference(name):
        extension = ".app" if name == "EntryQA" else ".xctest"
        return (f'<BuildableReference BuildableIdentifier="primary" '
                f'BlueprintIdentifier="{target_ids[name]}" BuildableName="{name}{extension}" '
                f'BlueprintName="{name}" ReferencedContainer="container:EntryQA.xcodeproj"/>')

    scheme.write_text(
        '<?xml version="1.0" encoding="UTF-8"?><Scheme version="1.7">'
        '<BuildAction buildImplicitDependencies="YES"><BuildActionEntries>'
        '<BuildActionEntry buildForTesting="YES" buildForRunning="YES" '
        'buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">'
        + reference("EntryQA") + '</BuildActionEntry></BuildActionEntries></BuildAction>'
        '<TestAction buildConfiguration="Debug" shouldUseLaunchSchemeArgsEnv="YES">'
        '<Testables>' + ''.join('<TestableReference skipped="NO">' + reference(n)
                               + '</TestableReference>'
                               for n in ["EntryQATests", "EntryQAUITests"])
        + '</Testables></TestAction><LaunchAction buildConfiguration="Debug">'
        '<BuildableProductRunnable runnableDebuggingMode="0">' + reference("EntryQA")
        + '</BuildableProductRunnable></LaunchAction></Scheme>')
    resolved = project / "project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
    resolved.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(repo / "Researchers.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
                 resolved)
    print(project)


if __name__ == "__main__":
    main()
