# Signed GitHub updates

[Documentation](README.md) · [Product specification](../PRODUCT_SPEC.md) · [Contributor guide](../CONTRIBUTING.md)

EasyFlow checks the public GitHub Releases `latest` endpoint for stable releases. The endpoint excludes drafts and prereleases; EasyFlow also checks those flags and compares numeric `major.minor.patch` versions before offering anything. Automatic checks are enabled by default in public builds, start about ten seconds after launch when due, and run at most once per 24 hours while the app remains open. Manual checks are always available in Settings. A GitHub rate limit or network error leaves the installed app untouched.

## Trust and limitations

The updater does not use Sparkle, a server, or a Developer ID. Each public updater build pins a 32-byte Ed25519 public key in its `Info.plist`. Three assets are required for an in-app update:

- `EasyFlow.zip`: the ad-hoc-signed app bundle;
- `EasyFlow.update.json`: repository, semantic version, bundle ID, archive name, byte length, and SHA-256;
- `EasyFlow.update.sig`: Ed25519 signature over the exact JSON bytes.

EasyFlow verifies the signature against its pinned key, checks the archive hash and size, validates ZIP paths, extracts only the expected app, checks its bundle ID, version, executable, build channel, and code-signing integrity, then permits replacement. The helper repeats verification after the main app quits. An unsigned release or one missing any asset is visible in Settings but cannot install itself. GitHub's asset digest alone does not establish authenticity.

The first updater-enabled public release must be installed manually by users of older releases. That manually obtained app establishes the pinned-key trust chain for later updates. With ad-hoc signing, macOS cannot independently authenticate EasyFlow's publisher as it could with a Developer ID; users should obtain that first app from the official `Natizh/easyflow` release and verify the published key through a trusted maintainer channel. A compromised signing key requires a new manually installed trust bootstrap; do not silently rotate the pinned key through an update signed by an unknown key.

## Development builds

`scripts/build-dev-app.sh`, `scripts/build-release-app.sh`, `scripts/package-release.sh`, and `scripts/install.sh` produce or install explicit `development`-channel bundles. Such builds never schedule automatic GitHub checks and cannot invoke the in-app installer. Manual checking can inspect the UI without installing a public version. The channel is stored in `EasyFlowBuildChannel`, separate from the displayed version. A public bundle requires a valid pinned key and is prepared only by `scripts/build-public-update-app.sh`.

Development Settings includes a `Preview Update UI` menu for deterministic Available, 50% Downloading, Error, and Reset states. It uses no network and cannot install its fixture. This lets the maintainer inspect the update interface before publishing any release.

Public Settings omits the preview menu, all development explanations, and the entire Fullscreen Diagnostics section. The release gate renders Settings with the packaged public bundle identity and checks the resulting view for functional update controls and absence of development controls:

```sh
EASYFLOW_PUBLIC_APP_FIXTURE=.build/public-app/EasyFlow.app swift test --filter SettingsPresentationTests
```

## Maintainer key setup — manual, before the first public updater release

Do this yourself on a trusted Mac with FileVault enabled. **Do not ask an agent to generate or publish the production private key.** From the EasyFlow repository, run:

```sh
swift scripts/create-update-keypair.swift "$HOME/Library/Application Support/EasyFlowSigning"
```

The script refuses to overwrite keys. Keep `update-private-key.txt` readable only by your account, backed up offline in at least one separate encrypted location. Never commit it, place it in CI secrets, attach it to a GitHub release, or share it in chat. The public file can be reviewed and published. Record its fingerprint in your release notes or another maintainer-controlled channel. If the private key is lost, existing apps cannot trust future updater artifacts automatically.

Once provisioned, **do not rerun the key-generation command**. Release scripts discover `update-private-key.txt` and `update-public-key.txt` in `~/Library/Application Support/EasyFlowSigning/` automatically. The directory must remain outside Git and private permissions must remain `0700` for the directory and `0600` for the private file. `scripts/check-release-secrets.py` scans Git's index and distributable app/ZIP contents before signing; packaging stops if the private key or a sensitive credential file is staged or packaged. `.gitignore` adds matching rules as defense in depth.

