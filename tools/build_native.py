#!/usr/bin/env python3
"""Build the local Godot bridge from the locked workspace."""
import argparse, pathlib, platform, shutil, subprocess
ROOT=pathlib.Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--release',action='store_true');a=p.parse_args()
subprocess.run(['cargo','build','--locked','-p','curl-godot','-p','curl-transport']+(['--release'] if a.release else []),cwd=ROOT,check=True)
name={'Darwin':'libcurl_godot.dylib','Linux':'libcurl_godot.so','Windows':'curl_godot.dll'}[platform.system()]
(ROOT/'native/bin').mkdir(exist_ok=True,parents=True)
shutil.copy2(ROOT/'target'/('release' if a.release else 'debug')/name,ROOT/'native/bin'/name)
print('Built',name)
transport=name.replace('curl_godot','pebble_iroh')
shutil.copy2(ROOT/'target'/('release' if a.release else 'debug')/transport,ROOT/'native/bin'/transport)
print('Built',transport)
