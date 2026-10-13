#!/bin/zsh
set -euo pipefail

repository_root="${0:A:h:h}"
default_key_directory="$HOME/Library/Application Support/EasyFlowSigning"
if [[ $# -gt 2 ]]; then
  print -u2 -r -- "Usage: build-public-update-app.sh [public-key-file] [private-key-file]"
  exit 1
fi
public_key_file="${1:-$default_key_directory/update-public-key.txt}"
private_key_file="${2:-$default_key_directory/update-private-key.txt}"
python3 "$repository_root/scripts/check-release-secrets.py" \
  --private "$private_key_file" --public "$public_key_file"
if [[ ! -f "$public_key_file" ]]; then
  print -u2 -r -- "Public verification key file was not found."
  exit 1
fi
public_key="$(tr -d '[:space:]' < "$public_key_file")"
python3 - "$public_key" <<'PY'
import base64, sys
try:
    assert len(base64.b64decode(sys.argv[1], validate=True)) == 32
except Exception:
    raise SystemExit('Expected a base64-encoded 32-byte Ed25519 public key')
PY

app="$repository_root/.build/public-app/EasyFlow.app"
EASYFLOW_APP_OUTPUT="$app" "$repository_root/scripts/build-dev-app.sh" release
plist="$app/Contents/Info.plist"
plutil -replace EasyFlowBuildChannel -string public "$plist"
plutil -replace EasyFlowUpdatePublicKey -string "$public_key" "$plist"
codesign --force --deep --sign "${EASYFLOW_SIGN_IDENTITY:--}" "$app"
"$repository_root/scripts/verify-release-app.sh" "$app"
python3 "$repository_root/scripts/check-release-secrets.py" \
  --private "$private_key_file" --public "$public_key_file" --app "$app"
print -r -- "Public-channel app prepared locally: $app"
