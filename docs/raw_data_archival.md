# Raw Data Archival System

## Overview

The raw data archival system compresses and stores the `raw_data` JSON column from `points` into encrypted archive files (ActiveStorage). This reduces database size for old data while keeping it recoverable.

**Pipeline:** `Archive → Verify → Clear` (3-phase safety)

Each phase is independent and must be run manually. No data is deleted until explicitly cleared after successful verification.

## Prerequisites

Set the `ARCHIVE_RAW_DATA=true` environment variable to enable archival. Without it, the `archive` task exits immediately.

Optionally set `ARCHIVE_ENCRYPTION_KEY` for a custom encryption key (defaults to `Rails.application.secret_key_base`).

## Architecture

### What happens to a point during archival

| Phase | `raw_data` column | `raw_data_archived` | `raw_data_archive_id` | Archive file |
|-------|-------------------|---------------------|-----------------------|-------------|
| Before archival | `{...data...}` | `false` | `nil` | — |
| After **Archive** | `{...data...}` (unchanged) | `true` | set to archive ID | Created (encrypted gzip JSONL) |
| After **Verify** | `{...data...}` (unchanged) | `true` | set | `verified_at` stamped on archive |
| After **Clear** | `{}` (emptied) | `true` | set | Intact — only source of raw_data now |
| After **Restore** | `{...data...}` (restored) | `false` | `nil` | Intact (not deleted) |

### Key safety properties

- **Archive** only targets points 2+ months old with non-empty `raw_data`
- **Archive** includes immediate verification (download + decrypt + checksum) before marking points
- **Clear** only operates on archives that passed verification (`verified_at` is set)
- **Restore** writes data back from archive files to the `raw_data` column
- Advisory locks prevent concurrent archival of the same user/month

### Storage format

- **Format:** JSONL (one JSON line per point: `{"id": 123, "raw_data": {...}}`)
- **Compression:** gzip
- **Encryption:** AES-256-GCM via `ActiveSupport::MessageEncryptor`
- **Storage:** ActiveStorage (local disk or S3 depending on config)
- **Chunking:** One chunk per user/year/month (appends new chunks if re-run)

## Manual Workflow (Rake Tasks)

All tasks are under the `points:raw_data` namespace. Run inside the app container:

```bash
docker compose exec web bundle exec rake <task>
```

### 1. Check current status

```bash
rake points:raw_data:status
```

Shows: archive count, verified/unverified split, points archived/cleared, storage used, top users.

### 2. Archive (compress raw_data into files)

```bash
# Archive all eligible points (2+ months old, all users)
rake points:raw_data:archive
```

This does NOT delete or modify `raw_data` on points. It:
- Finds points where `raw_data_archived = false` and `raw_data IS NOT NULL` and `raw_data != '{}'`
- Groups by user/year/month
- Compresses into gzip JSONL, encrypts, stores via ActiveStorage
- Sets `raw_data_archived = true` and `raw_data_archive_id` on points
- Performs immediate verification (download + decrypt + checksum match)

**Points' `raw_data` column is untouched.** You can query it normally.

### 3. Verify (integrity check)

```bash
# Verify all unverified archives
rake points:raw_data:verify

# Verify specific month
rake points:raw_data:verify[USER_ID,YEAR,MONTH]
```

Downloads each archive, decrypts, decompresses, checks:
- Content checksum matches stored hash
- Point count matches expected count
- Point IDs checksum matches
- Sampled raw_data values match database (stride-based sampling)

Sets `verified_at` on passing archives.

### 4. Clear (remove raw_data from database)

```bash
# Clear all verified archives
rake points:raw_data:clear_verified

# Clear specific month
rake points:raw_data:clear_verified[USER_ID,YEAR,MONTH]
```

**This is the destructive step.** Sets `raw_data = {}` on points linked to verified archives. After this, raw_data only exists in the archive files.

Only operates on archives where `verified_at IS NOT NULL`.

