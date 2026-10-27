#!/usr/bin/env python3
"""Drive installed solo menus/calls with adb taps on the dedicated test emulator.

The one-use development observer exports actual control geometry and state while
normal save/preference persistence is disabled. It never injects game commands.
"""
import argparse
import hashlib
import json
import pathlib
import subprocess
import time
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[1]
PACKAGE = 'dev.maccam912.pebblegranite'
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('apk', type=pathlib.Path)
p.add_argument('--serial', required=True)
p.add_argument('--adb', default=str(pathlib.Path.home() / 'Library/Android/sdk/platform-tools/adb'))
p.add_argument('--drills', action='store_true', help='Exercise takeout and timing drills using actual touch deliveries')
a = p.parse_args()
nonce = uuid.uuid4().hex
out = ROOT / 'build/probes' / (('drills-ui-' if a.drills else 'solo-ui-') + nonce)
out.mkdir(parents=True)
events = []
last_state = {}
print('SOLO_UI_EVIDENCE ' + str(out), flush=True)


def adb(*args, check=True, input=None):
    return subprocess.run([a.adb, '-s', a.serial, *map(str, args)], input=input,
                          capture_output=True, check=check, timeout=120).stdout


def read_file(path):
    return adb('exec-out', 'run-as', PACKAGE, 'cat', 'files/' + path, check=False)


def read_state():
    global last_state
    try:
        state = json.loads(read_file('diagnostics/ui-state-' + nonce + '.json'))
        if state.get('nonce') == nonce:
            last_state = state
            return state
    except (ValueError, UnicodeDecodeError):
        pass
    return None


def wait_for(predicate, description, timeout=90):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        state = read_state()
        if state and state.get('expired'):
            raise RuntimeError('Installed observer expired during ' + description)
        if state and predicate(state):
            (out / 'last-state.json').write_text(json.dumps(state, indent=2) + '\n')
            print('SOLO_UI ' + description, flush=True)
            return state
        time.sleep(.2)
    raise RuntimeError('Timed out: ' + description + '\n' + json.dumps(last_state))


def capture(name):
    # State is written before the next draw; let the renderer present it too.
    time.sleep(.5)
    data = adb('exec-out', 'screencap', '-p')
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise RuntimeError('Expected an Android screenshot')
    (out / (name + '.png')).write_bytes(data)


def tap(name):
    state = wait_for(lambda s: bool(s['controls'].get(name))
                     and not s['controls'][name].get('disabled', False), name + ' available')
    point = state['controls'][name]
    adb('shell', 'input', 'tap', point['x'], point['y'])
    events.append({'tap': name, 'x': point['x'], 'y': point['y'], 'time': time.monotonic()})
    time.sleep(.3)


def choose(name, desired):
    tap(name)
    # Touch-opened Android PopupMenu has no keyboard-focused row. Its first
    # Down selects row zero; subsequent Downs reach the desired row.
    for _ in range(desired + 1):
        adb('shell', 'input', 'keyevent', 'KEYCODE_DPAD_DOWN')
        time.sleep(.08)
    adb('shell', 'input', 'keyevent', 'KEYCODE_ENTER')
    time.sleep(.4)


def saves():
    names = ['practice-session.json', 'match-session.json', 'solo-teams.json',
             'target-drills.json', 'play-settings.cfg']
    names += ['ice-notes-' + mode + '.json' for mode in ['practice', 'mixed', 'solo', 'drills']]
    return {name + suffix: hashlib.sha256(read_file(name + suffix)).hexdigest()
            for name in names for suffix in ['', '.bak']}



