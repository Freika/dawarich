# Milestone 6 native map contracts

Status: S1 foundation contracts implemented, 2026-10-10. The controller starts tracks B/C/D only after the separate S1 SHA artifact exists. Source baseline is `bdaa9aa36`; the A0 measured baseline is recorded in `native-m6-inventory.md`.

## Session and domain admission

`Dawarich.Maps.principal(user, locale)` returns an Accounts.Scope containing a sanitized actor and a SHA-256 fingerprint of the original Devise session salt. Raw API keys, password hashes and provider settings never enter this scope. The fingerprint remains immutable across refreshes. `Maps.admit(scope)` returns a refreshed sanitized scope; `Maps.with_actor(scope, effect)` independently checks that original fingerprint, lock/deletion/status/subscription before invoking the effect with its transient domain actor. Commands must recheck inside their transaction when they span a read/effect boundary.

`Maps.page(scope, params, opts)` wraps the existing MapPage queries and returns `{:ok, projection}` or `{:error, :stale_session | :unauthorized | :not_found | :invalid | :unavailable}`. Projection excludes credentials, bulk points/tracks and signed subscription URLs. Settings on the actor are allowlisted. Existing hybrid consumers of MapPage remain unchanged until X1; no native host delegates its UI to them.

`DawarichWeb.MapLiveAuth` is the dedicated native host hook. Its `live_session/1` signs the original map identity into the server mount session. Connected mount also compares the socket session actor ID; events, params, info and async each re-admit. Session loss clears state and redirects to sign-in. Resource refusal clears the projection and records a typed error in place, with no reload to the same URL. X1 adopts this hook on the routed hosts.

## Integrated dependency boundaries

Stage-2 switches are complete. No cross-milestone dependency adapter remains.

| Boundary | Integrated module | Preserved admission |
| --- | --- | --- |
| Principal | M4 Principal.project and DataAccess.admit | Original session_version, sanitized state, fresh callback admission |
| Family | Maps.Family over Families page, Locations, History and Commands | Atomic consent snapshot, numeric invitation/reveal boundary |
| Trip | Maps.Trip over Trips.Pages and Commands | Owned bounded cards, description, fresh resource admission |
| Public | Maps.PublicGrant over Sharing.Public; Maps.Public over Sharing.Pages/Delivery | Immutable versioned grant, independent current cookie proof, bounded 31-day cursors |
| Realtime | Maps.Realtime and EventBus | Typed M4 producer events; retained external point/track transport |
| Notes | Trips.Notes; NotesApi.Read.index/3 and Write.create/4 | Fresh owned day/Visit admission; integrated m5 notes/ActionText |
| Route video | RouteVideos.Uploads and M4 Uploads | Opaque owner-bound reservation, verified object claim, cancellation |
| Poster progress | Posters.Events | Publish only after successful worker transaction |
| Styles | Native poster theme_loader/style_builder | Pure native modules, no Rails JavaScript graph |

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

`Maps.Trip.config(scope,id)` returns only scalar metadata/range/display options. `read` returns the same config plus overview path/device windows/plan over the cookie `trip` HTTP resource, never LiveView assigns. Current implementation delegates TripPage's existing ownership/settings/plan gates and data calculations; unsupported/missing reads become a typed refusal without a hybrid redirect. M5 Pages now owns admission and presentation; the existing shared TripPage remains the geometry provider.

## Trip runtime and insertion

`NativeTripMapPanel.panel` keys the Trip canvas by `tripId`. `TripHook` lazily imports `mountTrip`; one runtime owns its day routes, plan, flights and photos. Reads refresh current owned Trip metadata/device windows before exact geometry is loaded. Destruction cancels style/point reads and releases every owned layer. Reconnect reuses its map. Its stable `source` has `fixedRange: true`, verifies both current revision and fresh Trip range, and separates visible poster flight arcs from video/replay timed GPS. `trip:day` carries only a day identity; parent page integration belongs to X1 and the m5 adapter switch.

## Preview contracts

`NativeMapPreview.preview` accepts resource ID or a form range, interactivity/numbering/style scalars, and public-stat UUID/bounds. It serializes no path, plan, credentials or owner identity. `MapPreview` observes visibility and admits at most two live previews per document by default; hiding/destroying releases its slot, map, read and listeners. Reconnect refreshes the same visible owner. This safety default awaits measured O8 acceptance. Trip/form data uses the scoped cookie reader; public stats only request the existing UUID-clipped hexagon API with credentials omitted. Public refusal clears geometry before retry; localized hover/popups and style restoration are owned by the preview. M5 native form, monthly and public report hosts are integrated.

## Public capability boundary

