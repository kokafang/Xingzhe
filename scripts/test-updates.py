#!/usr/bin/env python3
"""Real Sparkle download/install tests, isolated from Xingzhe and power settings."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import uuid

ROOT = Path(__file__).resolve().parent.parent
SPARKLE = ROOT / "build/dependencies/Sparkle-2.9.6"
ACCOUNT = "local.xingzhe.awake"
PUBLIC_KEY = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())["SUPublicEDKey"]

def run(*args):
    subprocess.run(list(map(str, args)), check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

sdk = subprocess.check_output(["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True).strip()
run("xcrun", "swiftc", "-swift-version", "5", "-sdk", sdk, "-target", "arm64-apple-macos13.0",
    "-module-cache-path", ROOT / "build/cache", ROOT / "Sources/Shared/UpdatePreparation.swift",
    ROOT / "Tests/UpdateIntegration/main.swift", "-F", SPARKLE, "-framework", "Sparkle",
    "-framework", "AppKit", "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
    "-o", ROOT / "build/UpdateIntegration")

class Handler(SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass

cases = sys.argv[1:] or ["install", "tampered", "tampered-feed", "no-update", "downgrade", "offline"]
for case in cases:
    folder = Path(tempfile.mkdtemp(prefix="update-test-", dir=ROOT / "build"))
    web = folder / "web"
    web.mkdir()
    result = folder / "events.txt"
    server = ThreadingHTTPServer(("127.0.0.1", 0), partial(Handler, directory=str(web)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    prefix = f"http://localhost:{server.server_port}/"
    bundle_id = "local.xingzhe.update-test." + uuid.uuid4().hex
    def bundle(destination, version, complete=False):
        contents = destination / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        (contents / "Frameworks").mkdir()
        shutil.copy2(ROOT / "build/UpdateIntegration", contents / "MacOS/UpdateIntegration")
        run("ditto", SPARKLE / "Sparkle.framework", contents / "Frameworks/Sparkle.framework")
        info = {"CFBundleIdentifier": bundle_id, "CFBundleName": "Xingzhe Update Test",
                "CFBundleExecutable": "UpdateIntegration", "CFBundlePackageType": "APPL",
                "CFBundleVersion": version, "CFBundleShortVersionString": "1.0." + version,
                "LSMinimumSystemVersion": "13.0", "LSUIElement": True,
                "SUFeedURL": prefix + ("missing.xml" if case == "offline" else "appcast.xml"),
                "SUPublicEDKey": PUBLIC_KEY, "SUVerifyUpdateBeforeExtraction": True,
                "SURequireSignedFeed": True, "SUEnableAutomaticChecks": False,
                "SUAllowsAutomaticUpdates": False, "TestResultPath": str(result),
                "TestCompleteOnLaunch": complete,
                "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True}}
        (contents / "Info.plist").write_bytes(plistlib.dumps(info))
        run("codesign", "--force", "--sign", "-", destination)
        run("codesign", "--verify", "--deep", "--strict", destination)
    source = folder / "installed/Xingzhe Update Test.app"
    target = folder / "new/Xingzhe Update Test.app"
    bundle(source, "3" if case == "downgrade" else ("2" if case == "no-update" else "1"))
    bundle(target, "2", complete=True)
    archive = web / "update.zip"
    run("ditto", "-c", "-k", "--keepParent", "--norsrc", "--noextattr", target, archive)
    run(SPARKLE / "bin/generate_appcast", "--account", ACCOUNT, "--maximum-deltas", "0",
        "--download-url-prefix", prefix, "-o", web / "appcast.xml", web)
    if case == "tampered-feed":
        feed = web / "appcast.xml"
        feed.write_bytes(feed.read_bytes().replace(b"<title>", b"<title>modified", 1))
    if case == "tampered":
        with archive.open("ab") as f:
            f.write(b"invalid-signature")
    output = (folder / "process.log").open("w")
    process = subprocess.Popen([str(source / "Contents/MacOS/UpdateIntegration")], stdout=output, stderr=output)
    try:
        deadline = time.monotonic() + 55
        while time.monotonic() < deadline:
            events = result.read_text() if result.exists() else ""
            if "updated\n" in events or "error:" in events or "no-update\n" in events:
                break
            time.sleep(0.2)
        events = result.read_text() if result.exists() else ""
        info = plistlib.loads((source / "Contents/Info.plist").read_bytes())
        if case == "install":
            assert "updated\n" in events and info["CFBundleVersion"] == "2", events
            assert events.index("restored\n") < events.index("launched:2\n"), events
        elif case in ("no-update", "downgrade"):
            assert "no-update\n" in events and "downloading\n" not in events, events
        else:
            assert "error:" in events and info["CFBundleVersion"] == "1" and "updated\n" not in events, events
        print(f"PASS {case}: {folder}", flush=True)
    except Exception:
        print((folder / "process.log").read_text(), file=sys.stderr)
        print(f"FAIL {case}: {folder}\n{events}", file=sys.stderr)
        raise
    finally:
        server.shutdown()
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=5)
        output.close()
