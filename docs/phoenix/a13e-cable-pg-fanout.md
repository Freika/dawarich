# Optional PostgreSQL Cable fan-out

Redis remains the default Cable transport. `DAWARICH_CABLE_TRANSPORT=pg` selects the optional native PostgreSQL backend; `redis` selects the existing backend, and other values fail startup. PG is a closed native producer/client island until Rails Cable producers and clients retire. It neither publishes to Rails Redis subscribers nor bridges Redis events. Routes, Cloud ownership, authentication and channel authorization retain their existing gates.

## Publication and transactions

`Dawarich.Cable.Bus.publish/2` returns `{:ok, integer}` for either transport. Redis returns its receiver count; PG returns an event sequence, which may still be pending an outer transaction. Neither means acknowledged socket delivery. `publish/3`, `Cable.broadcast_to/4`, `Cable.turbo/5` and `Cable.refresh/2` accept `repo: caller_repo`. PG defaults to `Jobs.repo/0`; explicit repositories take precedence. Redis retains its existing behavior.

Only `phoenix.cable_streams` and `phoenix.cable_events` are added. Each prefix has a counter row whose transaction lock serializes sequence allocation through commit or rollback. Events and counter increments share the caller's transaction; rollback leaves no gap. Different namespaces remain independent. Payloads are stored as exact binary bytes. Append near the end of domain work: long outer transactions block later publications in that namespace. No dedicated Cable connections, session locks, LISTEN/NOTIFY or new dependency are introduced.

Notification/trip source claims pass their claim repository through to Cable. Source deletion, prepend and badge appends commit together; append failures roll the claim back. There is no producer retry or automatic Redis fallback.

## Live subscriptions and retention

Each node polls its namespace every 200 ms in ordered batches of at most 100 using the existing Repo pool. Independent nodes read every event and dispatch through node-local PubSub. There is no fixed delivery latency under database contention.

Subscriptions capture a committed sequence fence before readiness acknowledgement. Older events are ignored. Aliases for an active broadcasting preserve its fence and last-delivered sequence; only final unsubscribe removes membership. Sequence metadata never appears in ActionCable frames. New pollers start at committed high-water and do not replay history.

Events remain for at least 60 seconds after their first committed observation. Retention stamps dormant history without dispatching it, never extends an observation, and prunes only a contiguous expired prefix in bounded transactions. An unobserved or unexpired row stops pruning. Committed sequences are never reused.

A cursor behind `retired_through` terminates the monitored Bus. Existing sockets receive `server_restart`, `reconnect: true`, then close 1000. Bus loss or an ambiguous dispatch failure follows that same reconnect boundary. Query errors before dispatch retain the cursor and use logged backoff without payload logging. There is no durable browser replay or exactly-once claim across failures.

## Rollback and release prerequisites

Future rollback to Rails must restart with `DAWARICH_CABLE_TRANSPORT=redis` together with `DAWARICH_RAILS_ROUTES=cable` or `DAWARICH_RAILS_SLICES=cable`. Hand-back alone while PG producers continue loses deliveries to Rails subscribers. Existing sockets reconnect on restart.

Tests-only branch acceptance does not activate PG. Browser stands, Docker/image checks, actual two-node socket fan-out, pooler transaction-mode probes and loaded-stop acceptance are **deferred to the controller mini lane**. Preserve the existing Redis coexistence probe first. PG probes require the small producer/transport selectors in the existing `SP/a12a-c3-v3/{two_nodes.sh,lib.sh,cable_probe.exs}` kit; unchanged Rails/Redis publication cannot prove PG delivery. Namespace serialization throughput must pass existing release load budgets before activation. Rails producer/client retirement remains a prerequisite.

Plan: `/Users/frey/projects/dawarich/superpowers/plans/2026-10-04-phoenix-a13e-cable-pg-fanout-plan.md`. Release commands and browser specs are recorded there and in `2026-10-04-phoenix-release-tier-runbook.md`. ED-470–472 record the optional timing, retention and result differences. No AFFiNE writes for this channel-isolation/data-exposure task.

## Evidence

`cable/bus_test.exs` pins Redis default, validation and the disabled-bus guard. `cable/pg_store_test.exs` proves commit visibility, sequence blocking and rollback. `cable/pg_bus_test.exs` proves acknowledgement fences, bounded polling, independent pollers, aliases/unsubscribe and retention loss. `cable/pg_retention_test.exs` pins first-observed expiry and contiguous pruning. `cable_pg_test.exs` pins repository forwarding and every recorded producer byte, including a payload over 8 KiB. `cable/pg_turbo_events_test.exs` pins claim atomicity, competing relays, append failure and publisher death. Real socket tests in `dawarich_web/cable_pg_test.exs` pin exact frames, restart/reconnect and user/share isolation; `cable_route_test.exs` pins transport-independent hand-back. Existing Redis corpus replay remains required.
