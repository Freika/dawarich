# Cloud preparation component

`Dawarich.Release.Cloud` is a preparation API. The integration head keeps public native Cloud lifecycle refused until the external L1 handoff. The conditional admission candidate on `feat/l1-guard-flip` remains subject to independent security review and controller integration.

## Cloud configuration and delivery

ADR-20261007-L1-configuration — implemented 2026-10-07 under the controller's B2/B3 hardening brief; external L1 acceptance remains pending. The review demonstrated plaintext signed-customer delivery and false successful receipts under missing configuration. The decision is to fail closed at configuration/admission and again at delivery, preserving optional Partnero and Rails HTTP-status behavior. Relying only on TLS verification after choosing an HTTP origin, or treating missing settings as successful skips, was rejected because both lose the intended security or retry boundary.

Cloud boot, preparation preflight and readiness require a nonblank `JWT_SECRET_KEY` and a valid `MANAGER_URL`. Manager must use an HTTPS origin without embedded credentials, path, query or fragment. Failures name the setting and required correction without printing its value. Browser and mobile signup readiness applies the same validation; self-hosted boot and signup require no Cloud settings.

Self-hosted creation and hard deletion publish no Manager callbacks, including when Manager settings are present. Partnero signup attribution and subscription family callbacks also remain Cloud-only. Rails gates creation on Cloud mode and skips Manager delivery when `MANAGER_URL` is absent; native deletion suppresses that unused self-hosted intent at publication. Explicit Cloud deletion still publishes one unlink snapshot, and delivery retains strict configuration validation. The regression is `test/dawarich/users/self_hosted_callbacks_test.exs`.

Manager delivery validates configuration again before signing and sending. Missing or invalid configuration returns a retryable configuration error and does not create a delivery receipt. Repairing configuration permits the retained event to be delivered. HTTPS verifies peer certificates and hostnames; Partnero keeps its fixed `https://api.partnero.com` origin. Manager still acknowledges any HTTP status, matching Rails, and transport failures remain retryable.

Partnero remains optional for Cloud boot. An attributed callback with a nonblank referral requires a nonblank `PARTNERO_API_KEY`; missing credentials retain failed work without a delivery receipt. A blank referral or a missing/deleted user is a semantic no-op, rather than a missing-configuration delivery success.

Synthetic HTTP listeners require the explicit internal `test_loopback: true` option and the test-build-only `cloud_test_loopback` compile setting. Only numeric IPv4/IPv6 loopback origins qualify. Production builds default the setting to false and no environment variable enables it; boot and JWT signing never accept plaintext origins. Photo-provider behavior is separate and unchanged.

These security corrections are recorded as `ED-FIX-L1-HTTPS`, `ED-FIX-L1-CONFIG` and `ED-FIX-L1-PARTNERO` in [expected differences](../../app-phoenix/parity/expected_diffs.md). Named regressions and mutation evidence are in `test/dawarich/cloud/hardening_test.exs` and the controller's hardening report. They do not authorize native Cloud lifecycle admission or the external L1 handoff.

## Session connections

Cloud provisioning and after-commit callback delivery use dedicated Postgrex sessions for session advisory locks. A transaction-pooled application connection cannot carry those locks. Configure `DATABASE_SESSION_URL` with a direct PostgreSQL or session-pooling endpoint for the same database as the application Repo. `:database_session_url` application configuration and the provisioning `:session_url` option provide the same seam. The existing direct Repo configuration remains compatible when no separate URL is needed.

Port 6432 and explicit transaction/statement pooling modes are refused for session connections. Nonstandard transaction-pooling application endpoints must declare `DATABASE_POOLING_MODE=transaction`; they require a separate session URL. The configured session endpoint must support session locks; endpoint capability is an operator contract, not inferred from a successful TCP connection. Unavailable, malformed or mismatched session connections refuse before provisioning writes. Locks remain held across application receipt transactions and HTTP delivery, with the session closed on completion or process death. The provisioning lease still uses transactional table updates, which are safe through the application pool.

Session URL TLS settings preserve Repo SSL configuration unless explicitly overridden. `sslmode=verify-full` and `verify-ca` verify the certificate and hostname; `PGSSLROOTCERT` selects an explicit root certificate. `require` requests encrypted transport, while `disable` is an explicit local transport choice.

`AfterCommit.intent/4`, `AfterCommit.Callback.run/4` and `Cloud.ProviderHTTP.post/5` retain their public signatures and result contracts. Intent publication locks the account row before the event transaction lock, matching account-changing callers. Callback HTTP has an independent ten-second total deadline, unaffected by photo-provider settings or caller timeout options. A delivery receipt still cannot make HTTP and SQL atomic across process death; provider replay uses the same event identity.

