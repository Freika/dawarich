# Stats, insights, digests and public month closure

Package Q implements plan A tasks Q01–Q14. Rails 1.15.3 remains the source contract. Native command readiness remains controlled by the existing ownership registry; this package does not make workers claimable or remove coexistence hand-back.

## Native browser stats update

`Stats.WebCommands.update/5` receives repo, user, year, month and context with locale/now. Valid months publish one typed `stats.calculate_month` outbox command; `all` publishes twelve in source order inside one transaction under `command:stats.calculate_month`. Invalid periods return the source 303 alert without publishing. Explicit Sidekiq ownership returns a pre-effect hand-back. Browser actions use existing Rails session and CSRF adapters, source notice text and active-until ordering.

Minimal Q route wiring adds a stats request pipeline and PUT/POST-override update routes to `router.ex`. Package O06 must reconcile these additions with its final route wiring. Shared transport rules and global route constraints remain outside Q.

Source capture extends the existing stats fixture generator, because O03 captures were absent at the allocated base. Existing fixture bytes remain unchanged. `a12f3a-q06.json` records January, padded January, all twelve months and rejected periods. Q09/Q10 source captures are available for the subsequent digest tasks.

Q06 named test: initial missing-function RED; GREEN (1 test, 0 failures); M-Q06 omits December and fails the captured job-list assertion; restored GREEN (1 test, 0 failures). Browser cases run with self-hosted true, explicit Cloud false and unset default. Native payloads coerce source year/month strings to integers required by the existing worker decoder. No reverse Rails command is written.

## Remaining work

Q01–Q05, Q07–Q14 remain under implementation. Q06 transport edge envelopes, owner-race/enqueue-failure coverage and native worker terminal evidence still need integration with the shared transport/effect owners. Passing supported browser requests does not close those branches or retire Rails fragment jobs.

Final package gates and AFFiNE synchronization are pending.
