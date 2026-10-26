#!/usr/bin/env python3
"""Fetch hash-pinned official Godot editor/templates, or use GODOT_BIN override."""
import hashlib,json,os,pathlib,platform,shutil,subprocess,sys,urllib.request,zipfile
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
        partial=archive.with_suffix(archive.suffix+'.partial')
        curl=shutil.which('curl.exe' if platform.system()=='Windows' else 'curl')
        if curl:
            subprocess.run([curl,'--fail','--location','--retry','3','--connect-timeout','30','--silent','--show-error','--output',str(partial),url],check=True)
        else:
            with urllib.request.urlopen(url,timeout=60) as response, partial.open('wb') as out:
                shutil.copyfileobj(response,out,1024*1024)
        partial.replace(archive)
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
def templates(installed_android=False):
    if platform.system()=='Darwin':base=pathlib.Path.home()/'Library/Application Support/Godot/export_templates'
    elif platform.system()=='Windows':base=pathlib.Path(os.environ['APPDATA'])/'Godot/export_templates'
    else:base=pathlib.Path.home()/'.local/share/godot/export_templates'
    dest=base/LOCK['godot'].replace('-','.')
    if installed_android:
        for name in ['android_debug.apk','android_source.zip']:
            if not (dest/name).is_file(): raise RuntimeError('Missing installed Android template: '+str(dest/name))
        print('Using existing Android templates at',dest)
        return dest
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
    if args:
        limit=(600 if '--full-match' in args else 120) if "--headless" in args and "--script" in args else None
        sys.exit(subprocess.run([executable(),*args],cwd=ROOT,timeout=limit).returncode)
    print(executable())
