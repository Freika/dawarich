# Phoenix framework practices review — 2026-10-08

Scope: `feat/phoenix-port` working tree at `/Users/frey/projects/dawarich/dawarich/.worktrees/phoenix-port`, baseline HEAD `7e90969a7a4d8ad28b3be24d38754635aac3d9ac`, including the existing uncommitted Elixir/performance changes. Compared against official Phoenix 1.8.15 and LiveView 1.2.12 documentation. This is a targeted architecture/source review and one local parser reproduction, not an exhaustive security or browser audit. Application code was not changed.

## Assessment

The runtime and core framework mechanisms follow Phoenix well. The application layer follows the conventions partially: domain contexts exist, but their boundaries leak, and the browser is a deliberate LiveView/Turbo/Stimulus hybrid. Functional migration completion and framework idiomaticity are separate questions. A numeric compliance percentage would give false precision.

| Area | Assessment | Evidence |
| --- | --- | --- |
| OTP/runtime | Good foundation | Supervised Repo, Oban, Task.Supervisor, PubSub and Endpoint/listener; runtime secrets/configuration in config/runtime.exs. |
| Templates/components | Good foundation | HEEx, declared component attrs/slots, HTMLFormatter, existing embed_templates. Both inline and external templates are supported. |
| Context boundaries | Partial | 86 domain-directory files reference DawarichWeb; 14 direct Repo.query/query! call sites in 11 web files in the bounded scan below. Some references are harmless presentation adapters; several cross actual domain boundaries. |
| LiveView data lifecycle | Partial | 38 LiveView modules; synchronous data loads, no assign_async/start_async/stream_async calls found in them. Four use temporary_assigns. Large map points/tracks are loaded through API/tiles rather than MapLive assigns. |
| Browser integration | Explicit hybrid | rails_bridge.js actually imports and starts Stimulus; app.js coordinates Turbo and LiveView teardown/reconnect; forms use keyed phx-update="ignore" islands. |
| Authentication/authorization | Positive mechanisms, custom implementation | HTTP plugs plus live_session/on_mount, connected-session identity comparison, per-event checks, session sign-out broadcasts and password-hash checks; stronger admin hooks. Not certified complete by this review. |
| Database | Legitimate schemaless/SQL choice, room for consolidation | Only three use Ecto.Schema declarations in domain directory. Ecto permits schemaless queries and raw SQL; PostGIS and Rails schema compatibility justify these. Query ownership/validation duplication is the issue, not schema count. |
| Tests/observability | Strong functional baseline | Last completed run: 9,937 tests, 0 failures, with 6 existing exclusions and 3 skips; Ecto Sandbox, endpoint/LiveView/parity tests, DB query/queue metrics, Sentry/Oban reporting. Suite was not rerun for this read-only assessment. |

Inventory: 1,176 .ex files / 111,110 lines under lib/dawarich; 509 .ex files / 51,407 lines under lib/dawarich_web; 254 web .ex files at the directory root. Counts describe the current source snapshot, not an automatic quality score. The direct-web-SQL scan matched Repo.query/query! and Dawarich.Repo.query/query!, so it is not a complete call graph. LiveView inventory matched use DawarichWeb, :live_view and use Phoenix.LiveView.

## Highest-priority findings

### 1. Add total native request-body limits (operational priority)

app-phoenix/lib/dawarich_web/api/transport.ex:89 recursively calls read_body with a 1 MiB per-read length and appends every :more result. There is no accumulated-byte limit before materializing the entire body and decoding JSON. Its multipart parser length is 9,223,372,036,854,775,807 (line 55). The legacy 2 MiB classification in api/body.ex is bypassed for dawarich_native_api requests.

Local reproduction on the existing compiled app, Elixir 1.20.4, without starting the application or a database:

```elixir
body = Jason.encode!(%{"payload" => String.duplicate("x", 9 * 1024 * 1024)})
conn = Plug.Test.conn(:post, "/api/v1/points", body)
       |> Plug.Conn.put_req_header("content-type", "application/json")
parsed = DawarichWeb.Api.Transport.parse(conn)
IO.inspect(%{input_bytes: byte_size(body),
             parsed_payload_bytes: byte_size(parsed.assigns.api_params["payload"]),
             halted: parsed.halted, status: parsed.status})
```

