# ADR-0017 native frontend cleanup implementation record

Status: **DRAFT implementation record**, 2026-10-10. ADR-0017 is accepted; this record describes its milestone 7 consequences and pending evidence. It makes no new lifecycle/default decision. Canonical ADR-0017 is in the shared workspace, `docs/adr/0017-phoenix-native-frontend-without-hotwire.md`, mirrored in AFFiNE as document `uP52h-O2kIQNEYt45VeLX`.

## Context

The native feature migrations replace Rails DOM preservation with behavior contracts, yet the m7 base still carries shared bridge/Turbo startup, request ownership/envelopes/proxies and Rails frontend asset discovery. Removing names alone would lose API/auth/data/security behavior and leave lazy/worker/build dependencies unproven. [The inventory](native-m7-inventory.md) records these consumers; [the C1 ledger](native-m7-test-retargets.md) separates retained witnesses, delivered feature successors and planned shared-cleanup tests.

## Accepted decision and implementation consequences

Use one native esbuild entrypoint, named browser-library hooks, server-owned LiveView state and contexts taking an authenticated Scope. Direct native routes and local refusals replace per-request coexistence; Rails remains a separately started whole-app fallback artifact. `.html`/`format=html` aliases retain full native documents; orphan UI frame/Turbo formats retire after last-consumer attestation. Independently consumed API/storage/auth/wire contracts remain. Existing Cloud lifecycle/admission preconditions and defaults are outside this implementation record.

Native assets must use native production digest/static resolution. Keep Tailwind/DaisyUI while replacing Rails importmap/Sprockets frontend discovery; preserve independent runtime data and positive renderer/font/geodata/Swagger/PWA inputs. Group surviving web/browser files by feature without renaming modules or rewriting namespaces. Every old behavior case survives through a named reader/successor before its adapter is retired.

## Alternatives already considered

Keeping the hybrid or wrapping its controller registry under another name keeps multiple client runtimes and ownership contracts. Copying the Rails manifest into a native-named file preserves the dependency rather than implementing native discovery. Removing protocol/data cases alongside DOM fixtures silently changes retained public behavior. ADR-0017 and the approved milestone plan select native feature migration followed by consumer-driven shared cleanup.

## Consequences and verification

Markup equality ceases to be the migrated page oracle; public API/crypto/effect bytes remain valid contracts. Separate live_session boundaries require native full-document transitions, not a same-session navigation shim. Physical moves must retain adjacent templates and partition-safe support. Secret handling, stale async rejection, context admission and worker/library teardown remain behavior requirements.

DRAFT until A/B/C1 and X4/X5 finish: production digest URLs and image payload, no-upstream refusals, exact fixture/register reconciliation, full ExUnit seeds/all partitions, stage standalone G44 and English/German 390px evidence. The controller removed performance measurements (D1–D4); no resource/control matrix is required. Existing eager byte/bundle-boundary tests and functional lifecycle cases remain.

Current incremental evidence is in [inventory Appendix G](native-m7-inventory.md#appendix-g--c1-incremental-named-case-and-reader-successors-2026-10-10). No final acceptance or Rails-independent artifact is claimed. Rails bugs fixed by this documentation/retarget brief: none.

Related: [architecture context](native-frontend-context.md), [development workflow](native-frontend-development.md), historical [map Turbo navigation](native-map-navigation.md) and [form isolation](../phoenix-form-patch-isolation.md). Historical records stay intact with superseding references.
