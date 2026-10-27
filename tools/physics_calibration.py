#!/usr/bin/env python3
"""Compare measured curling shots with the native deterministic model.

Run cargo build --release -p curl-server first. Baseline-only cases characterize
simulation behaviour; only explicitly measured cases can satisfy --check.
"""
import argparse
import hashlib
import json
import math
import os
import pathlib
import subprocess
import tempfile
from decimal import Decimal

ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_SERVER = ROOT / 'target/release' / ('curl-server.exe' if os.name == 'nt' else 'curl-server')
SCALE = 1 << 32
METRICS = {'downrange_mm', 'curl_mm', 'duration_ms', 'turns_milli'}


def number(value, name, low, high):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or not low <= value <= high:
        raise ValueError(f'{name} must be a finite number in [{low}, {high}]')
    return value


def fixed(value):
    return int(Decimal(str(value)) * SCALE / 1000)


def validate(case):
    if not isinstance(case, dict) or not isinstance(case.get('id'), str) or not case['id']:
        raise ValueError('Each case needs an id')
    if set(case) - {'id', 'source', 'release', 'observed', 'tolerance', 'sweep'}:
        raise ValueError('Unsupported case fields; contact/obstacle setups need a separate experiment')
    release = case.get('release', {})
    if not isinstance(release, dict) or set(release) - {'vx_mm_s', 'vy_mm_s', 'spin_milli_rps'}:
        raise ValueError('Release accepts only explicitly named mm/s and milli-revolutions/s fields')
    number(release.get('vx_mm_s', 0), 'vx_mm_s', -2000, 2000)
    number(release.get('vy_mm_s'), 'vy_mm_s', 100, 6000)
    number(release.get('spin_milli_rps'), 'spin_milli_rps', -3000, 3000)
    observed, tolerance = case.get('observed', {}), case.get('tolerance', {})
    if not isinstance(observed, dict) or not isinstance(tolerance, dict) or set(observed) - METRICS or set(tolerance) != set(observed):
        raise ValueError('Observed metrics and tolerances must have the same supported keys')
    for key in observed:
        number(observed[key], key, 0 if key in ['duration_ms', 'downrange_mm'] else -100000, 100000)
        number(tolerance[key], 'tolerance.' + key, .001, 100000)
    source = case.get('source', {})
    if not isinstance(source, dict) or source.get('kind') not in ['measured', 'synthetic', 'baseline']:
        raise ValueError('source.kind must be measured, synthetic or baseline')
    if source['kind'] == 'measured':
        if not observed or not all(isinstance(source.get(key), str) and source[key].strip() for key in ['reference', 'method', 'conditions']):
            raise ValueError('Measured cases need observations, reference, method and conditions')
    if source['kind'] == 'baseline' and observed:
        raise ValueError('Baseline cases cannot claim measured observations')
    sweep = case.get('sweep')
    if sweep is not None:
        if not isinstance(sweep, dict): raise ValueError('sweep must be an object')
        for key, lo, hi in [('start_tick', 0, 14399), ('end_tick', 1, 14400), ('effort', 1, 255)]:
            value = number(sweep.get(key), 'sweep.' + key, lo, hi)
            if int(value) != value: raise ValueError('Sweep ticks and effort must be integers')
        if sweep['end_tick'] <= sweep['start_tick']: raise ValueError('Sweep interval must be nonempty')


def make_replay(template, case):
    validate(case)
    replay = json.loads(json.dumps(template))
    release = case['release']
    replay['release']['vel'] = {'x': fixed(release.get('vx_mm_s', 0)), 'y': fixed(release['vy_mm_s'])}
    replay['release']['spin'] = fixed(release['spin_milli_rps'])
    replay['sweeps'] = []
    if sweep := case.get('sweep'):
        replay['sweeps'] = [{'tick': tick, 'inputs': [{'stone': 0, 'brush': 0, 'effort': int(sweep['effort']), 'lateral_mm': 0, 'ahead_mm': 180}]}
                            for tick in range(int(sweep['start_tick']), int(sweep['end_tick']))]
    return replay


def measure(replay, outcome):
    sim = outcome['sim']
    stone = next(s for s in sim['stones'] if s['id'] == replay['release']['stone'])
    start = replay['release']['pos']
    dx, dy = [(stone['pos'][axis] - start[axis]) * 1000 / SCALE for axis in ['x', 'y']]
    vx, vy = [replay['release']['vel'][axis] / SCALE for axis in ['x', 'y']]
    speed = math.hypot(vx, vy)
    # A boundary exit is truncated motion, not a measured stopping point. A short
    # hogged stone still completes its physical stop and can be compared.
    boundary_exit = abs(stone['pos']['x']) + fixed(142) >= fixed(2375) or stone['pos']['y'] - fixed(142) > fixed(1829)
    return {
        'downrange_mm': round((dx * vx + dy * vy) / speed, 3),
        'curl_mm': round((dx * vy - dy * vx) / speed, 3),
        'duration_ms': round(outcome['ticks'] * 1000 / 240, 3),
        'turns_milli': round(stone['turns'] * 1000 / SCALE, 3),
    }, boundary_exit


