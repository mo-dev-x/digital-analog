#!/usr/bin/env python3
"""Deterministic, dependency-free Xcode project generator; Python 3.10+."""
import hashlib,json,pathlib,plistlib
ROOT=pathlib.Path(__file__).resolve().parents[1]
def uid(value):return hashlib.sha1(value.encode()).hexdigest()[:24].upper()
class Raw(str):pass
def ref(value):return Raw(uid(value))
objects={}
def add(key,isa,**fields):objects[uid(key)]={'isa':isa,**fields};return ref(key)
def serialize(v):
    if isinstance(v,Raw):return v
    if isinstance(v,dict):return '{ '+' '.join(json.dumps(k)+' = '+serialize(x)+';' for k,x in v.items())+' }'
    if isinstance(v,list):return '('+', '.join(map(serialize,v))+')'
    if isinstance(v,int):return str(v)
    return json.dumps(str(v))
app=list(sorted((ROOT/'App').glob('*.swift')))
tests=list(sorted((ROOT/'Tests').glob('*.swift')))
for p in app+tests:
    name=str(p.relative_to(ROOT)); kind='sourcecode.swift'
    add(name,'PBXFileReference',lastKnownFileType=kind,path=name,sourceTree='<group>');add('build:'+name,'PBXBuildFile',fileRef=ref(name))
for name,kind in [('Resources/Assets.xcassets','folder.assetcatalog'),('Resources/THIRD_PARTY.md','text'),('Tests/Fixtures/tone.wav','audio.wav'),('Tests/Fixtures/visual-reference.jpeg','image.jpeg')]:
    add(name,'PBXFileReference',lastKnownFileType=kind,path=name,sourceTree='<group>');add('build:'+name,'PBXBuildFile',fileRef=ref(name))
