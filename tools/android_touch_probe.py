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
p.add_argument('--startup-wait', type=float, default=5,
               help='Seconds for first-install shader compilation before sending gestures')
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
    # Wait for actual settlement before touching restart. An autosave mtime can
    # also advance during travel, so it is not proof that fresh ice was applied.
    started = time.monotonic()
    saved = None
    while time.monotonic() - started < 90:
        raw = adb('exec-out', 'run-as', PACKAGE, 'cat', 'files/practice-session.json', check=False)
        try:
            saved = json.loads(raw)
        except (ValueError, UnicodeDecodeError):
            time.sleep(.2)
            continue
        shots = [r['data'] for r in saved['records'] if r['kind'] == 'Shot']
        if not saved.get('pending_delivery') and (not shots or shots[-1].get('final_hash')):
            break
        time.sleep(.2)
    else:
        raise RuntimeError('Previous delivery did not settle before Fresh ice')
    adb('shell', 'input', 'tap', '1880', '1012')
    # Restart confirmation: logical centre (778, 480), fitted at 1.35x +336.
    # A fresh, empty session skips the prompt. This fixture never clears stones
    # through the separate capacity action between these resets.
    if any(r['kind'] == 'Shot' for r in saved['records']):
        time.sleep(.4)
        adb('shell', 'input', 'tap', '1386', '648')
    while time.monotonic() - started < 100:
        raw = adb('exec-out', 'run-as', PACKAGE, 'cat', 'files/practice-session.json', check=False)
        try:
            current = json.loads(raw)
            if not current.get('pending_delivery') and not any(r['kind'] != 'Idle' for r in current['records']):
                time.sleep(.4)
                print('FRESH_ICE_READY %.2fs' % (time.monotonic() - started), flush=True)
                return
        except (ValueError, UnicodeDecodeError):
            pass
        time.sleep(.2)
    raise RuntimeError('Fresh ice did not produce an empty saved session')


# Reviewed 2400x1080 fixture: this grip lies within the current handle hit area.
# The stroke uses relative motion, with logical coordinates fitted at 1.35x +336.
def drive():
    event('DOWN', 1200, 752)
    time.sleep(.08)
    event('MOVE', 1200, 788)
    time.sleep(.06)
    event('MOVE', 1200, 778)
    time.sleep(.14)
    event('MOVE', 1200, 734)


def journal(name):
    # Autosave may be replacing the file while adb reads it. Retry only an
    # incomplete JSON read, retaining all gameplay assertions below.
    for attempt in range(10):
        raw = adb('exec-out', 'run-as', PACKAGE, 'cat', 'files/practice-session.json')
        try:
            result = json.loads(raw)
        except json.JSONDecodeError:
            if attempt == 9:
                (out / (name + '-session.json')).write_bytes(raw)
                raise
            time.sleep(.1)
            continue
        (out / (name + '-session.json')).write_bytes(raw)
        return result


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
time.sleep(a.startup_wait)
capture('ready')
results = {}
for direction, label in [(1, 'right'), (-1, 'left')]:
    fresh()
    drive()
    time.sleep(.8)
    capture(label + '-held')
    # Actual moving contacts precede UP. Merely changing UP coordinates does not
    # exercise Android's moving-touch path consistently across input providers.
    event('MOVE', 1200, 734)
    event('MOVE', 1200 + direction * 48, 725)
    time.sleep(.04)
    event('MOVE', 1200 + direction * 96, 716)
    event('UP', 1200 + direction * 96, 716)
    time.sleep(1.2)
    capture(label + '-released')
    shots = [r for r in journal(label)['records'] if r['kind'] == 'Shot']
    if len(shots) != 1:
        raise RuntimeError('Expected exactly one touch delivery: ' + label)
    release = shots[0]['data']['release']
    if release['spin'] * direction <= 0 or release['pos']['y'] / 4294967296 >= -28.593:
        raise RuntimeError('Incorrect touch release: ' + str(release))
    results[label] = release
    if label == 'right':
        # Auto Sweeper view tracks the stone. This reviewed screen point remains
        # inside the legal brush region; the accepted spans verify its bounds.
        event('DOWN', 1186, 601)
        for i in range(10):
            time.sleep(.04)
            event('MOVE', 1160 if i % 2 == 0 else 1212, 601)
        event('UP', 1212, 601)
        time.sleep(1.2)
        capture('scrub-released')
        scrubbed = [r for r in journal('scrubbed')['records'] if r['kind'] == 'Shot'][0]['data']
        spatial = [s for s in scrubbed['sweeps'] if s['input']['effort'] > 0]
        if not spatial or not any(s['input']['lateral_mm'] != 0 for s in spatial):
            raise RuntimeError('Android scrub did not record spatial heat input')
        if not all(-350 <= s['input']['lateral_mm'] <= 350 and
                   80 <= s['input']['ahead_mm'] <= 700 for s in spatial):
            raise RuntimeError('Android scrub escaped brush bounds')
        time.sleep(1.2)
        quiet = [r for r in journal('scrub-stopped')['records'] if r['kind'] == 'Shot'][0]['data']
        if quiet['sweeps'] != scrubbed['sweeps']:
            raise RuntimeError('Android scrub kept heating after lift')
        # The GUI's independent accessible route must still generate steady,
        # centered effort through real touchscreen down/up events.
        event('DOWN', 907, 1012)
        time.sleep(1.2)
        capture('hold-sweeping')
        event('UP', 907, 1012)
        time.sleep(1.2)
        held = [r for r in journal('hold-swept')['records'] if r['kind'] == 'Shot'][0]['data']
        steady = [s for s in held['sweeps'] if s['input']['effort'] == 255 and
                  s['input']['lateral_mm'] == 0 and s['input']['ahead_mm'] == 180]
        if not steady:
            raise RuntimeError('Android accessible hold did not record steady sweeping')
        results['sweeping'] = {'spatial_spans': spatial, 'hold_spans': steady,
                               'stopped_after_lift': True}
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
event('DOWN', 1200, 752)
time.sleep(.12)
event('MOVE', 1200, 752)
event('MOVE', 1152, 743)
time.sleep(.04)
event('MOVE', 1104, 734)
event('UP', 1104, 734)
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
event('UP', 1200, 734)
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
