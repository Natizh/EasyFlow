#!/usr/bin/env python3
"""Fail closed if local signing credentials could enter Git or an app asset."""

import argparse
import base64
import os
from pathlib import Path
import stat
import subprocess
import sys
import zipfile


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_KEYS = Path.home() / "Library/Application Support/EasyFlowSigning"
SENSITIVE_NAMES = {"update-private-key.txt", "update-private-key", "private.key"}
SENSITIVE_SUFFIXES = {".pem", ".p12", ".pfx", ".ed25519", ".key"}


def fail(message: str) -> None:
    raise SystemExit(f"Release security check failed: {message}")


def sensitive_name(name: str) -> bool:
    lower = name.lower()
    return lower in SENSITIVE_NAMES or lower.endswith(tuple(SENSITIVE_SUFFIXES))


def key_bytes(path: Path, private: bool) -> tuple[bytes, bytes]:
    if path.is_symlink() or not path.is_file():
        fail("a signing key is missing or is a symbolic link")
    metadata = path.stat()
    if metadata.st_uid != os.getuid():
        fail("a signing key is not owned by the current user")
    if private and metadata.st_mode & (stat.S_IRWXG | stat.S_IRWXO):
        fail("the private signing key has group or other permissions")
    if private and (path.resolve().is_relative_to(ROOT) or path.parent.stat().st_mode & (stat.S_IRWXG | stat.S_IRWXO)):
        fail("the private signing key or its directory is not isolated from the repository")
    encoded = path.read_bytes().strip()
    try:
        decoded = base64.b64decode(encoded, validate=True)
    except ValueError:
        fail("a signing key is not valid base64")
    if len(decoded) != 32:
        fail("a signing key is not 32 bytes")
    return encoded, decoded


def scan_stream(handle, forbidden: tuple[bytes, ...]) -> None:
    overlap = b""
    while True:
        chunk = handle.read(1024 * 1024)
        if not chunk:
            return
        data = overlap + chunk
        if any(token in data for token in forbidden):
            fail("private signing material was found in staged or packaged content")
        overlap = data[-128:]


def git_files(flag: str) -> list[str]:
    result = subprocess.run(
        ["git", flag, "-z"] if flag == "ls-files" else
        ["git", "diff", "--cached", "--name-only", "-z", "--diff-filter=ACMR"],
        cwd=ROOT, check=True, capture_output=True,
    )
    return [os.fsdecode(value) for value in result.stdout.split(b"\0") if value]


def scan_git(forbidden: tuple[bytes, ...]) -> None:
    paths = set(git_files("ls-files")) | set(git_files("diff"))
    for path in paths:
        if sensitive_name(Path(path).name) or "EasyFlowSigning" in Path(path).parts:
            fail("a private-key path is tracked or staged")
        staged = subprocess.run(["git", "show", f":{path}"], cwd=ROOT, capture_output=True)
        if staged.returncode == 0:
            if any(token in staged.stdout for token in forbidden):
                fail("private signing material is staged in Git")


def scan_app(app: Path, forbidden: tuple[bytes, ...]) -> None:
    if not app.is_dir():
        fail("the app bundle is missing")
    for path in app.rglob("*"):
        if path.is_symlink() or sensitive_name(path.name):
            fail("the app bundle contains a link or private-key file")
        if path.is_file():
            with path.open("rb") as handle:
                scan_stream(handle, forbidden)


def scan_archive(archive: Path, forbidden: tuple[bytes, ...]) -> None:
    if archive.name != "EasyFlow.zip" or not zipfile.is_zipfile(archive):
        fail("the distribution archive is missing or invalid")
    with zipfile.ZipFile(archive) as bundle:
        for member in bundle.infolist():
            if sensitive_name(Path(member.filename).name) or member.file_size > 250 * 1024 * 1024:
                fail("the archive contains a private-key file or oversized entry")
            if not member.is_dir():
                with bundle.open(member) as handle:
                    scan_stream(handle, forbidden)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--private", type=Path, default=DEFAULT_KEYS / "update-private-key.txt")
    parser.add_argument("--public", type=Path, default=DEFAULT_KEYS / "update-public-key.txt")
    parser.add_argument("--app", type=Path)
    parser.add_argument("--archive", type=Path)
    args = parser.parse_args()
    encoded_private, raw_private = key_bytes(args.private, private=True)
    key_bytes(args.public, private=False)
    forbidden = (encoded_private, raw_private)
    scan_git(forbidden)
    if args.app:
        scan_app(args.app, forbidden)
    if args.archive:
        scan_archive(args.archive, forbidden)
    print("Release secret preflight passed; no private signing material was found.")


if __name__ == "__main__":
    main()
