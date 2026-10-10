# Milestone 6 native map contracts

Status: S1 foundation contracts implemented, 2026-10-10. The controller starts tracks B/C/D only after the separate S1 SHA artifact exists. Source baseline is `bdaa9aa36`; the A0 measured baseline is recorded in `native-m6-inventory.md`.

## Session and domain admission

`Dawarich.Maps.principal(user, locale)` returns an Accounts.Scope containing a sanitized actor and a SHA-256 fingerprint of the original Devise session salt. Raw API keys, password hashes and provider settings never enter this scope. The fingerprint remains immutable across refreshes. `Maps.admit(scope)` returns a refreshed sanitized scope; `Maps.with_actor(scope, effect)` independently checks that original fingerprint, lock/deletion/status/subscription before invoking the effect with its transient domain actor. Commands must recheck inside their transaction when they span a read/effect boundary.

`Maps.page(scope, params, opts)` wraps the existing MapPage queries and returns `{:ok, projection}` or `{:error, :stale_session | :unauthorized | :not_found | :invalid | :unavailable}`. Projection excludes credentials, bulk points/tracks and signed subscription URLs. Settings on the actor are allowlisted. Existing hybrid consumers of MapPage remain unchanged until X1; no native host delegates its UI to them.

`DawarichWeb.MapLiveAuth` is the dedicated native host hook. Its `live_session/1` signs the original map identity into the server mount session. Connected mount also compares the socket session actor ID; events, params, info and async each re-admit. Session loss clears state and redirects to sign-in. Resource refusal clears the projection and records a typed error in place, with no reload to the same URL. X1 adopts this hook on the routed hosts.

## Dependency adapters

| Adapter | Current implementation | Accepted dependency awaited | Switch task |
| --- | --- | --- | --- |
| `Dawarich.Maps.Dependencies.Trip` | TripPage.load/gate, projected metadata + HTTP geometry/windows/plan | m5 owned Trip read/map insertion facade | Dedicated switch retaining owner/range/privacy cases |
| `Dawarich.Maps.Dependencies.Family` | FamilyPage admission + Families.Locations/FamilyApi.Closure history | m4 fresh family consent/delivery facade | Dedicated adapter switch retaining withdrawal/session tests |
| `Dawarich.Maps.Dependencies.Principal` | Accounts.get, Devise salt fingerprint, sanitized Scope | m4 fresh/sanitized principal and callback admission | Controller integrates m4, then dedicated adapter switch with original-session revocation tests |

The other O10 dependencies (m4 upload claims/finalization, owner invalidations, family consent/public admission; m5 Trip/Visit/timeline projections and map insertion points) receive one thin adapter each when the owning A/B/D task first consumes them. The ledger will name actual modules and methods at that point. No duplicated domain queries or placeholder native fallback is part of this contract.

## Verification

A1 covers real LiveView events/params/queued info/async delivery on a routed test host; scope refresh followed by password revocation; actor deletion, lock, inactive/pending status; credential-free projection and state; typed missing-place refusal. Named mutations and strict direct-caller batches are recorded in the implementation report.

## Browser read adapter

`/native/map/data` reserves a read-only manifest: points; tracks and track points; tile points/tracks; settings; bounds/hexagons/fog; countries; photos/thumbnails; location suggestions; places/search/nearby; visits; Areas; timeline. GET and HEAD authenticate only the fresh Rails-compatible session cookie; Bearer alone does not authenticate here, account keys in query params are rejected, and cross-origin browser requests are refused. Mutation verbs under this prefix return 405. External `/api/v1` routes retain their Bearer contracts.

`BrowserMapData` dispatches to the existing domain/controller read implementations. Map/Visit read dispatch explicitly selects their native closure independently of coexistence mode; no HTTP proxy or hybrid UI is involved. API entitlement and account scoping remain in those implementations. Inactive-account reads remain allowed where the existing API allows them; pending-payment and stale session refusals remain. Responses vary by Cookie and are private/no-store, with existing validators/epochs retained. Settings omit provider credentials. Point/track/place/visit/photo reads require bounded pages (default/max 1,000 rows per page).

