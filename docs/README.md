# EasyFlow documentation

[EasyFlow](../README.md) keeps quick notes, active tasks, and task context at the edge of your Mac desktop. This index separates everyday help from the technical contracts behind the app.

## Start using EasyFlow

| Guide | What you will find |
| --- | --- |
| [Installation](INSTALLATION.md) | Download, first launch, permissions, updates, and removal. |
| [User guide](USER_GUIDE.md) | Capture, tasks, Steps, images, keyboard controls, and Settings. |
| [Troubleshooting](TROUBLESHOOTING.md) | Hidden panels, multiple displays, sync, updates, and local data. |
| [Release notes](releases/README.md) | Changes and version-specific installation information. |
| [A note from the creator](../README.md#a-note-from-the-creator) | The motivation, product work, and role of AI in building EasyFlow. |

## Build and understand the app

| Document | Responsibility |
| --- | --- |
| [Contributor guide](../CONTRIBUTING.md) | Local setup, relevant checks, documentation, and website maintenance. |
| [Product specification](../PRODUCT_SPEC.md) | Product scope, durable principles, and current behavior. |
| [UX behavior](UX_BEHAVIOR.md) | Exact interactions, focus, panel transitions, and draft safety. |
| [Architecture](ARCHITECTURE.md) | Native services, source layout, lifecycle, and implementation boundaries. |
| [Data model](DATA_MODEL.md) | Local identity, storage, migrations, ordering, and deletion. |
| [Apple Reminders sync](REMINDERS_SYNC.md) | Data ownership, authorization, reconciliation, and failure handling. |
| [Signed updates](UPDATES.md) | Build channels, artifact verification, signing, and release procedure. |
| [Accessibility audit](ACCESSIBILITY_AUDIT.md) | Dated findings, validation evidence, and manual checks. |
| [Agent contract](../AGENTS.md) | Repository rules for agents and contributors. |

The product specification and subsystem contracts define behavior. User guides explain that behavior; release notes and the accessibility audit record history rather than replacing the current contracts.

## Key terms

| Term | Meaning |
| --- | --- |
| Main Panel | The edge panel containing capture, active tasks, Recently Completed, and Settings. |
| Secondary Panel | One contextual panel immediately inward, reused for notes or task details. |
| Quick Note | A captured note in the inbox, with text, images, or both. |
| Main Task | An active piece of work; only its title, completion, and existence synchronize. |
| Step | A one-level action inside a Main Task; completed Steps remain in position. |
| Attached Note | A note moved from the inbox into a Main Task, preserving its identity and content. |
| Effort | A local estimate from 1 to 4. Position, rather than effort, expresses priority. |

[Back to EasyFlow](../README.md)
