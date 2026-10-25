#!/usr/bin/env python3
"""Portable core gate. A trace folds the canonical state hash of every tick."""
import json,pathlib,re,subprocess,sys
ROOT=pathlib.Path(__file__).resolve().parents[1]
compat=json.loads((ROOT/'compatibility.json').read_text())
for key,file,constant in [('model','curl-sim','MODEL_VERSION'),('protocol','curl-proto','PROTOCOL_VERSION'),('replay','curl-proto','REPLAY_VERSION')]:
    source=(ROOT/'crates'/file/'src/lib.rs').read_text()
    assert int(re.search(constant+r': u32 = (\d+)',source).group(1))==compat[key], 'Compatibility metadata mismatch'
def run(args):subprocess.run(args,cwd=ROOT,check=True)
run(['cargo','fmt','--all','--','--check'])
run(['cargo','test','--locked','--workspace','--exclude','curl-godot'])
actual=subprocess.check_output(['cargo','run','--locked','--release','-p','curl-server','--','golden'],cwd=ROOT,text=True)
expected=(ROOT/'validation/golden.txt').read_text()
if actual.replace('\r\n','\n')!=expected:print('Golden trace mismatch:\n'+actual);sys.exit(1)
print('Core and every-tick determinism traces passed')
