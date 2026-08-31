# Triage Labels

The engineering skills speak in terms of triage roles. This file maps those roles to the label strings that actually exist in this repo.

Verify the list before relying on it: `gh label list --repo Freika/dawarich --limit 200`.

| Role                        | Label in this repo | Meaning                                        |
| --------------------------- | ------------------ | ---------------------------------------------- |
| Needs maintainer evaluation | *(no label)*       | Untriaged = simply has no state label yet      |
| Waiting on reporter         | `question`         | Waiting on the reporter for more information   |
| Accepted, queued            | `planned`          | Accepted and scheduled for work                |
| Shipped                     | `implemented`      | Landed in a release                            |
| Will not be actioned        | `wontfix`          | Declined; `not planned` is the close reason    |

Kind labels, applied alongside the state label: `bug`, `enhancement`, `documentation`, `question`.
Area labels: `backend`, `ruby`, `javascript`, `docker`, `photos`, `Integration`, `HomeAssistant`, `synology`, `scratch-map`, `dependencies`, `github_actions`.

⚠️ The mapping is lossy: this repo has no dedicated triage-queue or agent-readiness labels, so "needs evaluation" is represented by the *absence* of a state label, and there is no way to mark an issue AFK-ready. Don't fabricate one.

⛔ This repo does not use a `needs-triage` / `needs-info` / `ready-for-agent` / `ready-for-human` vocabulary. Do not apply those names.

⚠️ Applying an unknown label is **not** a safe no-op. `gh issue edit --add-label` rejects a name the repo doesn't have, but the raw REST endpoint (`POST /repos/{owner}/{repo}/issues/{n}/labels`) **silently creates** it and applies it — permanently polluting the repo's label set. Never probe label existence by trying to apply one; read it with `gh label list` or `gh api repos/Freika/dawarich/labels/<name>` instead, and ask before creating any new label.
