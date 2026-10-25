#!/usr/bin/env python3
"""Build one native bridge and export its matching platform package."""
import argparse,hashlib,json,os,pathlib,platform,shutil,subprocess,sys,zipfile
from godot import executable,templates
from verify_export import verify
from android_services import build as build_android_services, verify_package as verify_android_services
ROOT=pathlib.Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('platform',choices=['linux','windows','macos','android']);p.add_argument('--number',default='1');a=p.parse_args()
if not a.number.isdigit() or int(a.number)<1: p.error('number must be positive')
def run(args,env=None):subprocess.run(args,cwd=ROOT,check=True,env=env)
libdir=ROOT/'native/bin';libdir.mkdir(exist_ok=True,parents=True)
if a.platform=='android':
    # The host editor must load the extension while importing Android resources.
    run([sys.executable,'tools/build_native.py','--release'])
    sdk=pathlib.Path(os.environ.get('ANDROID_HOME',os.environ.get('ANDROID_SDK_ROOT',str(pathlib.Path.home()/'Library/Android/sdk'))))
    ndk=sdk/'ndk/28.1.13356709/toolchains/llvm/prebuilt'/('darwin-x86_64' if platform.system()=='Darwin' else 'linux-x86_64')/'bin'
    target='aarch64-linux-android';run(['rustup','target','add',target])
    env=os.environ.copy();env['CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER']=str(ndk/'aarch64-linux-android29-clang');env['CC_aarch64_linux_android']=env['CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER'];env['AR_aarch64_linux_android']=str(ndk/'llvm-ar')
    run(['cargo','build','--locked','--release','-p','curl-godot','-p','curl-transport','--target',target],env)
    for name in ['curl_godot','pebble_iroh']:
        shutil.copy2(ROOT/'target'/target/('release/lib'+name+'.so'),libdir/('lib'+name+'.android.so'))
elif a.platform=='macos':
    targets=['aarch64-apple-darwin','x86_64-apple-darwin']
    for target in targets:
        run(['rustup','target','add',target]);run(['cargo','build','--locked','--release','-p','curl-godot','-p','curl-transport','--target',target])
    for name in ['curl_godot','pebble_iroh']:
        paths=[str(ROOT/'target'/target/('release/lib'+name+'.dylib')) for target in targets]
        run(['lipo','-create',*paths,'-output',str(libdir/('lib'+name+'.dylib'))])
else:run([sys.executable,'tools/build_native.py','--release'])
template_dir=templates();godot=executable()
if a.platform=='android':
    build_android_services()
# Set export-only version metadata in a temporary modified preset, restoring it.
presets=ROOT/'export_presets.cfg';original=presets.read_text()
settings=None;original_settings=None
if a.platform=='android':
    if platform.system()=='Darwin': settings=pathlib.Path.home()/'Library/Application Support/Godot/editor_settings-4.7.tres'
    elif platform.system()=='Windows': settings=pathlib.Path(os.environ['APPDATA'])/'Godot/editor_settings-4.7.tres'
    else: settings=pathlib.Path.home()/'.config/godot/editor_settings-4.7.tres'
    original_settings=settings.read_bytes() if settings.exists() else None
    key=pathlib.Path.home()/'.local/share/pebble-and-granite/signing/development.keystore'
    if not key.exists():key=pathlib.Path.home()/'.android/debug.keystore'
    jdk=os.environ.get('JAVA_HOME','/opt/homebrew/opt/openjdk@17')
    values={'export/android/android_sdk_path':str(sdk),'export/android/java_sdk_path':jdk,'export/android/debug_keystore':str(key),'export/android/debug_keystore_user':'androiddebugkey','export/android/debug_keystore_pass':'android'}
    settings.parent.mkdir(parents=True,exist_ok=True)
    settings.write_text('[gd_resource type="EditorSettings" format=3]\n\n[resource]\n'+''.join(k+' = '+json.dumps(v)+'\n' for k,v in values.items()))
try:
    presets.write_text(original.replace('version/code=1','version/code='+a.number).replace('version/name="0.0.1-dev"','version/name="0.0.'+a.number+'-dev"'))
    out=ROOT/'build'/a.platform;out.mkdir(parents=True,exist_ok=True)
    filename={'linux':'pebble-and-granite.x86_64','windows':'pebble-and-granite.exe','macos':'pebble-and-granite.zip','android':'pebble-and-granite.apk'}[a.platform]
    preset={'linux':'Linux','windows':'Windows','macos':'macOS','android':'Android'}[a.platform]
    run([godot,'--headless','--path',str(ROOT),'--editor','--import','--frame-delay','1000'])
    run([godot,'--headless','--path',str(ROOT),*(['--install-android-build-template'] if a.platform=='android' else []),'--export-debug',preset,str(out/filename)])
    if a.platform=='android':verify_android_services(out/filename)
    if a.platform!='android':verify(a.platform,out/filename)
    downloads=ROOT/'build/download';downloads.mkdir(exist_ok=True)
    name='pebble-and-granite-'+a.number+'-'+a.platform
    if a.platform in ['android','macos']:
        result=downloads/(name+('.apk' if a.platform=='android' else '.zip'));shutil.copy2(out/filename,result)
    else:
        result=downloads/(name+'.zip')
        with zipfile.ZipFile(result,'w',zipfile.ZIP_DEFLATED) as z:
            for f in out.rglob('*'):
                if f.is_file():z.write(f,f.relative_to(out))
    digest=hashlib.sha256(result.read_bytes()).hexdigest()
    (downloads/(name+'.sha256')).write_text(digest+'  '+result.name+'\n')
    revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    (downloads/(name+'.json')).write_text(json.dumps({'commit':revision,'platform':a.platform,'build':a.number,'sha256':digest,'godot':'4.7-stable',**json.loads((ROOT/'compatibility.json').read_text()),'status':'development feel lab'},indent=2)+'\n')
finally:
    presets.write_text(original)
    if settings:
        if original_settings is None:settings.unlink(missing_ok=True)
        else:settings.write_bytes(original_settings)