Browser `createReader({origin, fetch, maxPages, maxRows, timers, timeoutMs})` provides `read(resource, params, {signal,onData})`, `pages(resource, params, options)`, `reset()`, `destroy()` and `revision`. Resource names come from the fixed manifest; URLs and account-key injection are refused. Every request uses same-origin credentials and its own AbortSignal/deadline; reset/destruction aborts and invalidates old generations. `read` returns `{status: "ok" | "no_data", data, headers, revision}`; empty arrays are successful reads, bounds 404/zero is no-data, other HTTP failures throw a status-bearing generic error. Abort throws AbortError. `pages` returns complete bounded rows or rejects a row/page limit, without silent truncation. Geometry remains browser-local. Limits are operation safety defaults, not measured export acceptance budgets.

## Browser host and disposal

`MapHook` lazily imports `map/runtime/host.js`. `mountHost({element,pushEvent,reader,loadLibrary,loadStyle,attach,refresh})` owns exactly one runtime and an explicit `source`. Its `createMapRuntime` accepts injected services and supplies `mount()`, `update(config)`, `reconnect()`, `destroy()`, `map`, `config`, `state`. The host owns its child root, map and reader; cleanup runs in reverse acquisition order, destruction is idempotent, and owners never clear a global map/worker pool. Late chunk/style/attachment completion cannot allocate or retain a destroyed host. Reconnect refreshes the existing map. Configuration replacement invalidates older initialization and reader generations. Async acquisition has an owned deadline and AbortSignal; late attachment disposers still run.

`attach` receives `{map, config, reader, lifetime, operation, signal}` and returns a disposer or its promise. Use `operation.check()` after asynchronous stages, `lifetime.own(disposer)` for acquired resources and the supplied signal for requests. `refresh` receives the same operation contract and is responsible for bounded layer refresh; high-volume geometry never goes through pushEvent. Error receipts contain generic codes only.

`createStudioSource({getState,readSnapshot,applyDates,fixedRange})` provides `snapshot({purpose,signal})`, `applyDates(range,{signal})`, `reset()`, `destroy()`, `fixedRange`. Purpose is poster/video/replay. Snapshot waits for bounded browser reads and verifies the current owner revision before returning `{revision,range,title,...data}`; data owns points and later track/photo/flight additions. Source state has `{revision,title,range:{startAt,endAt,importId,timezone}}`. Host's initial exact-data adapter pages points; A6/A11 deepen trip/device/flight semantics without changing this injection contract. Trip sources set fixedRange; dates are refused without a network write. Map date changes await the injected server acknowledgement and its matching current revision.

## Event and wiring points at S1

| Direction | Name | Bounded payload / ownership |
| --- | --- | --- |
| Server to host | `map:config` | allowlisted scalar config and monotonic revision; A wires B9 projection |
| Server to host | `map:invalidate` | identity/revision receipt; refetch in browser, A14 wires m4 producers |
| Server to host | `map:clear` | refusal code; release visible map/data before late callbacks |
| Host to server | `map:ready` | revision only |
| Host to server | `map:failed` | generic code only |
| Studio source to server | `map:range` | `{startAt,endAt,importId,timezone}`; B9 validates and returns `{revision}` after host config acknowledgement |

Canvas roots are the only ignored DOM. Proposed stable IDs are `native-map`, `native-trip-map`, `native-family-map`, `native-public-map`, `native-poster-studio`, `native-video-studio`; repeated previews append resource identity. Hooks register as Map, Trip, Family, PublicMap, MapPreview, PosterStudio, VideoStudio and Onboarding as their owners land. A owns hooks/index, app.js, router/route manifests, layouts, MapLive and shared host/gallery delegation. B supplies map_live commands/timeline and components; C/D supply studio modules/components. Integrating those modules requires explicit injected source objects, with no global controller registry or application-shaped facade. The S1 SHA artifact is the controller handoff; route removal and complete page adoption remain X1 after parity.

## Native host packaging

`DawarichWeb.NativeMapHost.map_host` renders a keyed ignored canvas root with the Map hook. Config accepts only namespace/revision/title/styleUrl, range startAt/endAt/importId/timezone, and mapOptions center/zoom/minZoom/maxZoom/bearing/pitch/projection/interactive/attributionControl. No resource arrays or account/provider credentials are serialized. Hosts remain responsible for fresh admission and monotonic configuration revisions.

