# Elixir 1.20.4 and external HEEx assessment

Date: 2026-10-08. Worktree: `feat/phoenix-port`.

## Runtime

The latest stable official Elixir release verified on 2026-10-08 is [v1.20.4](https://github.com/elixir-lang/elixir/releases/tag/v1.20.4). The project moves from 1.18.3 to 1.20.4 with Erlang/OTP 27 retained. The release publishes OTP 27, 28 and 29 archives; upgrading Erlang is a separate decision. Production targets still use Debian trixie's OTP and the existing `include_erts: false` release arrangement.

Pins agree in `app-phoenix/.tool-versions`, `mix.exs`, CI, the partition runner, proxy stack and Rails parity subprocess helpers. CI cache keys include `.tool-versions` to avoid restoring compiled artifacts under an old toolchain. Docker installs the official `elixir-otp-27.zip`, verifies its SHA256 (`4389f216eec086b34a08d70a3eb0a649d00e6631987d1cbb649a2f81092f034c`), and asserts OTP 27 in the builder. Future version bumps must update both version and archive digest.

Local setup:

```sh
cd app-phoenix
asdf install
export PATH="$HOME/.asdf/shims:$PATH"
mix local.hex --force
mix local.rebar --force
mix deps.get
mix format --check-formatted
MIX_ENV=test mix compile --force --warnings-as-errors
```

The local project toolchain is installed as Elixir 1.20.4-otp-27; the global Homebrew default is unchanged. Dependencies remain locked to their existing versions. Compiler compatibility updates make external bitstring size variables explicitly pinned, replace deprecated bitwise negation, simplify statically unreachable branches, compute a module before function capture and guard numeric epoch comparisons. Remember-cookie validation now explicitly handles `Float.parse/1` returning `:error` for overflow, preserving rejection rather than raising `MatchError`. Migration lock loss now has its intended CLI error message rather than an unmatched `describe/1` clause. The ExUnit partition runner accepts both old summaries and 1.20's `Result: P/N passed` format.

## Template assessment

Recommendation: progressively extract large page/component markup to `.html.heex`, while retaining short components inline. This is a maintainability change, with no expected request throughput or memory improvement from moving the source alone. Both forms compile with `Phoenix.LiveView.TagEngine` and `Phoenix.LiveView.HTMLEngine`; verified in the project's locked LiveView 1.2.12 source. There is no per-request disk template read. The existing ADR-0016 LiveView and Rails markup choice remains in force.

Inventory: 263 inline `~H` blocks in 166 web modules and 34 external HEEx files. Good initial candidates (template lines, excluding surrounding Elixir):

| Module | HEEx lines | Reason |
| --- | ---: | --- |
| `components/poster_studio_actions.ex` | 273 | One large markup block |
| `components/map_tools_tab.ex` | 250 | One large markup block |
| `components/public_digest.ex` | 247 | One large markup block |
| `settings_live/general.ex` | 246 | Page render is exclusively HEEx |
| `components/map_settings_more.ex` | 238 | One large markup block |

LiveViews support an adjacent file automatically. For example:

```text
lib/dawarich_web/settings_live/
  general.ex          # mount, page assigns, events, helpers
  general.html.heex   # markup; no explicit render/1 required
```

If `render/1` prepares assigns, retain that preparation and call an embedded template, as `SettingsLive.BackgroundJobs` already does. For function components use `embed_templates "map_tools_tab/*"` with `map_tools_tab/tools_tab.html.heex`; preserve `attr`/`slot` declarations using a bodyless `def tools_tab(assigns)` and keep helper functions in the component module. Do not move queries or business logic into templates.

Tailwind already scans `app-phoenix/lib/**/*.{ex,heex}`, the HTML formatter already handles both forms, and Docker copies the full `lib` directory. No infrastructure change is needed. This request assessed migration feasibility; no mass template conversion was performed.

Validation for a later extraction: retain existing rendered HTML assertions, selectors, attributes, hooks and LiveView event tests; run relevant page/component tests and Tailwind/release builds. Changing test expectations to accommodate altered markup is unnecessary for a mechanical extraction.

Primary references: [LiveView template collocation](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#module-template-collocation), [embedding templates](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html#embed_templates/2). Related architecture: `docs/adr/0016-ported-pages-are-liveview-with-the-rails-markup.md`.

## Verification

Final validation: 9937 tests, 0 failures (seed404), forced compilation with warnings-as-errors, full formatting, and both arm64 production target builds/runtime checks pass. Verification results and logs are recorded in `docs/phoenix/performance-regressions-20261008.md`. Artifact directory: `/Users/frey/projects/dawarich/benchmarks/performance-regressions-20261008/`. Benchmark reports from earlier runs retain their original Elixir 1.18.3 provenance; they were not rerun on 1.20.4.