### 5. Full workflow (all 3 steps)

```bash
rake points:raw_data:archive_full
```

Runs Archive → Verify → Clear sequentially. Aborts before Clear if any verification fails.

### 6. Restore (bring data back)

```bash
# Restore specific month to database
rake points:raw_data:restore[USER_ID,YEAR,MONTH]

# Restore all months for a user
rake points:raw_data:restore_all[USER_ID]

# Restore to cache only (temporary, 1 hour, for migrations)
rake points:raw_data:restore_temporary[USER_ID,YEAR,MONTH]
```

Downloads archive, decrypts, decompresses, writes `raw_data` back to points. Resets `raw_data_archived = false` and `raw_data_archive_id = nil`.

**Note:** Archive records are NOT deleted by restore. Points just get their data back.

### 7. Reset (remove all archives, undo everything)

```bash
rake points:raw_data:reset_all
```

Complete reset — as if archival never happened:
1. Restores `raw_data` from archives for any points that were cleared
2. Resets `raw_data_archived` and `raw_data_archive_id` on all points
3. Deletes all archive records and their ActiveStorage files

Run `VACUUM ANALYZE points;` afterward to reclaim space.

## Using from Rails Console

```ruby
# Archive a specific month
Points::RawData::Archiver.new.archive_specific_month(user_id, year, month)

# Verify a specific archive
Points::RawData::Verifier.new.verify_specific_archive(archive_id)

# Clear a specific archive
Points::RawData::Clearer.new.clear_specific_archive(archive_id)

# Restore a month
Points::RawData::Restorer.new.restore_to_database(user_id, year, month)

# Restore all for a user
Points::RawData::Restorer.new.restore_all_for_user(user_id)

# Check archive stats
Points::RawDataArchive.count
Points::RawDataArchive.where.not(verified_at: nil).count
Point.where(raw_data_archived: true).count
Point.where(raw_data_archived: true, raw_data: {}).count
```

## Accessing archived data in application code

Points include the `Archivable` concern which provides:

```ruby
# Returns raw_data from DB if present, falls back to archive file
point.raw_data_with_archive

# Restore a single point's raw_data
point.restore_raw_data!(raw_data_hash)

# Scopes
Point.archived          # raw_data_archived = true
Point.not_archived      # raw_data_archived = false
```

**Use `raw_data_with_archive` instead of `raw_data`** in any code that needs to work with archived points. Direct `raw_data` access returns `{}` for cleared points.

## Monitoring

Prometheus metrics are emitted at each step:

| Metric class | Emitted by |
|-------------|-----------|
| `Metrics::Archives::Operation` | Archive, Verify, Clear, Restore (operation + status) |
| `Metrics::Archives::PointsArchived` | Archive (added), Clear/Restore (removed) |
| `Metrics::Archives::Verification` | Archive (immediate), Verify (full) |
| `Metrics::Archives::Size` | Archive (blob byte_size) |
| `Metrics::Archives::CompressionRatio` | Archive (original vs compressed) |
| `Metrics::Archives::CountMismatch` | Archive (when expected != actual) |

## File locations

| Component | Path |
|-----------|------|
| Archiver service | `app/services/points/raw_data/archiver.rb` |
| Verifier service | `app/services/points/raw_data/verifier.rb` |
| Clearer service | `app/services/points/raw_data/clearer.rb` |
| Restorer service | `app/services/points/raw_data/restorer.rb` |
| Encryption | `app/services/points/raw_data/encryption.rb` |
| Chunk compressor | `app/services/points/raw_data/chunk_compressor.rb` |
| Archive model | `app/models/points/raw_data_archive.rb` |
| Archivable concern | `app/models/concerns/archivable.rb` |
| Rake tasks | `lib/tasks/points_raw_data.rake` |
| Migrations | `db/migrate/20251206000001_*` through `db/migrate/20260216190000_*` |
