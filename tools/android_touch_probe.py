#!/usr/bin/env python3
"""Exercise direct-ice gestures on an explicitly selected 2400x1080 test emulator.

This uses Fresh ice between cases. Existing practice files are copied to the
local evidence directory first. It does not erase app storage or network identity.
"""
import argparse
import atexit
import hashlib
import json
import pathlib
import struct
import subprocess
import time
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[1]
PACKAGE = 'dev.maccam912.pebblegranite'
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('apk', type=pathlib.Path)
p.add_argument('--serial', required=True)
p.add_argument('--adb', default=str(pathlib.Path.home() / 'Library/Android/sdk/platform-tools/adb'))
a = p.parse_args()
out = ROOT / 'build/probes' / ('touch-' + uuid.uuid4().hex)
out.mkdir(parents=True)
events = []
contact = None


def adb(*args, check=True):
    return subprocess.run([a.adb, '-s', a.serial, *args], capture_output=True,
                          check=check, timeout=120).stdout


def capture(name):
    data = adb('exec-out', 'screencap', '-p')
    if data[:8] != b'\x89PNG\r\n\x1a\n' or struct.unpack('>II', data[16:24]) != (2400, 1080):
        raise RuntimeError('This observed input layout requires a 2400x1080 landscape test emulator')
    (out / (name + '.png')).write_bytes(data)


def event(kind, x, y):
    global contact
    if kind not in ['UP', 'CANCEL']:
        contact = (x, y)
    events.append({'time': time.monotonic(), 'kind': kind, 'x': x, 'y': y})
    adb('shell', 'input', 'touchscreen', 'motionevent', kind, str(x), str(y))
    if kind in ['UP', 'CANCEL']:
        contact = None


def release_contact():
    if contact is not None:
        try:
            adb('shell', 'input', 'touchscreen', 'motionevent', 'CANCEL',
                str(contact[0]), str(contact[1]), check=False)
        except (OSError, subprocess.SubprocessError):
            pass


atexit.register(release_contact)


def fresh():
    # 1280x800 game fitted to 2400x1080: x offset 336, scale 1.35.
    adb('shell', 'input', 'tap', '1688', '1012')
    time.sleep(.4)


def drive():
    event('DOWN', 1200, 715)
    time.sleep(.08)
    event('MOVE', 1200, 751)
    time.sleep(.06)
    event('MOVE', 1200, 741)
    time.sleep(.14)
    event('MOVE', 1200, 697)


def journal(name):
    raw = adb('exec-out', 'run-as', PACKAGE, 'cat', 'files/practice-session.json')
    (out / (name + '-session.json')).write_bytes(raw)
    return json.loads(raw)


adb('install', '-r', '-t', str(a.apk.resolve()))
for name in ['practice-session.json', 'practice-session.json.bak']:
    raw = adb('exec-out', 'run-as', PACKAGE, 'cat', 'files/' + name, check=False)
    if raw:
        (out / ('before-' + name)).write_bytes(raw)
adb('shell', 'am', 'force-stop', PACKAGE)
activity = adb('shell', 'cmd', 'package', 'resolve-activity', '--brief', PACKAGE).decode().strip().splitlines()[-1]
if not activity.startswith(PACKAGE + '/'):
    raise RuntimeError('Unexpected launcher')
adb('shell', 'am', 'start', '-W', '-n', activity)
time.sleep(5)
capture('ready')
results = {}
for direction, label in [(1, 'right'), (-1, 'left')]:
    fresh()
    drive()
    time.sleep(.8)
    capture(label + '-held')
    # Actual moving contacts precede UP. Merely changing UP coordinates does not
    # exercise Android's moving-touch path consistently across input providers.
    event('MOVE', 1200, 697)
    event('MOVE', 1200 + direction * 48, 688)
    time.sleep(.04)
    event('MOVE', 1200 + direction * 96, 679)
    event('UP', 1200 + direction * 96, 679)
    time.sleep(1.2)
    capture(label + '-released')
    shots = [r for r in journal(label)['records'] if r['kind'] == 'Shot']
    if len(shots) != 1:
        raise RuntimeError('Expected exactly one touch delivery: ' + label)
    release = shots[0]['data']['release']
    if release['spin'] * direction <= 0 or release['pos']['y'] / 4294967296 >= -28.593:
        raise RuntimeError('Incorrect touch release: ' + str(release))
    results[label] = release
fresh()
drive()
time.sleep(1.6)
capture('before-pause')
# Background with the contact still held. Android cancels the contact as focus
# leaves; the game must save the held plan instead of submitting a release.
adb('shell', 'input', 'keyevent', 'KEYCODE_HOME')
contact = None
time.sleep(.5)
frozen = journal('paused')
if not frozen.get('pending_delivery') or any(r['kind'] in ['Shot', 'HogViolation'] for r in frozen['records']):
    raise RuntimeError('Background did not preserve the held delivery')
time.sleep(1)
adb('shell', 'am', 'start', '-W', '-n', activity)
time.sleep(3)
capture('resumed-held')
if journal('resumed-before-regrip') != frozen:
    raise RuntimeError('Resuming advanced the slide before regrip')
event('DOWN', 1200, 715)
time.sleep(.12)
event('MOVE', 1200, 715)
event('MOVE', 1152, 706)
time.sleep(.04)
event('MOVE', 1104, 697)
event('UP', 1104, 697)
time.sleep(1.2)
capture('resumed-released')
resumed = journal('resumed-finish')
shots = [r for r in resumed['records'] if r['kind'] == 'Shot']
if resumed.get('pending_delivery') or len(shots) != 1 or shots[0]['data']['release']['spin'] >= 0:
    raise RuntimeError('Regrip did not produce one left-curl delivery')
results['pause_resume'] = {'frozen': frozen['pending_delivery'], 'release': shots[0]['data']['release']}
fresh()
drive()
time.sleep(6)
capture('hog-held')
log = journal('hog')
faults = [r for r in log['records'] if r['kind'] == 'HogViolation']
if len(faults) != 1 or any(r['kind'] == 'Shot' for r in log['records']):
    raise RuntimeError('Held stone did not become exactly one hog fault')
event('UP', 1200, 697)
time.sleep(.3)
if journal('hog-after-up') != log:
    raise RuntimeError('Lift after the fault changed the journal')
results['hog'] = faults[0]
results.update(apk_sha256=hashlib.sha256(a.apk.read_bytes()).hexdigest(), serial=a.serial,
               android_sdk=adb('shell', 'getprop', 'ro.build.version.sdk').decode().strip(),
               events=events, ok=True)
(out / 'result.json').write_text(json.dumps(results, indent=2) + '\n')
fresh()
print('ANDROID_DIRECT_TOUCH_OK', out)
