#!/usr/bin/env python3
"""Release validation and artifact preparation; Python standard library only.

This tool never creates/pushes tags or publishes releases unless the explicit
`publish` command is called. Signing material is read only by `android-signing`.
"""

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import zipfile


ROOT = Path(__file__).resolve().parents[2]
VERSION = re.compile(r"(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\+([1-9]\d*)")
TAG = re.compile(r"v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)")


def run(*args, cwd=ROOT):
    result = subprocess.run(args, cwd=cwd, text=True, capture_output=True)
    if result.returncode:
        raise ValueError(f"Command failed: {' '.join(args)}\n{result.stderr.strip()}")
    return (result.stdout or result.stderr).strip()


def manifest(text):
    matches = re.findall(r"^version:\s*['\"]?([^\s'\"#]+)['\"]?\s*(?:#.*)?$", text, re.M)
    if len(matches) != 1 or not VERSION.fullmatch(matches[0]):
        raise ValueError("Expected exactly one version: MAJOR.MINOR.PATCH+BUILD (positive integer build).")
    full = matches[0]
    name, build = full.split("+")
    if int(build) > 2_100_000_000:
        raise ValueError("Build exceeds Android's maximum versionCode.")
    return {"version": name, "build_number": build, "full_version": full, "tag": f"v{name}"}


def version_at(ref):
    return manifest(run("git", "show", f"{ref}:app/pubspec.yaml"))


def require_tag(tag):
    if not TAG.fullmatch(tag):
        raise ValueError("Release tag must look like v0.2.0; do not include +BUILD or a branch name.")


def commit_at(ref):
    return run("git", "rev-parse", "--verify", f"{ref}^{{commit}}")


