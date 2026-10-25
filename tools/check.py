#!/usr/bin/env python3
"""Portable core gate. A trace folds the canonical state hash of every tick."""
import pathlib,subprocess,sys
ROOT=pathlib.Path(__file__).resolve().parents[1]
def run(args):subprocess.run(args,cwd=ROOT,check=True)
run(['cargo','fmt','--all','--','--check'])
run(['cargo','test','--locked','--workspace','--exclude','curl-godot'])
actual=subprocess.check_output(['cargo','run','--locked','--release','-p','curl-server','--','golden'],cwd=ROOT,text=True)
expected=(ROOT/'tests/golden.txt').read_text()
if actual.replace('\r\n','\n')!=expected:print('Golden trace mismatch:\n'+actual);sys.exit(1)
print('Core and every-tick determinism traces passed')
