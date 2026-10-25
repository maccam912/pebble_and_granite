#!/usr/bin/env python3
"""Install and verify one explicitly selected Android device/emulator package."""
import argparse,json,pathlib,subprocess,time,uuid
ROOT=pathlib.Path(__file__).resolve().parents[1]
PACKAGE='dev.maccam912.pebblegranite'
p=argparse.ArgumentParser();p.add_argument('apk',type=pathlib.Path);p.add_argument('--serial',required=True);p.add_argument('--adb',default=str(pathlib.Path.home()/'Library/Android/sdk/platform-tools/adb'));a=p.parse_args()
def adb(*args,check=True):
    return subprocess.run([a.adb,'-s',a.serial,*args],capture_output=True,check=check,timeout=120)
adb('install','-r','-t',str(a.apk.resolve()))
activity=adb('shell','cmd','package','resolve-activity','--brief',PACKAGE).stdout.decode().strip().splitlines()[-1]
if not activity.startswith(PACKAGE+'/'):raise RuntimeError('APK did not resolve the expected application')
nonce=uuid.uuid4().hex
adb('shell','am','force-stop',PACKAGE)
adb('shell','am','start','-W','-n',activity,'--esa','command_line_params','--,--self-test,--probe-id='+nonce)
deadline=time.monotonic()+90
report=None
while time.monotonic()<deadline:
    raw=adb('exec-out','run-as',PACKAGE,'cat','files/diagnostics/self-test.json',check=False)
    try:
        candidate=json.loads(raw.stdout)
        if candidate.get('nonce')==nonce:report=candidate;break
    except (ValueError,UnicodeDecodeError):pass
    time.sleep(1)
if not report:raise RuntimeError('No fresh Android self-test result')
if not report.get('ok') or report.get('trace')!=(ROOT/'validation/golden.txt').read_text():raise RuntimeError('Android trace mismatch: '+str(report))
evidence=ROOT/'build/evidence';evidence.mkdir(parents=True,exist_ok=True)
(evidence/'android-self-test.json').write_text(json.dumps(report,indent=2)+'\n')
print('ANDROID_RUNTIME_OK',a.serial)
