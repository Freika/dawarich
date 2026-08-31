# Domain Docs

How the engineering skills should consume this repo's domain documentation.

## Before exploring, read these

- **`CLAUDE.md`** at the repo root — the authoritative architecture and conventions file for this repo. Always read it.
- **`docs/adr/`** — architecture decision records, if the directory exists.

⚠️ As of this writing this repo has **no** `CONTEXT.md` and **no** `docs/adr/`. If a file listed here doesn't exist, **proceed silently** — don't flag its absence and don't propose creating one upfront. A domain-modeling pass creates them lazily, only when a term or decision actually gets resolved — they are not prerequisites for working here.

## Layout

Dawarich is a single-context Rails app — there is no `src/` and no per-context split:

```
/
├── CLAUDE.md          ← architecture + conventions (authoritative)
├── app/               ← models, controllers, services, serializers, queries, jobs
├── lib/
├── config/
├── db/
├── spec/
└── docs/
    └── agents/        ← this directory
```

Domain vocabulary lives in `app/models/` and `app/services/`; treat those names as the glossary until a `CONTEXT.md` exists.

## Use the codebase's vocabulary

When your output names a domain concept (an issue title, a refactor proposal, a hypothesis, a spec name), use the term the code already uses — `Point`, `Track`, `Visit`, `Place`, `Area`, `Trip`, `Stat`, `Import`. Don't drift to synonyms.

If the concept you need has no name in the codebase, that's a signal: either you're inventing language the project doesn't use (reconsider), or there's a real gap worth noting.

## Flag conflicts

If your output contradicts a documented decision in `CLAUDE.md` or an ADR, surface it explicitly rather than silently overriding:

> _Contradicts the "Points → lonlat" convention in CLAUDE.md, but worth reopening because…_
