#!/usr/bin/env python3
"""Offline GitHub release fixture. It only accesses the temporary test directory."""
import json
import os
from pathlib import Path
import shutil
import sys

root = Path(os.environ['ROLLO_RELEASE_FIXTURE'])
state_path = root / 'state.json'
state = json.loads(state_path.read_text())
args = sys.argv[1:]
with (root / 'calls.jsonl').open('a') as log:
    log.write(json.dumps(args) + '\n')
assert args[0] == 'release'
command = args[1]
if command == 'view':
    if not state['exists']:
        sys.exit(1)
    if args[-1] == 'tagName,isDraft':
        print(json.dumps({'tagName': state['tag'], 'isDraft': state['draft']}))
    else:
        assert args[-1] == 'assets'
        names = list(state['assets'])
        if state.get('stale_asset'):
            names.append('unrelated-download.pkg')
        print(json.dumps({'assets': [{'name': name} for name in names]}))
elif command == 'create':
    assert '--draft' in args and '--verify-tag' in args
    state.update(exists=True, draft=True)
elif command == 'upload':
    for path in args[4:]:
        source = Path(path)
        shutil.copyfile(source, root / 'assets' / source.name)
        if source.name not in state['assets']:
            state['assets'].append(source.name)
elif command == 'download':
    destination = Path(args[args.index('--dir') + 1])
    for name in state['assets']:
        shutil.copyfile(root / 'assets' / name, destination / name)
    if state.get('tamper'):
        (destination / state['assets'][0]).write_bytes(b'altered download')
elif command == 'edit':
    assert '--draft=false' in args
    state['draft'] = False
else:
    raise AssertionError(args)
state_path.write_text(json.dumps(state))
