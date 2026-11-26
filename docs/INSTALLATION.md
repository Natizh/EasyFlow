# Install EasyFlow

[Documentation](README.md) · [User guide](USER_GUIDE.md) · [Troubleshooting](TROUBLESHOOTING.md)

EasyFlow requires **macOS 14 or later**. Standard and Frosted appearances are available on that baseline; Liquid Glass requires macOS 26. Reminders permission is optional for local use and required for Main Task synchronization.

## Download the app

1. Open the official [latest release](https://github.com/Natizh/EasyFlow/releases/latest).
2. Download **EasyFlow.zip** from its assets and double-click to extract it.
3. Drag **EasyFlow.app** to **Applications**.
4. Open it. EasyFlow runs without a Dock icon or menu-bar item.
5. Hold the pointer briefly at the far-right outer edge of your desktop. On multiple displays, this is the outer edge of the rightmost display, not an internal seam.

Use the workspace's Settings gear to select Left instead, adjust the panels, or enable **Launch at Login**.

## First launch and macOS security

The community app is **ad-hoc signed**, without an Apple Developer ID signature or Apple notarization. macOS can therefore block the first launch of a downloaded build.

After trying to open the app, go to **System Settings → Privacy & Security**, find the EasyFlow notice, and choose **Open Anyway**. Confirm the macOS prompt. Depending on the macOS version, Control-clicking the app in Finder and choosing **Open** may also offer a confirmation.

Only approve an app you obtained from the official repository. These steps use macOS's per-app confirmation; there is no need to disable Gatekeeper globally. A newly downloaded build may need confirmation again.

## Connect Apple Reminders

Allow access when EasyFlow asks if you want synchronization. EasyFlow creates a dedicated **EasyFlow** list when needed, or reuses exactly one suitable writable list of that name. You do not need to create it first.

If access is denied, notes and the local workspace remain usable. You can review access under **System Settings → Privacy & Security → Reminders**, then reopen EasyFlow and review its Reminders status in Settings.

Only Main Task **title, completion, and existence** synchronize. Notes, images, Descriptions, Steps, order, and effort stay local. A list in a syncing Reminders account can make the Main Task core available on other devices. See the [sync boundary](REMINDERS_SYNC.md).

## Update an existing installation

| Installed build | How to update |
| --- | --- |
| Older than v1.5.0 | Manually install v1.5.0 or a newer public release to establish the updater's trusted key. |
| Public v1.5.0 or later | Open Settings → Software Updates. Check for updates and choose Install Update when a verified release is available. |
| Local source/development build | Rebuild from source, or manually install a public release. Development builds cannot install public releases in-app. |

Public builds check GitHub quietly, about daily, when automatic checks are enabled. Installation requires your action. EasyFlow authenticates updater metadata with a pinned Ed25519 key and verifies the archive before replacement; this is separate from Apple Developer ID signing and notarization.

For manual replacement, quit EasyFlow through Settings, then replace the app in Applications with the freshly extracted app. Updates replace the app bundle, leaving workspace data and Apple Reminders in place. If the install location is read-only or cannot be modified by your user, the updater offers a verified manual-install path. See [update troubleshooting](TROUBLESHOOTING.md#an-update-will-not-install).

## Build from source

Use the [contributor setup](../CONTRIBUTING.md#build-and-run). Source builds require **Swift 6** and Apple's developer tools, in addition to macOS 14+; they use the development update channel.

## Quit or remove EasyFlow

Open the Settings gear and choose **Quit EasyFlow**. To remove the app, choose **Uninstall EasyFlow…**, then **Reveal App and Quit**, and move the revealed app to Trash. The uninstall aid deregisters Launch at Login and waits for pending edits to save.

Removing the app preserves workspace data, preferences, and Apple Reminders. It does not perform a data reset. See [local data and backup](TROUBLESHOOTING.md#where-is-my-data-and-how-can-i-back-it-up) before managing those files yourself.
