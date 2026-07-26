#!/usr/bin/env python3
from pathlib import Path
import json, re, sys, xml.etree.ElementTree as ET
ROOT = Path(__file__).resolve().parents[1]
M = ROOT / 'module'
errors=[]
def fail(msg): errors.append(msg)

def props(path):
    out={}
    for line in path.read_text(encoding='utf-8').splitlines():
        if '=' in line and not line.lstrip().startswith('#'):
            k,v=line.split('=',1); out[k]=v
    return out
p=props(M/'module.prop')
expected='v1.0.0-beta.1'
if p.get('version') != expected: fail('module version mismatch')
if p.get('versionCode') != '100001': fail('versionCode mismatch')
if p.get('id') != 'audiorange': fail('module id mismatch')
if p.get('updateJson') != 'https://raw.githubusercontent.com/lolokeksu/AudioRange/main/update.json': fail('updateJson mismatch')
update=json.loads((ROOT/'update.json').read_text(encoding='utf-8'))
if update.get('version') != expected or update.get('versionCode') != 100001: fail('update.json version mismatch')
ET.parse(ROOT/'docs/assets/splash.svg')

# No former project/version lineage in active source.
for path in list(M.rglob('*')) + [ROOT/'README.md',ROOT/'README_RU.md',ROOT/'CHANGELOG.md']:
    if not path.is_file() or path.name in {'banner.png','webicon.png','manifest.sha256'}: continue
    try: text=path.read_text(encoding='utf-8')
    except UnicodeDecodeError: continue
    for forbidden in ('redwin','msRedwin','Public RC','4.4.4','previous community Studio','Migration from v3.x','Volume Steps Studio','Volume-Steps-Studio','volume_steps_studio','volstepsctl','vsteps','VSS_','vss_'):
        if forbidden.lower() in text.lower(): fail(f'{path.relative_to(ROOT)} contains legacy marker {forbidden}')

# HTML/JS consistency.
html=(M/'webroot/index.html').read_text(encoding='utf-8')
js=(M/'webroot/app.js').read_text(encoding='utf-8')
ids=re.findall(r'\bid=["\']([^"\']+)', html)
if len(ids) != len(set(ids)): fail('duplicate HTML id')
refs=set(re.findall(r'\$\(["\']([^"\']+)["\']\)', js))
missing=sorted(refs-set(ids))
if missing: fail('missing HTML ids: '+', '.join(missing))
if '<button' in re.sub(r'<summary\b[^>]*>.*?</summary>', '', html, flags=re.S|re.I): pass
for summary in re.findall(r'<summary\b[^>]*>(.*?)</summary>', html, flags=re.S|re.I):
    if '<button' in summary.lower(): fail('button nested inside summary')

# Security/static boundaries.
text='\n'.join(x.read_text(encoding='utf-8',errors='ignore') for x in M.rglob('*') if x.is_file() and x.suffix not in {'.png'})
for pattern in (r'\bcurl\b',r'\bwget\b',r'\beval\b',r'\bsetenforce\b',r'chmod\s+777',r'\bnc\s',r'\bsocat\b'):
    if re.search(pattern,text,re.I): fail('forbidden runtime pattern: '+pattern)
for path in M.rglob('*'):
    if path.is_file() and path.read_bytes()[:4] == b'\x7fELF': fail('unexpected ELF: '+str(path.relative_to(ROOT)))

# Shell executable permissions in source tree.
for rel in ('customize.sh','post-fs-data.sh','service.sh','action.sh','uninstall.sh','bin/audiorangectl','system/bin/audiorange'):
    if not (M/rel).stat().st_mode & 0o111: fail('not executable: module/'+rel)

if errors:
    print('\n'.join('FAIL: '+e for e in errors), file=sys.stderr)
    raise SystemExit(1)
print('Static checks passed.')
