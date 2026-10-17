# Copilot issue triage

The workflow `.github/workflows/triage.yml` uses Copilot Triage v0.6.2 pinned
by commit. Project policy lives in `.github/triage.yml`. It labels issues,
answers from configured evidence, and suggests duplicates without closing them.
Pull requests are excluded. Existing reports are not automatically backfilled.

## Activation and verification

1. Add repository Actions secret `COPILOT_GITHUB_TOKEN`: a fine-grained token
   with Copilot Requests permission and available Copilot allowance. Never commit it.
2. Release both configuration files to `master`, the default branch. The action
   always reads configuration and sources from that branch, including previews.
3. Run `gh workflow run triage.yml --repo Freika/dawarich -f kind=issue -f number=NUMBER`.
   Manual runs always use dry-run: inspect the Actions job summary for labels,
   proposed replies, citations, and duplicate suggestions. They consume credits.
4. Preview several bug reports and feature requests before relying on automatic
   triage. Once present on the default branch, issue and discussion events run
   automatically. Verify the first live assessment and its published result.

The current labels are bug, documentation, enhancement, and question. Sources
include README, contributing guide, changelog, Markdown docs, and selected Rails
source directories. External documentation is not crawled. Logs and location
exports must be redacted before posting; the bot must not request private traces.

Ordinary follow-ups are selective. `/triage` requests reassessment;
`/triage mute` silences a conversation and maintainer-only `/triage unmute`
restores it. Failures are reported in job summaries. To stop all automatic
triage, disable the Copilot Triage workflow in Actions.

Rails and browser tests do not exercise this configuration-only integration;
verify YAML and workflow syntax locally, then use a Copilot-authenticated preview.
Shared engineering documentation: AFFiNE, “Dawarich — Copilot triage runbook”.
Upstream: https://github.com/marketplace/actions/copilot-triage