def github_api(route):
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    token = os.environ.get("GH_TOKEN", "")
    if not re.fullmatch(r"[\w.-]+/[\w.-]+", repo) or not token:
        raise ValueError("GITHUB_REPOSITORY and GH_TOKEN are required for GitHub operations.")
    api = os.environ.get("GITHUB_API_URL", "https://api.github.com").rstrip("/")
    request = urllib.request.Request(
        f"{api}/repos/{repo}/{route}",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json",
                 "X-GitHub-Api-Version": "2022-11-28", "User-Agent": "Smart-Walker-Releases"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        if error.code == 404 and route.startswith("releases/tags/"):
            return None
        raise ValueError(f"GitHub API request failed with HTTP {error.code}; refusing to assume no release exists.") from error


def marker(commit):
    return f"<!-- smart-walker-release commit={commit} -->"


def sha256(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as contents:
        for chunk in iter(lambda: contents.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def ensure_unpublished(tag, commit):
    release = github_api(f"releases/tags/{urllib.parse.quote(tag, safe='')}")
    if release is None:
        # Draft visibility differs from published tag lookups. Explicitly list
        # releases as well so a failed upload can resume its own draft safely.
        page = 1
        while True:
            releases = github_api(f"releases?per_page=100&page={page}")
            matches = [item for item in releases if item.get("tag_name") == tag]
            if matches:
                release = matches[0]
                break
            if len(releases) < 100:
                return False
            page += 1
    if not release["draft"]:
        raise ValueError(f"{tag} is already published. Publish a new version instead of replacing its binaries.")
    if marker(commit) not in (release.get("body") or "") or release["target_commitish"] != commit:
        raise ValueError("Existing draft does not belong to this workflow/source commit; review it manually.")
    return True


def changelog(version, ref=None):
    text = run("git", "show", f"{ref}:CHANGELOG.md") if ref else (ROOT / "CHANGELOG.md").read_text()
    match = re.search(rf"^## \[{re.escape(version)}\][^\n]*\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not match or not match[1].strip():
        raise ValueError(f"Add a nonempty ## [{version}] section to CHANGELOG.md before releasing.")
    return match[1].strip()


def validate(args):
    require_tag(args.tag)
    ref = f"refs/tags/{args.tag}"
    commit = commit_at(ref)
    base = commit_at(args.base_ref)
    if subprocess.run(["git", "merge-base", "--is-ancestor", commit, base], cwd=ROOT).returncode:
        raise ValueError(f"{args.tag} must identify a commit already merged into {args.base_ref}.")
    info = version_at(commit)
    if info["tag"] != args.tag:
        raise ValueError(f"Tag {args.tag} does not match manifest version {info['full_version']}.")
    sdk = run("git", "show", f"{commit}:app/.flutter-version").strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+", sdk):
        raise ValueError("app/.flutter-version must pin one stable Flutter version.")
    changelog(info["version"], commit)

    # Enforce monotonic versionCode even for failed but retained release tags.
    # Ignore unrelated legacy tags and tags outside the release branch history.
    for previous in run("git", "tag", "--merged", args.base_ref, "--list", "v*").splitlines():
        if previous == args.tag or not TAG.fullmatch(previous):
            continue
        previous_ref = f"refs/tags/{previous}"
        if commit_at(previous_ref) == commit:
            raise ValueError("One source commit cannot declare multiple release versions.")
        older = version_at(previous_ref)
        if older["tag"] != previous:
            raise ValueError(f"Existing tag {previous} does not match its manifest; fix the release history first.")
        if int(info["build_number"]) <= int(older["build_number"]):
            raise ValueError(f"Build must exceed {older['build_number']} from {previous}.")
        if tuple(map(int, info["version"].split("."))) <= tuple(map(int, older["version"].split("."))):
            raise ValueError(f"Public version must be newer than {previous}.")

    if args.check_github:
        remote = github_api(f"commits/{urllib.parse.quote(args.tag, safe='')}")
        if remote["sha"] != commit:
            raise ValueError("Remote tag differs from the fetched source commit.")
        ensure_unpublished(args.tag, commit)
    info.update(commit=commit, flutter_version=sdk)
    print(json.dumps(info, indent=2))
    if args.github_output:
        with Path(args.github_output).open("a") as output:
            for key, value in info.items():
                output.write(f"{key}={value}\n")


def check_source(args):
    require_tag(args.tag)
    info = manifest((ROOT / "app/pubspec.yaml").read_text())
    if info["tag"] != args.tag or commit_at("HEAD") != args.commit:
        raise ValueError("Checked-out source/version differs from the validated release commit.")
    if commit_at(f"refs/tags/{args.tag}") != args.commit:
        raise ValueError("Release tag moved after validation; refusing to build or publish.")
    changelog(info["version"])


def property_value(value):
    # Properties.load(InputStream) uses ISO-8859-1 and Java escape syntax.
    result = []
    for char in value:
        if char in "\\:=#! ":
            result.append("\\" + char)
        elif char in "\n\r\t\f":
            result.append({"\n": r"\n", "\r": r"\r", "\t": r"\t", "\f": r"\f"}[char])
        elif not 32 <= ord(char) < 127:
            encoded = char.encode("utf-16-be")
            result.extend(f"\\u{int.from_bytes(encoded[i:i + 2], 'big'):04x}" for i in range(0, len(encoded), 2))
        else:
            result.append(char)
    return "".join(result)


def android_signing(args):
    names = {"storePassword": "ANDROID_KEYSTORE_PASSWORD", "keyAlias": "ANDROID_KEY_ALIAS",
             "keyPassword": "ANDROID_KEY_PASSWORD"}
    if not os.environ.get("ANDROID_KEYSTORE_BASE64") or any(not os.environ.get(name) for name in names.values()):
        raise ValueError("Configure all four ANDROID_* signing secrets before running a release.")
    key = Path(args.keystore).resolve()
    properties = ROOT / "app/android/key.properties"
    if key.exists() or properties.exists():
        raise ValueError("Signing destination already exists; refusing to overwrite local signing material.")
    contents = base64.b64decode("".join(os.environ["ANDROID_KEYSTORE_BASE64"].split()), validate=True)
    if not contents:
        raise ValueError("Signing keystore is empty.")
    key.parent.mkdir(parents=True, exist_ok=True)
    with key.open("xb") as output:
        key.chmod(0o600)
        output.write(contents)
    values = {"storeFile": str(key), **{k: os.environ[v] for k, v in names.items()}}
    with properties.open("x", encoding="ascii") as output:
        properties.chmod(0o600)
        output.write("\n".join(f"{k}={property_value(v)}" for k, v in values.items()) + "\n")
    print("Temporary Android signing files created; secret values were not logged.")


def package_ios(args):
    app = Path(args.app).resolve()
    destination = Path(args.output).resolve()
    info = manifest((ROOT / "app/pubspec.yaml").read_text())
    with (app / "Info.plist").open("rb") as source:
        plist = plistlib.load(source)
    if (plist.get("CFBundleShortVersionString"), plist.get("CFBundleVersion")) != (info["version"], info["build_number"]):
        raise ValueError("Built iOS version/build does not match the manifest.")
    if plist.get("CFBundleIdentifier") != "com.xichengyang.Smart-Walker":
        raise ValueError("Expected the production iOS identity, not the .dev identity.")
    if (app / "_CodeSignature").exists() or (app / "embedded.mobileprovision").exists():
        raise ValueError("Expected an unsigned documentation app without an embedded provisioning profile.")
    if not (app / plist["CFBundleExecutable"]).is_file():
        raise ValueError("Built application executable is missing.")
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        raise ValueError("Refusing to replace an existing IPA.")
    with tempfile.TemporaryDirectory() as temporary:
        payload = Path(temporary) / "Payload"
        payload.mkdir()
        shutil.copytree(app, payload / app.name, symlinks=True)
        run("/usr/bin/ditto", "-c", "-k", "--keepParent", str(payload), str(destination))
    with zipfile.ZipFile(destination) as archive:
        if f"Payload/{app.name}/Info.plist" not in archive.namelist() or archive.testzip():
            raise ValueError("IPA payload validation failed.")
    print(f"Created {destination.name}: UNSIGNED, documentation only, not installable as distributed.")


def record(args):
    info = manifest((ROOT / "app/pubspec.yaml").read_text())
    artifact = Path(args.artifact).resolve()
    unsigned = "-unsigned" if args.platform == "ios" else ""
    suffix = "ipa" if args.platform == "ios" else "apk"
    expected = f"SmartWalker-{info['version']}-{args.platform}{unsigned}.{suffix}"
    if artifact.name != expected or not artifact.is_file() or artifact.stat().st_size == 0:
        raise ValueError(f"Expected nonempty artifact {expected}.")
    info.update(commit=commit_at("HEAD"), platform=args.platform, artifact=artifact.name,
                sha256=sha256(artifact),
                flutter=json.loads(run("flutter", "--version", "--machine")),
                workflow_run_id=os.environ.get("GITHUB_RUN_ID"),
                workflow_run_attempt=os.environ.get("GITHUB_RUN_ATTEMPT"),
                runner={name: os.environ.get(name) for name in ["RUNNER_OS", "RUNNER_ARCH", "ImageOS", "ImageVersion"]})
    if args.platform == "android":
        certificate = Path(args.certificate).read_text()
        fingerprints = re.findall(r"Signer #\d+ certificate SHA-256 digest: ([a-fA-F0-9]+)", certificate)
        if not fingerprints:
            raise ValueError("APK signature verification did not report a signing certificate.")
        sdk = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
        if not sdk:
            raise ValueError("ANDROID_HOME is required to inspect the release APK.")
        badging = run(str(Path(sdk) / "build-tools/36.0.0/aapt"), "dump", "badging", str(artifact))
        package = re.search(r"^package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", badging, re.M)
        if not package or package.groups() != ("com.xichengyang.smart_walker", info["build_number"], info["version"]):
            raise ValueError("Built Android application identity/version/build does not match the release manifest.")
        info.update(signing="release-keystore", signing_certificate_sha256=fingerprints,
                    java=run("java", "-version"),
                    android_toolchain={"compile_sdk": 36, "build_tools": "36.0.0", "ndk": "28.2.13676358",
                                       "cmake": "3.22.1",
                                       "gradle_wrapper": (ROOT / "app/android/gradle/wrapper/gradle-wrapper.properties").read_text()})
    else:
        info.update(signing="unsigned-documentation-only", installable_as_distributed=False,
                    xcode=run("xcodebuild", "-version"))
    artifact.with_name(f"{args.platform}-build.json").write_text(json.dumps(info, indent=2) + "\n")


def assemble(args):
    require_tag(args.tag)
    info = manifest((ROOT / "app/pubspec.yaml").read_text())
    if info["tag"] != args.tag:
        raise ValueError("Release tag/manifest mismatch.")
    source = Path(args.input).resolve()
    destination = Path(args.output).resolve()
    destination.mkdir(parents=True, exist_ok=True)
    builds = {}
    for platform in ["android", "ios"]:
        build = json.loads((source / f"{platform}-build.json").read_text())
        unsigned = "-unsigned" if platform == "ios" else ""
        extension = "ipa" if platform == "ios" else "apk"
        name = f"SmartWalker-{info['version']}-{platform}{unsigned}.{extension}"
        artifact = source / name
        if any(build.get(k) != info[k] for k in ["version", "build_number", "full_version", "tag"]):
            raise ValueError(f"{platform} metadata version mismatch.")
        if build.get("commit") != args.commit or build.get("artifact") != name or build.get("platform") != platform:
            raise ValueError(f"{platform} metadata source/artifact mismatch.")
        if sha256(artifact) != build.get("sha256"):
            raise ValueError(f"{platform} artifact checksum mismatch.")
        if build.get("flutter", {}).get("frameworkVersion") != (ROOT / "app/.flutter-version").read_text().strip():
            raise ValueError(f"{platform} build did not use the pinned Flutter SDK.")
        expected_signing = "release-keystore" if platform == "android" else "unsigned-documentation-only"
        if build.get("signing") != expected_signing:
            raise ValueError(f"Unexpected {platform} signing status.")
        shutil.copy2(artifact, destination / name)
        builds[platform] = build
    info.update(commit=args.commit, platforms=builds)
    (destination / "build-info.json").write_text(json.dumps(info, indent=2) + "\n")
    assets = sorted([*destination.glob("*.apk"), *destination.glob("*.ipa"), destination / "build-info.json"])
    (destination / "SHA256SUMS.txt").write_text("".join(
        f"{sha256(path)}  {path.name}\n" for path in assets))
    notes = (
        f"# Smart Walker {args.tag}\n\n{changelog(info['version'])}\n\n"
        f"**Version:** {info['full_version']}  \n**Source commit:** `{args.commit}`\n\n"
        "## Artifacts\n\n"
        "- **Android APK:** signed release build. Updates require the same signing key.\n"
        "- **iOS unsigned IPA:** documentation/archive only. Not an Apple-signed export; "
        "cannot be installed or submitted as distributed. No Apple signing credentials were used.\n"
        "- **build-info.json:** source, version, toolchain, signing status, and artifact checksums.\n"
        "- **SHA256SUMS.txt:** checksums of the binaries and build-info.json.\n\n"
        "This is a development pre-release. Automated packaging does not imply hardware validation.\n\n"
        f"{marker(args.commit)}\n"
    )
    (destination / "RELEASE_NOTES.md").write_text(notes)


def publish(args):
    require_tag(args.tag)
    if commit_at(f"refs/tags/{args.tag}") != args.commit:
        raise ValueError("Release tag moved before publication.")
    remote = github_api(f"commits/{urllib.parse.quote(args.tag, safe='')}")
    if remote["sha"] != args.commit:
        raise ValueError("Remote release tag moved before publication.")
    directory = Path(args.directory).resolve()
    info = json.loads((directory / "build-info.json").read_text())
    if info["tag"] != args.tag or info["commit"] != args.commit:
        raise ValueError("Release metadata/source mismatch.")
    exists = ensure_unpublished(args.tag, args.commit)
    repo = os.environ["GITHUB_REPOSITORY"]
    assets = [directory / build["artifact"] for build in info["platforms"].values()]
    assets.extend([directory / "build-info.json", directory / "SHA256SUMS.txt"])
    expected_hashes = {line.split("  ", 1)[1]: line.split("  ", 1)[0]
                       for line in (directory / "SHA256SUMS.txt").read_text().splitlines()}
    for path in assets[:-1]:
        if expected_hashes.get(path.name) != sha256(path):
            raise ValueError(f"Final release asset {path.name} differs from its recorded checksum.")
    if not exists:
        run("gh", "release", "create", args.tag, "--repo", repo, "--verify-tag", "--target", args.commit,
            "--draft", "--prerelease", "--title", f"Smart Walker {args.tag}",
            "--notes-file", str(directory / "RELEASE_NOTES.md"))
    # A failed upload can be retried only against this workflow's own draft.
    run("gh", "release", "upload", args.tag, "--repo", repo, "--clobber", *(str(path) for path in assets))
    run("gh", "release", "edit", args.tag, "--repo", repo, "--draft=false", "--prerelease", "--latest=false",
        "--notes-file", str(directory / "RELEASE_NOTES.md"))
    print(f"Published {args.tag} with {len(assets)} release assets.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    command = commands.add_parser("validate", help="Validate an existing tag against main and its manifest.")
    command.add_argument("--tag", required=True)
    command.add_argument("--base-ref", default="origin/main")
    command.add_argument("--check-github", action="store_true")
    command.add_argument("--github-output")
    command.set_defaults(action=validate)
    command = commands.add_parser("check-source", help="Verify a build checks out the validated source.")
    command.add_argument("--tag", required=True)
    command.add_argument("--commit", required=True)
    command.set_defaults(action=check_source)
    command = commands.add_parser("android-signing", help="Write temporary signing files from Actions secrets.")
    command.add_argument("--keystore", required=True)
    command.set_defaults(action=android_signing)
    command = commands.add_parser("package-ios", help="Package an unsigned app as a documentation-only IPA.")
    command.add_argument("--app", required=True)
    command.add_argument("--output", required=True)
    command.set_defaults(action=package_ios)
    command = commands.add_parser("record", help="Record build provenance and artifact hash.")
    command.add_argument("--platform", choices=["android", "ios"], required=True)
    command.add_argument("--artifact", required=True)
    command.add_argument("--certificate", default="")
    command.set_defaults(action=record)
    command = commands.add_parser("assemble", help="Verify artifacts and create checksums/notes.")
    command.add_argument("--tag", required=True)
    command.add_argument("--commit", required=True)
    command.add_argument("--input", required=True)
    command.add_argument("--output", required=True)
    command.set_defaults(action=assemble)
    command = commands.add_parser("publish", help="Explicitly publish artifacts using the GitHub CLI.")
    command.add_argument("--tag", required=True)
    command.add_argument("--commit", required=True)
    command.add_argument("--directory", required=True)
    command.set_defaults(action=publish)
    args = parser.parse_args()
    try:
        args.action(args)
    except (ValueError, OSError, KeyError, json.JSONDecodeError, plistlib.InvalidFileException,
            urllib.error.URLError, zipfile.BadZipFile) as error:
        parser.exit(1, f"Release error: {error}\n")


if __name__ == "__main__":
    main()