"""End-to-end tests for scripts/verify-apk.py against tiny APKs built with the SDK's aapt2.

Locally the tests skip without an SDK aapt2 and android.jar; in CI (CI set) they fail instead.
"""

import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "verify-apk.py"
_spec = importlib.util.spec_from_file_location("verify_apk", SCRIPT)
verify_apk = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(verify_apk)

MANIFEST = """<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.example.verifyapk" android:versionName="1.0">
    <application/>
</manifest>
"""


class VerifyApkTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        aapt = verify_apk.find_aapt()
        jars = []
        if aapt and os.path.basename(aapt) == "aapt2":
            sdk = Path(aapt).parents[2]
            jars = sorted(sdk.glob("platforms/*/android.jar"))
        if not jars:
            msg = "needs aapt2 and an android.jar from the Android SDK"
            if os.environ.get("CI"):
                raise RuntimeError(msg)
            raise unittest.SkipTest(msg)
        cls.aapt, cls.jar = aapt, str(jars[-1])

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        (self.tmp / "AndroidManifest.xml").write_text(MANIFEST)

    def build_apk(self, min_sdk, abis=()):
        apk = self.tmp / f"min{min_sdk}-{'-'.join(abis) or 'java'}.apk"
        subprocess.run(
            [self.aapt, "link", "-o", str(apk), "-I", self.jar,
             "--manifest", str(self.tmp / "AndroidManifest.xml"),
             "--min-sdk-version", str(min_sdk), "--target-sdk-version", "34"],
            check=True, capture_output=True)
        with zipfile.ZipFile(apk, "a") as z:
            for abi in abis:
                z.writestr(f"lib/{abi}/libgojni.so", b"")
        return str(apk)

    def verify(self, *apks, abi="armeabi-v7a"):
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--require-min-sdk", "22", "--require-abi", abi, *apks],
            capture_output=True, text=True)

    def test_min_sdk_22_with_abi_passes(self):
        r = self.verify(self.build_apk(22, ["armeabi-v7a"]))
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("minSdk       : 22  OK", r.stdout)
        self.assertIn("PASS", r.stdout)

    def test_min_sdk_too_new_fails(self):
        r = self.verify(self.build_apk(26, ["armeabi-v7a"]))
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("TOO NEW", r.stdout)
        self.assertIn("FAIL (minSdk)", r.stdout)

    def test_missing_abi_fails(self):
        r = self.verify(self.build_apk(22, ["arm64-v8a"]))
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("missing armeabi-v7a", r.stdout)

    def test_pure_java_passes(self):
        r = self.verify(self.build_apk(22))
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("pure-Java", r.stdout)

    def test_any_failing_apk_fails_the_run(self):
        r = self.verify(self.build_apk(22, ["armeabi-v7a"]), self.build_apk(26, ["armeabi-v7a"]))
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)


if __name__ == "__main__":
    unittest.main()
