# Family and account terminal Rails oracles

The family and account readers use tracked captures in `app-phoenix/test/rails_fixtures/`. Historical external fixtures remain unchanged. The emitters under `app-phoenix/scripts/parity/` are the only source of captured bytes; Phoenix responses never generate a fixture.

Family capture uses production exception handling (`show_exceptions: :all`, detailed exceptions disabled). Every case records status, normalized headers, the complete body and all relevant database tables after the request. Family writes retain mail effects as well. Account captures retain database, mail/job and cache effects; repeated deletion requests record their prerequisite first request. A selected account recapture merges only the named Rails results into the existing complete corpus.

The terminal readers check former replay cases against their captured effects. Family writes traverse the real HTTP endpoint for every case, compare source mail effects and notification events, and retain the independent domain comparisons. Account deletion checks native durable jobs, confirmation-token signatures/claims and the rate-limit cache entry/TTL. The request database and clock are authoritative for native account producers; native API admission supplies durable ownership without the obsolete mode switch.

Cloud family refusals retain the captured status, headers and body. The source emitter redacts its checkout token; the reader verifies the native token's signature, identity, purpose, UUID and expiry before substituting the same placeholder. Original response framing remains checked. Error responses require an absent ETag; successful crypto responses retain the existing ETag checks. No normalization rule changes. The mine response orders members by user id to retain the captured Rails order after physical row updates; its focused probe changes only transaction-local planner settings.

One explicit difference is retained: `replay_member_settings_null` captures Rails' 500 caused by dereferencing null settings. Phoenix safely treats absent sharing settings as disabled and returns the existing disabled-sharing response without changing any row. See ED-NATIVE-S2GB-NULL-FAMILY-SETTINGS and FRB-NATIVE-S2GB-NULL-FAMILY-SETTINGS.

Validation uses the allocated targeted runner, warnings as errors and seeds 404/202, plus changed-module/direct-caller tests, formatting and strict test-environment compilation. Full ExUnit and browser acceptance remain controller-owned. AFFiNE synchronization is pending under this brief's prohibition on remote writes.