`Maps.Dependencies.Public.config/read` uses a separately validated share capability, never an owner Scope. Current SharedLinks/FamilyAudience and SharedApi privacy queries remain authoritative. Private phrase grants contain only a second-hashed unlock fingerprint and exact signed cookie expiry; SessionStore exposes these as ephemeral connection metadata and drops them before cookie persistence. Family grants validate the original viewer session and fresh membership; their Rails phrase exemption is retained. Revocation, expiry, phrase rotation, deleted owners, missing resources and changed grants are typed refusals. Native reads re-admit after completion before emitting provider bytes or geometry. External APIs remain unchanged.


PublicMapLive consumes only metadata plus an opaque capability fingerprint. Connected mount replaces the HTTP proof with current trusted connection session metadata. Every callback re-admits; expiry is an owned timer keyed by deadline/revision/token. Refusal clears config and destroys the hook through map:clear. Phrase unlock remains `/s/:id/unlock` HTTP. Native map host additionally admits shareId/publicType/routeEnabled/validUntil scalars.

Native public browser reads use GET/HEAD `/native/public/maps/:id/{metadata,points,route,photos,photos/:photo_id/thumbnail}`. Only source is a query parameter; every result is capability-admitted before and after the effect, never an impersonated owner. Responses are private/no-store with Cookie Vary; typed locked/not_found/changed/unavailable refusal. Existing public sampling (10,000 points and 100 public photos) is preserved, with no pagination completeness claim. External shared API and unlock/download contracts remain unchanged.

Public runtime owns public reader/route/day/latest/photo layers and a public-only fixed-range replay source. Metadata is reread before publication; a changed grant clears cached geometry and photos rather than restoring them on style reload. `show_photos=false` performs no photo acquisition. Public Trip `byDay` and route thresholds are profile values; live location remains separate from the route-history flag. Normalized locale/photo labels persist through scalar config updates. No browser-only public poster/video source is admitted.

`MapLive.Subscriptions.sync(socket, descriptor)` subscribes connected admitted map/trip/family/public-live owners through Maps.Realtime. Reconcile is idempotent; `deliver` re-admits queued events, releases changed topics and stores only a bounded digest ledger. `map:invalidate` has kind/revision scalars, with no point/edit/HTML/binary payload. `release` runs before callback admission halts; normal bus process monitoring handles host exit. Native owners call sync/deliver/reconnect at X1 integration. Native typed producers are integrated; eight-field external point tuples remain unchanged.

The common MapHook lazily loads `createRealtime` with the concrete owner. Pre-ready invalidations are bounded metadata, and active reconciliation coalesces bursts into one current and one follow-up read. Typed revision dedupe survives reconnect; clear/destruction drains queued timers/receipts before releasing the map. Ordinary page eager graph contains no map-data helper.

Native pure basemap classification and fallback composition preserve style-document versus tile/sprite/glyph failures, root-relative style URLs, XYZ vector/raster detection and source/layer stack order. These independent modules do not fetch styles. A15 loader/theme and disposal-aware fallback fetch wiring consume C0.2 theme/schema at controller integration.

Viewport persistence accepts only `user:<positive account ID>` namespaces generated by the admitted server host. The native cache starts empty and retains same-user native views; legacy API-key-derived entries are not read or migrated (ED-NATIVE-M6-VIEW-IDENTITY). Account changes restore that account’s saved view or the supplied fallback. Owned moveend listeners are removed without writing on destruction, and late restores are inert. RTL uses the supplied packaged plugin URL with lazy per-library registration; warm library state is separate from host-owned handles and errors are typed. A15 loader/default asset wiring remains pending C0.2/controller integration.


## Integrated map commands and replay

`MapLive.Native` owns native range/calendar/timeline/settings/entity/selection/Area/segment/point/enrichment events and keyed components; route adoption remains X1. Dialogs/feed controls live outside the ignored canvas. Safe UI labels are server-produced plain-text templates. The one shared native editor/point-command history changes only after an accepted typed revision; stale replies restore canonical coordinates and render bounded conflict feedback.

Map/Trip/PublicMap roots insert one `NativeMapReplay` component and inject one replay owner over their existing scoped source. Replay opens through bounded exact snapshot reads, retains one rAF clock and owns panel/density/follow/cycle/card/marker lifetimes. Photos reveal by profile day and playhead; date/day replacement and close discard popups, requests, blobs and listeners. Ordinary photos hide while replay owns the display and restore on close. Map and Trip acquire the photo window once using `start_date`/`end_date`; Trip retains device-window point filtering and PublicMap keeps grant revalidation. A profile timezone change creates a new replay clock. Photo UI is a guarded lazy import and stays outside the ordinary map-open graph. Close returns focus to its opener; revocation/host disposal releases everything.