The minified S1 eager graph measures 168,125 raw / 51,666 gzip bytes; the Map hook contributes 878 raw bytes and the existing demo contributes 1,368 (its 2 KB budget remains enforced). No map engine is in the eager graph and no Rails JavaScript is in any native chunk. MapLibre stays the vendored external module with its worker siblings; fflate 0.8.2 and mp4-muxer 5.2.2 match the existing Rails importmap. Studio engine/hook imports will be registered as C/D deliver them. These are measured foundation sizes; export and route budgets await O8 measurements.

## Tile layers

`createBaseLayers({map,config,freshness,onError,onEmptyTracks})` owns point/track vector sources, style/error/empty listeners and focused edit exclusions. `mount`, `update`, `edit({trackId,pointIds} | null)` and `destroy` never fetch complete history. Epoch changes refresh once, range/import changes retain z-order, style replacement restores sources and edit filters. Points and heatmap toggle independently; flight aggregate masking and fog source keep-alive retain the original corpus. RecentPointLayer remains a focused data sink for A14 live arrivals.

`createTileFreshness(origin)` supplies owner-scoped `bump("points" | "tracks")`, `transformRequest` and `destroy`. Only exact same-origin native tile prefixes carry cookie credentials and a refresh version. External tile/style hosts receive no credentials or refresh identity. The native host applies the transform through an injected service and waits for map load before reporting ready. Added config scalars: epoch, pointsEnabled, tracksEnabled, heatmapEnabled, trackColor, styleName; flight and selected-point geometry remain explicit browser services.

## Exact geometry snapshots

`readRouteSnapshot(reader,state,{purpose,signal,deviceWindows,routeOptions})` pages points using the unchanged profile-local range strings and import ID. The HTTP domain owns timezone interpretation. It filters exact data by device windows, groups device buckets, splits route time/distance gaps, preserves the existing kilometre-versus-metre threshold convention and antimeridian interpolation. Existing device/GeoJSON/time-overlap corpora run against the native modules.

Poster snapshots with visible flights read the owned `/native/map/data/flights` closure, replace fully flight-contained GPS lines with great-circle arcs and retain adjacent ground segments. Video/replay retain timed GPS points; they do not synthesize flight points. `createStudioSource` gates publication against current revision and caller cancellation; Trip supplies its own device-window adapter in A11. Reader deadlines also settle when a transport ignores its AbortSignal. Bulk geometry remains browser-local.

## Lazy density ownership

The host imports `createDensityLayers` only when fog, hexagons or scratch is enabled. H3 4.4.0 and PMTiles 4.5.0 remain separate layer-demand imports, matching the source pins. The density owner restores current sources after style replacement, reconciles range/import/epoch changes, and disposes its listeners, canvas, reads and timers without affecting another map or the shared library worker pool. Disabled density performs no exact-history read. Hexagons page the complete bounded point window; country membership uses the cookie-authenticated `/native/map/data/countries` closure. Limit/expiry failures are visible and do not publish partial history as success.

Additional scalar config is fogEnabled/fogMode/fogRadius/hexagonsEnabled/scratchEnabled. The server normalizes locale against the available translations and supplies a plain-text hexagon count label; user-provided markup is never evaluated. Layer progress is a root-local `map:progress` DOM event carrying only loaded/complete counts; generic failure codes use the existing `map:failed` receipt. Geometry and cell buffers remain local to the owner.

At A7 the minified eager graph remains 168,125 raw / 51,666 gzip bytes. The static map-open graph is 25,565 raw / 9,006 gzip and excludes density/H3/PMTiles. Density's static graph is 20,753 raw / 6,982 gzip; library chunks are measured separately in the implementation report. Production browser/390-px checks now belong to stage acceptance under the revised controller decision in the approved plan.

## Photos

`PhotosLayer` owns clustered sources, viewport DOM markers, spider legs, popup listeners and image object URLs. `createPhotoLoader` pages the full bounded cookie window with unchanged start_date/end_date parameters before publication; failed or cancelled partial reads never become successful photo data. Provider partial-source headers produce one bounded warning while retaining successful rows. Backend listing/cache semantics remain delegated to the existing Photos.Index; the browser-only adapter paginates that result without changing external API responses or provider credentials.

