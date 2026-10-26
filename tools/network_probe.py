#!/usr/bin/env python3
"""Verify a full Iroh match/reconnect path across desktop and an installed APK.

Use --desktop for a local process-boundary rehearsal of the same client probe.
This deliberately uses a direct endpoint; room-code discovery is tested separately.
"""
import argparse, hashlib, json, pathlib, subprocess, time, uuid
from godot import executable
ROOT = pathlib.Path(__file__).resolve().parents[1]
PACKAGE = 'dev.maccam912.pebblegranite'
p = argparse.ArgumentParser()
p.add_argument('--apk', type=pathlib.Path)
p.add_argument('--serial')
p.add_argument('--desktop', action='store_true')
p.add_argument('--relay-only', action='store_true')
p.add_argument('--adb', default=str(pathlib.Path.home() / 'Library/Android/sdk/platform-tools/adb'))
a = p.parse_args()
if not a.desktop and (not a.apk or not a.serial): p.error('Android requires --apk and --serial')
if a.desktop and (a.apk or a.serial): p.error('--desktop does not install an APK')
nonce = uuid.uuid4().hex
directory = ROOT / 'build/probes' / nonce
directory.mkdir(parents=True)
def adb(*args, check=True, input=None):
    return subprocess.run([a.adb, '-s', a.serial, *args], capture_output=True,
                          check=check, timeout=120, input=input)
def read_json(path):
    try: return json.loads(path.read_text())
    except (OSError, ValueError): return None
activity = None
if not a.desktop:
    adb('install', '-r', '-t', '-d', str(a.apk.resolve()))
    activity = adb('shell', 'cmd', 'package', 'resolve-activity', '--brief', PACKAGE).stdout.decode().strip().splitlines()[-1]
    if not activity.startswith(PACKAGE + '/'): raise RuntimeError('Unexpected application activity')
    adb('shell', 'am', 'force-stop', PACKAGE)
host_log = (directory / 'host.log').open('w')
cmd = [executable(), '--headless', '--path', str(ROOT), '--script', 'tests/cross_device_host.gd', '--', '--probe-dir=' + str(directory)]
if a.relay_only: cmd.append('--relay-only')
host = subprocess.Popen(cmd, cwd=ROOT, stdout=host_log, stderr=subprocess.STDOUT)
client = None
request_path = 'files/diagnostics/self-test-request.json'
report = None
try:
    deadline = time.monotonic() + 60
    endpoint = None
    while time.monotonic() < deadline:
        endpoint = read_json(directory / 'endpoint.json')
        if endpoint: break
        if host.poll() is not None: raise RuntimeError('Host failed; see ' + str(directory / 'host.log'))
        time.sleep(.1)
    if not endpoint: raise RuntimeError('Host did not become ready; see ' + str(directory))
    request = {'schema': 2, 'nonce': nonce, 'endpoint': endpoint['endpoint'], 'relay_only': a.relay_only}
    payload = json.dumps(request).encode()
    assert len(payload) <= 256
    if a.desktop:
        (directory / 'request.json').write_bytes(payload)
        client_log = (directory / 'client.log').open('w')
        client = subprocess.Popen([executable(), '--headless', '--path', str(ROOT), '--script', 'tests/cross_device_client.gd', '--', '--request=' + str(directory / 'request.json')], cwd=ROOT, stdout=client_log, stderr=subprocess.STDOUT)
    else:
        adb('exec-out', 'run-as', PACKAGE, 'mkdir', '-p', 'files/diagnostics')
        adb('exec-in', 'run-as', PACKAGE, 'dd', 'of=' + request_path, 'bs=1', 'count=' + str(len(payload)), input=payload)
        adb('shell', 'am', 'start', '-W', '-n', activity)
    deadline = time.monotonic() + 200
    while time.monotonic() < deadline:
        if a.desktop:
            text = (directory / 'client.log').read_text()
            for line in text.splitlines():
                if line.startswith('NETWORK_PROBE_RESULT '): report = json.loads(line.removeprefix('NETWORK_PROBE_RESULT '))
            if client.poll() is not None and not report: raise RuntimeError('Client failed; see ' + str(directory))
        else:
            raw = adb('exec-out', 'run-as', PACKAGE, 'cat', 'files/diagnostics/network-test.json', check=False)
            try:
                candidate = json.loads(raw.stdout)
                if candidate.get('nonce') == nonce: report = candidate
            except (ValueError, UnicodeDecodeError): pass
        if report: break
        if host.poll() is not None and not (read_json(directory / 'host.json') or {}).get('ok'):
            raise RuntimeError('Host failed; see ' + str(directory))
        time.sleep(.25)
    if not report: raise RuntimeError('No fresh client result; see ' + str(directory))
    if not report.get('ok'):
        (directory / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
        raise RuntimeError('Client probe failed: ' + str(report))
    host.wait(timeout=15)
    authoritative = read_json(directory / 'host.json')
    report['host'] = authoritative
    if not a.desktop: report['apk_sha256'] = hashlib.sha256(a.apk.read_bytes()).hexdigest()
    (directory / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
    if not report.get('ok') or not authoritative or not authoritative.get('ok') or not authoritative.get('released_from_held') or not authoritative.get('reconnected_held') or not report.get('reconnected_held') or report['hash'] != authoritative['hash']:
        raise RuntimeError('Cross-device verification failed: ' + str(report))
    print('NETWORK_PROBE_OK', 'desktop' if a.desktop else a.serial, directory / 'result.json')
finally:
    if client:
        if client.poll() is None: client.terminate()
        client.wait(timeout=10)
        client_log.close()
    if host.poll() is None: host.terminate()
    host.wait(timeout=10)
    host_log.close()
    if not a.desktop:
        adb('shell', 'am', 'force-stop', PACKAGE, check=False)
        adb('exec-out', 'run-as', PACKAGE, 'rm', '-f', request_path, 'files/network/probe-' + nonce + '.key', check=False)
