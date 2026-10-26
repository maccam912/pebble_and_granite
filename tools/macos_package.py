#!/usr/bin/env python3
"""Repair Godot's executable-name XML escaping and seal with Apple's codesign."""
import pathlib
import plistlib
import re
import subprocess
import tempfile
from xml.sax.saxutils import escape

from verify_export import extract_macos, verify_macos_bundle


def sign_bundle(app):
    app = pathlib.Path(app).resolve()
    executables = list((app / 'Contents/MacOS').iterdir())
    if len(executables) != 1 or not executables[0].is_file():
        raise RuntimeError('Expected one app executable')
    info = app / 'Contents/Info.plist'
    # Godot 4.7 escapes the display name but inserts the executable name raw.
    # Parse after replacing this one field; unrelated malformed XML must fail.
    source, count = re.subn(
        r'(<key>CFBundleExecutable</key>\s*)<string>.*?</string>',
        lambda match: match[1] + '<string>' + escape(executables[0].name) + '</string>',
        info.read_text(),
    )
    if count != 1:
        raise RuntimeError('Expected one CFBundleExecutable')
    info.write_bytes(plistlib.dumps(plistlib.loads(source.encode()), sort_keys=False))
    with tempfile.TemporaryDirectory(prefix='pebble-sign-') as temp:
        entitlements = pathlib.Path(temp) / 'entitlements.plist'
        entitlements.write_bytes(plistlib.dumps({
            'com.apple.security.cs.disable-library-validation': True,
        }))
        # Sign nested native bridges first, then the enclosing bundle. Apple's
        # signer also regenerates CodeResources with correctly escaped paths.
        for library in sorted((app / 'Contents/Frameworks').glob('*.dylib')):
            subprocess.run(['codesign', '--force', '--sign', '-', '--timestamp=none',
                            str(library)], check=True)
        subprocess.run(['codesign', '--force', '--sign', '-', '--timestamp=none',
                        '--options', 'runtime', '--entitlements', str(entitlements),
                        str(app)], check=True)
    verify_macos_bundle(app)


def finalize(artifact):
    artifact = pathlib.Path(artifact).resolve()
    with tempfile.TemporaryDirectory(prefix='pebble-macos-') as temp:
        stage = pathlib.Path(temp)
        app = extract_macos(artifact, stage / 'unpacked')
        sign_bundle(app)
        output = stage / 'signed.zip'
        # Only ship the app; Godot's debug .command launcher also mishandles '&'.
        subprocess.run(['ditto', '-c', '-k', '--keepParent', '--norsrc',
                        str(app), str(output)], check=True)
        artifact.write_bytes(output.read_bytes())


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('artifact', help='Export ZIP, or an extracted .app to repair')
    args = parser.parse_args()
    if pathlib.Path(args.artifact).suffix == '.app':
        sign_bundle(args.artifact)
    else:
        finalize(args.artifact)
