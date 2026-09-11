#!/usr/bin/env python3
"""Validate the published feed metadata and Ed25519 archive signature."""
import base64
import pathlib
import plistlib
import subprocess
import sys
import xml.etree.ElementTree as ET

feed, archive = map(pathlib.Path, sys.argv[1:])
ns = {"s": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
item = ET.parse(feed).find("./channel/item")
assert item is not None, "No update in feed"
enclosure = item.find("enclosure")
assert enclosure is not None
signature = enclosure.attrib["{" + ns["s"] + "}edSignature"]
assert len(base64.b64decode(signature, validate=True)) == 64
assert int(enclosure.attrib["length"]) == archive.stat().st_size
assert enclosure.attrib["url"].endswith("/" + archive.name)
root = pathlib.Path(__file__).resolve().parent.parent
with (root / "build/醒着.app/Contents/Info.plist").open("rb") as f:
    info = plistlib.load(f)
public_key = subprocess.check_output([str(root / "build/dependencies/Sparkle-2.9.6/bin/generate_keys"),
                                      "--account", "local.xingzhe.awake", "-p"], text=True).strip()
assert public_key == info["SUPublicEDKey"], "Signing account does not match the app's public key"
assert item.findtext("s:version", namespaces=ns) == info["CFBundleVersion"]
assert item.findtext("s:shortVersionString", namespaces=ns) == info["CFBundleShortVersionString"]
assert item.findtext("s:minimumSystemVersion", namespaces=ns) == "13.0"
# Verification uses Sparkle's public-key verifier CLI. No key is exported.
subprocess.run([str(root / "build/dependencies/Sparkle-2.9.6/bin/sign_update"),
                "--account", "local.xingzhe.awake", "--verify", str(archive), signature], check=True)
print("PASS: update version, compatibility, archive size and EdDSA signature")
