# Standalone sharing consent negotiation

The sharing browser helper registers an owner, signs in, then PATCHes
`/settings/changelog_consent` with form body `decision=declined` and the session's
`X-CSRF-Token`. Playwright's request API supplies `Accept: */*` when the helper
omits an explicit Accept header. Rails selects the first declared response
format, Turbo stream, for that wildcard.

`SettingsMiscActions` uses the existing `PageAccept.formats/2` and
`PageAccept.negotiate/2` with Rails' declaration order: Turbo stream, then HTML.
The same parser already serves `PageEnvelope`, including calendar negotiation.
No parser, authentication, CSRF, ownership or lifecycle admission rule changes.

| Accept | Consent response |
| --- | --- |
| `*/*`, `*/*;q=0.5` | 200 Turbo stream; replaces version indicator and consent setting |
| Absent, empty, `text/html`, `text/*` | 302 HTML redirect back, falling back to home |
| HTML preferred by quality | 302 HTML redirect |
| Turbo preferred by quality | 200 Turbo stream |
| `text/vnd.turbo-stream.html, */*` without XHR | 302 HTML redirect under Rails' browser Accept rule |
| `application/json` | 406 after persisting a valid consent decision, matching Rails |

A missing application-level Accept option and a genuinely absent HTTP header
are distinct. Real Rails integration requests confirm that a genuinely absent
header redirects; it must not be normalized to wildcard.

Regression evidence lives in
`app-phoenix/test/dawarich_web/settings_consent_negotiation_test.exs`.
It covers the exact browser PATCH, ordered formats, form method override,
Turbo-Frame, session authentication and CSRF refusal. Each named test has a
recorded RED/GREEN/production-mutation/restored-GREEN cycle in the controller's
implementation report. Rails behavior is preserved; no Rails bug is fixed.
