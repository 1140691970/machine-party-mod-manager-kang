"""Stage immutable desktop updates, then promote the tested manifest."""
import datetime
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import urllib.request

root = Path(__file__).resolve().parent.parent
config = json.loads((root / "apps/desktop/src-tauri/tauri.conf.json").read_text(encoding="utf-8"))
version = config["version"]
if not re.fullmatch(r"(0|[1-9]\d*)(\.(0|[1-9]\d*)){2}", version):
    raise ValueError("Stable releases require a numeric version")
latest = config["plugins"]["updater"]["endpoints"][0]
base = latest.split("/v1/")[0] + "/v1/app-downloads/" + version
directory = root / "dist"
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


packages = {"windows-x86_64": "setup.exe"}


def existing_object(name):
    try:
        return read(base + "/" + name)[0]
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
        return None


def publish_immutable(name, file):
    existing = existing_object(name)
    if existing is None:
        upload(version + "/" + name, file, ["--if-none-match", "*"])
        existing = read(base + "/" + name)[0]
    if existing != file.read_bytes():
        raise ValueError("Published object differs from this build: " + name)


def release_notes():
    env_notes = os.environ.get("RELEASE_NOTES", "").strip()
    if env_notes:
        return env_notes
    changelog = root / "CHANGELOG.md"
    if not changelog.is_file():
        return ""
    lines = changelog.read_text(encoding="utf-8").splitlines()
    heading = re.compile(rf"^##\s+v?{re.escape(version)}(?:\s|$|—|-)")
    section = []
    inside = False
    for line in lines:
        if re.match(r"^##\s+", line):
            if inside:
                break
            if heading.match(line):
                inside = True
            continue
        if inside:
            section.append(line)
    return "\n".join(section).strip()


def stage():
    platforms = {}
    for target, name in packages.items():
        publish_immutable(name, directory / name)
        platforms[target] = {"url": base + "/" + name,
                             "signature": (directory / (name + ".sig")).read_text().strip()}

    existing = existing_object("manifest.json")
    if existing is None:
        payload = {
            "version": version,
            "pub_date": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "platforms": platforms,
        }
        notes = release_notes()
        if notes:
            payload["notes"] = notes
        manifest.write_text(json.dumps(payload), encoding="utf-8")
    else:
        saved = json.loads(existing)
        if saved["version"] != version or saved["platforms"].keys() != platforms.keys():
            raise ValueError("Unexpected staged manifest")
        for target, name in packages.items():
            entry = saved["platforms"][target]
            if entry["url"] != platforms[target]["url"] or not entry["signature"]:
                raise ValueError("Unexpected staged platform: " + target)
            (directory / (name + ".sig")).write_text(entry["signature"], encoding="ascii")
        manifest.write_bytes(existing)
    publish_immutable("manifest.json", manifest)


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
