#!/bin/sh
# Verify the hand-written Xcode project is internally consistent without Xcode.
# Catches the class of mistakes a Linux-only author makes: dangling UUIDs,
# files listed in a build phase but missing from disk, scheme/target drift.
set -eu

cd "$(dirname "$0")/.."

python3 - <<'PY'
import re
import sys
from pathlib import Path

root = Path('.')
pbx = (root / 'WB2API.xcodeproj/project.pbxproj').read_text()
scheme_path = root / 'WB2API.xcodeproj/xcshareddata/xcschemes/WB2API.xcscheme'
errors = []

ID = re.compile(r'(?<![0-9A-Za-z])([0-9A-F]{24})(?![0-9A-Za-z])')
refs = {m.group(1) for m in ID.finditer(pbx)}
defined = set(re.findall(
    r'^[ \t]+([0-9A-F]{24})(?:[ \t]+/\*.*?\*/)?[ \t]*= \{', pbx, re.M))
if refs - defined:
    errors.append(f'未定义的对象 ID: {sorted(refs - defined)}')
if defined - refs:
    errors.append(f'定义了但没被引用的 ID: {sorted(defined - refs)}')

filerefs = set(re.findall(
    r'([0-9A-F]{24})(?:[ \t]+/\*.*?\*/)?[ \t]*= \{isa = PBXFileReference;', pbx))
buildfiles = re.findall(
    r'([0-9A-F]{24})(?:[ \t]+/\*.*?\*/)?[ \t]*= \{isa = PBXBuildFile; fileRef = ([0-9A-F]{24})',
    pbx)
for bf, fr in buildfiles:
    if fr not in filerefs:
        errors.append(f'BuildFile {bf} 指向不存在的 fileRef {fr}')

bf_ids = {b for b, _ in buildfiles}
for phase in ('Sources', 'Resources'):
    block = re.search(rf'isa = PBX{phase}BuildPhase;(.*?)\n\t\t\}};', pbx, re.S)
    if not block:
        errors.append(f'缺少 {phase} 阶段')
        continue
    for oid in re.findall(r'([0-9A-F]{24}) /', block.group(1)):
        if oid not in bf_ids:
            errors.append(f'{phase} 阶段引用了未注册的 BuildFile {oid}')

# 磁盘文件 → 工程引用
group = root / 'WB2API'
paths = re.findall(r'path = ([A-Za-z0-9_.\-]+); sourceTree = "<group>";', pbx)
for name in ('WB2APIApp.swift', 'AppSettings.swift', 'RootView.swift',
             'ServerEditor.swift', 'BrowserView.swift'):
    if name not in pbx:
        errors.append(f'{name} 没有加进工程')
    if not list(group.rglob(name)):
        errors.append(f'{name} 在磁盘上不存在')

plist = root / 'WB2API/Info.plist'
if not plist.exists():
    errors.append('Info.plist 缺失')
else:
    import plistlib
    info = plistlib.loads(plist.read_bytes())
    for key in ('CFBundleIdentifier', 'CFBundleExecutable', 'UIApplicationSceneManifest',
                'UILaunchScreen', 'NSAppTransportSecurity'):
        if key not in info:
            errors.append(f'Info.plist 缺键 {key}')
    if not info['CFBundleIdentifier'].startswith('$('):
        errors.append('CFBundleIdentifier 应是 $(PRODUCT_BUNDLE_IDENTIFIER)')

    if 'INFOPLIST_FILE = WB2API/Info.plist;' not in pbx:
        errors.append('工程没有引用 Info.plist')

icon = root / 'WB2API/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png'
if not icon.exists():
    errors.append('AppIcon-1024.png 缺失，先跑 tools/make_icon.py')
else:
    from PIL import Image
    with Image.open(icon) as im:
        if im.size != (1024, 1024):
            errors.append(f'AppIcon 尺寸 {im.size} 不是 1024x1024')

# scheme ↔ target
target = re.search(
    r'([0-9A-F]{24})[ \t]+/\* WB2API \*/ = \{\n\t\t\tisa = PBXNativeTarget;', pbx)
if not target:
    errors.append('找不到 WB2API native target')
else:
    sch = scheme_path.read_text()
    ids = set(re.findall(r'BlueprintIdentifier = "([0-9A-F]{24})"', sch))
    if ids != {target.group(1)}:
        errors.append(f'scheme 的 BlueprintIdentifier {ids} 与 target {target.group(1)} 不一致')

if errors:
    print('✗ 工程校验失败：')
    for e in errors:
        print('  -', e)
    sys.exit(1)

print(f'✓ 工程校验通过：{len(defined)} 个对象、{len(buildfiles)} 个编译条目')
PY

# Swift 面层静态检查（括号平衡、必填 import）
python3 - <<'PY'
import re
import sys
from pathlib import Path

fail = False
for p in sorted(Path('WB2API/App').glob('*.swift')):
    s = p.read_text()
    t = re.sub(r'"""(?:.|\n)*?"""', '""', s)
    t = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', t)
    t = re.sub(r'//[^\n]*', '', t)
    if t.count('{') != t.count('}'):
        print(f'✗ {p.name}: 大括号不平衡')
        fail = True
    if t.count('(') != t.count(')'):
        print(f'✗ {p.name}: 圆括号不平衡')
        fail = True
    if 'import ' not in s:
        print(f'✗ {p.name}: 缺少 import')
        fail = True

if fail:
    sys.exit(1)
print('✓ Swift 源文件静态检查通过')
PY
