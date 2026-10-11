# Native frontend development

Status: **DRAFT**, 2026-10-10. Commands below are aligned with source on the m7 branch; only the reported targeted tests have been executed for this draft. A3/A4/B2/B3/X4/X5 must supply production build, serving, packaging and final runtime evidence before these instructions become an accepted release runbook.

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

## Edit native frontend code

The native entrypoint is `app-phoenix/assets/js/app.js`. `assets/js/hooks/index.js` registers named hooks for browser libraries; domain behavior lives in contexts taking `Accounts.Scope`. Keep library/editor/map/studio imports lazy, worker/style URLs compatible with production digests, and direct-upload adapters explicit. Native uploads do not imply a Hotwire dependency. Inspect the emitted graph as well as source markers: an import name scan alone misses bundled/lazy code.

LiveViews own forms, errors, confirmations, URL params and action acknowledgement. HTTP remains appropriate for session/cookie authentication, downloads, public unlock and signed storage. Use plain admitted HTTP forms at those boundaries. Across distinct live_sessions use a full document transition; within a compatible session use native navigation/patches. No controller registry, ignored editable island or per-request Rails handback is a native successor.

Keep credentials/capabilities out of retained form/socket state, event replies and logs. Renew credential forms after submit/error/close/reopen. Re-admit actors on params/events/info/async/reconnect and in scoped contexts. Async work needs a per-run token, bounded timeout and stale-result rejection. Maps/studios must destroy their own instances/workers/listeners on departure and ignore revoked private updates. Library-owned DOM may be ignored within a keyed hook; ordinary server-owned forms and gallery rows remain patchable.

**DRAFT serving workflow:** rebuild `mix assets.build` after JS changes; use the controller-prepared foreground native stand to load the exact app/E2E identities. The current dev config does not define an assets watcher. The current runtime has lifecycle/readiness/source-debt admission beyond an endpoint startup, so a generic `mix phx.server` is not a verified substitute for the prepared stand. Stop all services you start unless a brief explicitly requests otherwise. X4 will provide the accepted production/native and separate Rails artifact startup procedures; no start command or default is changed by this draft.

## Build and dependency removal

These are existing aliases from `app-phoenix/mix.exs`, run with the private test environment already supplied:

```sh
mix assets.deploy
mix format --check-formatted
mix compile --warnings-as-errors --all-warnings
```

`assets.build` invokes the configured `esbuild native` profile: ESM, splitting, output `priv/static/native`, and external `/maplibre/*` imports. `assets.deploy` minifies that profile and runs `phx.digest`, producing `priv/static/cache_manifest.json` and digested static outputs. The native JS graph/demo eager-byte caps remain required. These source-aligned commands are not fresh production-build evidence for this draft.

| Input/boundary | Current source | DRAFT accepted target / proof still needed |
| --- | --- | --- |
| Native JS | Phoenix esbuild entrypoint/profile; lazy hooks | Keep one native entrypoint and explicit library chunks; A2 emitted/lazy/worker graph and runtime checks. |
| CSS/fonts/images | Native root uses `DawarichWeb.Assets`; resolver reads Rails asset manifest | A3 native digest/static manifest and actual CSS/font/worker serving tests. Keep Tailwind/DaisyUI and useful source classes. |
| Importmap/Sprockets | `mix dawarich.build_inputs --root ... --out ...` still compiles Sprockets and exports importmap alongside runtime data | A3 separates data export from frontend discovery. Do not call an invented data-only alias or copy the old manifest under a new name. |
| Runtime data | i18n/achievements/timezone/geodata/OpenAPI and renderer/font inputs | Retain data/gzip/error invariants and positive asset manifest. Separate data requirements from legacy JS discovery. |
| Docker native stages | Current Dockerfile copies root Rails JS/vendor/assets/config and mixed build outputs | A4 removes obsolete native payload only after positive renderer/worker/font/PWA/Swagger tests; X4 actual image/export smoke. Rails build sources stay. |
| Feature locations | Existing web module/template families; new native browser families on feature branches | B4a–B4c/A4 physically group small families with unchanged module names, URLs and Scope/session contracts. No simultaneous namespace rewrite. |

A successful esbuild command alone does not prove native CSS, production font/worker URLs, renderer output or a Rails-independent image. Keep the historical hybrid build instructions as history until the corresponding runtime consumers are removed.

## Run native behavior tests

From the app checkout, set `M7_TARGETED_RUNNER` to the controller-supplied m7 runner:

```sh
zsh "$M7_TARGETED_RUNNER" \
  test/dawarich_web/native_shell_test.exs \
  test/dawarich_web/native_shell_events_test.exs \
  test/dawarich_web/native_root_test.exs \
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
npx playwright test --list native/navigation.spec.js
```

This is the planned C2 path; it may not exist until C2 lands. Use a delivered spec path on the assigned E2E head. `--list` proves discovery/syntax, not a browser pass. Select controls by role/label/testid and await native join/action acknowledgement rather than Turbo/Stimulus presence. Disable sensitive credential/share/export captures; assertions compare booleans rather than printing tokens or signed URLs.

G44 runs only at stage acceptance: stage 1 integrates 3c/3d/4/5; stage 2 integrates 6/7. The controller prepares the stand and runs three standalone lanes sequentially at frozen app/E2E/image identities. English/German 390px overflow, per-element bounds, keyboard/focus/Escape, navigation/reconnect and real lazy library/worker behavior belong to that acceptance. Unit hook stubs and spec discovery do not replace those checks.

The 2026-10-10 scope cut removes D1–D4 performance/load/resource measurements. Preserve existing byte-cap/bundle-boundary tests, behavior/lifecycle tests and functional packaging/fallback acceptance. Do not require a control matrix, report invented speedups or advance a milestone on partial evidence.
