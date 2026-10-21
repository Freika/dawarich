# Dawarich Phoenix

Status: **Native implementation guide finalized**, 2026-10-11. Stage-2 features are integrated; A/B shared cleanup and X4/X5 release acceptance remain pending.

Start with the [native frontend development workflow](../docs/phoenix/native-frontend-development.md), [architecture context](../docs/phoenix/native-frontend-context.md) and [ADR-0017 cleanup implementation record](../docs/phoenix/native-frontend-cleanup-adr.md). The [milestone 7 inventory](../docs/phoenix/native-m7-inventory.md) records current consumers and evidence; the [test successor ledger](../docs/phoenix/native-m7-test-retargets.md) protects retained behavior during deletion.

Native JavaScript starts at `assets/js/app.js`; esbuild emits `priv/static/native`, and `mix assets.deploy` also runs `phx.digest`. The current stylesheet/font/image resolver and Docker data/asset stage still use Rails frontend inputs. The development guide distinguishes today's commands from the proposed A3/A4 removal. No claim of a Rails-independent production artifact is made before X4/X5.

Tests use a private PostgreSQL/PostGIS database and private Redis through the controller's targeted runner. Do not run the repository-root Rails `make test` as the Phoenix gate. Full ExUnit and standalone G44 browser lanes are controller acceptance steps, not part of implementation checks. Rails remains separately documented by the repository-root README and AGENTS instructions.
