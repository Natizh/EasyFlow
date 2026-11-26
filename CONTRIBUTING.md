# Contribute to EasyFlow

[Project overview](README.md) · [Documentation index](docs/README.md) · [Agent contract](AGENTS.md)

EasyFlow is a native macOS utility built with SwiftUI, AppKit, EventKit, and SQLite through GRDB. Start with the [product specification](PRODUCT_SPEC.md), then read the relevant subsystem contract before changing behavior. The [creator's note](README.md#a-note-from-the-creator) explains the project's origin and use of AI.

## Build and run

Use **macOS 14+** and a **Swift 6** toolchain through Xcode or Apple's Command Line Tools. If the tools are missing, run `xcode-select --install` and ensure the selected developer directory provides Swift 6.

```sh
git clone https://github.com/Natizh/EasyFlow.git
cd EasyFlow
swift build
swift test
```

To build a release-mode development app, install it, and launch it:

```sh
./scripts/install.sh
```

The installer uses `/Applications` when writable and otherwise `~/Applications`. It waits for the running app to quit and save, verifies the replacement, and retains the previous app for rollback. This is a real local installation, not an isolated test. For bundle inspection without installation, use `./scripts/build-dev-app.sh` or `./scripts/package-release.sh`.

All of those paths produce the **development** update channel. A development build cannot install public updates in-app. See [signed updates](docs/UPDATES.md) for public packaging and the separate, explicitly approved release procedure. Pushing a tag does not publish an app release.

## Keep changes focused

Preserve unrelated work and use a bounded branch for substantial changes. Follow the native stack and the documented local-data/Reminders boundary. Product behavior belongs in the [specification](PRODUCT_SPEC.md); update the [UX](docs/UX_BEHAVIOR.md), [architecture](docs/ARCHITECTURE.md), [data](docs/DATA_MODEL.md), or [sync](docs/REMINDERS_SYNC.md) contract when the implementation changes it.

Do not commit local databases, live Reminder data, task/note content, credentials, or private signing keys. Use temporary data and protocol-backed fakes for tests. Verify licensing before reusing external code.

## Validate a change

| Change | Checks |
| --- | --- |
| Swift implementation | `swift build`, `swift test`, and focused tests for changed behavior. |
| Persistence or sync | Migration, ordering, lifecycle, and fake Reminders reconciliation tests as applicable. |
| Panels, focus, or native controls | Repeatable manual checks on macOS: pointer, keyboard, fullscreen, Spaces, and relevant VoiceOver paths. |
| Documentation or website | `git diff --check`, relative links and anchors, shared assets, and desktop/mobile rendering. |
| Release packaging | Bundle/artifact validation and the manual gates in [UPDATES.md](docs/UPDATES.md). |

Linux cannot build or exercise the AppKit/SwiftUI app. GitHub's macOS CI runs the app build, tests, and development packaging; do not describe local native verification as passed when it was unavailable. The [accessibility audit](docs/ACCESSIBILITY_AUDIT.md) supplies detailed native regression procedures.

## Maintain the website and visuals

The public landing page is static HTML/CSS in [`website/`](website/index.html). GitHub Pages publishes it after relevant changes reach `main`; no JavaScript framework or package installation is required.

[`assets/brand/`](assets/brand/README.md) is the source of shared visuals for the README, guides, and website. The Pages workflow copies that folder to the published site's `assets/brand/` path. Use relative image URLs on the website so a deployment serves the matching assets from its own commit. Update the shared source once, rather than maintaining a separate website copy.

Keep illustrations explicitly labeled as illustrations. Real app screenshots should use non-private sample content and identify the relevant version or appearance. Update both the README and website if their content or visual framing changes.

## Propose and report

Explain the concrete behavior a change fixes and the checks performed in a pull request. For bugs, include version/build, macOS version, reproducible steps, and any display/Spaces details. Use [GitHub issues](https://github.com/Natizh/EasyFlow/issues) for reports and proposals; keep private content out of attachments.
