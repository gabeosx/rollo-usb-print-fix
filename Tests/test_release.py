#!/usr/bin/env python3
"""Exercise release publication offline with macOS's system Bash."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parent.parent


class ReleaseTests(unittest.TestCase):
    def publish(self, *, version='0.2.2', exists=False, draft=True, tamper=False, stale_asset=False):
        with tempfile.TemporaryDirectory(prefix='rollo-release-test-') as temporary:
            root = Path(temporary)
            for folder in ['script', 'Packaging', 'dist', 'bin', 'fixture/assets', 'runner']:
                (root / folder).mkdir(parents=True, exist_ok=True)
            for name in ['publish_release.sh', 'version.py']:
                shutil.copyfile(SOURCE / 'script' / name, root / 'script' / name)
            shutil.copyfile(SOURCE / 'Tests/fixture_gh.py', root / 'bin/gh')
            (root / 'bin/gh').chmod(0o755)
            (root / 'VERSION').write_text(version + '\n')
            (root / 'Packaging/ReleaseNotes.md').write_text('Synthetic release.\n')
            names = [f'{prefix}Rollo-USB-Print-Fix-{version}-signed.pkg' for prefix in ['', 'Remove-']]
            names.append(f'Rollo-USB-Print-Fix-Setup-{version}-signed.zip')
            for name in names:
                (root / 'dist' / name).write_bytes(('Synthetic ' + name).encode())
            (root / 'dist/SHA256SUMS-signed.txt').write_text(''.join(
                hashlib.sha256((root / 'dist' / name).read_bytes()).hexdigest() + '  ' + name + '\n' for name in names))
            state_path = root / 'fixture/state.json'
            state_path.write_text(json.dumps(dict(tag='v' + version, exists=exists, draft=draft,
                                                 assets=[], tamper=tamper, stale_asset=stale_asset)))
            env = dict(os.environ, PATH=str(root / 'bin') + os.pathsep + os.environ['PATH'],
                       ROLLO_RELEASE_FIXTURE=str(root / 'fixture'), RUNNER_TEMP=str(root / 'runner'),
                       RELEASE_TAG='v' + version, GITHUB_STEP_SUMMARY=str(root / 'summary'))
            subprocess.run(['git', 'init', '-q'], cwd=root, env=env, check=True)
            subprocess.run(['git', 'add', 'VERSION'], cwd=root, env=env, check=True)
            subprocess.run(['git', '-c', 'user.name=Release Test', '-c', 'user.email=test@example.invalid',
                            'commit', '-qm', 'Synthetic fixture'], cwd=root, env=env, check=True)
            env['RELEASE_COMMIT'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
            result = subprocess.run(['/bin/bash', 'script/publish_release.sh'], cwd=root, env=env, capture_output=True, text=True)
            calls = [json.loads(line) for line in (root / 'fixture/calls.jsonl').read_text().splitlines()]
            return result, json.loads(state_path.read_text()), calls

    def test_stable_release_on_system_bash(self):
        result, state, calls = self.publish()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(state['draft'])
        self.assertNotIn('--prerelease', next(call for call in calls if call[1] == 'create'))

    def test_prerelease(self):
        result, state, calls = self.publish(version='0.2.2-rc.1')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('--prerelease', next(call for call in calls if call[1] == 'create'))

    def test_draft_retry(self):
        result, state, calls = self.publish(exists=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(call[1] == 'create' for call in calls))

    def test_published_release_is_terminal(self):
        result, state, calls = self.publish(exists=True, draft=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(call[1] in {'upload', 'edit'} for call in calls))

    def test_altered_download_is_not_published(self):
        result, state, calls = self.publish(tamper=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(state['draft'])

    def test_unknown_asset_is_not_published(self):
        result, state, calls = self.publish(stale_asset=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(state['draft'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
