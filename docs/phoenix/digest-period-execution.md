# Digest period execution

Status: accepted, 2026-10-07. Supersedes the digest checkpoint decisions in
`stats-native-effects.md`. Controller ruling: fix4 RX-STATS, rereview2 R2.
AFFiNE counterpart: `Dawarich — ADR-20261007-digest-period-state — One shared
digest period execution record` (`7wYcTSdinqYkkeAIvwpT-`).

## Context and decision

The previous two-checkpoint protocol could not let Rails recognize an older
native generation before native retry promoted its marker. A shared receipt
lock serialized current work but could not resolve incompatible historical
completion identities. The controller requires one authoritative period state.

Rails and Phoenix share one `phoenix.digest_executions` row per calculation
effect, user, year and month. Yearly month is zero. A fresh job ID does not create
a second generation or mail admission for the same period.

Both runtimes acquire a PostgreSQL transaction advisory lock on the JSON array
`[effect,user_id,year,month]` before reading or changing this record. The earlier
execution-receipt lock is also retained for compatibility. Decisions use the
period row; `processed_commands` markers are compatibility output and legacy
upgrade inputs.

| State | Next operation | Failure behavior |
| --- | --- | --- |
| Absent | Claim and generate | An uncommitted claim disappears on crash |
| claimed | Generate under the period lock | Failure releases the claim and preserves source notifications |
| generated, mail | Publish mail intent only | Rollback retains generated; retry never regenerates |
| generated, missing | Complete without mail | No user lookup or calculation is repeated |
| published | Finish | No generation or publication is repeated |

Successful stats/digest writes commit with `generated`. Publication commits its
durable mail intent with `published`. Source continuation after internally
reported stats errors, partial intermediate stats writes on digest failure,
locale, timezone, missing-user behavior and mail eligibility remain unchanged.
Published means durable mail admission, not email delivery or `sent_at`.

## Alternatives and consequences

Adding another checkpoint lookup retains multiple authoritative records and
requires reconstructing irreversible historical event IDs in each runtime.
The single record makes the failure boundary explicit and permits either
runtime to finish publication. The trade-off is additive schema and upgrade
reconciliation. A period is now the effect identity, so new job IDs for an
already completed period cannot trigger another calculation or mail admission.

## Upgrade and rollback

The additive migration `20261007235900_create_digest_executions.exs` creates the
period table and flushes queued DDL before live reconciliation. It checks for
source table presence and schema/table read privileges so scratch schema bootstrap
and migration roles without public access remain usable. The native outbox is
optional; Rails 1.15.3 digest results are imported before that table exists.
Its SQL backfill imports existing digests as generated, or
published when `sent_at` or a retained durable mail intent is present. Retained Oban/outbox/reverse arguments are
scanned in batches of 500 to identify older successful generation and terminal
markers, including successful no-data generation without a digest row. Explicit
failed checkpoints are never imported as success; their erroneous matching
legacy terminal marker is released before either runtime retries. Existing new-protocol rows
are not overwritten.

Imported rows retain a `legacy` flag until their first locked reconciliation.
Published is terminal and cannot be demoted by legacy generation markers.
A matching legacy terminal marker promotes a pending imported period to published;
a matching shared or older generation marker preserves its recorded outcome.
Reconciliation clears the flag, after which execution decisions use only the
period record. An old checkpoint UUID alone is irreversible: the persisted
result or retained accepted arguments supply its period provenance.

Run the additive migration before starting upgraded consumers. Old consumers
must be quiesced during migration and upgrade; their old checkpoint protocol
does not acquire the new period lock. Do not run an unpatched historical
consumer concurrently with upgraded consumers. Rails alone continues its
source flow when the Phoenix period table is absent. No public Rails schema
change is required, and removing Phoenix leaves Rails 1.15.3 usable. Existing
mail poller/consumer recovery remains responsible for admitted delivery.

Code: `app/services/users/digests/execution.rb` and
`app-phoenix/lib/dawarich/digests/{execution,generation,execution_upgrade}.ex`.
Regression matrix: `period_execution_spec.rb` (RX15–RX21, RX26),
`fix4_rxstats_test.exs` (RX10–RX14, RX18, RX24–RX25, RX27), plus retained RX01–RX09.
The legacy regression executes the real pre-fix3 generator, rolls back terminal
publication, applies upgrade reconciliation, then checks both writer orders.
`digest_execution_migration_test.exs` (RX29) runs the actual migration against
synthetic public results and guards DDL ordering before reconciliation. RX30
checks migration roles denied public schema/table access; RX31 covers the Rails
1.15.3 schema before a native outbox exists.