def run_solo():
    wait_for(lambda s: s['mode'] == 'practice' and s['sequence'] > 2, 'initial scene', timeout=90)
    capture('01-initial')
    tap('settings')
    state = wait_for(lambda s: s['settings_visible'], 'settings open')
    choose('role', 5)
    state = wait_for(lambda s: s['human_position'] == 5, 'calling-only selected', timeout=12)
    choose('difficulty', 2)
    state = wait_for(lambda s: s['difficulty'] == 2, 'elite selected', timeout=12)
    if not state['fast']:
        tap('fast')
    wait_for(lambda s: s['fast'], 'fast watching enabled')
    capture('02-settings')
    tap('done')
    wait_for(lambda s: not s['settings_visible'], 'settings closed')
    tap('solo')
    wait_for(lambda s: s['mode'] == 'solo' and s['planned'] and s['team'] == 0,
             'Gold AI call ready', timeout=90)
    # The empty-board suggestion is a draw; choose a guard through the real menu.
    choose('shot_kind', 1)
    wait_for(lambda s: s['planned'] and s['kind'] == 'Guard', 'guard solved')
    tap('zoom')
    wait_for(lambda s: s['zoomed'] and s['camera'] == 'House' and s['camera_size'] < 3, 'guard zoom')
    capture('03-called-guard-zoom')
    tap('zoom')
    before = wait_for(lambda s: s['planned'] and not s['target_visible'], 'direction-only skip view')
    tap('out_turn')
    changed = wait_for(lambda s: s['turn'] == -1 and not s['planning'], 'out-turn selected')
    if changed['broom_mm'] != before['broom_mm']:
        raise RuntimeError('Turn choice moved the broom')
    start = changed['broom']
    # Actual drag, in device pixels, then verify the authoritative line selection.
    touch('DOWN', start['x'], start['y'])
    time.sleep(.1)
    touch('MOVE', start['x'] + 45, start['y'])
    time.sleep(.1)
    touch('UP', start['x'] + 45, start['y'])
    moved = wait_for(lambda s: abs(s['broom_mm'] - changed['broom_mm']) > 100, 'skip broom dragged')
    if moved['target_visible'] or moved['camera'] != 'House':
        raise RuntimeError('Dragging broom revealed a target or left the house view')
    capture('03b-manual-broom-turn')
    tap('send')
    wait_for(lambda s: s['run_active'] and s['team'] == 0, 'AI Gold delivery')
    tap('hard')
    wait_for(lambda s: s['call_override'] == 255, 'HARD obeyed')
    capture('04-hard-call')
    tap('off')
    wait_for(lambda s: s['call_override'] == 0, 'OFF obeyed')
    capture('05-off-call')
    tap('settings')
    wait_for(lambda s: s['settings_visible'], 'motion settings open')
    tap('steady')
    wait_for(lambda s: s['steady_camera'] and s['camera'] == 'House', 'steady overhead enabled')
    tap('done')
    capture('05b-steady-overhead')
    wait_for(lambda s: s['delivered_count'] >= 1 and s['review_count'] >= 1, 'first shot settled', timeout=120)
    tap('ice_board')
    paused = wait_for(lambda s: s['board_visible'], 'ice board open')
    pause_hash = paused['hash']
    time.sleep(1.3)
    check_pause = wait_for(lambda s: s['board_visible'], 'board remains open')
    if not check_pause['board_visible'] or check_pause['hash'] != pause_hash:
        raise RuntimeError('Ice board did not pause the installed game')
    capture('06-ice-board')
    tap('board_close')
    wait_for(lambda s: not s['board_visible'], 'ice board closed')
    wait_for(lambda s: s['team'] == 1 and s['run_active'] and s['fast_active'],
             'opponent fast travel', timeout=120)
    capture('07-opponent-fast')
    final = wait_for(lambda s: s['delivered_count'] == 2 and s['team'] == 0 and s['planned'],
                     'second Gold approval', timeout=120)
    if final['review_count'] != 2 or final['human_position'] != 5 or final['difficulty'] != 2:
        raise RuntimeError('Installed solo state lost role/accuracy/observations')
    capture('08-second-gold-call')
    raw = read_file('diagnostics/ui-match-' + nonce + '.json')
    journal = json.loads(raw)
    if format(journal['hash'], '016x') != final['journal_hash']:
        raise RuntimeError('Installed journal does not match the observer snapshot')
    journal_path = out / 'match-session.json'
    journal_path.write_bytes(raw)
    verified = subprocess.run(['cargo', 'run', '--locked', '--release', '-p', 'curl-server', '--',
                               'verify-match', str(journal_path)], cwd=ROOT, capture_output=True, text=True, check=True)
    (out / 'verify-match.txt').write_text(verified.stdout)
    if saves() != before_saves:
        raise RuntimeError('Installed UI probe modified normal player saves/preferences')
    result = {'ok': True, 'serial': a.serial, 'nonce': nonce,
              'apk_sha256': hashlib.sha256(a.apk.read_bytes()).hexdigest(), 'final_state': final,
              'events': events, 'normal_saves_unchanged': True,
              'audio_boundary': 'Device voice availability only; no-audio emulator, no audible approval.'}
    (out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print('ANDROID_SOLO_UI_OK ' + str(out), flush=True)

def touch(kind, x, y):
    adb('shell', 'input', 'touchscreen', 'motionevent', kind, x, y)
    events.append({'touch': kind, 'x': x, 'y': y, 'time': time.monotonic()})


def throw_from_handle():
    state = read_state()
    x, y = state['handle']['x'], state['handle']['y']
    # Relative stroke on the observed live handle. A longer push and earlier
    # lift make it robust to adb command latency without missing the hog lines.
    # Use one forward event: a small initial nudge would consume the 120 ms
    # drive window while a later adb command is still starting.
    touch('DOWN', x, y)
    try:
        time.sleep(.08)
        touch('MOVE', x, y + 36)
        time.sleep(.06)
        touch('MOVE', x, y - 90)
        time.sleep(.35)
        touch('MOVE', x, y - 90)
        touch('MOVE', x + 48, y - 99)
        time.sleep(.04)
        touch('MOVE', x + 96, y - 108)
        touch('UP', x + 96, y - 108)
    finally:
        adb('shell', 'input', 'touchscreen', 'motionevent', 'CANCEL', x, y, check=False)


def verify_drill(name, state):
    raw = read_file('diagnostics/ui-session-' + nonce + '.json')
    journal = out / (name + '-session.json')
    journal.write_bytes(raw)
    verified = subprocess.run(['cargo', 'run', '--locked', '--release', '-p', 'curl-server', '--',
                               'verify-session', str(journal)], cwd=ROOT, capture_output=True, text=True, check=True)
    (out / (name + '-verify.txt')).write_text(verified.stdout)
    result = json.loads(verified.stdout)
    if result['hash'] != state['journal_hash']:
        raise RuntimeError('Installed drill journal does not match the replayed state')


def run_drills():
    wait_for(lambda s: s['mode'] == 'practice' and s['sequence'] > 2, 'initial scene')
    # This relative touch fixture has only been reviewed at the dedicated resolution.
    import struct
    data = adb('exec-out', 'screencap', '-p')
    if struct.unpack('>II', data[16:24]) != (2400, 1080):
        raise RuntimeError('Drill stroke requires the reviewed 2400x1080 landscape layout')
    tap('drills')
    wait_for(lambda s: s['mode'] == 'drills', 'drills entered')
    choose('drill_kind', 4)
    ready = wait_for(lambda s: s['drill_kind'] == 4 and s['delivered'] == 0 and not s['drill_results'], 'takeout target ready')
    capture('01-takeout-target')
    if ready['phase'] != 'Ready':
        raise RuntimeError('Takeout setup was counted as a player attempt')
    throw_from_handle()
    takeout = wait_for(lambda s: s['drill_kind'] == 4 and len(s['drill_results']) == 1 and not s['run_active'] and s['hash'] == s['journal_hash'], 'takeout graded', timeout=90)
    capture('02-takeout-grade')
    verify_drill('takeout', takeout)
    tap('next')
    wait_for(lambda s: s['drill_attempt'] == 1 and s['delivered'] == 0 and len(s['drill_results']) == 1, 'next takeout target')
    choose('drill_kind', 5)
    wait_for(lambda s: s['drill_kind'] == 5 and s['drill_attempt'] == 0 and s['drill_goal_ms'] == 14000, 'timing goal ready')
    capture('03-timing-goal')
    for attempt in range(3):
        throw_from_handle()
        timing = wait_for(lambda s: s['drill_kind'] == 5 and len(s['drill_results']) == 1 and not s['run_active'] and s['hash'] == s['journal_hash'], 'timing graded', timeout=90)
        (out / ('timing-attempt-' + str(attempt) + '-session.json')).write_bytes(read_file('diagnostics/ui-session-' + nonce + '.json'))
        if 'split_ms' in timing['drill_results'][0]:
            break
        if attempt == 2:
            raise RuntimeError('Three actual strokes failed to reach both hog lines')
        tap('restart')
        wait_for(lambda s: s['restart_visible'], 'restart confirmation')
        tap('restart_confirm')
        wait_for(lambda s: not s['drill_results'] and s['delivered'] == -1, 'timing round restarted')
    capture('04-timing-grade')
    if 's slower' not in timing['report'] and 's faster' not in timing['report'] and 'on target' not in timing['report']:
        raise RuntimeError('Measured timing lacked signed feedback')
    verify_drill('timing', timing)
    tap('next')
    final = wait_for(lambda s: s['drill_attempt'] == 1 and s['drill_goal_ms'] == 15000, 'next timing goal')
    if saves() != before_saves:
        raise RuntimeError('Drill probe modified normal player saves/preferences')
    result = {'ok': True, 'serial': a.serial, 'nonce': nonce,
              'apk_sha256': hashlib.sha256(a.apk.read_bytes()).hexdigest(), 'takeout': takeout,
              'timing': timing, 'final_state': final, 'events': events, 'normal_saves_unchanged': True}
    (out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print('ANDROID_DRILLS_UI_OK ' + str(out), flush=True)


if adb('shell', 'getprop', 'ro.boot.qemu.avd_name').decode().strip() != 'pebble_granite_lab':
    raise RuntimeError('This fixture requires the dedicated pebble_granite_lab emulator')
adb('install', '-r', '-t', str(a.apk.resolve()))
adb('shell', 'am', 'force-stop', PACKAGE)
before_saves = saves()
request = 'files/diagnostics/self-test-request.json'
adb('exec-out', 'run-as', PACKAGE, 'mkdir', '-p', 'files/diagnostics')
payload = json.dumps({'schema': 3, 'nonce': nonce}).encode()
adb('exec-in', 'run-as', PACKAGE, 'dd', 'of=' + request, 'bs=1', 'count=' + str(len(payload)), input=payload)
activity = adb('shell', 'cmd', 'package', 'resolve-activity', '--brief', PACKAGE).decode().strip().splitlines()[-1]
if not activity.startswith(PACKAGE + '/'):
    raise RuntimeError('APK did not resolve the expected application')
try:
    adb('shell', 'am', 'start', '-W', '-n', activity)
    if a.drills:
        run_drills()
    else:
        run_solo()
except Exception:
    capture('failure')
    (out / 'last-state.json').write_text(json.dumps(last_state, indent=2) + '\n')
    raise
finally:
    adb('shell', 'am', 'force-stop', PACKAGE, check=False)
    adb('exec-out', 'run-as', PACKAGE, 'rm', '-f', request,
        'files/diagnostics/ui-state-' + nonce + '.json',
        'files/diagnostics/ui-state-' + nonce + '.json.tmp',
        'files/diagnostics/ui-match-' + nonce + '.json',
        'files/diagnostics/ui-match-' + nonce + '.json.tmp',
        'files/diagnostics/ui-session-' + nonce + '.json',
        'files/diagnostics/ui-session-' + nonce + '.json.tmp', check=False)
