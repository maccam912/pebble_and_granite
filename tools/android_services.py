#!/usr/bin/env python3
"""Compile the project-owned Godot v2 Android bridge against pinned engine classes."""
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import zipfile
from godot import ROOT, templates


OUTPUT = ROOT/'addons/pebble_mobile/bin/pebble-mobile.aar'
WORK = ROOT/'build/android-services'


def digest(path):
    with Path(path).open('rb') as file:
        return hashlib.file_digest(file, 'sha256').hexdigest()


def source_archive():
    return templates()/'android_source.zip'


def archive(path, entries):
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as output:
        for name, data in sorted(entries.items()):
            info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            output.writestr(info, data)


def verify_package(path):
    """Structural export gate; OS behavior has a separate installed-APK probe."""
    with zipfile.ZipFile(path) as package:
        prefix = 'base/' if str(path).endswith('.aab') else ''
        manifest = package.read(prefix+'manifest/AndroidManifest.xml' if prefix else 'AndroidManifest.xml')
        metadata = 'org.godotengine.plugin.v2.PebbleMobile'
        if not any(metadata.encode(encoding) in manifest for encoding in ['utf-8', 'utf-16-le']):
            raise RuntimeError('Exported Android manifest lacks PebbleMobile registration')
        bytecode = [name for name in package.namelist() if name.startswith(prefix+('dex/' if prefix else 'classes')) and name.endswith('.dex')]
        marker = b'Ldev/pebblegranite/platform/PebbleMobile;'
        if not any(marker in package.read(name) for name in bytecode):
            raise RuntimeError('Exported Android DEX lacks PebbleMobile bridge')
    print('PEBBLE_MOBILE_MANIFEST_AND_DEX_VERIFIED '+Path(path).name, flush=True)


def build(source_path=None):
    WORK.mkdir(parents=True, exist_ok=True)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    sdk = Path(os.environ.get('ANDROID_HOME', str(Path.home()/'Library/Android/sdk')))
    jdk = Path(os.environ.get('JAVA_HOME', '/opt/homebrew/opt/openjdk@17'))
    javac = jdk/'bin'/('javac.exe' if os.name == 'nt' else 'javac')
    android = sdk/'platforms/android-36/android.jar'
    with zipfile.ZipFile(source_path or source_archive()) as source:
        library = source.read('libs/release/godot-lib.template_release.aar')
    library_hash = hashlib.sha256(library).hexdigest()
    files = [ROOT/'native/android/PebbleMobile.java', ROOT/'native/android/AndroidManifest.xml', Path(__file__)]
    source_hash = hashlib.sha256(b''.join(path.read_bytes() for path in files)).hexdigest()
    version = subprocess.check_output([str(javac), '-version'], text=True, stderr=subprocess.STDOUT).strip()
    metadata = {'source_hash':source_hash, 'godot_library_sha256':library_hash, 'android_api':36,
                'android_jar_sha256':digest(android), 'java_release':17, 'compiler':version}
    manifest = WORK/'manifest.json'
    if OUTPUT.exists() and manifest.exists():
        previous = json.loads(manifest.read_text())
        if all(previous.get(key) == value for key, value in metadata.items()) and previous.get('sha256') == digest(OUTPUT):
            return previous
    with zipfile.ZipFile(io.BytesIO(library)) as source:
        (WORK/'godot-classes.jar').write_bytes(source.read('classes.jar'))
    classes = WORK/'classes'
    classes.mkdir(exist_ok=True)
    # Remove only this tool's previous class outputs, so deleted inner classes
    # cannot survive a later source edit into the packaged bridge.
    for path in classes.rglob('*.class'):
        path.unlink()
    subprocess.run([str(javac), '-encoding', 'UTF-8', '-g:none', '--release', str(metadata['java_release']),
                    '-classpath', os.pathsep.join([str(android), str(WORK/'godot-classes.jar')]),
                    '-d', str(classes), str(files[0])], check=True)
    jar = WORK/'classes.jar'
    archive(jar, {path.relative_to(classes).as_posix():path.read_bytes() for path in classes.rglob('*.class')})
    archive(OUTPUT, {'classes.jar':jar.read_bytes(), 'AndroidManifest.xml':files[1].read_bytes(), 'R.txt':b''})
    metadata['sha256'] = digest(OUTPUT)
    manifest.write_text(json.dumps(metadata, indent=2)+'\n')
    return metadata


if __name__ == '__main__':
    print(json.dumps(build(), indent=2))