Result: input_bytes=9,437,198; parsed_payload_bytes=9,437,184; halted=false; status=nil. This demonstrates acceptance in the parser, not an HTTP benchmark, an OOM experiment, or proof that a deployed reverse proxy has no independent limit.

Recommended change: explicit configurable total limits per request class, counting actual bytes even for chunked bodies, with a 413 response. Imports/uploads need separately chosen limits and streaming; do not impose an arbitrary small JSON cap on all import formats. Multipart files normally stream to temporary disk, so distinguish JSON RAM consumption from upload disk/parameter budgets. This matters at the previously requested 512 MiB/1 GiB caps.

Official basis: [Plug.Parsers](https://plug.hexdocs.pm/Plug.Parsers.html) documents total request limits, RequestTooLargeError and per-parser customization; [Plug.Conn.read_body](https://plug.hexdocs.pm/Plug.Conn.html#read_body/2) describes incremental reads.

### 2. Tighten domain/web boundaries (architecture priority)

Concrete examples:

- lib/dawarich/point_list.ex:6 imports DawarichWeb.TripsGate to parse a page number, then calls it at line 41.
- lib/dawarich/map_page.ex:105 uses DawarichWeb.Params inside domain data loading.
- lib/dawarich/insights/fragments.ex:5 references web components and renders their HTML into Rails-compatible fragment caches. That module is a presentation/cache adapter, despite living in the domain tree.
- lib/dawarich_web/trip_document.ex:40 performs a direct ownership query; lib/dawarich_web/area_actions.ex:14 does the same for areas.
- lib/dawarich_web/api/standalone_map.ex:76 owns the tile transaction, statement timeout and execution.

Recommended change: move generic parsing/hosting policy to domain-neutral modules; keep rendering adapters in the presentation layer; expose small domain operations for owned resources and tile reads. Preserve existing owner filters and responses. Do not introduce a one-line facade for every helper or rewrite the whole database layer.

Official basis: [Phoenix contexts](https://phoenix.hexdocs.pm/contexts.html) place data access/validation behind domain modules; [directory structure](https://phoenix.hexdocs.pm/directory_structure.html) distinguishes business logic from the web interface.

### 3. Reduce avoidable LiveView work (performance priority)

- InsightsLive.Details.mount/3 synchronously calls Details.load(fill: true) and renders fragments. Insights.Details can calculate missing/stale digests through Details.Digests. LiveView mounts initially over HTTP and again on connection; cold computation and duplicate reads deserve instrumentation.
- MapLive.handle_params/3 calls MapPage.load synchronously on both mounts; this includes multiple metadata/gallery reads, while points/track geometry correctly remain outside assigns.
- NavbarHooks schedules :navbar_refresh every 10 seconds per connected view and calls Navbar.unread/1, a DB query. NotificationSession already subscribes to notification broadcasts. 100 connected views imply roughly 10 timer-driven unread queries/second even without changes, assuming one such view per connection and no delayed timers.

Recommended change: measure queries and duration separately for static mount, connected mount and events; move expensive connected-only work to assign_async/start_async with explicit loading/error states where the UI contract allows; send persistent digest work through the existing durable jobs/cache. Avoid simply skipping all disconnected loads, which changes initial HTML/parity. Consolidate notification refresh through events, keeping polling only as a justified fallback.

There were no LiveView stream calls found in the scanned modules. That is not itself a defect: points pages are capped at 50 rows and some collections already use temporary_assigns. Use streams for growing or frequently changing collections when measurement justifies them.

Official basis: [LiveView lifecycle, async operations and streams](https://phoenix-live-view.hexdocs.pm/Phoenix.LiveView.html).

### 4. Make the hybrid frontend decision explicit (maintenance priority)

priv/static/js/rails_bridge.js:46 imports @hotwired/stimulus and starts an Application on an island; app.js registers RailsStimulus hooks and Turbo lifecycle listeners. components/tag_form.ex:14 submits an ordinary POST form and isolates editable fields at line 23. These are running client mechanisms, not only legacy data attributes.

Current repo docs phoenix/native-map-navigation.md and phoenix-form-patch-isolation.md explicitly describe this hybrid and its form protections. However, the accepted parent-repository ADR-0016 (also in AFFiNE) says Stimulus is retired entirely. Record the discrepancy and decide whether the hybrid is the long-term architecture or staged debt. This audit does not supersede that ADR or make the product decision on the user's behalf.

For ordinary forms, .form/to_form plus phx-change/phx-submit can simplify lifecycle ownership. Keep MapLibre/studio hooks where a browser library should own its DOM. phx-update="ignore" is supported and appropriate for such islands; its presence is not an anti-pattern.

Official basis: [Phoenix.Component forms](https://phoenix-live-view.hexdocs.pm/Phoenix.Component.html#form/1) explicitly permits ignored forms; [JS interoperability](https://phoenix-live-view.hexdocs.pm/js-interop.html) supports custom hook lifecycles.

## Secondary improvements

- Api.Transport.call/2 rescues native request exceptions into a 500 response without reporting the exception in that branch. RailsErrors.respond/3 renders a response only. Existing Sentry startup uses an error logger handler and Oban exception events. Verify that a deliberate native controller failure produces one captured exception with its stacktrace; if not, add centralized capture before translating the response. This audit did not run that end-to-end Sentry proof and does not assert every exception is lost.
- Consolidate auth policy gradually: LiveAuth, AdminLiveAuth and NotificationSession currently split connected identity, sign-out and event authorization checks. Phoenix 1.8 Scope can make the actor/permissions context explicit, but the absence of a Scope struct does not establish missing authorization. [Scopes](https://phoenix.hexdocs.pm/scopes.html), [LiveView security model](https://phoenix-live-view.hexdocs.pm/security-model.html).
- Organize route/action helpers by feature; 254 web modules at the root make discovery harder. Folder names and controller generators are conventions, not correctness requirements. Custom Plug handlers are supported.
- Move the largest inline HEEx blocks to .html.heex for readability, as already assessed in elixir-1.20-and-heex-20261008.md. There is no intrinsic request-speed/RAM win from template relocation.
- Retire runtime routing/coexistence gates only after confirming the product no longer supports coexistence/rollback. Names containing Rails do not prove a Ruby process is still required; cookie, cache and wire-format compatibility may remain necessary.
- Schemaless Ecto/SQL, manual transaction functions and non-Gettext translation are not framework violations. Prefer changesets for new ordinary CRUD when they reduce duplicated validation; retain purpose-built bulk/PostGIS paths. [Schemaless Ecto](https://ecto.hexdocs.pm/schemaless-queries.html), [SQL adapter](https://ecto-sql.hexdocs.pm/Ecto.Adapters.SQL.html).

## Verification and next step

Source inspection and official documentation comparison completed. The 9 MiB parser proof passed through parsing without rejection. No production code, migrations, service configuration or ADR decisions were changed; no benchmarks, servers or full suite were started. Existing uncommitted work was preserved.

Suggested implementation order: total input budgets and error-capture proof; domain/web boundaries in one feature; measured LiveView loading/polling; frontend decision and then gradual form/template cleanup. Performance benefit must be measured after each functional change, not inferred from greater resemblance to generators.


## User direction after the review — 2026-10-08

The user explicitly requests a complete Phoenix-native frontend, LiveView and context refactor, removing Turbo and Stimulus from the final native runtime. The hybrid described above is current implementation history, not the target architecture. Exact Rails DOM/Hotwire attributes are no longer acceptance criteria; user behavior, privacy, stored data and public contracts remain protected.

The proposed sequence and gates are in [native-frontend-contexts-plan-20261008.md](native-frontend-contexts-plan-20261008.md), mirrored in [AFFiNE](https://affine.dwri.xyz/workspace/c309ded7-e11e-4e72-ba6f-aec8a31a740b/hjP0OmfxQolck93eTDkPh). Planning is complete; implementation has not started. No ADR is superseded by this planning note.

