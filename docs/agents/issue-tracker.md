# Issue tracker

Dawarich uses **two** forges. Getting this wrong means silently missing work.

| Surface | Lives on | Tool |
| --- | --- | --- |
| Issues | GitHub (`Freika/dawarich`) | `gh` CLI |
| Pull requests | **self-hosted OneDev** (`https://onedev.dwri.xyz`, project `dawarich`) | OneDev REST API |
| Pull requests | GitHub — both maintainer branches and contributor forks | `gh` CLI |

⛔ The two PR pools **partially overlap, and neither contains the other**. Some branches are pushed to both forges and appear as a PR on each; most exist on only one. So triaging a single surface always leaves real, unreviewed PRs on the other — **check both, and de-duplicate by source branch name**, which is the reliable join key (OneDev `sourceBranch` ↔ GitHub `headRefName`).

Don't assume GitHub PRs are external-only: a large share are same-repo maintainer branches, not forks. Use `isCrossRepository` if you need to tell them apart.

To measure the current overlap rather than guessing:

```bash
TOKEN=$(security find-generic-password -s onedev-cli -a onedev.dwri.xyz -w)
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://onedev.dwri.xyz/~api/pulls?query=open&offset=0&count=200" \
  | python3 -c 'import sys,json;print("\n".join(sorted(p["sourceBranch"] for p in json.load(sys.stdin))))' > /tmp/od-branches
gh pr list --repo Freika/dawarich --state open --limit 200 --json headRefName \
  --jq '.[].headRefName' | sort > /tmp/gh-branches
comm -12 /tmp/od-branches /tmp/gh-branches   # on both forges
```

## Issues (GitHub)

- **Create**: `gh issue create --title "..." --body "..."` (heredoc for multi-line bodies).
- **Read**: `gh issue view <number> --comments`
- **List**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'`, plus `--label` / `--state` filters.
- **Comment**: `gh issue comment <number> --body "..."`
- **Label**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."` — only labels that exist; see `triage-labels.md`.
- **Close**: `gh issue close <number> --comment "..."`

`gh` infers the repo from the clone's remote.

## Pull requests (OneDev)

> OneDev is maintainer-only infrastructure. External contributors have no account there and open their PRs on GitHub instead; if that is your situation, skip the rest of this section. Skipping it does not make GitHub the whole picture — see the overlap note above.

Authenticate with a OneDev access token in `ONEDEV_TOKEN`:

```bash
TOKEN="${ONEDEV_TOKEN:?set ONEDEV_TOKEN to a OneDev access token}"
OD() { curl -s -H "Authorization: Bearer $TOKEN" "https://onedev.dwri.xyz/~api$1"; }
```

On the maintainer's macOS machine the token can be sourced from the Keychain instead:

```bash
export ONEDEV_TOKEN=$(security find-generic-password -s onedev-cli -a onedev.dwri.xyz -w)
```

- **List open PRs**: `OD "/pulls?query=open&offset=0&count=100"`
- **Resolve display number → internal id**: `OD "/pulls?query=%22Number%22%20is%20%22dawarich%23<n>%22&offset=0&count=1"` → `.[0].id`
- **Detail / comments / reviews**: `OD "/pulls/<id>"`, `OD "/pulls/<id>/comments"`, `OD "/pulls/<id>/reviews"`
- **Web URL**: `https://onedev.dwri.xyz/dawarich/~pulls/<number>`

⛔ Three traps: the API takes the internal `id`, never the display `number` — always resolve first. The resource is `/pulls`, not `/pull-requests` (404s). The `onedev` CLI wrapper mangles paths, so use `curl` as above.

`baseCommitHash` on the PR object **is** the merge-base, so the diff below is already the correct three-dot review diff — no `merge-base` computation needed.

```bash
git remote get-url onedev >/dev/null 2>&1 || git remote add onedev https://onedev.dwri.xyz/dawarich.git
git fetch onedev --quiet
git diff "<baseCommitHash>..onedev/<sourceBranch>"
```

The `git fetch` is required: `onedev/<sourceBranch>` is a remote-tracking ref and won't resolve until it has been fetched.

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

`gh issue view <number> --comments`.