def compare(case, metrics, boundary_exit):
    errors = {key: {'observed': value, 'model': metrics[key], 'error': round(metrics[key] - value, 3),
                    'tolerance': case['tolerance'][key], 'within_tolerance': abs(metrics[key] - value) <= case['tolerance'][key]}
              for key, value in case.get('observed', {}).items()}
    kind = case['source']['kind']
    status = 'truncated' if boundary_exit else ('baseline' if kind == 'baseline' else
             ('synthetic' if kind == 'synthetic' else ('within_tolerance' if all(e['within_tolerance'] for e in errors.values()) else 'outside_tolerance')))
    return {'id': case['id'], 'source': case['source'], 'status': status, 'model': metrics, 'comparisons': errors}


def run(manifest_path, server, output_path, check=False):
    if output_path.resolve() in [manifest_path.resolve(), server.resolve()]:
        raise ValueError('Report path must not overwrite measurements or the native binary')
    raw = manifest_path.read_bytes()
    if len(raw) > 1024 * 1024: raise ValueError('Manifest exceeds 1 MiB')
    manifest = json.loads(raw)
    if not isinstance(manifest, dict): raise ValueError('Manifest must be an object')
    cases = manifest.get('cases')
    if manifest.get('schema') != 1 or not isinstance(cases, list) or not 1 <= len(cases) <= 64:
        raise ValueError('Expected schema 1 with 1–64 cases')
    for case in cases: validate(case)
    if len({c['id'] for c in cases}) != len(cases): raise ValueError('Duplicate case id')
    server = server.resolve()
    def native(*args):
        result = subprocess.run([str(server), *map(str, args)], capture_output=True, text=True, timeout=90)
        if result.returncode: raise ValueError(result.stderr.strip() or 'Native simulation failed')
        return result.stdout
    with tempfile.TemporaryDirectory(prefix='curl-calibration-') as directory:
        path = pathlib.Path(directory) / 'replay.json'
        native('example', path)
        template = json.loads(path.read_text())
        expected = json.loads((ROOT / 'compatibility.json').read_text())['model']
        if template['model'] != expected: raise ValueError('Native binary model is stale; rebuild curl-server')
        results = []
        for case in cases:
            replay = make_replay(template, case)
            path.write_text(json.dumps(replay))
            outcome = json.loads(native('replay', path))
            metrics, truncated = measure(replay, outcome)
            result = compare(case, metrics, truncated)
            result.update(trace=outcome['trace'], state=outcome['state'])
            results.append(result)
    measured = [r for r in results if r['source']['kind'] == 'measured']
    aggregate = {}
    for metric in METRICS:
        errors = [r['comparisons'][metric]['error'] for r in measured if r['status'] != 'truncated' and metric in r['comparisons']]
        if errors:
            aggregate[metric] = {'count': len(errors), 'bias': sum(errors) / len(errors), 'rmse': math.sqrt(sum(e * e for e in errors) / len(errors))}
    report = {'schema': 1, 'model': expected, 'manifest_sha256': hashlib.sha256(raw).hexdigest(),
              'binary_sha256': hashlib.sha256(server.read_bytes()).hexdigest(),
              'measured_cases': len(measured), 'aggregate': aggregate, 'cases': results,
              'calibration_status': ('no_measurements' if not measured else ('within_supplied_tolerances' if all(r['status'] == 'within_tolerance' for r in measured) else 'mismatch')),
              'boundary': 'Matching supplied observations is not broad physics validation; coefficients were not changed.'}
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(report, indent=2) + '\n')
    for result in results:
        print(result['id'], result['status'], json.dumps(result['model'], sort_keys=True))
    print('Report:', output_path)
    return (2 if not measured else (0 if report['calibration_status'] == 'within_supplied_tolerances' else 1)) if check else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=pathlib.Path)
    parser.add_argument('--server', type=pathlib.Path, default=DEFAULT_SERVER)
    parser.add_argument('--output', type=pathlib.Path, default=ROOT / 'build/physics-calibration.json')
    parser.add_argument('--check', action='store_true', help='Fail without measured cases or outside supplied tolerances')
    args = parser.parse_args()
    try:
        return run(args.manifest, args.server, args.output, args.check)
    except (ValueError, KeyError, TypeError, OSError, subprocess.TimeoutExpired) as error:
        parser.exit(2, str(error) + '\n')


if __name__ == '__main__':
    raise SystemExit(main())
