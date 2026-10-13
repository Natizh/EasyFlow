#!/bin/zsh
set -euo pipefail

repository_root="${0:A:h:h}"
default_key_directory="$HOME/Library/Application Support/EasyFlowSigning"
if [[ $# -gt 2 ]]; then
  print -u2 -r -- "Usage: package-public-update.sh [private-key-file] [public-key-file]"
  exit 1
fi
private_key_file="${1:-$default_key_directory/update-private-key.txt}"
public_key_file="${2:-$default_key_directory/update-public-key.txt}"
dist_directory="${EASYFLOW_DIST_DIR:-$repository_root/dist-public}"
app="$repository_root/.build/public-app/EasyFlow.app"

python3 "$repository_root/scripts/check-release-secrets.py" \
  --private "$private_key_file" --public "$public_key_file"
"$repository_root/scripts/build-public-update-app.sh" "$public_key_file" "$private_key_file"
mkdir -p "$dist_directory"
archive="$dist_directory/EasyFlow.zip"
rm -f "$archive" "$dist_directory/EasyFlow.update.json" "$dist_directory/EasyFlow.update.sig"
ditto -c -k --keepParent "$app" "$archive"
python3 "$repository_root/scripts/check-release-secrets.py" \
  --private "$private_key_file" --public "$public_key_file" --app "$app" --archive "$archive"
version="$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")"
swift "$repository_root/scripts/sign-update.swift" \
  "$private_key_file" "$public_key_file" "$archive" "$version" "$dist_directory"
swift "$repository_root/scripts/verify-update-artifact.swift" \
  "$public_key_file" "$archive" "$dist_directory/EasyFlow.update.json" \
  "$dist_directory/EasyFlow.update.sig" "$version"
python3 "$repository_root/scripts/check-release-secrets.py" \
  --private "$private_key_file" --public "$public_key_file" --app "$app" --archive "$archive"
print -r -- "Signed update assets prepared locally in: $dist_directory"
