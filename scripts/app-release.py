"""Stage immutable Windows updates, then promote the tested manifest."""
import datetime
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import urllib.request

config = json.loads(Path("tauri.conf.json").read_text(encoding="utf-8"))
version = config["version"]
if not re.fullmatch(r"(0|[1-9]\d*)(\.(0|[1-9]\d*)){2}", version):
    raise ValueError("Stable releases require a numeric version")
latest = config["plugins"]["updater"]["endpoints"][0]
base = latest.split("/v1/")[0] + "/v1/app-downloads/" + version
directory = Path("dist")
manifest = directory / "manifest.json"
account = os.environ["ACCOUNT_ID"]
bucket = os.environ["BUCKET"]
if bucket != "machine-party-mods" or not re.fullmatch("[0-9a-f]{32}", account):
    raise ValueError("Invalid R2 destination")


def upload(key, file, condition):
    subprocess.run(["aws", "--endpoint-url", f"https://{account}.r2.cloudflarestorage.com",
                    "s3api", "put-object", "--bucket", bucket, "--key", "app-releases/" + key,
                    "--body", str(file), *condition], check=True)


def read(url):
    request = urllib.request.Request(url, headers={"User-Agent": "MachinePartyModManager-Release/" + version})
    with urllib.request.urlopen(request, timeout=90) as response:
        return response.read(), response.headers.get("ETag")


def stage():
    installer = directory / "setup.exe"
    for name, file in [("setup.exe", installer), ("manifest.json", manifest)]:
        url = base + "/" + name
        try:
            existing, _ = read(url)
        except urllib.error.HTTPError as error:
            if error.code != 404:
                raise
            existing = None
        if name == "manifest.json":
            if existing:
                saved = json.loads(existing)
                if saved["version"] != version or saved["platforms"]["windows-x86_64"]["url"] != base + "/setup.exe":
                    raise ValueError("Unexpected staged manifest")
                file.write_bytes(existing)
                (directory / "setup.exe.sig").write_text(saved["platforms"]["windows-x86_64"]["signature"], encoding="ascii")
            else:
                file.write_text(json.dumps({
                    "version": version, "pub_date": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                    "platforms": {"windows-x86_64": {"url": base + "/setup.exe",
                        "signature": (directory / "setup.exe.sig").read_text().strip()}}
                }), encoding="utf-8")
        if existing is None:
            upload(version + "/" + name, file, ["--if-none-match", "*"])
        if read(url)[0] != file.read_bytes():
            raise ValueError("Published object differs from this build: " + name)


def promote():
    previous, etag = read(latest)
    candidate = manifest.read_bytes()
    if previous != candidate:
        if previous and tuple(map(int, json.loads(previous)["version"].split("."))) >= tuple(map(int, version.split("."))):
            raise ValueError("Refusing to replace an equal or newer stable version")
        upload("stable/latest.json", manifest, ["--if-match", etag] if previous else ["--if-none-match", "*"])
    if read(latest)[0] != candidate:
        raise ValueError("Public stable manifest verification failed")


{"stage": stage, "promote": promote}[sys.argv[1]]()
