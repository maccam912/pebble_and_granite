#!/usr/bin/env python3
"""Run the exported desktop executable, not the editor/source project."""
import argparse,json,pathlib,subprocess,tempfile,uuid,zipfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
def verify(platform,artifact):
    artifact=pathlib.Path(artifact).resolve()
    with tempfile.TemporaryDirectory(prefix='pebble-export-') as temp:
        if platform=='macos':
            stage=pathlib.Path(temp)
            with zipfile.ZipFile(artifact) as archive:
                for member in archive.infolist():
                    path=pathlib.PurePosixPath(member.filename)
                    if path.is_absolute() or '..' in path.parts:raise RuntimeError('Unsafe package path')
                    archive.extract(member,stage)
                    dest=stage/member.filename
                    if dest.is_file():dest.chmod((member.external_attr>>16)&0o777 or 0o644)
            binaries=list(stage.glob('*.app/Contents/MacOS/*'))
            if len(binaries)!=1:raise RuntimeError('Expected one app executable')
            executable=binaries[0]
        else:executable=artifact
        nonce=uuid.uuid4().hex
        result=subprocess.run([str(executable),'--headless','--','--self-test','--probe-id='+nonce],capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=120)
        lines=[line.split('PEBBLE_SELF_TEST_RESULT ',1)[1] for line in result.stdout.splitlines() if 'PEBBLE_SELF_TEST_RESULT ' in line]
        if result.returncode or len(lines)!=1:raise RuntimeError('Exported runtime failed:\n'+result.stdout+result.stderr)
        report=json.loads(lines[0])
        if not report.get('ok') or report.get('nonce')!=nonce or report.get('trace')!=(ROOT/'validation/golden.txt').read_text():raise RuntimeError('Exported simulation trace mismatch')
        print('EXPORTED_RUNTIME_OK',platform)
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('platform',choices=['linux','windows','macos']);parser.add_argument('artifact');args=parser.parse_args();verify(args.platform,args.artifact)
