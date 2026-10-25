#!/usr/bin/env python3
"""Install and verify one explicitly selected Android device/emulator package."""
import argparse,hashlib,json,pathlib,subprocess,time,uuid
ROOT=pathlib.Path(__file__).resolve().parents[1]
PACKAGE='dev.maccam912.pebblegranite'
p=argparse.ArgumentParser();p.add_argument('apk',type=pathlib.Path);p.add_argument('--serial',required=True);p.add_argument('--adb',default=str(pathlib.Path.home()/'Library/Android/sdk/platform-tools/adb'));a=p.parse_args()
def adb(*args,check=True,input=None):
    return subprocess.run([a.adb,'-s',a.serial,*args],capture_output=True,check=check,timeout=120,input=input)
adb('install','-r','-t',str(a.apk.resolve()))
activity=adb('shell','cmd','package','resolve-activity','--brief',PACKAGE).stdout.decode().strip().splitlines()[-1]
if not activity.startswith(PACKAGE+'/'):raise RuntimeError('APK did not resolve the expected application')
nonce=uuid.uuid4().hex
request='files/diagnostics/self-test-request.json'
adb('shell','am','force-stop',PACKAGE)
# 4.7's exported launcher drops command-line extras, while its game activity is
# intentionally unexported. A development-build request lives in this app's own
# sandbox, consumed once at startup. Do not weaken the Android manifest.
adb('exec-out','run-as',PACKAGE,'mkdir','-p','files/diagnostics')
payload=json.dumps({'schema':1,'nonce':nonce}).encode()
# exec-in forwards stdin; exec-out only reads output. Bounded dd also avoids
# relying on a remote EOF to finish the request.
adb('exec-in','run-as',PACKAGE,'dd','of='+request,'bs=1','count='+str(len(payload)),input=payload)
report=None
try:
    adb('shell','am','start','-W','-n',activity)
    deadline=time.monotonic()+90
    while time.monotonic()<deadline:
        raw=adb('exec-out','run-as',PACKAGE,'cat','files/diagnostics/self-test.json',check=False)
        try:
            candidate=json.loads(raw.stdout)
            if candidate.get('nonce')==nonce:report=candidate;break
        except (ValueError,UnicodeDecodeError):pass
        time.sleep(1)
finally:
    adb('exec-out','run-as',PACKAGE,'rm','-f',request,check=False)
if not report:raise RuntimeError('No fresh Android self-test result')
if not report.get('ok') or report.get('trace')!=(ROOT/'validation/golden.txt').read_text():raise RuntimeError('Android trace mismatch: '+str(report))
report['apk_sha256']=hashlib.sha256(a.apk.read_bytes()).hexdigest()
evidence=ROOT/'build/evidence';evidence.mkdir(parents=True,exist_ok=True)
(evidence/'android-self-test.json').write_text(json.dumps(report,indent=2)+'\n')
print('ANDROID_RUNTIME_OK',a.serial)
