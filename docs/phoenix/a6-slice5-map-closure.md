# A6 slice 5 map implementation closure

Status: bounded implementation complete on `feat/phoenix-a6-slice5`, 2026-10-05. Browser, stand and image release acceptance remains open. This does not retire Rails or complete A12/A13.

Plan: `/Users/frey/projects/dawarich/superpowers/plans/2026-10-04-phoenix-a6-slice5-map-plan.md`. The accepted starting head was `6fff723cf`, including slice 4; the feature branch subsequently synchronized through integration head `e2809edeb`. Full gates below tested code head `fdf91951b`.

Slices 1–4 implement the admitted map shell, timeline/residency frames, point/tag/segment reads and supported tag, segment and point-list writes. Slice 5 mechanically extracts point presentation/refresh operations, corrects pending subscription setup during teardown and early toggles, and pins producer payloads and independent map/Cable rollback. No additional material A6-owned web route family remains in this bounded implementation.

## Ownership and retained Rails surfaces

| Surface | Native/shared files under `app-phoenix/lib/dawarich_web/` unless specified | Retained Rails / next owner |
|---|---|---|
| `/map`, `/map/v2`, controls and studio hosts | `page_routes.ex`, `map_live.ex`, `components/map_index.ex`, `components/map_panel.ex`, `layouts/map{,_root}.html.heex` | `app/controllers/map/maplibre_controller.rb`, map views/layout; rollback until A12 |
| Timeline, calendar, track-info and residency frames | `map_frame_routes.ex`, `map_frames.ex`, `map_frames_gate.ex` | Rails timeline/residency controllers; unsupported states replay |
| Points/tags/segment reads and point-address frame | `page_routes.ex`, `map_frame_routes.ex`, `map_data_gate.ex`, `points_live/index.ex`, `tags_live/{index,form}.ex` | Points/tags/segment controllers; direct address and unsupported requests remain Rails |
| Tag writes, segment override/reset, point-list deletion | `tag_actions.ex`, `segment_actions.ex`, `point_list_actions.ex` and their gates/services | Supported slice-4 shapes only; Rails rollback and residual effect handlers remain |
| Map REST APIs, tiles, filters, settings/privacy APIs | Existing `api/map_controller.ex`, `api_read_routes.ex`, `api_routes.ex` where admitted | A4 owns residual `/api/v1/*`; existing native APIs retain ownership |
| Place/visit/area forms, drawer, videos/posters, shares/family | Existing `a8_routes.ex`, `a9_routes.ex`, `map_frame_routes.ex` and their modules | A4/A8/A9; existing native and Rails boundaries remain |
| `GET /visits` navigation | `a8_routes.ex`, `VisitsNavigation` | A8; unsupported navigation retains Rails fallback |
| Realtime UI and map lifecycle | Shared `app/javascript/maps_maplibre/channels/map_channel.js`, realtime controller/helper; `app-phoenix/priv/static/js/map_shell.js` | Shared Rails assets remain intentionally wrapped |
| Cable transport and channel access | `cable.ex`, `cable/socket.ex`, `cable_proxy.ex`, `slices.ex`; `app-phoenix/lib/dawarich/cable/{channels,identity,bus}.ex` | A12a; Rails channels, Cloud and configured Cable fallback remain |
| Broadcast effects and retirement | Existing reverse-command queue; Rails `Points::LiveBroadcaster`, `MapEdits::Publisher` and other handlers | A3/A1.x/A4/A9 produce effects; A12 removes residual Rails bridges; A13 removes Redis |
| Legacy map redirects and asset deletion | Retained `config/routes.rb`, `config/importmap.rb`, Rails assets | `/map/v1`, `/maps/v2` and deletion remain A12; track recalculation remains A1.x/transportation |

The inventory's original conceptual slice numbers differ from the executed slices: slice 3 covered simple reads and slice 4 their supported writes. Its historical Rails-only socket recommendation was superseded by A12a's native ActionCable-compatible `/cable`; slice 5 adds no transport migration.

## Rollback

Add keys to the existing comma-separated configuration, preserving every other configured key:

```text
DAWARICH_RAILS_ROUTES=map,points,tags,tracks
```

`map` returns map pages and map frames to Rails. `points`, `tags` and `tracks` independently return their admitted reads and writes. The `map` key alone does not affect these simple pages/writes, `/api/v1/*` or Cable. Unsupported inputs keep their existing raw Rails replay.

Cable is independent; append `cable` when it also needs Rails rollback:

```text
DAWARICH_RAILS_ROUTES=map,points,tags,tracks,cable
```

The existing `DAWARICH_RAILS_SLICES=cable` control also returns Cable to Rails. Cloud retains its Cable fallback. The browser still uses the same ActionCable consumer and `/cable` URL.

## Local evidence

- P1–P4: complete Rails point/family/track producer literals, four normalized map events, tuple/marker ordering, date-window rejection, delayed setup cancellation, reconnect/early-toggle uniqueness, all-channel unsubscribe and actual map/Cable route independence. Twenty named production mutations were observed red and restored green; the implementation reports retain names and errors.
- R1: the existing read/write Rails generators ran twice in separate processes; all 35 refreshed fixtures compared byte-identically. Native map/frame/data/write/window/importmap parity: 59 tests, zero failures. Swagger was copied back and compared after each RSpec run.
- C1: Node 579 passed, zero failed/skipped; scoped Rails 207 examples, zero failures; Biome eight files; RuboCop `--cache false` eleven files without offenses; compilation and formatting passed.
- C2: unchanged `resync-check.sh` and `seedrun.sh`/`slot.sh`, Redis 7229 and private Phoenix database. Full ExUnit seeds 404 and 202 each completed with 6,410 tests, zero failures, zero invalid and six existing `rails_parity` exclusions. Seeds 101/303, including the brief's final 101, were skipped under the controller's 2026-10-04 merge ruling; the third integration seed belongs to the controller.
- Session-5 isolation: reader/TLS/GPX/visit-lock files passed three times each. KML repeated its 60-second timeout; three raw spool readers received bounded 64 KiB read-ahead. The unchanged KML file then passed three times (58.9/33.0/27.8 seconds); KMZ/private-spool coverage passed 84 tests. Diagnostic output was removed. No assertion, fixture, timeout, retry or skip changed.
- Mandated committed-range and changed-file secret scans passed. Touched production sizes: realtime controller 264 lines, point helper 99, KML importer 101, KML point reader 189; each remains below 300.

[ED-405](../../app-phoenix/parity/expected_diffs.md) records the historical teardown/early-toggle correction in the shared controller. Close that exception when both release baselines contain the correction. Extraction and buffered KML reads add no product parity exception. Existing slice-1–4 differences, including ED-380–384's delayed effects and atomicity boundaries, and A12a Cable differences remain authoritative.

## Deferred to the controller mini lane

- Existing Track B live-mode/API, family/realtime/family-layer, timeline sync, point deletion/drag editing and map-settings journeys.
- Existing MapShell lifecycle spec: leave before setup, prove no detached subscriptions, return with one active set; execute the `C3-late` cancellation mutation.
- Real-page no-socket load, reconnect and unsubscribe with native Cable and configured Rails fallback.
- Slice-3/4 point-list, tag CRUD and segment-frame roundtrip browser journeys.
- Existing stand/image smoke and later integration/platform/locale acceptance.

No browser/stand/image proof is inferred from Node, RSpec or ExUnit. Rails controllers, views, specs, assets and channels remain. AFFiNE writes are prohibited by this task's binding auth-boundary restriction; the controller may later publish a permitted short progress pointer under its own authorization.