The integrated map/poster/video style adapters import native C theme/schema/render modules and A6 geometry. The recursive native graph contains no Rails JavaScript inputs.

## Integrated studio operation bounds (O8)

Controller integration keeps the reviewed values: first idle: 60 seconds; negotiation: 30 seconds (one overall owned deadline); hook reply: 30 seconds; upload: 1 byte–250 MiB; gallery: 10 rows. Storage PUT is bounded by five minutes. Poster capture is bounded by five minutes and print upload by ten minutes. These bounds refuse visibly and release owned resources; no codec, paper size, DPI step-down, frame duration or media format changes. Controller 20:50 scope cut removes browser resource, heap/GPU and workload timing measurements from X4/X5.

## Native map route retirement

Timeline feeds, calendar, track-info, segment drawers/writes and point-address frame URLs now return HTTP410 without dispatching an effect or a Rails hand-back. Native successors are `MapLive.Timeline`, `TimelineFilters`, `SegmentCommands` and `VisitCommands`. External API geometry and write contracts remain unchanged. `/map/residency` remains for Insights, `/places/nearby` for independent Places navigation, Area/point-list/recalculation writes for their surviving pages, poster/video HTTP actions for current Trip consumers and gallery seeds. Those surviving callers prevent deleting their shared domain/transport modules before the corresponding milestone integration.

Public `/s/:id` now uses the production PublicMapLive session and native root. Successful, locked and revoked page states remain native; their LiveView shell responds200, while phrase-unlock stays the existing HTTP POST with its exact cookie/redirect/status contracts. PublicMapLive records each admitted static GET once with the existing SharedLinks view counter; HEAD, connected mount, reconnect and locked/refused visits do not increment it.

## Static production closure budgets

X4 reads the minified emitted files and sums each recursive static closure, with dynamic imports and external URLs excluded. The metafile supplies only graph edges; its reported byte fields are not trusted. `Dawarich.Build.NativeAssetBudget` rejects missing/unknown closures, malformed receipts, and either raw or gzip excess. Caps are decimal bytes, frozen with roughly15–22% headroom over the integrated measurement.

| Entry | Measured raw / gzip | Raw cap | Gzip cap |
| --- | --- | --- | --- |
| app | 173727 / 53312 | 200000 | 65000 |
| map | 112158 / 39266 | 130000 | 45000 |
| poster | 50623 / 21873 | 60000 | 26000 |
| video | 88071 / 30408 | 100000 | 36000 |

Named static tests exercise each exact boundary, every one-byte excess, malformed receipts, and an actual emitted oversized banner with dishonest metadata. Browser memory/resource measurements remain outside acceptance under the controller scope cut; functional owner/navigation/cancel behavior remains covered by native behavior successors.

## Trip presentation insertion contract

Maps.Trip.view/3 reads one fresh owner-admitted TripPage and projects safe config, presentation and two studio scalars from that same read. Presentation contains source summary/countries/days/notes/itinerary metadata, no path/device-window/plan JSON, API key or stream token. Photo and itinerary source destinations reject credential-bearing URLs; thumbnails use cookie-authenticated reads. NativeMap renders read-only presentation, refreshes it on params, updates the title and clears both presentation/title on a refused resource. Malformed IDs refuse locally. Native action/day/notes controls and production parent insertion remain X1 work; probe behavior is not a production route claim.

Trip day selection uses fresh admitted days and `trip:select_day` receipts. The Trip hook owns this handler, buffers an early receipt until map readiness, calls only its current layer owner, and removes the handler on destruction. Removing the resource refuses the next day command and clears the owner. Canonical production parent insertion is active.

Native Trip notes keep only one bounded editor projection. The server selects the date/note from its freshly admitted Trip days; save/update/delete use the existing WebNotes domain service through Dawarich.Trips.Notes. Validation preserves the editor; cancel writes nothing; losing resource admission clears the root/editor and map owner. Browser notes use the principal Repo rather than the configurable job repository.

Trip photo/flight/plan visibility uses local Boolean overrides, pruned against freshly admitted settings/plan capability. Controls emit safe map:config receipts; all-days expansion emits an all-day selection receipt without changing the studios' Trip range. ARIA states are explicit text values.

Native Trip itinerary presentation uses pure source formatters. A stop-focus event carries only its identity; the server resolves admitted current coordinates and emits trip:focus only while the plan is visible. The Trip hook buffers early focus until readiness and removes its handler on destruction. Unknown/malformed IDs and removed stops do not emit focus; revoked resources clear the map.

