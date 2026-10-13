#!/bin/zsh
set -euo pipefail

repository_root="${0:A:h:h}"
public_app="$repository_root/.build/public-app/EasyFlow.app"
"$repository_root/scripts/verify-release-app.sh" "$public_app"

test_directory="$(mktemp -d /private/tmp/easyflow-updater-e2e.XXXXXX)"
function cleanup() { rm -rf "$test_directory" }
trap cleanup EXIT

swift "$repository_root/scripts/create-update-keypair.swift" "$test_directory/keys"
test_public_key="$(tr -d '[:space:]' < "$test_directory/keys/update-public-key.txt")"
ditto "$public_app" "$test_directory/Updater.app"
plutil -replace EasyFlowUpdatePublicKey -string "$test_public_key" \
  "$test_directory/Updater.app/Contents/Info.plist"
codesign --force --deep --sign - "$test_directory/Updater.app"

cat > "$test_directory/stub.swift" <<'SWIFT'
import Foundation
let marker = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("launched.txt")
try? Data("isolated updater launch".utf8).write(to: marker, options: .atomic)
SWIFT
swiftc "$test_directory/stub.swift" -o "$test_directory/EasyFlow-stub"

function make_fixture_app() {
  local app="$1"
  local version="$2"
  mkdir -p "$app/Contents/MacOS"
  cp "$test_directory/EasyFlow-stub" "$app/Contents/MacOS/EasyFlow"
  cp "$repository_root/Support/Info.plist" "$app/Contents/Info.plist"
  plutil -replace CFBundleShortVersionString -string "$version" "$app/Contents/Info.plist"
  plutil -replace EasyFlowBuildChannel -string public "$app/Contents/Info.plist"
  plutil -replace EasyFlowUpdatePublicKey -string "$test_public_key" "$app/Contents/Info.plist"
  codesign --force --deep --sign - "$app"
}

old_app="$test_directory/installed/EasyFlow.app"
new_app="$test_directory/source/EasyFlow.app"
make_fixture_app "$old_app" "1.4.9"
make_fixture_app "$new_app" "1.5.0"
print -r -- "isolated workspace" > "$test_directory/installed/EasyFlow.sqlite"
mkdir -p "$test_directory/installed/Attachments"
print -r -- "isolated attachment" > "$test_directory/installed/Attachments/image.txt"

archive="$test_directory/EasyFlow.zip"
ditto -c -k --keepParent "$new_app" "$archive"
swift "$repository_root/scripts/sign-update.swift" \
  "$test_directory/keys/update-private-key.txt" \
  "$test_directory/keys/update-public-key.txt" \
  "$archive" 1.5.0 "$test_directory"
swift "$repository_root/scripts/verify-update-artifact.swift" \
  "$test_directory/keys/update-public-key.txt" "$archive" \
  "$test_directory/EasyFlow.update.json" "$test_directory/EasyFlow.update.sig" 1.5.0

python3 - "$test_directory" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
request = {
    "destinationPath": str(root / "installed/EasyFlow.app"),
    "archivePath": str(root / "EasyFlow.zip"),
    "manifestPath": str(root / "EasyFlow.update.json"),
    "signaturePath": str(root / "EasyFlow.update.sig"),
    "version": "1.5.0",
    "runningPID": 2147483647,
}
(root / "install-request.json").write_text(json.dumps(request))
PY

"$test_directory/Updater.app/Contents/MacOS/EasyFlow" \
  --easyflow-install-update "$test_directory/install-request.json" &
helper_pid=$!
for attempt in {1..240}; do
  if ! kill -0 "$helper_pid" 2>/dev/null; then break; fi
  sleep 0.25
done
if kill -0 "$helper_pid" 2>/dev/null; then
  kill "$helper_pid" 2>/dev/null || true
  print -u2 -r -- "Isolated helper timed out."
  exit 1
fi
wait "$helper_pid"

[[ "$(plutil -extract CFBundleShortVersionString raw "$old_app/Contents/Info.plist")" == "1.5.0" ]] || {
  print -u2 -r -- "Helper did not install the expected version."
  exit 1
}
rollback=("$test_directory"/installed/EasyFlow.app.rollback-*(N))
[[ ${#rollback} -eq 1 ]] || { print -u2 -r -- "Expected one rollback app."; exit 1; }
[[ "$(plutil -extract CFBundleShortVersionString raw "$rollback[1]/Contents/Info.plist")" == "1.4.9" ]] || {
  print -u2 -r -- "Rollback app has the wrong version."
  exit 1
}
[[ "$(cat "$test_directory/installed/EasyFlow.sqlite")" == "isolated workspace" ]] || {
  print -u2 -r -- "Isolated workspace file changed."
  exit 1
}
[[ "$(cat "$test_directory/installed/Attachments/image.txt")" == "isolated attachment" ]] || {
  print -u2 -r -- "Isolated attachment changed."
  exit 1
}
for attempt in {1..80}; do
  [[ -f "$test_directory/installed/launched.txt" ]] && break
  sleep 0.25
done
[[ -f "$test_directory/installed/launched.txt" ]] || {
  print -u2 -r -- "Updated app did not create its relaunch marker."
  exit 1
}
print -r -- "Isolated signed A-to-B helper update, relaunch, rollback retention, and data preservation passed."
