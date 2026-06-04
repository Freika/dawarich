# Security Scanning

Automated security scanning runs in GitHub Actions on every pull request, every
push to `master` and `dev`, and on a weekly schedule (Mondays). All third-party
actions are pinned to a commit SHA. No secrets beyond the built-in `GITHUB_TOKEN`
are required.

Findings from the SARIF-producing scanners land in the repository **Security →
Code scanning** tab, grouped by category.

## Workflows

| Workflow | Job | Tool | Catches | Gate |
|----------|-----|------|---------|------|
| `security.yml` | `brakeman` | Brakeman | Rails SAST (SQLi, XSS, mass assignment, unsafe redirects, etc.) | Report-only |
| `security.yml` | `bundler-audit` | bundler-audit | Known-vulnerable gems in `Gemfile.lock` (advisory DB refreshed in-job) | **Blocking** |
| `security.yml` | `semgrep` | Semgrep (`p/ruby`, `p/rails`, `p/secrets`, `p/owasp-top-ten`) | SAST + secret patterns | Report-only |
| `security.yml` | `gitleaks` | gitleaks | Secrets in the PR/push diff | **Blocking** |
| `trivy.yml` | `image` | Trivy (image) | OS/library CVEs in the built Docker image (fixable HIGH/CRITICAL) | Report-only |
| `trivy.yml` | `config` | Trivy (config) | Dockerfile / IaC misconfigurations | Report-only |

**Report-only** jobs always pass; their findings still upload to the Security tab.
This is intentional for the first pass — gather signal before gating merges.
To gate on them later, remove the `continue-on-error: true` step (Brakeman /
Semgrep / Trivy config) or set the Trivy `image` scan `--exit-code 1`.

**Trivy image scan:** reports HIGH/CRITICAL CVEs that have a fix available
(`--ignore-unfixed`). Runs from the pinned `ghcr.io/aquasecurity/trivy` container
against the locally built image. Set `--exit-code 1` to make fixable
HIGH/CRITICAL CVEs block merges.

Dependency and base-image freshness is handled by Dependabot
(`.github/dependabot.yml`): weekly PRs for `bundler`, the Docker base image
(`/docker`), and GitHub Actions versions (which keeps the SHA pins current).

## Full git-history secret scan (run locally)

The CI `gitleaks` job scans only the PR/push **diff**. Because this repository is
public, a secret committed years ago remains exposed even if later removed — so
scan the **entire history** locally with:

```bash
docker run --rm -v "$(pwd):/repo" -w /repo \
  ghcr.io/gitleaks/gitleaks:latest \
  detect --source=. --redact -v
```

To produce a report file for triage:

```bash
docker run --rm -v "$(pwd):/repo" -w /repo \
  ghcr.io/gitleaks/gitleaks:latest \
  detect --source=. --redact --report-format sarif --report-path gitleaks-history.sarif
```

Confirmed historical hits should be **rotated** (assume exposed), then optionally
suppressed from future runs via a `.gitleaks.toml` allowlist keyed on the
finding fingerprint.

## Running the scanners locally

```bash
bundle exec brakeman --no-progress          # Rails SAST
bundle exec bundle-audit update && bundle exec bundle-audit check   # vulnerable gems
pip install semgrep && semgrep scan --config p/ruby --config p/rails --config p/secrets --config p/owasp-top-ten
docker build -f docker/Dockerfile -t dawarich:scan . && trivy image --ignore-unfixed --severity HIGH,CRITICAL dawarich:scan
trivy config .                               # Dockerfile / IaC misconfig
```
