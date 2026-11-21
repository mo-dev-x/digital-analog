#!/usr/bin/env python3
"""Compile/run the XCTest suite without SwiftPM process monitoring (Linux fallback)."""
import argparse,os,pathlib,re,shutil,subprocess
ROOT=pathlib.Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--swiftc',default=shutil.which('swiftc'));p.add_argument('--include');p.add_argument('--library');a=p.parse_args()
if not a.swiftc:raise SystemExit('Swift compiler not found')
build=ROOT/'.test-build/core';build.mkdir(parents=True,exist_ok=True)
flags=['-I',str(ROOT/'Core/Sources/CSQLite')]
if a.include:flags+=['-Xcc','-I'+a.include]
if a.library:flags+=['-L',a.library]
ext='.dylib' if os.uname().sysname=='Darwin' else '.so'
lib=build/('libDigitalAnalogCore'+ext)
subprocess.run([a.swiftc,'-emit-library','-emit-module','-enable-testing','-module-name','DigitalAnalogCore',*flags,*map(str,sorted((ROOT/'Core/Sources/DigitalAnalogCore').glob('*.swift'))),'-emit-module-path',str(build/'DigitalAnalogCore.swiftmodule'),'-o',str(lib)],check=True)
test=ROOT/'Core/Tests/DigitalAnalogCoreTests/CoreTests.swift'
entries=[]
for name,signature in sorted(re.findall(r'func (test\w+)\([^)]*\)([^\{]*)\{',test.read_text())):
 entries.append(f'("{name}", '+(f'asyncTest({name})' if 'async' in signature else name)+')')
main=build/'main.swift';main.write_text('import XCTest\nextension CoreTests { static let allTests = [\n'+',\n'.join(entries)+'\n] }\nXCTMain([testCase(CoreTests.allTests)])\n')
exe=build/'core-tests'
subprocess.run([a.swiftc,'-enable-testing','-module-name','DigitalAnalogCoreTests',*flags,'-I',str(build),'-L',str(build),'-lDigitalAnalogCore',str(test),str(main),'-o',str(exe)],check=True)
env=os.environ.copy();key='DYLD_LIBRARY_PATH' if ext=='.dylib' else 'LD_LIBRARY_PATH';env[key]=str(build)+os.pathsep+env.get(key,'')
os.execve(str(exe),[str(exe)],env)
