# Phoenix error reporting (A12f-3o tasks 12–17)

Rails reference: integrated Rails 1.15.3 at Phoenix base `8d6368fc3`.
Sources: `config/initializers/{01_constants,sentry,filter_parameter_logging}.rb`,
`lib/{sentry_log_redactor,sentry_logs_logger}.rb`, and installed sentry-ruby 7.0.0
`Sentry::Configuration#environment_from_env`. Source characterization:
`spec/initializers/sentry_spec.rb` and `spec/lib/sentry_log_redactor_spec.rb`.

## Configuration

The official Hex SDK is pinned to Sentry 13.5.1, compatible with Elixir 1.18.3
and OTP 27.3.4.1. It uses Jason and the existing OTP inets HTTP client with
certificate and hostname verification, without an additional HTTP dependency.

| Input | Rails contract / Phoenix behavior |
| --- | --- |
| `SENTRY_DSN` | Same Sentry or GlitchTip DSN. Missing/empty disables sending and handler attachment. |
| Environment | `SENTRY_CURRENT_ENV`, then `SENTRY_ENVIRONMENT`, `RAILS_ENV`, `RACK_ENV`, then `development`, exactly as sentry-ruby resolves it. |
| `SENTRY_ENABLE_LOGS` | Case-insensitive `true`, default false. Error capture is independent. |
| `SENTRY_TRACES_SAMPLE_RATE` | Default 0.05, parsed and retained in `:dawarich, :error_reporting`. |
| `SENTRY_PROFILES_SAMPLE_RATE` | Default 0.1, parsed and retained in `:dawarich, :error_reporting`. |

Tracing is disabled: this SDK requires OpenTelemetry dependencies and
instrumentation which this cut does not add. The Elixir SDK has no Rails-style
profiling sample-rate option. Retaining these inputs does not promise sampled
traces or profiles. No analytics key or alternative Phoenix DSN is required.
Test configuration ignores deployed DSNs; release subprocess tests inject only
synthetic configuration and use a loopback receiver.

SDK references: https://sentry.hexdocs.pm/13.5.1/readme.html,
https://sentry.hexdocs.pm/13.5.1/setup-with-plug-and-phoenix.html,
https://sentry.hexdocs.pm/13.5.1/Sentry.HTTPClient.html,
https://sentry.hexdocs.pm/13.5.1/Sentry.html#flush/1.

## Privacy and capture boundaries

Rails filters passwords, secrets, tokens, keys, encryption material, salts,
certificates, OTP, SSN, CVV/CVC, latitude/longitude, email, name and phone.
Its optional log filter also masks Authorization/API keys, access/refresh tokens,
credit cards and email strings. Phoenix uses a stricter envelope allowlist:
exception type, sanitized stack and operational surface/worker/queue/attempt
labels survive. Request/query/body/cookies/headers, user identity, socket/session,
job arguments, nested context, breadcrumbs, source context, attachments and
exception values are removed. No full request or LiveView breadcrumbs are enabled.
Opted-in logs retain severity and timing with filtered body and empty attributes;
this deliberately reveals less than Rails' free-form messages.

Bandit reports through the SDK crash logger with the Bandit domain enabled.
Phoenix keeps its original 500 status and static HTML. No PlugCapture wrapper is
used and endpoint plug ordering is unchanged.

Shared LiveViews use a tag-only mount hook. Direct LiveView usage is covered by
crash-stack classification in the logger. The SDK's context/breadcrumb hook is
not installed because it collects URI, socket identifiers and event payloads.
The current production census uses the shared macro throughout. Tests cover
both forms, connected mounts and events, without changing process exits.

Oban uses one `[:oban, :job, :exception]` handler. It preserves existing job logging,
retry schedules, attempt counts and final discard. The SDK's automatic Oban
capture is disabled to avoid duplication; no args/meta/payload is attached.
SDK event deduplication is disabled because distinct scrubbed failures can have
identical stacks; actual web, LiveView and Oban tests assert one envelope per failure.

Release CLI rescues capture before converting exceptions to exit 1. Native
`Release.migrate/seed` eval paths use the same nested command scope to report
once and re-raise the original exception. SDK startup does not start the web
endpoint, job supervision or application supervisor. Synchronous release sending
uses the existing client timeouts (1 second connect, 2 seconds request), no HTTP
retries, then the SDK flush API with a 2 second bound. Reporting failures leave
the original exception, exit status and database effects unchanged.

## Verification and handoff

Focused tests live in `test/dawarich/error_reporting`,
`test/dawarich_web/{error_reporting,live_error_reporting}_test.exs` and
`test/dawarich/jobs/error_reporting_test.exs`. Tests assert complete SDK envelopes
through its HTTP client seam or a local HTTP receiver. Release tests build and
invoke the existing release executable/eval seam, with no web application start.
The assigned report records RED/GREEN/mutation/restored evidence and the full
ExUnit seed 404/202 gates. No deployed telemetry backend is contacted.

This is the Sentry portion of A12f-3o, not whole-release acceptance. AFFiNE writes
are forbidden by the controller plan for this assignment; this repository file
and the assigned implementation report are the handoff documentation.
