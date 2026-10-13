#!/bin/zsh
set -euo pipefail

repository_root="${0:A:h:h}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  print -u2 -r -- "EasyFlow can only be built and installed on macOS."
  exit 1
fi

if ! command -v swift >/dev/null 2>&1 || ! command -v xcrun >/dev/null 2>&1; then
  cat >&2 <<'EOF'
Apple's developer command-line tools are required to build EasyFlow.

Install them with:
  xcode-select --install

Then run ./scripts/install.sh again.
EOF
  exit 1
fi

if [[ $# -gt 1 ]]; then
  print -u2 -r -- "Usage: ./scripts/install.sh [path/to/EasyFlow.app]"
  exit 1
fi
if [[ $# -eq 1 ]]; then
  source_app="${1:A}"
else
  "$repository_root/scripts/build-release-app.sh"
  source_app="$repository_root/.build/release-app/EasyFlow.app"
fi
"$repository_root/scripts/verify-release-app.sh" "$source_app"

if [[ ! -d "$source_app" ]]; then
  print -u2 -r -- "EasyFlow.app was not produced."
  exit 1
fi

swift -e 'import AppKit
let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.natizh.easyflow")
for app in apps { _ = app.terminate() }
for _ in 0..<300 {
  if NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.natizh.easyflow").isEmpty { exit(0) }
  Thread.sleep(forTimeInterval: 0.1)
}
fputs("EasyFlow is still running. Installation stopped to protect pending saves.\n", stderr)
exit(1)'

if [[ -w /Applications ]]; then
  destination="/Applications/EasyFlow.app"
else
  mkdir -p "$HOME/Applications"
  destination="$HOME/Applications/EasyFlow.app"
fi

if [[ "$source_app" == "$destination" ]]; then
  print -u2 -r -- "Source and installation destination must differ."
  exit 1
fi
if [[ -e "$destination" ]]; then
  if [[ ! -d "$destination" ]] || \
    [[ "$(plutil -extract CFBundleIdentifier raw "$destination/Contents/Info.plist" 2>/dev/null)" != "io.github.natizh.easyflow" ]]; then
    print -u2 -r -- "Destination is not a verified EasyFlow app. Installation stopped."
    exit 1
  fi
fi

destination_parent="${destination:h}"
staging_directory="$(mktemp -d "$destination_parent/.easyflow-install.XXXXXX")"
staged_app="$staging_directory/EasyFlow.app"
backup="$destination.rollback-$(date +%Y%m%d-%H%M%S)-$$"
function restore_on_failure() {
  local exit_code=$?
  if [[ $exit_code -ne 0 && -d "$backup" ]]; then
    if [[ -d "$destination" ]]; then mv "$destination" "$staging_directory/failed-EasyFlow.app"; fi
    mv "$backup" "$destination"
    print -u2 -r -- "Previous EasyFlow restored: $destination"
  fi
  rm -rf "$staging_directory"
}
trap restore_on_failure EXIT

ditto "$source_app" "$staged_app"
codesign --verify --deep --strict "$staged_app"
if [[ -d "$destination" ]]; then mv "$destination" "$backup"; fi
mv "$staged_app" "$destination"
codesign --verify --deep --strict "$destination"

print -r -- "Installed EasyFlow: $destination"
if [[ -d "$backup" ]]; then print -r -- "Previous app retained for rollback: $backup"; fi

if [[ "${EASYFLOW_INSTALL_NO_OPEN:-0}" != "1" ]]; then
  open "$destination"
fi
