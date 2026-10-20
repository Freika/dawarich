# Native frontend development

Status: **Implementation guide finalized**, 2026-10-11, against the integrated stage-2 m7 base. Commands are source-aligned; the [C-track results](native-m7-inventory.md#track-c-implementation-results-2026-10-11) distinguish executed targeted tests from pending acceptance. The A/B cleanup deliveries are merged; the integration report records the executed checks and remaining reconciliation. X4/X5 still supply production build, serving, packaging, fallback and runtime evidence; this guide is not yet an accepted release runbook.

## Prepare a private checkout

Use the controller-assigned feature branch and private resources. Keep database names, Redis/listener ports, scratch paths and credentials out of tracked files. Obtain the fixture link and targeted runner from the controller; `test/fixtures` points to the separately owned E2E corpus. An app SHA does not pin those external bytes. Do not regenerate or prune the corpus to match new markup.

`mix.exs` currently requires Elixir `~> 1.20`. The approved m7 targeted runner selects Elixir 1.20.4/OTP 27.3.4.1; an older generic 1.18.3 environment does not satisfy this branch. Use the runner's toolchain when running Mix manually. Define `PHOENIX_TEST_DATABASE` and `PHOENIX_TEST_REDIS_URL` from the private allocation before every Mix invocation, including build/format commands. In test mode the partition suffix is appended to the database prefix; Redis ports also advance with `MIX_TEST_PARTITION`. Never rely on shared defaults.

From `app-phoenix`, after supplying private settings:

```sh
: "${PHOENIX_TEST_DATABASE:?private test database prefix required}"
: "${PHOENIX_TEST_REDIS_URL:?private Redis URL required}"
export PATH="$HOME/.asdf/shims:$PATH"
export ASDF_ERLANG_VERSION=27.3.4.1 ASDF_ELIXIR_VERSION=1.20.4-otp-27
export DATABASE_HOST=127.0.0.1 MIX_ENV=test
mix deps.get
(cd assets && npm ci --cache "${NATIVE_NPM_CACHE:?private npm cache required}")
mix assets.setup
mix assets.build
```

The variables in these examples must be set by the developer/controller; they are not committed allocations. The commands install dependencies/build assets, not a web service. Missing dependencies or private test schema are setup work. Use the targeted runner's schema preparation for its private database. For a separately assigned Rails schema oracle, detect Ruby first, use Ruby 3.4.9 with the returned activation command, and invoke Rails only with `RAILS_ENV=test DATABASE_NAME="$PRIVATE_DATABASE" REDIS_URL="$PRIVATE_REDIS_URL"` inline. Never export `DATABASE_NAME`; load only the authorized database credential fields without printing them. Do not use `ecto.reset`/`ecto.drop`: the aliases intentionally refuse.

## Test fixture isolation

Whole-format import recordings pin parent and initial-child identities. Compose their setup with the storage/environment fixture only; do not create an unrelated auto-ID lease import first. A generated row can already occupy a recorded identity before `SeedIds` has a chance to advance its sequence. `A12f3bImportsFixture.setup/1` accepts an existing context for these cases, while `setup/0` retains its lease fixture.

In a shared SQL sandbox, drain a LiveView's async reads with `render_async/1` before changing authorization data or patching the view, and drain the patched reads before the next change. Canceling a task during its checkout can disconnect the shared holder while the test owner is still alive. Clock tests should settle the reads before expiring access so they exercise re-admission without racing the sandbox connection.

## Edit native frontend code

The native entrypoint is `app-phoenix/assets/js/app.js`. `assets/js/hooks/index.js` registers named hooks for browser libraries; domain behavior lives in contexts taking `Accounts.Scope`. Keep library/editor/map/studio imports lazy, worker/style URLs compatible with production digests, and direct-upload adapters explicit. Native uploads do not imply a Hotwire dependency. Inspect the emitted graph as well as source markers: an import name scan alone misses bundled/lazy code.

LiveViews own forms, errors, confirmations, URL params and action acknowledgement. HTTP remains appropriate for session/cookie authentication, downloads, public unlock and signed storage. Use plain admitted HTTP forms at those boundaries. Across distinct live_sessions use a full document transition; within a compatible session use native navigation/patches. No controller registry, ignored editable island or per-request Rails handback is a native successor.

Keep credentials/capabilities out of retained form/socket state, event replies and logs. Renew credential forms after submit/error/close/reopen. Re-admit actors on params/events/info/async/reconnect and in scoped contexts. Async work needs a per-run token, bounded timeout and stale-result rejection. Maps/studios must destroy their own instances/workers/listeners on departure and ignore revoked private updates. Library-owned DOM may be ignored within a keyed hook; ordinary server-owned forms and gallery rows remain patchable.

**Development serving workflow:** rebuild `mix assets.build` after JS changes; use the controller-prepared foreground native stand to load the exact app/E2E identities. The current dev config does not define an assets watcher. The current runtime has lifecycle/readiness/source-debt admission beyond an endpoint startup, so a generic `mix phx.server` is not a verified substitute for the prepared stand. Stop all services you start unless a brief explicitly requests otherwise. X4 will provide the accepted production/native and separate Rails artifact startup procedures; no start command or default is changed by these instructions.

## Build and dependency removal

These are existing aliases from `app-phoenix/mix.exs`, run with the private test environment already supplied:

```sh
mix assets.deploy
mix format --check-formatted
mix compile --warnings-as-errors --all-warnings
```

`assets.build` first runs `dawarich.native_assets` to compile Tailwind/native styles and copy the positive static ledger, then invokes the configured `esbuild native` profile: ESM, splitting, output `priv/static/native`, and external `/maplibre/*` imports. Both aliases audit the emitted import closure with `dawarich.native_graph`. `assets.deploy` minifies that profile and runs `phx.digest`, producing `priv/static/cache_manifest.json` and digested static outputs. The native JS graph/demo eager-byte caps remain required. These source-aligned commands are not fresh production-build evidence for this delivery.

| Input/boundary | Current source | Owner delivery / acceptance still needed |
| --- | --- | --- |
| Native JS | Phoenix esbuild entrypoint/profile, feature hooks and lazy library/worker chunks | A1/A2 merged; emitted graph and per-feature byte caps remain required. |
| CSS/fonts/images | `Dawarich.Build.NativeAssets`, `assets/native-static.json` and Phoenix digest resolution | A3 merged; native stylesheet/font/worker serving tests remain required. Tailwind/DaisyUI and source class inputs stay. |
| Importmap/Sprockets | Isolated `tools/rails_frontend` legacy oracle/tooling | Native build discovery does not call these tools. Rails whole-app build sources and their independent parity tests stay. |
| Runtime data | `mix dawarich.build_inputs --root ... --out ...` exports i18n/achievements/timezone/geodata | Data exports are independent of frontend configuration; retain exact bytes and validation. |
| Docker native stages | Positive native static/renderer/font/PWA/Swagger inputs | A4 recipe changes merged; X4 still owns actual image/export/startup acceptance. |
| Feature locations | Web families under `dawarich_web/features`, browser hooks under `hooks` and library code under `maps`/`studios` | A4/B4 moves merged, retaining module names, URLs, Scope and session contracts. |

A successful esbuild command alone does not prove native CSS, production font/worker URLs, renderer output or a Rails-independent image. Keep the historical hybrid build instructions as history until the corresponding runtime consumers are removed.

## Run native behavior tests

From the app checkout, set `M7_TARGETED_RUNNER` to the controller-supplied m7 runner:

```sh
zsh "$M7_TARGETED_RUNNER" \
  test/dawarich_web/native_shell_test.exs \
  test/dawarich_web/native_shell_events_test.exs \
  test/dawarich_web/native_root_test.exs \
  test/dawarich/build/native_m7_corpus_ledger_test.exs \
  --warnings-as-errors --seed 404
node --test app-phoenix/test/client/native_account_menu_patch_test.mjs \
  app-phoenix/test/client/account_menu_patch_test.mjs
```

The runner changes into `app-phoenix`, supplies the toolchain/private database/Redis, and prepares its private schema if missing. Keep `--warnings-as-errors`. Run every changed module's test file and direct callers; when registers change include their readers, including `a12f3a_o_closure_test.exs`, `a12f3b_s02_test.exs` and `native_m7_route_ledger_test.exs`. Some oracle cases carry the existing `rails_parity` exclusion; a targeted pass does not mean the excluded corpus ran. Preserve exact API/crypto/effect fixtures and the [named successor mapping](native-m7-test-retargets.md).

For a new named behavior: record assertion RED, minimal GREEN, a named mutation that fails it, restored GREEN. Setup/compile failures do not count as RED. New ExUnit modules use `async: true` unless they mutate global state; record a sync reason in the assigned plan. Pure documentation edits/path-only moves use source/link/compile/consumer checks instead of new tests that mirror file layout.

Full ExUnit is authorized only by a FULL GATE brief and only through the controller's `seedrun.sh`, using fresh private partitions, seeds 404 then 202, and every partition exit/count. Do not start it during an implementation/fix round, bypass its machine-wide slots or share its databases with targeted runs. Full RSpec, if required by changed Ruby code, uses `slot.sh`; copy and restore Swagger around every RSpec batch. Wait for every suite summary before finishing.

## Native E2E and acceptance

Edit E2E only in the controller-assigned E2E checkout. From that checkout, an implementation-time discovery check is:

```sh
E2E_APP_MODE=standalone SELF_HOSTED=true npx playwright test --list \
  native/navigation.spec.js native/frontend-free.spec.js \
  native/assets-budget.spec.js native/socket-lifecycle.spec.js
node --test unit/native-asset-probe.test.mjs
```

C2 supplies this path and the companion `frontend-free`, `assets-budget` and `socket-lifecycle` specs on its E2E delivery head. Use the app/E2E pair recorded in Results. `--list` proves discovery/syntax, not a browser pass. Select controls by role/label/testid and await native join/action acknowledgement rather than Turbo/Stimulus presence. Disable sensitive credential/share/export captures; assertions compare booleans rather than printing tokens or signed URLs.

G44 runs only at stage acceptance: stage 1 integrates 3c/3d/4/5; stage 2 integrates 6/7. The controller prepares the stand and runs three standalone lanes sequentially at frozen app/E2E/image identities. English/German 390px overflow, per-element bounds, keyboard/focus/Escape, navigation/reconnect and real lazy library/worker behavior belong to that acceptance. Unit hook stubs and spec discovery do not replace those checks.

The 2026-10-10 scope cut removes D1–D4 performance/load/resource measurements. Preserve existing byte-cap/bundle-boundary tests, behavior/lifecycle tests and functional packaging/fallback acceptance. Do not require a control matrix, report invented speedups or advance a milestone on partial evidence.

## Browser contracts and measurements

C2 adds same-session/back-forward navigation, full document/session boundaries, expired-session draft refusal, lazy editor/emoji/map/studio admission, share revocation across reconnect and bounded map/worker teardown. Native video-gallery fixtures now use reservation/storage/save acknowledgements from the owned VideoStudio hook. Resolve that hook through its owning `[data-phx-session]` element before calling `getHook`; `getViewByEl` resolves a LiveView, not a hook element. Trip video ranges show exact endpoints in the route timezone, while the trip summary shows dates only. Accepted import-detail deletion returns immediately to the imports list with the deletion notice; cleanup remains asynchronous. The replay error case uses the native map hook and persistent server flash; ED-NATIVE-M7-C2-FLASH keeps the historical Rails retry correction separate from pending native browser evidence. No global controller registry is used.

The asset probe drains every response-body promise, includes `.js`/`.mjs` fetched worker bodies, removes its own response listener and emits only declared static pathnames and scalar measurements. `decoded` is the body delivered by Playwright; `gzip` is reconstructed with Node gzip for a stable cap; `wire` is optional response Content-Length, not a measured transfer total or parse time. Undeclared script URLs are reported as a generic tag; queries, signed URLs and body text are never attached. Map probes count observed instances/removals and worker creations/terminations rather than asserting an unmeasured memory slope.

Source-feature browser successors already delivered on the stage-2 E2E base remain: `auth/` sign-in/registration/remember/OTP/recovery/session cases; `admin/` access/users/instance/background; `places/` native list/drawer/nearby; `imports/`, `imports-exports-zip.spec.js`, notifications and families lifecycle/consent; `trips/rich-description.spec.js`, notes, gallery and trip studio; `v2/map/` native public/family/replay/poster/video/export journeys. Their collection or prior source presence is not a new lane pass. Sensitive captures remain disabled on the new/retargeted credential/share paths.

Controller acceptance must execute the eight new browser cases plus changed inherited cases, named navigation/auth/revocation/destruction mutations and English/German 390px label, keyboard/focus/Escape and document/Range overflow checks. C2's 17-test/11-file discovery and two probe unit passes do not satisfy that gate. Record any skips/flakes, exact identities and unsupported measurements in X5 Results; no performance/control experiment is required.

X4 packaging commands and smoke contracts are documented in [native production smoke](native-production-smoke.md). Executed artifact evidence belongs to the controller report; X5 remains the release acceptance gate.

### X5 group 1 browser contract reconciliation

The native account menu submits logout as an HTTP POST form with a DELETE override. LiveView DOM reconciliation preserves browser open/closed state for that form-bearing disclosure, while a server removing the logout action can still close or replace it. This avoids the initial connected render closing the menu between opening it and submitting logout.

Browser successors wait for the destination path and native join before history checks, and open both the mobile navigation and nested My Data disclosure before selecting Imports. Native RichText owns a lazily loaded Trix textbox and its readiness acknowledgement; Trix alone is an admitted library, while the ActionText wrapper and Hotwire runtime remain forbidden. Poster close uses its native dialog form. Disconnect checks inspect transport state rather than an obsolete CSS class. Offline simulation explicitly disconnects the existing socket; reconnect readmission preserves the map instance and authorized route sources while refreshing server metadata.

Asset audits drain observed browser response bodies. When Chromium cannot retain a body, they fetch the same declared static pathname without query parameters, verify status and audit its canonical bytes. Undeclared URLs and failed observed responses stay refused. Decoded/gzip values then describe canonical served bytes; optional wire Content-Length remains from the observed response. This is a tooling correction, not a raised cap or a transfer/parse-time measurement.

Executed lane evidence and exact code identities are recorded in the controller report `fix-x5f1.report.md`. Milestone/release acceptance remains controller-owned.

Public map refresh compares grant fields independently from the request lease deadline. Fresh API reads may renew that deadline as time advances; an advancing finite deadline is admitted only when every other metadata field remains equal. A shortened, removed or newly bounded deadline remains a mixed-grant refusal, as do route/range/photo/capability changes. Server authorization and the LiveView deadline remain authoritative; this correction changes no public API or lease duration.

## Browser timing regressions

Map config echoes are idempotent after layer-preference normalization. Reapplying the current config shares the preceding update result and preserves reader generation, pending editor reads and selected timeline geometry; changed configs retain their existing invalidation. `map_config_echo_test.mjs` holds real cookie-reader responses to verify this without timing assumptions.

Point-edit history browser setup and cleanup acknowledge preceding LiveView commands with a `map:ready` reply and drain the client settings/config promises they started before selecting or moving points. A checked input, idle camera or loaded tiles alone does not establish that server settings reached the editor. Style changes use the persisted appearance control; calling `owner.settings()` alone changes only client state, which a subsequent authoritative server config can replace. This contract is mirrored in AFFiNE's `Dawarich — Native map layer browser regressions`.

Registration assertions select the locale used by their labels explicitly, including when the shared account previously chose another language. A connected LiveView alone does not establish the language of its controls.

Family tests complete the localized tab's map admission before reloading the other tab, and await fresh map-read completion, rendered consent state and the existing `map:ready` acknowledgement before the next consent change. A locale parameter persists account settings; overlapping that write with the other tab's guarded snapshot can produce `grant_changed`. Snapshot refusal remains fail-closed. Consent revocation, retained canvases and fresh reconnect reads remain required.

Replay advancement tests seek their owned short fixture segment before starting normal-speed playback. The shared day's first minute can contain unrelated points and is not a bounded timing fixture.

Poster Escape cancellation disposes export and order ownership synchronously on the native dialog's `cancel` event. The dialog loses its open state before the queued `close` observer runs, so that observer alone cannot prevent a completed encoder from delivering a file. The cancellation test holds only the detached PDF export canvas's JPEG encoder, releases it once, and withholds the close observer. The preview backdrop also calls `toBlob`; its callback is not export readiness, and PNG export uses a separate encoder. These barriers verify cancellation without sleeps or retries. The controller's `fix-flakes-s2` report records the ordered-prefix verification and mutation evidence.
