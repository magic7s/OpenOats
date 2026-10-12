import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ReleaseMacOSMetadataTests(unittest.TestCase):
    def update(self, minimum=None):
        with tempfile.TemporaryDirectory() as directory:
            cask = Path(directory) / 'openoats.rb'
            cask.write_text((ROOT / 'Casks/openoats.rb').read_text())
            command = ['bash', str(ROOT / 'scripts/update_homebrew_cask.sh'), '9.9.9', '0' * 64]
            if minimum is not None:
                command.append(minimum)
            subprocess.run(command, env={**os.environ, 'CASK_PATH': str(cask)}, check=True)
            return cask.read_text()

    def test_sonoma_release_uses_homebrew_release_symbol(self):
        self.assertIn('depends_on macos: :sonoma', self.update('14.2'))

    def test_historical_release_keeps_its_higher_minimum(self):
        self.assertIn('depends_on macos: :sequoia', self.update('15.0'))

    def test_patch_version_uses_homebrew_release_symbol(self):
        self.assertIn('depends_on macos: :tahoe', self.update('26.1.2'))

    def test_unknown_release_is_rejected_without_changing_cask(self):
        with tempfile.TemporaryDirectory() as directory:
            cask = Path(directory) / 'openoats.rb'
            original = (ROOT / 'Casks/openoats.rb').read_text()
            cask.write_text(original)
            result = subprocess.run(
                ['bash', str(ROOT / 'scripts/update_homebrew_cask.sh'),
                 '9.9.9', '0' * 64, '99.0'],
                env={**os.environ, 'CASK_PATH': str(cask)},
                capture_output=True, text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Unsupported minimum macOS version', result.stderr)
            self.assertEqual(cask.read_text(), original)

    def test_legacy_two_argument_call_keeps_existing_requirement(self):
        source = (ROOT / 'Casks/openoats.rb').read_text()
        requirement = next(line for line in source.splitlines() if 'depends_on macos:' in line)
        self.assertIn(requirement, self.update())

    def test_invalid_minimum_is_rejected(self):
        with self.assertRaises(subprocess.CalledProcessError):
            self.update('invalid')