Thumbnail reads return owned image/jpeg Blobs via same-origin cookies; marker removal aborts its request and revokes its object URL, including when the transport ignores cancellation. No account key or provider URL is serialized into a marker or popup. Clustering, rings, viewport deduplication, zero-coordinate exclusion and escaped metadata remain source-compatible. Locale-normalized server labels are a fixed small dictionary, and only the photo canvas resources are ignored DOM. Added scalar config: photosEnabled; photoLabels is server-produced and ignores caller overrides.

The A8 minified photo static graph is15,365 raw/6,034 gzip bytes and stays outside the ordinary map-open graph (26,122/9,199). Eager graph remains168,125/51,666. Browser/390-px/resource acceptance remains with stage acceptance, as the controller decision requires.

## Entity display ownership

`createEntityLayers` owns viewport Visit reads, tag-filtered Places, circular Areas, Anomalies, selection display, style restoration and one popup. Complete bounded pages replace the current generation atomically. Viewport movement waits for an active range load and then refreshes only Visits. An empty place tag filter performs no Places read. Native Area pages slice the unchanged `Areas.Api.index` projection; the external API is unchanged.

`mountHost.entityLayers` exposes the owned display service: `visitPresentation({selectedId,status,dayRoute})` and `selected(geojson)` retain browser-local geometry across style replacement. Native popup selection sends only `map:select {kind: visit|place|area|point, id}` after matching a current owned feature. Track B commands must independently admit and authorize that resource. No feature properties or geometry enter the receipt. Host destruction cancels reads, clears selection, closes popups and removes every listener.

Additional config: visitsEnabled/placesEnabled/areasEnabled/anomaliesEnabled and placesTagFilters. Entity popup labels come only from normalized server translations with bounded interpolation tokens; replacing locale/range closes the old popup. This service introduces no controller registry.

## Family reads and overlay

Native cookie resources `family_locations` and `family_history` freshly admit family membership/entitlement and each member's sharing grant through the current family interfaces. History retains start/end, sharing-start/window and 5,000-point sampling semantics. Geometry is returned only over HTTP, never embedded in the map component. Family runtime clears its owned markers/history/popup before refresh, aborts obsolete requests and rejects late non-cooperative completions. Reconnect refreshes membership on the existing map. Style listeners and relative-time intervals belong to that owner; independent maps are unaffected. A14 uses authorized invalidations rather than trusting raw channel location events. m4 owns the surrounding page/forms; X1 adopts the extracted map insertion point.

`FamilyMap.family_map` is the m4 map insertion point: Family hook, scalar allowlist, server locale and original distance-in-words templates. `FamilyHook` shares only the thin lifecycle binding with Map; its runtime is a dedicated lazy import. Locale replacement disposes the previous popup/interval before repaint on the same map. No controller lookup or ActionCable dependency.

## Trip read boundary

`Maps.Dependencies.Trip.config(scope,id)` returns only scalar metadata/range/display options. `read` returns the same config plus overview path/device windows/plan over the cookie `trip` HTTP resource, never LiveView assigns. Current implementation delegates TripPage's existing ownership/settings/plan gates and data calculations; unsupported/missing reads become a typed refusal without a hybrid redirect. The m5 adapter switch will replace this current page projection with its accepted read facade and measure the deferred resource/query budgets.

## Trip runtime and insertion

`NativeTripMapPanel.panel` keys the Trip canvas by `tripId`. `TripHook` lazily imports `mountTrip`; one runtime owns its day routes, plan, flights and photos. Reads refresh current owned Trip metadata/device windows before exact geometry is loaded. Destruction cancels style/point reads and releases every owned layer. Reconnect reuses its map. Its stable `source` has `fixedRange: true`, verifies both current revision and fresh Trip range, and separates visible poster flight arcs from video/replay timed GPS. `trip:day` carries only a day identity; parent page integration belongs to X1 and the m5 adapter switch.

## Preview contracts

`NativeMapPreview.preview` accepts resource ID or a form range, interactivity/numbering/style scalars, and public-stat UUID/bounds. It serializes no path, plan, credentials or owner identity. `MapPreview` observes visibility and admits at most two live previews per document by default; hiding/destroying releases its slot, map, read and listeners. Reconnect refreshes the same visible owner. This safety default awaits measured O8 acceptance. Trip/form data uses the scoped cookie reader; public stats only request the existing UUID-clipped hexagon API with credentials omitted. Public refusal clears geometry before retry; localized hover/popups and style restoration are owned by the preview. m5/controller parent insertion remains X1.