for key,path,kind in [('appProduct','DigitalAnalog.app','wrapper.application'),('testProduct','DigitalAnalogTests.xctest','wrapper.cfbundle')]:add(key,'PBXFileReference',explicitFileType=kind,path=path,sourceTree='BUILT_PRODUCTS_DIR')
add('products','PBXGroup',children=[ref('appProduct'),ref('testProduct')],name='Products',sourceTree='<group>')
add('group','PBXGroup',children=[ref(str(p.relative_to(ROOT))) for p in app+tests]+[ref('Resources/Assets.xcassets'),ref('Resources/THIRD_PARTY.md'),ref('Tests/Fixtures/tone.wav'),ref('Tests/Fixtures/visual-reference.jpeg'),ref('products')],sourceTree='<group>')
add('corePackage','XCLocalSwiftPackageReference',relativePath='Core')
add('coreProduct','XCSwiftPackageProductDependency',package=ref('corePackage'),productName='DigitalAnalogCore')
add('coreLink','PBXBuildFile',productRef=ref('coreProduct'))
for target,paths in [('app',app),('test',tests)]:
    add(target+'Sources','PBXSourcesBuildPhase',buildActionMask=2147483647,files=[ref('build:'+str(p.relative_to(ROOT))) for p in paths],runOnlyForDeploymentPostprocessing=0)
    add(target+'Frameworks','PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[ref('coreLink')],runOnlyForDeploymentPostprocessing=0)
    resources=['Resources/Assets.xcassets','Resources/THIRD_PARTY.md'] if target=='app' else ['Tests/Fixtures/tone.wav','Tests/Fixtures/visual-reference.jpeg']
    add(target+'Resources','PBXResourcesBuildPhase',buildActionMask=2147483647,files=[ref('build:'+name) for name in resources],runOnlyForDeploymentPostprocessing=0)
    for mode in ['Debug','Release']:
        settings={'ARCHS':'arm64','ONLY_ACTIVE_ARCH':'YES' if mode=='Debug' else 'NO','SWIFT_VERSION':'5.0','IPHONEOS_DEPLOYMENT_TARGET':'17.0','TARGETED_DEVICE_FAMILY':'1','SDKROOT':'iphoneos','CODE_SIGN_STYLE':'Automatic','SWIFT_STRICT_CONCURRENCY':'targeted','SWIFT_OPTIMIZATION_LEVEL':'-Onone' if mode=='Debug' else '-O','ENABLE_USER_SCRIPT_SANDBOXING':'NO','CLANG_ENABLE_MODULES':'YES','GCC_C_LANGUAGE_STANDARD':'gnu11','OTHER_LDFLAGS':['$(inherited)','-lsqlite3'],'SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG' if mode=='Debug' else ''}
        if target=='app':settings.update({'PRODUCT_BUNDLE_IDENTIFIER':'personal.digitalanalog.player','PRODUCT_NAME':'DigitalAnalog','INFOPLIST_FILE':'Info.plist','ENABLE_TESTABILITY':'YES' if mode=='Debug' else 'NO','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks'],'ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon'})
        else:settings.update({'PRODUCT_BUNDLE_IDENTIFIER':'personal.digitalanalog.player.tests','PRODUCT_NAME':'DigitalAnalogTests','GENERATE_INFOPLIST_FILE':'YES','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/DigitalAnalog.app/DigitalAnalog','BUNDLE_LOADER':'$(TEST_HOST)','LD_RUNPATH_SEARCH_PATHS':['$(inherited)','@executable_path/Frameworks','@loader_path/Frameworks']})
        add(target+mode,'XCBuildConfiguration',buildSettings=settings,name=mode)
    add(target+'Configs','XCConfigurationList',buildConfigurations=[ref(target+'Debug'),ref(target+'Release')],defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
add('proxy','PBXContainerItemProxy',containerPortal=ref('project'),proxyType=1,remoteGlobalIDString=ref('appTarget'),remoteInfo='DigitalAnalog')
add('dependency','PBXTargetDependency',target=ref('appTarget'),targetProxy=ref('proxy'))
for key,name,kind in [('app','DigitalAnalog','application'),('test','DigitalAnalogTests','bundle.unit-test')]:
    phases=[ref(key+'Sources'),ref(key+'Frameworks'),ref(key+'Resources')]
    add(key+'Target','PBXNativeTarget',buildConfigurationList=ref(key+'Configs'),buildPhases=phases,buildRules=[],dependencies=[ref('dependency')] if key=='test' else [],name=name,productName=name,productReference=ref(key+'Product'),productType='com.apple.product-type.'+kind,packageProductDependencies=[ref('coreProduct')])
# A separate UI automation runner drives the real application through XCTest.
ui_paths=list(sorted((ROOT/'UITests').glob('*.swift')))
for p in ui_paths:
    name=str(p.relative_to(ROOT));add(name,'PBXFileReference',lastKnownFileType='sourcecode.swift',path=name,sourceTree='<group>');add('build:'+name,'PBXBuildFile',fileRef=ref(name))
    objects[uid('group')]['children'].append(ref(name))
add('uiProduct','PBXFileReference',explicitFileType='wrapper.cfbundle',path='DigitalAnalogUITests.xctest',sourceTree='BUILT_PRODUCTS_DIR')
objects[uid('products')]['children'].append(ref('uiProduct'))
add('uiSources','PBXSourcesBuildPhase',buildActionMask=2147483647,files=[ref('build:'+str(p.relative_to(ROOT))) for p in ui_paths],runOnlyForDeploymentPostprocessing=0)
add('uiFrameworks','PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)
for mode in ['Debug','Release']:
    settings=dict(objects[uid('test'+mode)]['buildSettings'])
    settings.pop('TEST_HOST',None);settings.pop('BUNDLE_LOADER',None)
    settings.update(PRODUCT_BUNDLE_IDENTIFIER='personal.digitalanalog.uitests',PRODUCT_NAME='DigitalAnalogUITests',TEST_TARGET_NAME='DigitalAnalog')
    add('ui'+mode,'XCBuildConfiguration',buildSettings=settings,name=mode)
add('uiConfigs','XCConfigurationList',buildConfigurations=[ref('uiDebug'),ref('uiRelease')],defaultConfigurationIsVisible=0,defaultConfigurationName='Debug')
add('uiTarget','PBXNativeTarget',buildConfigurationList=ref('uiConfigs'),buildPhases=[ref('uiSources'),ref('uiFrameworks')],buildRules=[],dependencies=[ref('dependency')],name='DigitalAnalogUITests',productName='DigitalAnalogUITests',productReference=ref('uiProduct'),productType='com.apple.product-type.bundle.ui-testing')
add('debugFixtures','PBXShellScriptBuildPhase',buildActionMask=2147483647,files=[],inputPaths=[],outputPaths=[],runOnlyForDeploymentPostprocessing=0,shellPath='/bin/bash',shellScript='if [ "$CONFIGURATION" = Debug ]; then cp "$PROJECT_DIR/Tests/Fixtures/tone.wav" "$PROJECT_DIR/Tests/Fixtures/visual-reference.jpeg" "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/"; fi',name='Install Debug-only interaction fixtures',alwaysOutOfDate=1)
objects[uid('appTarget')]['buildPhases'].append(ref('debugFixtures'))
for mode in ['Debug','Release']:add('project'+mode,'XCBuildConfiguration',buildSettings={'CLANG_ENABLE_MODULES':'YES','SWIFT_VERSION':'5.0','DEBUG_INFORMATION_FORMAT':'dwarf'},name=mode)
add('projectConfigs','XCConfigurationList',buildConfigurations=[ref('projectDebug'),ref('projectRelease')],defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
add('project','PBXProject',attributes={'LastUpgradeCheck':'2600','TargetAttributes':{uid('testTarget'):{'TestTargetID':uid('appTarget')}}},buildConfigurationList=ref('projectConfigs'),compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en','Base'],mainGroup=ref('group'),productRefGroup=ref('products'),projectDirPath='',projectRoot='',targets=[ref('appTarget'),ref('testTarget')],packageReferences=[ref('corePackage')])
objects[uid('project')]['targets'].append(ref('uiTarget'))
objects[uid('project')]['attributes']['TargetAttributes'][uid('uiTarget')]={'TestTargetID':uid('appTarget')}
project=ROOT/'DigitalAnalog.xcodeproj';project.mkdir(exist_ok=True)
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n'+serialize({'archiveVersion':1,'classes':{},'objectVersion':56,'objects':objects,'rootObject':ref('project')})+'\n')
def buildref(key,name,product):return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid(key)}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:DigitalAnalog.xcodeproj"/>'
a=buildref('appTarget','DigitalAnalog','DigitalAnalog.app');t=buildref('testTarget','DigitalAnalogTests','DigitalAnalogTests.xctest')
u=buildref('uiTarget','DigitalAnalogUITests','DigitalAnalogUITests.xctest')
scheme=project/'xcshareddata/xcschemes';scheme.mkdir(parents=True,exist_ok=True)
(scheme/'DigitalAnalog.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{a}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{t}</TestableReference><TestableReference skipped="NO">{u}</TestableReference></Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{a}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{a}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
info={'CFBundleDevelopmentRegion':'en','CFBundleDisplayName':'Digital Analog','CFBundleExecutable':'$(EXECUTABLE_NAME)','CFBundleIdentifier':'$(PRODUCT_BUNDLE_IDENTIFIER)','CFBundleInfoDictionaryVersion':'6.0','CFBundleName':'$(PRODUCT_NAME)','CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.2.0','CFBundleVersion':'2','LSRequiresIPhoneOS':True,'UILaunchScreen':{'UIColorName':'LaunchBackground'},'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False},'UIBackgroundModes':['audio'],'UISupportedInterfaceOrientations':['UIInterfaceOrientationPortrait'],'CADisableMinimumFrameDurationOnPhone':True,'UIFileSharingEnabled':False,'LSSupportsOpeningDocumentsInPlace':True}
with (ROOT/'Info.plist').open('wb') as f:plistlib.dump(info,f)
print(f'Generated Xcode project: {len(app)} app sources, {len(tests)} hosted test files')
