# Troubleshooting

[Documentation](README.md) · [Installation](INSTALLATION.md) · [User guide](USER_GUIDE.md)

## I launched EasyFlow but cannot find a window

EasyFlow normally has no Dock icon, menu-bar item, or persistent window. Hold the pointer at the far-right outer desktop edge for about 300 ms. If you selected Left previously, use the far-left edge instead. You can also reopen EasyFlow through Finder or Spotlight to reveal the workspace.

On multiple displays, use the outer edge of the leftmost or rightmost display selected by Panel Side. Edges between two displays do not activate it. Review macOS display arrangement if the physical and configured order differ.

## macOS blocks the app

The community build is ad-hoc signed and not Apple notarized. Obtain it from the official [GitHub Releases](https://github.com/Natizh/EasyFlow/releases) and follow [first-launch confirmation](INSTALLATION.md#first-launch-and-macos-security). Do not disable macOS security globally.

## Apple Reminders is not synchronizing

1. Check EasyFlow's Reminders status in Settings.
2. Check **System Settings → Privacy & Security → Reminders** and allow EasyFlow if you want synchronization.
3. Open Apple Reminders and inspect the dedicated **EasyFlow** list. Changes in other lists are outside the sync boundary.
4. If setup reports ambiguity, inspect duplicate writable lists named EasyFlow. Resolve their names deliberately after reviewing their contents; EasyFlow does not guess which list owns your work.
5. For propagation to another device, check that the list belongs to a syncing account and allow time for that account to synchronize.

The local workspace remains available when permission is denied or the external store is unavailable. Avoid deleting lists or resetting local storage as a repair shortcut. See [reconciliation and failure handling](REMINDERS_SYNC.md) for the exact rules.

## Notes or effort do not appear on my iPhone

Only Main Task title, completion, and existence synchronize with Apple Reminders. Quick Notes, images, Descriptions, Steps, task order, effort, and styling stay on the Mac. This is the intended boundary; Apple Reminders does not back up the full workspace.

## A completed task will not come back

The current version has no restore or uncomplete action. Uncompleting its Apple Reminder does not reactivate the EasyFlow task. Recently Completed shows the five most recent completions without deleting older completed records.

## An update will not install

| What you see | What to do |
| --- | --- |
| An older build without in-app updates | Manually install v1.5.0 or a newer public release first. |
| A development build | Rebuild from source or manually install a public build; public in-app installation is unavailable in this channel. |
| Network or GitHub rate-limit error | Keep using the installed app and try a manual check later. |
| Release visible without an install action | A public update needs the ZIP and both signed metadata assets. Use the official release's manual installation instructions. |
| Verification failure | Keep the installed app and report the version and exact error; do not bypass signature verification. |
| Read-only or non-writable installation | Follow the verified manual-install path, then replace the app in Applications after quitting. |

Updates replace the app bundle, not workspace data or Reminders. App update signatures and Apple's first-launch security confirmation are separate checks. See [signed updates](UPDATES.md).

## Where is my data and how can I back it up?

The workspace database and images are stored in:

```text
~/Library/Application Support/EasyFlow/
```

The database is `EasyFlow.sqlite`; local image files are in `Attachments/`. Preferences also live in macOS UserDefaults, outside that folder. Apple Reminders holds its own synchronized Main Task core.

There is no in-app full-workspace backup/restore flow. For a manual copy of the local database and attachments, **quit EasyFlow through Settings first**, then copy the entire EasyFlow Application Support folder, including any SQLite companion files. Back up macOS preferences separately if needed, or use a full Mac backup. Copying only the app or relying on Apple Reminders does not preserve all workspace context.

Do not delete or replace the live database to fix a problem. A manual restore also needs care because synchronization can reconcile restored task state with current Reminders data.

## Report a problem

Open a [GitHub issue](https://github.com/Natizh/EasyFlow/issues) with:

- EasyFlow version/build and macOS version;
- steps to reproduce, expected behavior, and what happened;
- panel side, display arrangement, and whether fullscreen or Spaces are involved;
- whether it happens using the pointer, keyboard, or VoiceOver;
- the exact error text, if available.

Use example content in screenshots and redact private task/note text. Do not attach your database, Reminder data, or signing keys.
