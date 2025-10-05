# Database Index Audit (2025-10-05)

## Observed ActiveRecord Query Patterns
- **Visits range filter** – `log/test.log:91056` shows repeated lookups with `WHERE "visits"."user_id" = ? AND (started_at >= ? AND ended_at <= ?)` ordered by `started_at`.
- **Imports deduplication checks** – `log/test.log:11130` runs `SELECT 1 FROM "imports" WHERE "name" = ? AND "user_id" = ?` (and variants excluding an `id`).
- **Family invitations association** – `app/models/user.rb:22` loads `sent_family_invitations`, which issues queries on `invited_by_id` even though only `family_id` currently has an index (`db/schema.rb:108-120`).

## Missing or Weak Index Coverage
1. **`family_invitations(invited_by_id)`**  
   - Evidence: association in `app/models/user.rb:22` plus schema definition at `db/schema.rb:112` lacking an index.  
   - Risk: every `user.sent_family_invitations` call scans by `invited_by_id`, which will degrade as invitation counts grow.  
   - Suggested fix: add `add_index :family_invitations, :invited_by_id` (consider `validate: false` first, then `validate_foreign_key` to avoid locking).

2. **`visits(user_id, started_at, ended_at)`**  
   - Evidence: range queries in `log/test.log:91056` rely on `user_id` plus `started_at`/`ended_at`, yet the table only has single-column indexes on `user_id` and `started_at` (`db/schema.rb:338-339`).  
   - Risk: planner must combine two indexes or fall back to seq scans for wide ranges.  
   - Suggested fix: add a composite index such as `add_index :visits, [:user_id, :started_at, :ended_at]` (or at minimum `[:user_id, :started_at]`) to cover the filter and ordering.

3. **`imports(user_id, name)`**  
   - Evidence: deduplication queries in `log/test.log:11130` filter on both columns while only `user_id` is indexed (`db/schema.rb:146-148`).  
   - Risk: duplicate checks for large import histories become progressively slower.  
   - Suggested fix: add a unique composite index `add_index :imports, [:user_id, :name], unique: true` if business rules prevent duplicate filenames per user.

## Potentially Unused Indexes
- `active_storage_attachments.blob_id` (`db/schema.rb:34`) and `active_storage_variant_records(blob_id, variation_digest)` (`db/schema.rb:53`) do not appear in application code outside Active Storage internals. They are required for Active Storage itself, so no action recommended beyond periodic verification with `ANALYZE` stats.

## Next Steps
- Generate and run migrations for the suggested indexes in development, then `EXPLAIN ANALYZE` the affected queries to confirm improved plans.  
- After deploying, monitor `pg_stat_statements` or query logs to ensure the new indexes are used and to detect any remaining hotspots.