## Recorded work and readiness

Reconciliation adopts the actual existing Oban job, preserving its operation and nested source request identities. Identity fields are excluded recursively only when comparing semantic source requests. Ambiguous candidates refuse rather than duplicating work.

Achievement parent and bulk receipts prove publication. Readiness requires a bulk publication manifest and a terminal receipt for every persisted child identity. Child receipts commit with the check result; an unsuccessful or unexecuted child prevents readiness. A separate Cloud completion identity retains verified completion after Oban pruning. Legacy bulk receipts without the completion manifest fail closed and need a retained-work disposition before handoff.

The default supported source data ledger contains the 24 data migration versions from the supported Rails source. Readiness compares the entire set: missing and extra versions both refuse. Fresh native provisioning atomically writes `phoenix_native_baseline=1` in `public.ar_internal_metadata` with the native baseline; this explicitly selects the empty historical data ledger for that origin. It never stamps historical source data migrations performed. Future declared release data versions are still required for both origins. Readiness remains SELECT-only and never reconciles, drains, copies registration settings or performs callbacks.

Code counterparts are `cloud/session_connection.ex`, `release/cloud_data_ledger.ex`, `release/cloud_jobs.ex` and `release/cloud_achievement_work.ex` under `app-phoenix/lib/dawarich`. Regressions are in `test/dawarich/cloud/session_connection_test.exs` and `test/dawarich/release/cloud_review_test.exs`. The canonical shared index is AFFiNE document `AVWr5ao5n-OKCZZbEphrP`; controller fix evidence is in the package A fix report.

## ADR-20261007-l1-admission-validation — one release admission rule

**Status/date:** Implemented on the conditional admission feature candidate, 2026-10-07; independent security acceptance, integration and rollout remain pending. This corrects review findings B1–B3 and does not certify an external endpoint's session capability.

**Decision:** `Dawarich.Cloud.EndpointURL` supplies fail-closed Manager-origin and session-URL validation to Cloud configuration, lifecycle admission and session connections. The shell environment guard calls `dawarich eval` with `Dawarich.Release.Lifecycle.admitted?/0`; it contains no separate URL grammar. A missing or failing release executable refuses native Cloud boot before downstream commands, retaining the existing refusal message. Guard evaluation output is suppressed to keep configuration errors from disclosing environment values.

Manager origins require HTTPS, a valid DNS or IPv4 host and a port in 1–65535, without credentials, path, query or fragment. Session URLs require PostgreSQL, a valid DNS/IP host, a decoded nonblank database, a valid port, no fragment and only the supported TLS/session query declarations. Whitespace, malformed escapes, ambiguous numeric hosts, repeated query keys and conflicting pooling declarations refuse. PgBouncer host markers, port 6432 (including zero-padded spelling), transaction/statement declarations and unsupported parameters refuse as session endpoints.

Known pooled application endpoints cannot be reused for leases. Identity comparison normalizes scheme-independent host/port, DNS case and one root dot, default/zero-padded ports and IPv6 spelling; credentials and database spelling cannot hide reuse. A genuinely distinct direct/session endpoint remains allowed. The operator must still guarantee actual session advisory-lock continuity and the existing runtime database-identity check must still pass.

**Alternatives:** Maintaining a shell regex alongside Elixir was rejected because the independent 648-case review demonstrated divergent and unsafe admissions. A successful connection alone cannot prove session lock continuity through a pooler.

**Verification:** Maintained regressions reproduce pooled reuse, malformed inputs, all 648 reviewer combinations, actual release/web/worker entry before effects, and complete public/private migration-ledger plus registration snapshots after each refused public/direct call. Named mutations target endpoint reuse, lower-level session checking, port validation, shell delegation and private writes. No self-hosted behavior or coexistence defaults change. The fix report records targeted checks; the controller owns the full integration gate.

Code counterparts: `app-phoenix/lib/dawarich/cloud/endpoint_url.ex`, `cloud/configuration.ex`, `cloud/session_connection.ex`, `release/lifecycle.ex`, `docker/entrypoint-env-guard.sh`. Regressions: `test/dawarich/release/admission_security_test.exs`, `test/dawarich/release_cloud_test.exs` and the existing entrypoint specs. Shared counterpart: AFFiNE `[dawarich] Doc: Cloud preparation component` (`CVRUdArG6nqbgf06wK-LC`). Evidence: controller report `fix2-l1-guard-flip.report.md`.