## Prepare a future public release

Only after local testing and the maintainer's explicit release approval:

1. Set `CFBundleShortVersionString` and `CFBundleVersion` in `Support/Info.plist` for the approved release. Ensure the version is strictly newer than the latest published stable release.
2. Run `swift build`, `swift test`, and the manual macOS GUI checks. Keep the production workspace and Reminders data out of build artifacts.
3. Run `./scripts/package-public-update.sh`. The script uses the existing keys at the default path, creates a public-channel ad-hoc-signed app, `dist-public/EasyFlow.zip`, and the two signed metadata assets. It checks that the public key matches the private key without printing the latter. For keys stored elsewhere, pass explicit private and public paths in that order: `./scripts/package-public-update.sh /secure/private-key.txt /secure/public-key.txt`. `build-public-update-app.sh`, `sign-update.swift`, and `verify-update-artifact.swift` likewise use the default directory when key arguments are omitted.
4. Inspect the archive, bundle version/channel, signature, checksum, and release notes. Test a signed update and a tampered archive against isolated disposable installations. Run `./scripts/test-isolated-updater.sh` to exercise the actual helper with disposable keys and apps under `/private/tmp`. Confirm relaunch, rollback retention, and data preservation. The helper test does not launch the production app or access its workspace.
5. Manually create the GitHub Release only after approval, attaching **all three** assets. Example: `gh release create vX.Y.Z dist-public/EasyFlow.zip dist-public/EasyFlow.update.json dist-public/EasyFlow.update.sig --repo Natizh/easyflow --title "EasyFlow vX.Y.Z" --notes-file /path/to/approved-notes.md`. This command is documentation, not an instruction to run it during local development.

The old `dist/EasyFlow.zip` made by `scripts/package-release.sh` is a development-channel CI artifact and must not be uploaded as a signed updater release. The release workflow has no automatic publishing step or private-key access. A tag alone does not publish anything.

## User installation and recovery

Settings shows the installed version, automatic-check preference, manual check, release notes, and an Install Update action only when all signed assets are present in a public build. Later suppresses the same update indicator until a different version appears. The app never opens panels or steals focus just because a check finds an update.

After the user chooses Install Update, EasyFlow downloads into a private temporary directory, verifies the signature and checksum, and starts a copy of its own trusted helper mode. Normal application termination flushes pending edits; the helper waits for the old process to exit. For a writable installed `.app`, it stages and verifies the new bundle beside the destination, moves the old bundle to a retained rollback path, replaces it, verifies again, and relaunches. The helper restores the old app if replacement or validation fails. It never deletes the SQLite database, attachments, preferences, or Reminders data.

If the app is translocated, on a read-only volume, or in a location the current user cannot modify, EasyFlow reveals the verified app in Finder for manual replacement. It never silently requests administrator privileges or bypasses Gatekeeper. A newly downloaded ad-hoc-signed version may require the normal macOS first-launch confirmation. Test these Finder and Gatekeeper paths on a real Mac before publishing.

## Local validation without production keys

Use disposable test keys and a temporary installation path. A fixture release JSON can drive the Settings state; the automated suite uses temporary Ed25519 keys and mock network responses. To exercise packaging scripts, create a **disposable** key pair in a temporary directory, sign a local archive, verify it, then delete the temporary keys and artifacts. Do not use the real `/Applications/EasyFlow.app` or production Application Support directory for destructive replacement tests. Verify the installed development build reports the development channel and never auto-installs the current public release.

## References and licensing

The behavior and interaction sequence were informed by the publicly visible [Vorssaint updater](https://github.com/vorssaint/vorssaint-utils/blob/main/Sources/Vorssaint/Services/Update/UpdateService.swift). Vorssaint's repository is [GPL-3.0-or-later](https://github.com/vorssaint/vorssaint-utils/blob/main/LICENSE); no Vorssaint source was copied or adapted. EasyFlow's implementation is independent and remains MIT. GitHub's [latest-release API documentation](https://docs.github.com/en/rest/releases/releases#get-the-latest-release) defines the stable-release endpoint used here.
