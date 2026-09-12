# Family history sharing contract

`PATCH /api/v1/families/sharing` accepts `history_before_sharing` (boolean).
Explicit true plus enabled history opens the selected rolling window, independent
of the sharing start date. Missing consent retains the prior policy. Disabling
history or all sharing clears consent. All windows retain plan and one-year caps.

`GET /api/v1/families/mine` advertises `history_before_sharing_supported`;
own sharing includes `history_before_sharing`. Members include `share_history`,
`history_window`, `history_before_sharing` and `sharing_started_at`. These fields
explain effective access without exposing additional location data.

For example, a member who restarted sharing today can explicitly grant access to
the last seven days. Yesterday's points then become available when the recipient
selects yesterday. Without that consent, access remains limited by the sharing
start date. Dates outside the selected rolling window remain inaccessible.

## Rollout

Companion mobile PR: https://github.com/dawarich-app/multiplatform-app/pull/123

No database migration or new environment configuration is required. Existing
history access is not expanded without explicit consent. The mobile changes can
ship first; the earlier-history confirmation is capability-gated until this server
is deployed. Member labels distinguish location only, location plus history and
legacy history restricted by the sharing start date.

Request specs verify real points before and after consent, rolling-window limits,
metadata, revocation, and re-enabling without prior consent. Existing family
services and permissions continue to constrain access.
