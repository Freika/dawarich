# Native Phoenix feature layout

Track B implementation, 2026-10-11. Milestone acceptance remains controller-owned. See [architecture context](native-frontend-context.md), [development](native-frontend-development.md) and [test successors](native-m7-test-retargets.md).

## Feature ownership

Surviving web adapters live under `app-phoenix/lib/dawarich_web/features/<feature>/`. Existing Elixir module names, route URLs, Scope interfaces, adjacent HEEx templates, PubSub subscriptions and browser hook identifiers stay unchanged.

| Task | Feature directories |
| --- | --- |
| B4a | accounts, settings, admin |
| B4b | imports, exports, notifications, families, sharing |
| B4c | points, places, tags, visits, stats, insights, digests, achievements, trips, maps, posters, videos |

HTTP API controllers remain under `dawarich_web/api`. Router/macros, generic HTTP/body/auth/session helpers, shared core components, layouts and chrome remain shared. Browser/build resources follow track A's layout. Domain contexts remain under `lib/dawarich`.

B2 resolves `.html` and `format=html` aliases to full native documents, preserving unrelated query parameters and guest return destinations. Frame and Turbo visit hints no longer select partial envelopes. Unsupported document formats refuse locally; genuine data/storage/wire negotiation retains its own contract. B3 dispatches requests directly through native admission, constraints and handlers. Unknown routes return local 404. Whole-app fallback packaging and runtime admission remain separate controller responsibilities.

## Domain utilities

Pure implementations belong to `Dawarich.Formatting` (translation/escaping, dates, times, numbers and stats), `Dawarich.Localization`, `Dawarich.Input.Params`/`UserZone`, `Dawarich.Settings.Input`, `Dawarich.Storage.BlobPath`/`UploadUrls`, `Dawarich.Trips.Itinerary` and `Dawarich.Sharing.UnlockToken`. Old web utility names delegate for compatibility with existing web callers; domain contexts call the actual domain implementations. Typed parameter errors, localized output, settings restrictions, itinerary encoding and share-proof hash bytes stay unchanged.

`Dawarich.NotFoundError` preserves the existing 404 status/message for domain Insights input errors. Web handlers retain their existing web exception where appropriate. Digest read closure consumes ordinary request-header data without constructing a Plug connection. Visits reads two-factor availability from the existing domain secret policy.

## Explicit infrastructure boundaries

The following retained adapters are infrastructure, rather than feature context presentation dependencies:

| Adapter | Contract and reason |
| --- | --- |
| `Dawarich.RuntimePolicy` | One temporary dependency adapter to the A-owned shared `LayoutAssigns.self_hosted?` primitive. It preserves the exact hosting policy until its shared owner extracts that primitive; it provides no routing or lifecycle fallback. |
| `Dawarich.Input.Upload` | Typed `Plug.Upload` input boundary used by imports and pending intake. Ordinary maps cannot impersonate an upload. Existing caller-specific errors remain unchanged. |
| `Dawarich.Cable.HTML` | Explicit external wire serializer for retained navbar/badge/recalculation/poster HTML. It invokes existing web components; event shape and HTML bytes remain the contract for unknown independent consumers. Native page delivery does not use these envelopes. `Dawarich.Cable.Frame` retains the external frame codec. |
| Insights `infrastructure/fragments.ex` | Legacy cached HTML renderer, physically located with web infrastructure; its existing `Dawarich.Insights.Fragments` module name remains for compatibility. |
| Application, Front and Front.Drainer | Endpoint/public-files/host boot configuration and graceful HTTP draining. Protected lifecycle/entrypoint admission is outside this task. |
| Metrics.Web, ErrorReporting and LogRedaction | Router telemetry classification, framework exception classification and safe connection redaction. |
| Auth.Admission, CredentialsClosure, ActionCsrf, SessionCookie, provider completion/failure and Apple callback/cookies | Real HTTP client-IP, cookie, CSRF, provider and session protocol boundaries. Existing security semantics remain. |
| Trial.Welcome and WelcomeSession | Welcome HTTP session and trusted client-IP boundaries; their formatting/localization now uses domain utilities. |
| Tiles.HTTP | Named HTTP tile transport adapter. |
| Subscriptions.Cache and AfterCommit.Worker | Existing RateLimit module identity is an opaque cache namespace, not a call to presentation logic. |

Business contexts do not import web formatting, parameter, settings projection, itinerary or proof functions. Infrastructure boundaries must stay explicit; a new context must not route through a web controller to obtain domain behavior.

## Verification and handoff

Serial family packets exercise real page/form/HTTP/admission/async behavior rather than synthetic file-layout assertions. Six async domain utility cases have assertion RED, GREEN, detected mutations and restored GREEN. Final B4c direct caller packet: 54 files, 318 passed, seed 404, warnings-as-errors; changed sources pass strict compilation and formatting. No browser, full-suite, packaging, resource or release acceptance is implied.

Two inherited stale test families remain for C/controller reconciliation: PublicLinkDelivery preparation/controller callbacks and FamilyNativeEvents milestone-4 controls consumed by the milestone-6 host. Their existing cases/fixtures are retained; current native delivery/command successors pass. Source-reader moves and exact test retargets are enumerated in the track B implementation report. The controller owns integrated ledger refresh, X4 packaging and X5 functional FULL GATE.

AFFiNE counterpart: **Dawarich — Native routing and feature boundary implementation (milestone 7 track B)**. The canonical milestone 7–8 mirror remains track C-owned.
