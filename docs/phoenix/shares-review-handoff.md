# SHARES review corrections and HOT handoff

Source: A12f-3b Plan A, S03–S07; controller rulings 13–14. Review findings F1–F4 are covered by the named tests in `app-phoenix/test/dawarich_web/a12f3b_review_test.exs`.

## Effective form methods

`ShareManagementForm.admit/2` preserves `_method` until `ShareManagementMethod.action/2` selects the operation. Only form-encoded POST bodies override the verb. DELETE on the create path selects destroy; PATCH on the revoke path selects revoke. Incompatible overrides hand back before any mutation. JSON `_method` values do not override the POST action. The original request method and raw body remain available for Rails replay.

TrackShareRoutes and TimelineShareRoutes include POST revoke declarations for the generated forms. HOT must also mount `DawarichWeb.ShareManagementOverrideRoutes.routes()` after the existing `share_form` pipeline; its supplemental POST revoke declarations cover live, trip and shared-list forms. Existing A9Routes retains its ordinary routes.

HOT must retain the existing admission handoff: replace `plug DawarichWeb.RailsForm` in `share_form` with `plug :share_form_admission` and provide `defp share_form_admission(conn, opts), do: DawarichWeb.ShareManagementForm.admit(conn, opts)`. Keep Body and RailsAuth ahead of admission. Mount TrackShareRoutes and TimelineShareRoutes before fallback routes. Shared hot files remain HOT-owned; these declarations and the adapter are exercised through a test router with real Rails cookies and CSRF.

## JSON validation failure

Under ruling 13, invalid JSON create without `hub` preserves the characterized Rails HTML 500 (`ActionView::MissingTemplate`) after validation. It does not replay after effects. Existing failed-live-replacement ended-event behavior remains unchanged. A JSON request with `hub` retains the Turbo 422 validation response; valid JSON create retains its redirect. Deferred source fix: [DRB-020](deferred-rails-bugs.md).

## Flexible timeline dates

Rails accepts `Date.parse` strings such as month names, named dates and slash-separated dates. The native timeline parser supports ISO dates only. Non-ISO create ranges hand back before validation or mutation; existing shares with non-ISO ranges hand back before document rendering. Original settings remain unchanged. This is a deliberate compatibility boundary until a complete Rails-compatible date parser is available; it does not redefine supported source inputs or silently normalize stored settings.

## Resolved track locale

TrackShareActions resolves locale from the user preference and Rails session before reading the form. Read.track accepts that resolved locale, and mutation resource lookup receives the same locale used by create. Direct domain reads resolve the user preference. Padded German preferences and a German session without a user preference therefore produce the German label and default persisted name.

Canonical shared index: AFFiNE “Dawarich — Phoenix SHARES native management handoff” (`sTHXI_y0g2E7VcjM02YGf`). The controller's execution plans remain authoritative for integration, photo prerequisites and release acceptance.
