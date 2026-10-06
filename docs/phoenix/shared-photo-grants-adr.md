# Shared photo grant context

Status: Accepted. Date: 2026-10-07.

AFFiNE counterpart: `kcLrxKCKEyl9xcbirP9V9`,
“Dawarich — ADR-20261007-shared-photo-grants — Bind thumbnail grants to current privacy and scope”.

## Context

S02 privacy review found that list filtering and ACL fingerprinting reread
privacy zones independently, permitting old visible IDs under a newly
expanded zone's key. Warm grants also omitted the effective resource window,
so editing a shared trip could leave excluded thumbnails accessible.
Rails memoizes zones within a request and avoids the first interleaving;
its window-blind grants reproduce the second defect (DRB-023).
The controller's review-fix brief explicitly authorizes a Phoenix privacy
correction even where Rails retains the leak.

## Decision

Resolve the owner's timezone, owner-scoped effective resource window and
privacy-zone snapshot once for grant construction. Use that same context
for provider search, filtering and the cache key. Every thumbnail request
resolves the current context before looking up or constructing its grant.
The v3 key hashes owner, resource type, resource ID, effective window and
sorted zones. Both list and cold-thumbnail paths use this key. Legacy v2
keys cannot authorize native thumbnails. Existing caps and provider caches
remain in effect.

Coexistence thumbnail replay passes through `SharedPhotoGuard` at
`RailsProxy.call`, using the same `Closure.allowed_photo?` policy before
opening the upstream connection. This includes GET/HEAD, `api_shared` slice
handoff and suffix requests. Lists and authorized thumbnails keep their
existing Rails path. Phrase, family-audience and unavailable-owner refusals
continue through their existing authorization path; the guard does not grant
access. A missing resource window is denied before grant-cache writes.
Standalone photo admission explicitly accepts the native producer even when
the coexistence route gate would hand enabled photos back.

## Alternatives and consequences

Invalidation from every zone/resource write would require covering all SQL,
background and coexistence writers. Binding grants to the read context
avoids that dependency. Repeating provider search for every thumbnail would
add network work; context binding preserves valid warm grants while making
scope and zone changes miss the previous key. Each warm request adds the
current settings/window/zone reads. Cache reuse across Rails and Phoenix
thumbnail grants is intentionally discontinued for privacy.

## Verification and references

Named S02F1 reproduces the query interleaving through actual GET/HEAD, with
list and cold paths. S02F2 warms a grant before editing trip boundaries.
Both require 404 without a provider thumbnail fetch after the change.
Mutations reread zones for key storage and omit the effective window;
each must fail its selector before restoration. Rails request probes
confirm F1 denial and F2's inherited 200/200 defect.

Repository counterparts: `shared-photos-s02-handoff.md` and
`deferred-rails-bugs.md` (DRB-023). Shared knowledge-base handoff:
AFFiNE `sTHXI_y0g2E7VcjM02YGf`; deferred-bugs register:
AFFiNE `K4KXXQgxcwGIkohuXyUQQ`.

S02C1 proves mounted standalone/default coexistence/Rails-slice window and
zone denial. S02C1Rails warms the real Rails controller/cache through an actual
Endpoint and TCP proxy bridge, then edits the shared trip in the shared test
database: Phoenix denies 404/404 without forwarding or Rails thumbnail
construction, while direct unchanged Rails still serves 200/200. It retains
valid forwarding and phrase refusal. M-S02C1 bypasses the proxy guard and
must fail both mounted regressions. S02C2 checks the fixed/deferred changelog;
its mutation removes the S02F2 regression reference. Fixed-bug counterpart:
`fixed-rails-bugs.md`; DRB-023 remains the deferred Rails repair, with no new
ED or DRB entry. Previously in-flight requests retain snapshot semantics.
