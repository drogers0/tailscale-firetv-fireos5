#!/usr/bin/env python3
"""
Verify an APK against old-Fire-OS constraints by reading its binary AndroidManifest.xml.

Version numbers and filenames lie; the manifest does not. This gates the build so a
silently-incompatible artifact cannot reach dist/.

Usage:
    verify-apk.py [--require-min-sdk 22] [--require-abi armeabi-v7a] APK [APK ...]

Reads the manifest via pyaxmlparser, falling back to aapt/aapt2 from the Android SDK
build-tools if that isn't installed.
"""

import argparse
import glob
import os
import re
import subprocess
import sys
import zipfile


def read_with_pyaxmlparser(path):
    try:
        from pyaxmlparser import APK
    except ImportError:
        return None
    a = APK(path)
    mn = a.get_min_sdk_version()
    tg = a.get_target_sdk_version()
    return {
        "package": a.package,
        "version": a.version_name,
        # None, not a default. An unknown minSdk must never silently pass.
        "min_sdk": int(mn) if mn is not None else None,
        "target_sdk": int(tg) if tg is not None else None,
    }


def find_aapt():
    roots = [os.environ.get("ANDROID_SDK_ROOT"), os.environ.get("ANDROID_HOME"),
             os.path.expanduser("~/Library/Android/sdk"), os.path.expanduser("~/Android/Sdk")]
    for root in filter(None, roots):
        for name in ("aapt2", "aapt"):
            hits = sorted(glob.glob(os.path.join(root, "build-tools", "*", name)))
            if hits:
                return hits[-1]
    return None


def read_with_aapt(path):
    aapt = find_aapt()
    if not aapt:
        return None
    try:
        out = subprocess.run([aapt, "dump", "badging", path],
                             capture_output=True, text=True, check=True).stdout
    except (subprocess.CalledProcessError, OSError):
        return None

    def grab(*patterns):
        for pat in patterns:
            m = re.search(pat, out)
            if m:
                return m.group(1)
        return None

    def grab_int(*patterns):
        v = grab(*patterns)
        return int(v) if v is not None else None

    return {
        "package": grab(r"package: name='([^']+)'"),
        "version": grab(r"versionName='([^']+)'"),
        # aapt2 prints "minSdkVersion:'22'"; aapt v1 prints "sdkVersion:'22'".
        # Both spellings must be handled — matching only one silently yields no
        # value, and any default here would let an incompatible APK pass.
        "min_sdk": grab_int(r"minSdkVersion:'(\d+)'", r"(?<!target)(?<!compile)\bsdkVersion:'(\d+)'"),
        "target_sdk": grab_int(r"targetSdkVersion:'(\d+)'"),
    }


def inspect(path):
    meta = read_with_pyaxmlparser(path) or read_with_aapt(path)
    if meta is None:
        sys.exit("error: need pyaxmlparser (pip install pyaxmlparser) or aapt in the Android SDK")
    if meta.get("min_sdk") is None:
        sys.exit(f"error: could not determine minSdkVersion for {path}; refusing to guess")

    with zipfile.ZipFile(path) as z:
        names = z.namelist()
    meta["abis"] = sorted({m.group(1) for n in names
                           if (m := re.match(r"lib/([^/]+)/", n))})
    meta["densities"] = sorted({m.group(1) for n in names
                                if (m := re.search(r"res/[^/]*-(\w*dpi)[/-]", n))})
    meta["size_mb"] = os.path.getsize(path) / 1048576
    return meta


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("apks", nargs="+")
    ap.add_argument("--require-min-sdk", type=int, default=None,
                    help="fail if the APK's minSdk exceeds this device API level")
    ap.add_argument("--require-abi", default=None,
                    help="fail if the APK has native libs but not this ABI")
    args = ap.parse_args()

    failed = False
    for path in args.apks:
        m = inspect(path)
        print("=" * 68)
        print(os.path.basename(path))
        print(f"  package      : {m['package']}")
        print(f"  version      : {m['version']}")
        print(f"  size         : {m['size_mb']:.1f} MB")

        problems = []

        line = f"  minSdk       : {m['min_sdk']}"
        if args.require_min_sdk is not None:
            if m["min_sdk"] > args.require_min_sdk:
                line += f"  *** TOO NEW — needs <= {args.require_min_sdk}, will not install ***"
                problems.append("minSdk")
            else:
                line += "  OK"
        print(line)
        print(f"  targetSdk    : {m['target_sdk'] if m['target_sdk'] is not None else 'unknown'}")

        if m["abis"]:
            line = f"  native ABIs  : {', '.join(m['abis'])}"
            if args.require_abi:
                if args.require_abi in m["abis"]:
                    line += "  OK"
                else:
                    line += f"  *** missing {args.require_abi} ***"
                    problems.append("abi")
            print(line)
        else:
            print("  native ABIs  : none (pure-Java, ABI-independent)  OK")

        print(f"  densities    : {', '.join(m['densities']) if m['densities'] else 'none (nodpi/universal)'}")

        if problems:
            print(f"  RESULT       : FAIL ({', '.join(problems)})")
            failed = True
        else:
            print("  RESULT       : PASS")

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
