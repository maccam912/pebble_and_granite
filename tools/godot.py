#!/usr/bin/env python3
"""Fetch hash-pinned official Godot editor/templates, or use GODOT_BIN override."""
import hashlib,json,os,pathlib,platform,subprocess,sys,urllib.request,zipfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
LOCK=json.loads((ROOT/'tools/toolchain.json').read_text())
CACHE=ROOT/'build/toolchain'
def asset(name):
    CACHE.mkdir(parents=True,exist_ok=True)
    (ROOT/'build/.gdignore').touch()
    archive=CACHE/name
    expected=LOCK['sha512'][name]
    if not archive.exists() or hashlib.sha512(archive.read_bytes()).hexdigest()!=expected:
        url='https://github.com/godotengine/godot-builds/releases/download/'+LOCK['godot']+'/'+name
        urllib.request.urlretrieve(url,archive)
    if hashlib.sha512(archive.read_bytes()).hexdigest()!=expected: raise RuntimeError('Godot download checksum mismatch')
    return archive
def executable():
    if os.environ.get('GODOT_BIN'):return os.environ['GODOT_BIN']
    suffix={'Linux':'linux.x86_64','Darwin':'macos.universal','Windows':'win64.exe'}[platform.system()]
    folder=CACHE/suffix
    name='Godot_v'+LOCK['godot']+'_'+suffix
    binary=folder/({'Darwin':'Godot.app/Contents/MacOS/Godot','Windows':name,'Linux':name}[platform.system()])
    if not binary.exists():
        with zipfile.ZipFile(asset(name+'.zip')) as z:z.extractall(folder)
        if platform.system()!='Windows':binary.chmod(0o755)
    return str(binary)
def templates():
    if platform.system()=='Darwin':base=pathlib.Path.home()/'Library/Application Support/Godot/export_templates'
    elif platform.system()=='Windows':base=pathlib.Path(os.environ['APPDATA'])/'Godot/export_templates'
    else:base=pathlib.Path.home()/'.local/share/godot/export_templates'
    dest=base/LOCK['godot'].replace('-','.')
    if not (dest/'version.txt').exists():
        with zipfile.ZipFile(asset('Godot_v'+LOCK['godot']+'_export_templates.tpz')) as z:
            for member in z.infolist():
                p=pathlib.PurePosixPath(member.filename)
                if p.parts[0]!='templates' or '..' in p.parts:raise RuntimeError('Invalid template path')
                if member.is_dir():continue
                out=dest/pathlib.Path(*p.parts[1:]);out.parent.mkdir(parents=True,exist_ok=True);out.write_bytes(z.read(member))
    return dest
if __name__=='__main__':
    args=sys.argv[1:]
    if '--install-templates' in args:templates();args.remove('--install-templates')
    if args:sys.exit(subprocess.call([executable(),*args],cwd=ROOT))
    print(executable())