Native Trip deletion, GPX/GeoJSON export and recalculation delegate to existing domain services through Dawarich.Maps.Dependencies.Trip. Every effect refreshes resource admission, local format/ownership refusals retain the page and show localized feedback, recalculation retains its cooldown/outbox behavior, and successful deletion/export navigate to their normal result pages. Edit/share navigation remains at pending m5/m4 page boundaries.

Trip delivery reconciles owned user/Trip topics, rechecks resource admission before callbacks, refreshes the safe presentation, and emits changed configuration to its current map owner. Refusal clears root/title/editor/gallery and local display choices and releases map subscriptions. Initial inactive principals do not mount studio owners. Tests settle subscription acknowledgement receipts before ownership withdrawal to make queued callback guard mutations deterministic. The parent has no direct async operation today; a common admission hook is registered for that phase.

### Main-map Family layer

The main native map keeps the `Family Members` layer preference and exposes only `familyEnabled` in its config. The client owns its member list, current locations, history overlay, centering feedback and polling; those arrays stay outside LiveView state. The layer uses the same scoped cookie location/history endpoints and overlay as the native Family page. Config changes, disable, refusal and disposal clear visible data and cancel pending reads. A superseded reader cannot publish after a newer result.

The optional Family stream is admitted through the canonical Maps.Family boundary only while the actor's current preference and membership allow it. Layer saves reconcile listeners. Membership loss releases the Family stream and emits a bounded reconnect invalidation while keeping ordinary map streams, which causes the private Family read to refuse and clear client data. Events carry kind/revision, never coordinates or legacy payloads.

Member controls keep source update timestamps in the profile timezone, sharing-since dates/history-day counts, localized singular/plural loaded feedback and ordinary map centering. Photos and Family remain separate lazy engines under the map owner's auxiliary-layer lifetime.

## Integrated source corpus and pending domain switches

The canonical Trip index uses `TripsLive.NativeIndex` and `NativeTripCard`; scalar preview configuration identifies an owned Trip and saved style, while scoped cookie reads supply its path/plan. Card metadata, units, country/day counts, pagination, empty/calculating states and local refusals retain the source corpus. M5 Trip form/editor routes precede the M6 show resource and mount native previews; the M6 trip show host mounts the rich-text editor. Principal, Family, Trip, Public, Realtime, Notes and RouteVideoUpload now consume the integrated canonical domain modules. Video dependencies now use the integrated poster modules and A6 geometry.

Native Map/Trip/Family/public routes ignore obsolete UI rollback keys and use their admitted native sessions. Consumed frame/address/segment endpoints refuse with 410, no cookie changes and no effects; the external APIs, retained form writes, downloads and phrase unlock retain their source protocols. Source-data fixtures keep their geometry, calendars, normalized fields, unit/date/country values, refusal/privacy, transaction/outbox and byte assertions. Named native behavior replaces importmap/controller/frame transport checks; the detailed test-retarget ledger records each successor. Current native CSS is checked against the Docker source closure and deterministic compilation, while unrelated asset exports retain their original hash contracts.

Standalone browser specs collect without execution during implementation. Actual native controls and independent scoped/API reads replace mutable controller probes; real socket/HTTP responses can be held for deterministic races but are never fabricated. The three pre-existing photo-integration and fifteen family-plan fixture fixmes remain declared upstream dependencies. Browser, locale and real-file checks belong to controller acceptance; browser resource measurements are excluded by the scope cut. X4 verifies only the emitted production graph, workers and frozen byte caps.

Stage 2: Visit notes call NotesApi.Read.index/3 and NotesApi.Write.create/4 directly after fresh map ownership admission. Native trip day notes use Dawarich.Trips.Notes.save/delete after Maps.admit; no Notes dependency module remains.

## Stage-2 map hosts and media activation

Private Stats month is a NativePage route with an owned_stats preview. Heatmap and bounded point layers use cookie readers and owner-local month bounds. Public monthly reports use NativePublicPage/NativePublicMonth with the M6 UUID-clipped preview, native chrome, lazy idempotent initialization and page-departure cancellation. Visits navigation refuses malformed query shapes locally; map Visit update/merge/bulk commands use canonical M5 Visits.Commands. Poster PNG encoding loads only when export starts; independent page startup caps remain frozen.

Stage-2 inherited named test replacements are recorded in [native-stage2-retargets.md](native-stage2-retargets.md). The integrated host keeps M4 cookie/session/signout admission, M5 Trip card styles and resource day windows, canonical M4 gallery thumbnails with a final delivery check, and all native form owners. Public monthly source distance, active-day and country totals accompany the native map/charts. Shared job-owner writer tests are synchronous because their locks persist across sandbox lifetimes; the admission protocols and production locking remain unchanged.
