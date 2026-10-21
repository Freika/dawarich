# Opt-in native Cloud web mapping

A12f-3c task 2 preserves the existing Cloud Procfile web command,
`cloud-entrypoint.sh puma -C config/puma.rb -p 5000`, as native listener
compatibility argv when both `SELF_HOSTED=false` and
`DAWARICH_PHOENIX_LIFECYCLE=true` are explicit. Default and self-hosted boot
continue using the coexistence front. This preparation does not authorize a
traffic switch or prove Cloud provisioning or retained HTTP route coverage.

The native Cloud branch runs `Dawarich.Release.halt_unless_ready()` before
starting the web release. Every nonzero readiness status is terminal, including
1/3/4/5; no Rails fallback, DB wait loop, migration or seed runs from this branch.
Cloud lifecycle readiness remains the lifecycle owner's contract. A refusal
there remains a refusal here.

The shell clears inherited Rails argv, native argv and process role, then passes
the original argument boundaries through `DAWARICH_NATIVE_ARGS`, using the
existing unit-separator framing convention, and selects the web role.
`Application.plan/2` consumes that input only for explicit native Cloud web,
through `Front.native_plan/2` and `NativeCommand`. Known Puma configuration,
port and single TCP bind map to native Endpoint children and the existing
drainer. There is no RailsServer child or Rails upstream. Unsupported options,
custom configurations, multiple listeners, non-web commands and missing argv
raise before starting application children. Quoting does not make unsupported
Puma options supported.

The existing native Cloud Sidekiq compatibility command still selects only
`sidekiq_idle`; its implementation is unchanged by this web mapping.

Related census and release obligations: [A12f release](a12f-ruby-free-release.md).
Verification lives in the existing Cloud/lifecycle regression specs and
`app-phoenix/test/dawarich/{application,front}_test.exs`.
