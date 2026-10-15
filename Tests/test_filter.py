#!/usr/bin/env python3
"""Developer-only, synthetic filter tests. No printer, vendor binary or label data."""
import pathlib
import subprocess
import tempfile
import time
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class FilterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix="rollo-filter-tests-")
        cls.work = pathlib.Path(cls.directory.name)
        converter = cls.work / "synthetic-converter"
        cls.wrapper = cls.work / "test-wrapper"
        cls.sidechannel = cls.work / "synthetic-sidechannel"
        subprocess.run(["xcrun", "clang", "-O2", str(ROOT / "Tests/fixture_converter.c"), "-o", str(converter)], check=True)
        subprocess.run(["xcrun", "clang", "-O2", "-Wall", "-Wextra", "-Werror", str(ROOT / "Tests/fixture_sidechannel.c"), "-o", str(cls.sidechannel)], check=True)
        subprocess.run(["xcrun", "clang", "-O2", "-Wall", "-Wextra", "-Werror",
                        '-DROLLO_VENDOR_CONVERTER="' + str(converter) + '"',
                        str(ROOT / "Sources/filter.c"), "-lcups", "-o", str(cls.wrapper)], check=True)
        cls.payload = bytes(range(256)) * 37  # 9472 synthetic bytes

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def args(self, options="test"):
        return [str(self.wrapper), "1", "test-user", "synthetic-test", "1", options]

    def test_stream_preserved_and_paced(self):
        started = time.monotonic()
        result = subprocess.run(self.args(), input=self.payload, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, self.payload)
        self.assertGreater(time.monotonic() - started, 0.30)
        self.assertIn(b"9472 unchanged bytes", result.stderr)

    def test_file_input_preserved(self):
        source = self.work / "synthetic-input"
        source.write_bytes(self.payload)
        result = subprocess.run(self.args() + [str(source)], stdin=subprocess.DEVNULL, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, self.payload)

    def test_converter_failure_propagates(self):
        result = subprocess.run(self.args("fail"), input=b"", capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 7)
        self.assertEqual(result.stdout, b"")

    def test_cancel_blocked_input_is_bounded(self):
        process = subprocess.Popen(self.args(), stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        time.sleep(0.1)
        started = time.monotonic()
        process.terminate()
        stdout, stderr = process.communicate(timeout=4)
        self.assertNotEqual(process.returncode, 0)
        self.assertEqual(stdout, b"")
        self.assertLess(time.monotonic() - started, 3)

    def test_backend_readiness_handshake(self):
        source = self.work / "sidechannel-input"
        source.write_bytes(self.payload)
        result = subprocess.run([str(self.sidechannel), str(self.wrapper), str(source), "1"], capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, self.payload)
        self.assertIn(b"readiness confirmed", result.stderr)

    def test_failed_readiness_sends_no_print_data(self):
        source = self.work / "sidechannel-failure-input"
        source.write_bytes(self.payload)
        result = subprocess.run([str(self.sidechannel), str(self.wrapper), str(source), "2"], capture_output=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"")
        self.assertIn(b"no print data sent", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
