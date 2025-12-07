# Points raw_data S3 Archival System Implementation Plan

**Version:** 1.2
**Date:** 2025-11-25
**Last Updated:** 2025-12-06
**Status:** Planning Phase

## 🔄 Version 1.2 Updates (2025-12-06)

**Key Changes:**
- ✅ **Optional archival system** - Controlled by `ARCHIVE_RAW_DATA` environment variable (default: disabled)
- ✅ **User model integration** - Added `has_many :raw_data_archives` with cascade deletion
- ✅ **GDPR compliance** - Complete data removal on user deletion (DB + S3)
- ✅ **Configuration section** - New section documenting ENV vars and opt-in behavior
- ✅ **Appendix C added** - User Model Integration with cascade deletion details

**Why These Changes:**
- Safe deployment: Feature disabled by default, can be enabled gradually
- Data privacy: Full cascade deletion ensures GDPR compliance
- Operational flexibility: Can disable archival instantly if issues arise
- User deletion: Archives and S3 files automatically cleaned up

## 🔄 Version 1.1 Updates (2025-11-25)

**Key Changes:**
- ✅ **No column accessor override** - Uses `raw_data_with_archive` method instead of overriding `raw_data` column
- ✅ **Archivable concern** - Extracted all archival logic to reusable `Archivable` concern
- ✅ **Migration guide** - Added comprehensive guide for updating existing code
- ✅ **JSONL appendix** - Added detailed explanation of JSONL format and why we use it
- ✅ **Updated file checklist** - Added concern files and additional modifications needed

**Why These Changes:**
- Avoids ActiveRecord column accessor conflicts
- Cleaner separation of concerns (Point model stays focused)
- Explicit method names (`raw_data_with_archive` vs `raw_data`)
- Reusable pattern for other models if needed

---

## Executive Summary

Implement a system to archive `points.raw_data` JSONB column using **ActiveStorage** to reduce database size from 50GB+ to ~15-20GB while maintaining ability to restore data for migrations and fixes.

**Key Benefits:**
- 60-70% database size reduction (~30-35GB saved)
- 10-20% query performance improvement
- ~$55/month storage costs
- Zero data loss with append-only architecture
- Full restore capabilities via rake tasks

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Configuration](#configuration) ✨ **NEW**
3. [Why ActiveStorage?](#why-activestorage)
4. [Implementation Phases](#implementation-phases)
5. [Migration Guide for Existing Code](#migration-guide-for-existing-code) ✨ **NEW**
6. [Rake Tasks for Restoration](#rake-tasks-for-restoration)
7. [Deployment Strategy](#deployment-strategy)
8. [Monitoring & Success Metrics](#monitoring--success-metrics)
9. [Rollback Plan](#rollback-plan)
10. [Timeline](#timeline)
11. [Cost Analysis](#cost-analysis)
12. [FAQ](#faq)
13. [Appendix A: What is JSONL?](#appendix-a-what-is-jsonl) ✨ **NEW**
14. [Appendix B: File Checklist](#appendix-b-file-checklist)
15. [Appendix C: User Model Integration](#appendix-c-user-model-integration) ✨ **NEW**

---

## Architecture Overview

### Current State

```
┌─────────────────────────────┐
│   Points Table (50GB)       │
│                             │
│  - id                       │
│  - user_id                  │
│  - timestamp                │
│  - lonlat (PostGIS)         │
│  - raw_data (JSONB) ← 30GB  │  ← Problem: 60% of table size
│  - ...other columns         │
└─────────────────────────────┘
```

### Target State

```
┌─────────────────────────────┐     ┌──────────────────────────────────┐
│   Points Table (15-20GB)    │     │  Points::RawDataArchive Model    │
│                             │     │                                  │
│  - id                       │     │  - id                            │
│  - user_id                  │     │  - user_id                       │
│  - timestamp                │     │  - year, month, chunk_number     │
│  - lonlat (PostGIS)         │     │  - point_count, checksum         │
│  - raw_data (NULL) ← freed  │     │  - metadata (JSONB)              │
│  - raw_data_archived (bool) │────▶│  - has_one_attached :file        │
│  - raw_data_archive_id      │     │                                  │
│  - timestamp_year (gen)     │     └──────────────┬───────────────────┘
│  - timestamp_month (gen)    │                    │
└─────────────────────────────┘                    │ ActiveStorage
                                                   │
                                    ┌──────────────▼───────────────────┐
                                    │  S3 / Local Storage              │
                                    │                                  │
                                    │  raw_data_000001.jsonl.gz (1MB)  │
                                    │  raw_data_000002.jsonl.gz (50KB) │
                                    │  ...append-only chunks           │
                                    └──────────────────────────────────┘
```

### Data Flow

**Archival (Monthly Cron):**
```
1. Find months 2+ months old with unarchived points
2. Create Points::RawDataArchive record
3. Compress points to JSONL.gz
4. Attach via ActiveStorage (handles S3 upload)
5. Atomically: Mark points archived, NULL raw_data
```

**Access (Lazy Loading):**
```
1. Point.raw_data called
2. Check if archived → yes
3. Check cache (1 day TTL) → miss
4. Fetch from archive.file.blob.download
5. Cache result, return data
```

**Restoration (Rake Task):**
```
1. Find all archives for user/month
2. Download via ActiveStorage
3. Decompress, parse JSONL
4. Update points: restore raw_data, unmark archived
```

---

## Configuration

### Environment Variables

The archival system is **opt-in** and controlled by a single environment variable:

```bash
# .env or environment
ARCHIVE_RAW_DATA=true    # Enable/disable archival (default: false)
STORAGE_BACKEND=s3       # Already exists: s3, local, etc.
```

**Important:** If `ARCHIVE_RAW_DATA` is not set to `"true"`, the entire archival system is disabled:
- Archive jobs won't run
- Archive service returns early
- No S3 costs incurred
- Existing code works unchanged

The archival lag period (2 months) is a constant in the code and can be modified if needed.

This allows gradual rollout and easy disabling if issues arise.

---

## Why ActiveStorage?

### Consistency with Existing Code

Dawarich already uses ActiveStorage for Import and Export models:

**Existing Pattern (Import model):**
```ruby
class Import < ApplicationRecord
  has_one_attached :file
end

# Usage in services
import.file.attach(io: File.open(path), filename: name)
content = import.file.blob.download
```

**Our Pattern (Archive model):**
```ruby
class Points::RawDataArchive < ApplicationRecord
  has_one_attached :file
end

# Usage in archiver
archive.file.attach(io: StringIO.new(compressed), filename: "...")
content = archive.file.blob.download
```

### Benefits Over Direct S3

| Feature | Direct S3 | ActiveStorage |
|---------|-----------|---------------|
| Backend flexibility | Manual config | Automatic via `STORAGE_BACKEND` env |
| Code consistency | New S3 client code | Same as Import/Export |
| Checksums | Manual implementation | Built-in via Blob |
| Local dev | Need MinIO/localstack | Works with local disk |
| Testing | Mock S3 clients | Use ActiveStorage test helpers |
| Cleanup | Manual delete calls | `file.purge_later` |
| Streaming | Custom chunking | Built-in `download { |chunk| }` |

### No Additional Configuration Needed

```ruby
# config/storage.yml - Already configured!
s3:
  service: S3
  access_key_id: <%= ENV.fetch("AWS_ACCESS_KEY_ID") %>
  secret_access_key: <%= ENV.fetch("AWS_SECRET_ACCESS_KEY") %>
  region: <%= ENV.fetch("AWS_REGION") %>
  bucket: <%= ENV.fetch("AWS_BUCKET") %>

# config/environments/production.rb - Already configured!
config.active_storage.service = ENV.fetch('STORAGE_BACKEND', :local)
```

**Result:** Zero new infrastructure setup! ✅

---

## Implementation Phases

### Phase 1: Database Schema (3 Migrations)

#### Migration 1: Create Points::RawDataArchive Table

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_points_raw_data_archives.rb
class CreatePointsRawDataArchives < ActiveRecord::Migration[8.0]
  def change
    create_table :points_raw_data_archives do |t|
      t.bigint :user_id, null: false
      t.integer :year, null: false
      t.integer :month, null: false
      t.integer :chunk_number, null: false, default: 1
      t.integer :point_count, null: false
      t.string :point_ids_checksum, null: false
      t.jsonb :metadata, default: {}, null: false
      t.datetime :archived_at, null: false

      t.timestamps
    end

    add_index :points_raw_data_archives, :user_id
    add_index :points_raw_data_archives, [:user_id, :year, :month]
    add_index :points_raw_data_archives, :archived_at
    add_foreign_key :points_raw_data_archives, :users
  end
end
```

#### Migration 2: Add Archival Columns to Points

```ruby
# db/migrate/YYYYMMDDHHMMSS_add_archival_columns_to_points.rb
class AddArchivalColumnsToPoints < ActiveRecord::Migration[8.0]
  def change
    add_column :points, :raw_data_archived, :boolean, default: false, null: false
    add_column :points, :raw_data_archive_id, :bigint, null: true

    add_index :points, :raw_data_archived,
      where: 'raw_data_archived = true',
      name: 'index_points_on_archived_true'
    add_index :points, :raw_data_archive_id

    add_foreign_key :points, :points_raw_data_archives,
      column: :raw_data_archive_id,
      on_delete: :nullify  # Don't delete points if archive deleted
  end
end
```

#### Migration 3: Add Generated Timestamp Columns

```ruby
# db/migrate/YYYYMMDDHHMMSS_add_generated_timestamp_columns_to_points.rb
class AddGeneratedTimestampColumnsToPoints < ActiveRecord::Migration[8.0]
  def change
    # Use PostgreSQL generated columns for automatic year/month extraction
    add_column :points, :timestamp_year, :integer,
      as: "(EXTRACT(YEAR FROM to_timestamp(timestamp))::int)",
      stored: true

    add_column :points, :timestamp_month, :integer,
      as: "(EXTRACT(MONTH FROM to_timestamp(timestamp))::int)",
      stored: true

    # Composite index for efficient archival queries
    add_index :points, [:user_id, :timestamp_year, :timestamp_month, :raw_data_archived],
      name: 'index_points_on_user_time_archived'
  end
end
```

**Why generated columns?**
- No application code needed to maintain
- Automatically updated on insert/update
- Can be indexed for fast queries
- PostgreSQL calculates on write (not on read)

### Phase 2: Models

#### Points::RawDataArchive Model

```ruby
# app/models/points_raw_data_archive.rb
class Points::RawDataArchive < ApplicationRecord
  belongs_to :user
  has_many :points, foreign_key: :raw_data_archive_id, dependent: :nullify

  has_one_attached :file

  validates :year, :month, :chunk_number, :point_count, presence: true
  validates :year, numericality: { greater_than: 1970, less_than: 2100 }
  validates :month, numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 12 }
  validates :chunk_number, numericality: { greater_than: 0 }
  validates :point_ids_checksum, presence: true

  validate :file_must_be_attached, on: :update

  scope :for_month, ->(user_id, year, month) {
    where(user_id: user_id, year: year, month: month)
      .order(:chunk_number)
  }

  scope :recent, -> { where('archived_at > ?', 30.days.ago) }
  scope :old, -> { where('archived_at < ?', 1.year.ago) }

  def month_display
    Date.new(year, month, 1).strftime('%B %Y')
  end

  def filename
    "raw_data_#{user_id}_#{year}_#{format('%02d', month)}_chunk#{format('%03d', chunk_number)}.jsonl.gz"
  end

  def size_mb
    return 0 unless file.attached?
    (file.blob.byte_size / 1024.0 / 1024.0).round(2)
  end

  private

  def file_must_be_attached
    errors.add(:file, 'must be attached') unless file.attached?
  end
end
```

#### Archivable Concern

**⚠️ Important:** We use a concern instead of overriding the `raw_data` column accessor to avoid ActiveRecord conflicts.

```ruby
# app/models/concerns/archivable.rb
module Archivable
  extend ActiveSupport::Concern

  included do
    # Associations
    belongs_to :raw_data_archive,
      class_name: 'Points::RawDataArchive',
      foreign_key: :raw_data_archive_id,
      optional: true

    # Scopes
    scope :archived, -> { where(raw_data_archived: true) }
    scope :not_archived, -> { where(raw_data_archived: false) }
    scope :with_archived_raw_data, -> {
      includes(raw_data_archive: { file_attachment: :blob })
    }
  end

  # Main method: Get raw_data with fallback to archive
  # Use this instead of point.raw_data when you need archived data
  def raw_data_with_archive
    # If raw_data is present in DB, use it
    return raw_data if raw_data.present? || !raw_data_archived?

    # Otherwise fetch from archive
    fetch_archived_raw_data
  end

  # Restore archived data back to database column
  def restore_raw_data!(value)
    update!(
      raw_data: value,
      raw_data_archived: false,
      raw_data_archive_id: nil
    )
  end

  # Cache key for long-term archive caching
  def archive_cache_key
    "raw_data:archive:#{self.class.name.underscore}:#{id}"
  end

  private

  def fetch_archived_raw_data
    # Check temporary restore cache first (for migrations)
    cached = check_temporary_restore_cache
    return cached if cached

    # Check long-term cache (1 day TTL)
    Rails.cache.fetch(archive_cache_key, expires_in: 1.day) do
      fetch_from_archive_file
    end
  rescue StandardError => e
    handle_archive_fetch_error(e)
  end

  def check_temporary_restore_cache
    return nil unless respond_to?(:timestamp_year) && timestamp_year && timestamp_month

    cache_key = "raw_data:temp:#{user_id}:#{timestamp_year}:#{timestamp_month}:#{id}"
    Rails.cache.read(cache_key)
  end

  def fetch_from_archive_file
    return {} unless raw_data_archive&.file&.attached?

    # Download and search through JSONL
    compressed_content = raw_data_archive.file.blob.download
    io = StringIO.new(compressed_content)
    gz = Zlib::GzipReader.new(io)

    result = nil
    gz.each_line do |line|
      data = JSON.parse(line)
      if data['id'] == id
        result = data['raw_data']
        break
      end
    end

    gz.close
    result || {}
  end

  def handle_archive_fetch_error(error)
    Rails.logger.error(
      "Failed to fetch archived raw_data for #{self.class.name} #{id}: #{error.message}"
    )
    Sentry.capture_exception(error) if defined?(Sentry)

    {} # Graceful degradation
  end
end
```

#### Point Model (Clean!)

```ruby
# app/models/point.rb
class Point < ApplicationRecord
  include Nearable
  include Distanceable
  include Archivable  # ← All archival logic in concern

  belongs_to :import, optional: true, counter_cache: true
  belongs_to :visit, optional: true
  belongs_to :user, counter_cache: true
  belongs_to :country, optional: true
  belongs_to :track, optional: true

  validates :timestamp, :lonlat, presence: true
  # ... rest of existing code ...

  # Keep existing scope for query optimization
  def self.without_raw_data
    select(column_names - ['raw_data'])
  end

  # ... rest of existing methods ...
end
```

**Usage:**
```ruby
# In services that need raw_data:
point.raw_data_with_archive  # Gets from DB or archive

# Regular column access (doesn't check archive):
point.raw_data  # May be NULL if archived

# For restoration:
point.restore_raw_data!(data)
```

### Phase 3: Archive Services

#### Service: Points::RawData::Archiver

```ruby
# app/services/points/raw_data/archiver.rb
class Points::RawData::Archiver
  SAFE_ARCHIVE_LAG = 2.months

  def initialize
    @stats = { processed: 0, archived: 0, failed: 0 }
  end

  def call
    unless archival_enabled?
      Rails.logger.info('Raw data archival disabled (ARCHIVE_RAW_DATA != "true")')
      return @stats
    end

    Rails.logger.info('Starting points raw_data archival...')

    archivable_months.find_each do |month_data|
      process_month(month_data)
    end

    Rails.logger.info("Archival complete: #{@stats}")
    @stats
  end

  def archive_specific_month(user_id, year, month)
    month_data = {
      'user_id' => user_id,
      'year' => year,
      'month' => month
    }

    process_month(month_data)
  end

  private

  def archival_enabled?
    ENV['ARCHIVE_RAW_DATA'] == 'true'
  end

  def archivable_months
    # Only months 2+ months old with unarchived points
    safe_cutoff = Date.current.beginning_of_month - SAFE_ARCHIVE_LAG

    Point.select(
      'user_id',
      'timestamp_year as year',
      'timestamp_month as month',
      'COUNT(*) as unarchived_count'
    ).where(raw_data_archived: false)
     .where('to_timestamp(timestamp) < ?', safe_cutoff)
     .group('user_id, timestamp_year, timestamp_month')
  end

  def process_month(month_data)
    user_id = month_data['user_id']
    year = month_data['year']
    month = month_data['month']

    lock_key = "archive_points:#{user_id}:#{year}:#{month}"

    # Advisory lock prevents duplicate processing
    ActiveRecord::Base.with_advisory_lock(lock_key, timeout_seconds: 0) do
      archive_month(user_id, year, month)
      @stats[:processed] += 1
    end
  rescue ActiveRecord::AdvisoryLockError
    Rails.logger.info("Skipping #{lock_key} - already locked")
  rescue StandardError => e
    Rails.logger.error("Archive failed for #{user_id}/#{year}/#{month}: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    @stats[:failed] += 1
  end

  def archive_month(user_id, year, month)
    # Find unarchived points for this month
    points = Point.where(
      user_id: user_id,
      timestamp_year: year,
      timestamp_month: month,
      raw_data_archived: false
    ).where.not(raw_data: nil)  # Skip already-NULLed points

    return if points.empty?

    point_ids = points.pluck(:id)

    Rails.logger.info("Archiving #{point_ids.count} points for user #{user_id}, #{year}-#{sprintf('%02d', month)}")

    # Create archive chunk
    archive = create_archive_chunk(user_id, year, month, points, point_ids)

    # Atomically mark points and NULL raw_data
    Point.transaction do
      Point.where(id: point_ids).update_all(
        raw_data_archived: true,
        raw_data_archive_id: archive.id,
        raw_data: nil  # Reclaim space!
      )
    end

    @stats[:archived] += point_ids.count

    Rails.logger.info("✓ Archived chunk #{archive.chunk_number} (#{archive.size_mb} MB)")
  end

  def create_archive_chunk(user_id, year, month, points, point_ids)
    # Determine chunk number (append-only)
    chunk_number = Points::RawDataArchive
      .where(user_id: user_id, year: year, month: month)
      .maximum(:chunk_number).to_i + 1

    # Compress points data
    compressed_data = Points::RawData::ChunkCompressor.new(points).compress

    # Create archive record
    archive = Points::RawDataArchive.create!(
      user_id: user_id,
      year: year,
      month: month,
      chunk_number: chunk_number,
      point_count: point_ids.count,
      point_ids_checksum: calculate_checksum(point_ids),
      archived_at: Time.current,
      metadata: {
        format_version: 1,
        compression: 'gzip',
        archived_by: 'Points::RawData::Archiver'
      }
    )

    # Attach compressed file via ActiveStorage
    filename = "raw_data_#{user_id}_#{year}_#{sprintf('%02d', month)}_chunk#{sprintf('%03d', chunk_number)}.jsonl.gz"

    archive.file.attach(
      io: StringIO.new(compressed_data),
      filename: filename,
      content_type: 'application/gzip'
    )

    archive
  end

  def calculate_checksum(point_ids)
    Digest::SHA256.hexdigest(point_ids.sort.join(','))
  end
end
```

#### Helper: Points::RawData::ChunkCompressor

```ruby
# app/services/points/raw_data/chunk_compressor.rb
class Points::RawData::ChunkCompressor
  def initialize(points_relation)
    @points = points_relation
  end

  def compress
    io = StringIO.new
    gz = Zlib::GzipWriter.new(io)

    # Stream points to avoid memory issues with large months
    @points.select(:id, :raw_data).find_each(batch_size: 1000) do |point|
      # Write as JSONL (one JSON object per line)
      gz.puts({ id: point.id, raw_data: point.raw_data }.to_json)
    end

    gz.close
    io.string  # Returns compressed bytes
  end
end
```

#### Service: Points::RawData::Restorer

```ruby
# app/services/points/raw_data/restorer.rb
class Points::RawData::Restorer
  def restore_to_database(user_id, year, month)
    archives = Points::RawDataArchive.for_month(user_id, year, month)

    raise "No archives found for user #{user_id}, #{year}-#{month}" if archives.empty?

    Rails.logger.info("Restoring #{archives.count} archives to database...")

    Point.transaction do
      archives.each do |archive|
        restore_archive_to_db(archive)
      end
    end

    Rails.logger.info("✓ Restored #{archives.sum(:point_count)} points")
  end

  def restore_to_memory(user_id, year, month)
    archives = Points::RawDataArchive.for_month(user_id, year, month)

    raise "No archives found for user #{user_id}, #{year}-#{month}" if archives.empty?

    Rails.logger.info("Loading #{archives.count} archives into cache...")

    cache_key_prefix = "raw_data:temp:#{user_id}:#{year}:#{month}"
    count = 0

    archives.each do |archive|
      count += restore_archive_to_cache(archive, cache_key_prefix)
    end

    Rails.logger.info("✓ Loaded #{count} points into cache (expires in 1 hour)")
  end

  def restore_all_for_user(user_id)
    archives = Points::RawDataArchive.where(user_id: user_id)
                                   .select(:year, :month)
                                   .distinct
                                   .order(:year, :month)

    Rails.logger.info("Restoring #{archives.count} months for user #{user_id}...")

    archives.each do |archive|
      restore_to_database(user_id, archive.year, archive.month)
    end

    Rails.logger.info("✓ Complete user restore finished")
  end

  private

  def restore_archive_to_db(archive)
    decompressed = download_and_decompress(archive)

    decompressed.each_line do |line|
      data = JSON.parse(line)

      Point.where(id: data['id']).update_all(
        raw_data: data['raw_data'],
        raw_data_archived: false,
        raw_data_archive_id: nil
      )
    end
  end

  def restore_archive_to_cache(archive, cache_key_prefix)
    decompressed = download_and_decompress(archive)
    count = 0

    decompressed.each_line do |line|
      data = JSON.parse(line)

      Rails.cache.write(
        "#{cache_key_prefix}:#{data['id']}",
        data['raw_data'],
        expires_in: 1.hour
      )

      count += 1
    end

    count
  end

  def download_and_decompress(archive)
    # Download via ActiveStorage
    compressed_content = archive.file.blob.download

    # Decompress
    io = StringIO.new(compressed_content)
    gz = Zlib::GzipReader.new(io)
    content = gz.read
    gz.close

    content
  rescue StandardError => e
    Rails.logger.error("Failed to download/decompress archive #{archive.id}: #{e.message}")
    raise
  end
end
```

### Phase 4: Export Optimization

```ruby
# app/services/users/export_data/points.rb (modify existing)

class Users::ExportData::Points
  def call
    # ... existing query code ...

    result.filter_map do |row|
      # ... existing code ...

      # Handle archived raw_data
      raw_data = if row['raw_data_archived']
        fetch_raw_data_from_archive(row['raw_data_archive_id'], row['id'])
      else
        row['raw_data']
      end

      point_hash = {
        # ... existing fields ...
        'raw_data' => raw_data
      }

      # ... existing code ...
      point_hash
    end
  end

  private

  # Cache downloaded archives to avoid re-downloading per point
  def fetch_raw_data_from_archive(archive_id, point_id)
    return {} if archive_id.nil?

    @archive_cache ||= {}

    unless @archive_cache[archive_id]
      archive = Points::RawDataArchive.find(archive_id)
      @archive_cache[archive_id] = parse_archive(archive)
    end

    @archive_cache[archive_id][point_id] || {}
  end

  def parse_archive(archive)
    # Download once, parse all points
    compressed = archive.file.blob.download
    io = StringIO.new(compressed)
    gz = Zlib::GzipReader.new(io)

    result = {}
    gz.each_line do |line|
      data = JSON.parse(line)
      result[data['id']] = data['raw_data']
    end

    gz.close
    result
  rescue StandardError => e
    Rails.logger.error("Failed to parse archive #{archive.id}: #{e.message}")
    {}
  end
end
```

### Phase 5: Background Jobs

```ruby
# app/jobs/points/raw_data/archive_job.rb
class Points::RawData::ArchiveJob < ApplicationJob
  queue_as :default

  def perform
    stats = Points::RawData::Archiver.new.call

    Rails.logger.info("Archive job complete: #{stats}")
  rescue StandardError => e
    Rails.logger.error("Archive job failed: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    raise
  end
end
```

```ruby
# app/jobs/points/raw_data/re_archive_month_job.rb
class Points::RawData::ReArchiveMonthJob < ApplicationJob
  queue_as :default

  def perform(user_id, year, month)
    Rails.logger.info("Re-archiving #{user_id}/#{year}/#{month} (retrospective import)")

    Points::RawData::Archiver.new.archive_specific_month(user_id, year, month)
  rescue StandardError => e
    Rails.logger.error("Re-archive failed: #{e.message}")
    Sentry.capture_exception(e) if defined?(Sentry)
    raise
  end
end
```

**Trigger re-archival after imports:**

```ruby
# app/services/imports/create.rb (or wherever import completes)
class Imports::Create
  def call
    # ... existing import logic ...

    # After successful import, check for retrospective points
    check_for_archived_months_needing_update
  end

  private

  def check_for_archived_months_needing_update
    # Find months where we added points to already-archived data
    affected_months = import.points
      .where(raw_data_archived: true)
      .select('DISTINCT timestamp_year, timestamp_month')

    affected_months.each do |month|
      # Queue job to create append-only chunk
      Points::RawData::ReArchiveMonthJob.perform_later(
        import.user_id,
        month.timestamp_year,
        month.timestamp_month
      )
    end
  end
end
```

---

## Migration Guide for Existing Code

After implementing the archival system, you'll need to update existing code that accesses `point.raw_data`.

### Step 1: Find All Usages

```bash
# Find all places where raw_data is accessed
grep -r "\.raw_data" app/services app/models --include="*.rb" > raw_data_usages.txt

# Common locations:
# - app/services/points/raw_data_lonlat_extractor.rb
# - app/services/google_maps/*_importer.rb
# - app/services/users/export_data/points.rb
# - app/serializers/*_serializer.rb
```

### Step 2: Decision Tree

For each usage, ask:

**Question 1:** Is this code creating/importing new points?
- ✅ **Yes** → Keep `point.raw_data` (data is in DB during import)
- ❌ **No** → Go to Question 2

**Question 2:** Does this code need to access potentially archived data?
- ✅ **Yes** → Change to `point.raw_data_with_archive`
- ❌ **No** → Keep `point.raw_data` (but add comment why)

### Step 3: Update Common Services

#### Example 1: RawDataLonlatExtractor

**Before:**
```ruby
# app/services/points/raw_data_lonlat_extractor.rb
class Points::RawDataLonlatExtractor
  def extract_lonlat(point)
    if point.raw_data.dig('activitySegment', 'waypointPath', 'waypoints', 0)
      # ... extract coordinates ...
    elsif point.raw_data['longitudeE7'] && point.raw_data['latitudeE7']
      # ... extract coordinates ...
    end
  end
end
```

**After:**
```ruby
# app/services/points/raw_data_lonlat_extractor.rb
class Points::RawDataLonlatExtractor
  def extract_lonlat(point)
    # Use raw_data_with_archive to support archived points
    raw = point.raw_data_with_archive

    if raw.dig('activitySegment', 'waypointPath', 'waypoints', 0)
      # ... extract coordinates ...
    elsif raw['longitudeE7'] && raw['latitudeE7']
      # ... extract coordinates ...
    end
  end
end
```

**Why:** This service is called for coordinate fixes/migrations, which may need archived data.

#### Example 2: Importer Services

**Keep as-is:**
```ruby
# app/services/google_maps/semantic_history_importer.rb
class GoogleMaps::SemanticHistoryImporter
  def build_point_from_location(longitude:, latitude:, timestamp:, raw_data:, accuracy: nil)
    {
      longitude: longitude,
      latitude: latitude,
      timestamp: timestamp,
      raw_data: raw_data  # ← Keep as-is, we're CREATING points
      # ...
    }
  end
end
```

**Why:** Import services create new points, so `raw_data` will be in the database.

#### Example 3: Export Service

**Before:**
```ruby
# app/services/users/export_data/points.rb
class Users::ExportData::Points
  def call
    points_sql = <<-SQL
      SELECT p.id, p.raw_data, ...
      FROM points p
      WHERE p.user_id = $1
    SQL

    result = ActiveRecord::Base.connection.exec_query(points_sql, 'Points Export', [user.id])

    result.map do |row|
      {
        'raw_data' => row['raw_data'],  # ← Problem: may be NULL if archived
        # ...
      }
    end
  end
end
```

**After (Option A - Use concern method):**
```ruby
class Users::ExportData::Points
  def call
    # Fetch points with archive association eager-loaded
    points = user.points.with_archived_raw_data.order(:id)

    points.map do |point|
      {
        'raw_data' => point.raw_data_with_archive,  # ← Handles archived data
        # ...
      }
    end
  end
end
```

**After (Option B - Batch fetch archives, see Phase 4 in plan):**
```ruby
# Already implemented in plan - caches downloaded archives
```

#### Example 4: Serializers

**Before:**
```ruby
# app/serializers/export_serializer.rb
class ExportSerializer
  def serialize(point)
    {
      id: point.id,
      raw_data: point.raw_data,  # ← May be NULL
      # ...
    }
  end
end
```

**After:**
```ruby
class ExportSerializer
  def serialize(point)
    {
      id: point.id,
      raw_data: point.raw_data_with_archive,  # ← Fetches from archive if needed
      # ...
    }
  end
end
```

### Step 4: Testing Your Changes

```ruby
# spec/services/points/raw_data_lonlat_extractor_spec.rb
RSpec.describe Points::RawDataLonlatExtractor do
  context 'with archived raw_data' do
    let(:archive) { create(:points_raw_data_archive, user: user, year: 2024, month: 6) }
    let(:point) { create(:point, user: user, raw_data: nil, raw_data_archived: true, raw_data_archive_id: archive.id) }

    before do
      # Mock archive content
      allow(archive.file.blob).to receive(:download).and_return(
        gzip_compress({ id: point.id, raw_data: { 'lon' => 13.4, 'lat' => 52.5 } }.to_json)
      )
    end

    it 'extracts coordinates from archived raw_data' do
      service = described_class.new(point)
      service.call

      expect(point.reload.longitude).to be_within(0.001).of(13.4)
      expect(point.reload.latitude).to be_within(0.001).of(52.5)
    end
  end
end
```

### Step 5: Gradual Rollout Strategy

1. **Week 1:** Update services, add tests
2. **Week 2:** Deploy changes (before archival starts)
3. **Week 3:** Start archival (code already handles it)

This ensures services work with both:
- Points with `raw_data` in DB (current state)
- Points with `raw_data` archived (future state)

### Common Patterns Summary

| Code Location | Change? | Reason |
|---------------|---------|--------|
| Importers (creating points) | ❌ No | raw_data is in DB during import |
| RawDataLonlatExtractor | ✅ Yes | Used for fixes/migrations |
| Export services | ✅ Yes | Users export all their data |
| Serializers for API | ✅ Yes | May serialize archived points |
| Display views | ✅ Yes | May show archived points |
| Background jobs (processing new imports) | ❌ No | Processing fresh data |
| Data migrations | ✅ Yes | May process old data |

---

## Rake Tasks for Restoration

```ruby
# lib/tasks/points_raw_data.rake
namespace :points do
  namespace :raw_data do
    desc 'Restore raw_data from archive to database for a specific month'
    task :restore, [:user_id, :year, :month] => :environment do |t, args|
      validate_args!(args)

      user_id = args[:user_id].to_i
      year = args[:year].to_i
      month = args[:month].to_i

      puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      puts "  Restoring raw_data to DATABASE"
      puts "  User: #{user_id} | Month: #{year}-#{sprintf('%02d', month)}"
      puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      puts ""

      restorer = Points::RawData::Restorer.new
      restorer.restore_to_database(user_id, year, month)

      puts ""
      puts "✓ Restoration complete!"
      puts ""
      puts "Points in #{year}-#{month} now have raw_data in database."
      puts "Run VACUUM ANALYZE points; to update statistics."
    end

    desc 'Restore raw_data to memory/cache temporarily (for data migrations)'
    task :restore_temporary, [:user_id, :year, :month] => :environment do |t, args|
      validate_args!(args)

      user_id = args[:user_id].to_i
      year = args[:year].to_i
      month = args[:month].to_i

      puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      puts "  Loading raw_data into CACHE (temporary)"
      puts "  User: #{user_id} | Month: #{year}-#{sprintf('%02d', month)}"
      puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      puts ""
      puts "Data will be available for 1 hour via Point.raw_data accessor"
      puts ""

      restorer = Points::RawData::Restorer.new
      restorer.restore_to_memory(user_id, year, month)

      puts ""
      puts "✓ Cache loaded successfully!"
      puts ""
      puts "You can now run your data migration."
      puts "Example:"
      puts "  rails runner \"Point.where(user_id: #{user_id}, timestamp_year: #{year}, timestamp_month: #{month}).find_each { |p| p.fix_coordinates_from_raw_data }\""
      puts ""
      puts "Cache will expire in 1 hour automatically."
    end

    desc 'Restore all archived raw_data for a user'
    task :restore_all, [:user_id] => :environment do |t, args|
      raise 'Usage: rake points:raw_data:restore_all[user_id]' unless args[:user_id]

      user_id = args[:user_id].to_i
      user = User.find(user_id)

      puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      puts "  Restoring ALL archives for user"
      puts "  #{user.email} (ID: #{user_id})"
      puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      puts ""

      archives = Points::RawDataArchive.where(user_id: user_id)
                                     .select(:year, :month)
                                     .distinct
                                     .order(:year, :month)

      puts "Found #{archives.count} months to restore"
      puts ""

      archives.each_with_index do |archive, idx|
        puts "[#{idx + 1}/#{archives.count}] Restoring #{archive.year}-#{sprintf('%02d', archive.month)}..."

        restorer = Points::RawData::Restorer.new
        restorer.restore_to_database(user_id, archive.year, archive.month)
      end

      puts ""
      puts "✓ All archives restored for user #{user_id}!"
    end

    desc 'Show archive statistics'
    task status: :environment do
      puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      puts "  Points raw_data Archive Statistics"
      puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      puts ""

      total_archives = Points::RawDataArchive.count
      total_points = Point.count
      archived_points = Point.where(raw_data_archived: true).count
      percentage = total_points > 0 ? (archived_points.to_f / total_points * 100).round(2) : 0

      puts "Archives: #{total_archives}"
      puts "Points archived: #{archived_points} / #{total_points} (#{percentage}%)"
      puts ""

      # Storage size via ActiveStorage
      total_blob_size = ActiveStorage::Blob
        .joins("INNER JOIN active_storage_attachments ON active_storage_attachments.blob_id = active_storage_blobs.id")
        .where("active_storage_attachments.record_type = 'Points::RawDataArchive'")
        .sum(:byte_size)

      puts "Storage used: #{ActiveSupport::NumberHelper.number_to_human_size(total_blob_size)}"
      puts ""

      # Recent activity
      recent = Points::RawDataArchive.where('archived_at > ?', 7.days.ago).count
      puts "Archives created last 7 days: #{recent}"
      puts ""

      # Top users
      puts "Top 10 users by archive count:"
      puts "─────────────────────────────────────────────────"

      Points::RawDataArchive.group(:user_id)
                          .select('user_id, COUNT(*) as archive_count, SUM(point_count) as total_points')
                          .order('archive_count DESC')
                          .limit(10)
                          .each_with_index do |stat, idx|
        user = User.find(stat.user_id)
        puts "#{idx + 1}. #{user.email.ljust(30)} #{stat.archive_count.to_s.rjust(3)} archives, #{stat.total_points.to_s.rjust(8)} points"
      end

      puts ""
    end

    desc 'Verify archive integrity for a month'
    task :verify, [:user_id, :year, :month] => :environment do |t, args|
      validate_args!(args)

      user_id = args[:user_id].to_i
      year = args[:year].to_i
      month = args[:month].to_i

      puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      puts "  Verifying Archives"
      puts "  User: #{user_id} | Month: #{year}-#{sprintf('%02d', month)}"
      puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      puts ""

      archives = Points::RawDataArchive.for_month(user_id, year, month)

      if archives.empty?
        puts "No archives found."
        exit
      end

      all_ok = true

      archives.each do |archive|
        print "Chunk #{archive.chunk_number}: "

        # Check file attached
        unless archive.file.attached?
          puts "✗ ERROR - File not attached!"
          all_ok = false
          next
        end

        # Download and count
        begin
          compressed = archive.file.blob.download
          io = StringIO.new(compressed)
          gz = Zlib::GzipReader.new(io)

          actual_count = 0
          gz.each_line { actual_count += 1 }
          gz.close

          if actual_count == archive.point_count
            puts "✓ OK (#{actual_count} points, #{archive.size_mb} MB)"
          else
            puts "✗ MISMATCH - Expected #{archive.point_count}, found #{actual_count}"
            all_ok = false
          end
        rescue => e
          puts "✗ ERROR - #{e.message}"
          all_ok = false
        end
      end

      puts ""
      if all_ok
        puts "✓ All archives verified successfully!"
      else
        puts "✗ Some archives have issues. Please investigate."
      end
    end

    desc 'Run initial archival for old data (safe to re-run)'
    task initial_archive: :environment do
      puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      puts "  Initial Archival (2+ months old data)"
      puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      puts ""
      puts "This will archive points.raw_data for months 2+ months old."
      puts "This is safe to run multiple times (idempotent)."
      puts ""
      print "Continue? (y/N): "

      response = $stdin.gets.chomp.downcase
      unless response == 'y'
        puts "Cancelled."
        exit
      end

      puts ""
      stats = Points::RawData::Archiver.new.call

      puts ""
      puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      puts "  Archival Complete"
      puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      puts ""
      puts "Months processed: #{stats[:processed]}"
      puts "Points archived: #{stats[:archived]}"
      puts "Failures: #{stats[:failed]}"
      puts ""

      if stats[:archived] > 0
        puts "Next steps:"
        puts "1. Verify a sample: rake points:raw_data:verify[user_id,year,month]"
        puts "2. Check stats: rake points:raw_data:status"
        puts "3. (Optional) Reclaim space: VACUUM FULL points; (during maintenance)"
      end
    end
  end
end

def validate_args!(args)
  unless args[:user_id] && args[:year] && args[:month]
    raise 'Usage: rake points:raw_data:TASK[user_id,year,month]'
  end
end
```

---

## Deployment Strategy

### Phase 1: Deploy Non-Breaking Changes (Week 1)

**Goal:** Add infrastructure without using it

```bash
# 1. Deploy migrations
rails db:migrate

# 2. Verify schema
rails db:schema:dump
git diff db/schema.rb

# 3. Check indexes created
psql -c "\d points" | grep -i index
psql -c "\d points_raw_data_archives" | grep -i index

# 4. Deploy code (models, services inactive)
git push production main

# 5. Monitor for 24 hours
# - Check database performance
# - Check for any errors related to new columns
# - Verify generated columns populate correctly
```

**Rollback:** Simple `rails db:rollback STEP=3`

### Phase 2: Test on Small Dataset (Week 2)

**Goal:** Validate archival works end-to-end

```bash
# Pick a test user with old data
# Example: User 123 with data from 2022

# 1. Manual archive
rails runner "Points::RawData::Archiver.new.archive_specific_month(123, 2022, 1)"

# 2. Verify archive created
rails runner "puts Points::RawDataArchive.where(user_id: 123, year: 2022, month: 1).inspect"

# 3. Verify ActiveStorage blob exists
rails runner "archive = Points::RawDataArchive.find_by(user_id: 123, year: 2022, month: 1); puts archive.file.attached?"

# 4. Verify points marked archived
rails runner "puts Point.where(user_id: 123, timestamp_year: 2022, timestamp_month: 1, raw_data_archived: true).count"

# 5. Test lazy loading
rails runner "point = Point.where(user_id: 123, timestamp_year: 2022, timestamp_month: 1).first; puts point.raw_data.inspect"

# 6. Verify integrity
rake points:raw_data:verify[123,2022,1]

# 7. Test restore
rake points:raw_data:restore_temporary[123,2022,1]

# 8. Clean up test
# (Leave archived for continued testing)
```

**Expected Results:**
- Archive file created in S3/local storage
- Points have `raw_data = NULL` in DB
- `Point.raw_data` still returns data (from cache/S3)
- No errors in logs

### Phase 3: Gradual Rollout (Weeks 3-5)

**Goal:** Archive progressively older data, monitoring each step

**Week 3: Archive 3+ Years Old**
```bash
# Safety: Very old data, rarely accessed
rake points:raw_data:initial_archive

# Monitor:
# - Database size (should decrease)
# - S3 storage (should increase)
# - Query performance (should improve)
# - Error logs (should be empty)

# Check stats
rake points:raw_data:status
```

**Week 4: Archive 2-3 Years Old**
```bash
# Adjust threshold temporarily
# In Points::RawData::Archiver, change SAFE_ARCHIVE_LAG to 2.years
rake points:raw_data:initial_archive

# Monitor same metrics
```

**Week 5: Archive 1-2 Years Old**
```bash
# Adjust threshold to 1.year
rake points:raw_data:initial_archive

# Monitor same metrics
```

**Week 6: Enable Monthly Cron**
```yaml
# config/schedule.yml (or crontab)
0 2 1 * * cd /app && rails points_raw_data:archive_job
# 2 AM on 1st of each month
```

### Phase 4: Reclaim Space (Week 7)

**Goal:** Actually reclaim disk space from NULLed raw_data

```sql
-- During maintenance window (low traffic period)

-- 1. Check current table size
SELECT
  pg_size_pretty(pg_total_relation_size('points')) as total_size,
  pg_size_pretty(pg_relation_size('points')) as table_size,
  pg_size_pretty(pg_indexes_size('points')) as indexes_size;

-- 2. Vacuum full (can take hours, locks table!)
-- IMPORTANT: This locks the table. Do during maintenance!
VACUUM FULL points;

-- 3. Reindex
REINDEX TABLE points;

-- 4. Update statistics
ANALYZE points;

-- 5. Check new size
SELECT
  pg_size_pretty(pg_total_relation_size('points')) as total_size,
  pg_size_pretty(pg_relation_size('points')) as table_size,
  pg_size_pretty(pg_indexes_size('points')) as indexes_size;
```

**Alternative (No Downtime):**
```sql
-- Use pg_repack extension if available
pg_repack -d dawarich_production -t points

-- Or create new table, copy data, swap
CREATE TABLE points_new (LIKE points INCLUDING ALL);
INSERT INTO points_new SELECT * FROM points;
-- ... swap tables atomically
```

---

## Monitoring & Success Metrics

### Database Metrics

```sql
-- Query to monitor archival progress
SELECT
  COUNT(*) FILTER (WHERE raw_data_archived = false) as not_archived,
  COUNT(*) FILTER (WHERE raw_data_archived = true) as archived,
  COUNT(*) as total,
  ROUND(100.0 * COUNT(*) FILTER (WHERE raw_data_archived = true) / COUNT(*), 2) as archived_percentage
FROM points;

-- Table size over time
SELECT
  pg_size_pretty(pg_total_relation_size('points')) as total_size,
  pg_size_pretty(pg_relation_size('points')) as table_size;

-- Average row size
SELECT
  pg_size_pretty(AVG(pg_column_size(points.*))::bigint) as avg_row_size
FROM points
LIMIT 10000;  -- Sample
```

### Application Metrics

```ruby
# config/initializers/prometheus.rb (if using Prometheus)

# Archive operations
archive_operations = Prometheus::Client::Counter.new(
  :points_raw_data_archives_total,
  docstring: 'Total number of archive operations',
  labels: [:status]  # success, failure
)

# Archived points
archived_points_total = Prometheus::Client::Gauge.new(
  :points_raw_data_archived_count,
  docstring: 'Number of points with archived raw_data'
)

# Storage size
archive_storage_bytes = Prometheus::Client::Gauge.new(
  :points_raw_data_archive_storage_bytes,
  docstring: 'Total storage used by archives'
)

# Cache hit rate
raw_data_cache_hits = Prometheus::Client::Counter.new(
  :points_raw_data_cache_hits_total,
  docstring: 'Cache hits for raw_data access',
  labels: [:cache_type]  # temporary, long_term, miss
)
```

### Success Criteria

| Metric | Baseline | Target | Alert If |
|--------|----------|--------|----------|
| Database size | 50GB | 15-20GB | > 25GB |
| Query perf (p95) | 200ms | 160-180ms | > 220ms |
| Archive success rate | N/A | > 99% | < 95% |
| Cache hit rate | N/A | > 80% | < 60% |
| Archive storage size | 0 GB | ~0.5-1 GB | > 5 GB |
| Export time (with archived) | 30s | < 36s | > 45s |

---

## Rollback Plan

### Level 1: Stop Archival (No Data Loss)

```bash
# 1. Disable cron job
# Comment out in config/schedule.yml or crontab

# 2. Stop any running archive jobs
# Via Sidekiq dashboard or:
rails runner "Sidekiq::Queue.new('default').each(&:delete) if Sidekiq::Queue.new('default').map(&:klass).include?('Points::RawData::ArchiveJob')"

# 3. Monitor - system still works, no new archival
```

### Level 2: Restore Data (Reversible)

```bash
# Restore all archived data back to database
rake points:raw_data:restore_all[user_id]  # Per user, or:

# Restore all users (can take hours)
rails runner "
  User.find_each do |user|
    puts \"Restoring user \#{user.id}...\"
    Points::RawData::Restorer.new.restore_all_for_user(user.id)
  end
"

# Verify restoration
rails runner "puts Point.where(raw_data_archived: true).count"  # Should be 0
```

### Level 3: Remove System (Nuclear)

```bash
# 1. Ensure all data restored (Level 2)

# 2. Remove foreign keys and indexes
rails dbconsole
# DROP INDEX IF EXISTS index_points_on_archived_true;
# DROP INDEX IF EXISTS index_points_on_user_time_archived;
# ALTER TABLE points DROP CONSTRAINT IF EXISTS fk_rails_points_raw_data_archives;

# 3. Rollback migrations
rails db:migrate:down VERSION=YYYYMMDDHHMMSS  # timestamp_columns
rails db:migrate:down VERSION=YYYYMMDDHHMMSS  # archival_columns
rails db:migrate:down VERSION=YYYYMMDDHHMMSS  # create_archives_table

# 4. Delete ActiveStorage blobs
rails runner "
  Points::RawDataArchive.find_each do |archive|
    archive.file.purge
    archive.destroy
  end
"

# 5. Remove code
git revert <commit-sha>
git push production main

# 6. VACUUM to reclaim space
psql -d dawarich_production -c "VACUUM FULL points;"
```

---

## Timeline

### Week 1: Foundation
- **Mon-Tue:** Create migrations, deploy
- **Wed-Thu:** Implement models, basic services
- **Fri:** Code review, tests

### Week 2: Core Services
- **Mon-Tue:** Complete Archiver service
- **Wed:** Complete Restorer service
- **Thu:** Export optimization
- **Fri:** Background jobs

### Week 3: Tools & Testing
- **Mon-Tue:** Rake tasks
- **Wed:** Comprehensive test suite
- **Thu-Fri:** Integration testing on staging

### Week 4: Production Deploy
- **Mon:** Deploy to production (code only, inactive)
- **Tue:** Test on single user
- **Wed-Fri:** Monitor, validate

### Week 5: Initial Archive
- **Mon:** Archive 3+ year old data
- **Tue-Fri:** Monitor metrics, validate

### Week 6: Expand Archive
- **Mon:** Archive 2+ year old data
- **Tue-Fri:** Monitor, optimize

### Week 7: Production Ready
- **Mon:** Enable monthly cron
- **Tue:** Final validation
- **Wed:** Documentation update
- **Thu-Fri:** Reclaim space (VACUUM FULL)

**Total: 7 weeks**

---

## Cost Analysis

### Database Savings

**Before:**
- Points table: 50GB
- Daily backup cost: ~$0.05/GB/day = $2.50/day = $75/month

**After:**
- Points table: 15GB (-70%)
- Daily backup cost: ~$0.75/day = $22.50/month
- **Savings: $52.50/month on backups**

### S3 Costs (20M points)

**Storage:**
- Compressed size: ~0.5GB (average 25 bytes per raw_data compressed)
- S3 Standard: $0.023/GB/month
- Cost: 500MB × $0.023 = **$0.012/month** (~negligible)

**Requests:**
- Monthly archival: ~50 PUT requests (50 users × 1 new month)
- User exports: ~100 GET requests/month
- PUT: $0.005/1000 = **$0.0003/month**
- GET: $0.0004/1000 = **$0.00004/month**

**Data Transfer:**
- Export downloads: ~10GB/month (100 exports × 100MB avg)
- First 10GB free, then $0.09/GB
- Cost: **$0/month** (under free tier)

**Total S3 Cost: ~$0.02/month** (essentially free!)

### Net Savings

**Total Monthly Savings: $52.50 - $0.02 = $52.48/month = $629.76/year**

Plus:
- Faster queries → better UX
- Faster backups → reduced downtime risk
- Room for growth → can add 20M more points before hitting old size

---

## FAQ

### Q: How do I enable/disable archival?

**A:** Control via environment variable:
```bash
# Enable archival
ARCHIVE_RAW_DATA=true

# Disable archival (default)
ARCHIVE_RAW_DATA=false
# or simply don't set the variable
```

When disabled:
- Archive jobs return immediately without processing
- No S3 operations occur
- No costs incurred
- Existing archived data remains accessible
- Can be re-enabled anytime by setting to `"true"`

**Deployment recommendation:**
1. Deploy code with `ARCHIVE_RAW_DATA=false`
2. Test on staging
3. Enable on production: `ARCHIVE_RAW_DATA=true`
4. Monitor for 1 week
5. If issues arise, set back to `false` immediately

### Q: What happens if S3 is down?

**A:** The app continues working with graceful degradation:
- New imports work (raw_data stored in DB)
- Existing non-archived points work normally
- Archived points return `{}` from `Point.raw_data` (logged to Sentry)
- Exports may be incomplete (raw_data missing for archived points)

### Q: Can I switch storage backends later?

**A:** Yes! ActiveStorage handles this:
```bash
# 1. Configure new backend in config/storage.yml
# 2. Set STORAGE_BACKEND=new_backend
# 3. Migrate blobs:
rails active_storage:migrate_blobs[s3,gcs]
```

### Q: How do I restore data for a specific migration?

**A:**
```bash
# 1. Temporarily restore to cache (1 hour)
rake points:raw_data:restore_temporary[123,2024,6]

# 2. Run your migration immediately
rails runner "
  Point.where(user_id: 123, timestamp_year: 2024, timestamp_month: 6).find_each do |point|
    # point.raw_data now returns archived data from cache
    point.fix_coordinates_from_raw_data
    point.save!
  end
"

# 3. Cache expires automatically in 1 hour
```

### Q: What if archive job fails?

**A:** Designed for safety:
- Advisory locks prevent duplicate processing
- Transactions ensure atomic DB updates
- Failed uploads don't mark points as archived
- Job retries automatically (Sidekiq)
- Sentry captures exceptions

### Q: Can I archive specific users only?

**A:** Yes, modify the archiver:
```ruby
# Archive only specific users
Points::RawData::Archiver.new.call(user_ids: [1, 2, 3])

# Or exclude users
Points::RawData::Archiver.new.call(exclude_user_ids: [123])
```

### Q: How do I monitor cache hit rates?

**A:**
```ruby
# Add instrumentation to Point#raw_data
def raw_data
  return super unless raw_data_archived?

  cached = check_temporary_restore_cache
  if cached
    Rails.logger.debug("Cache hit: temporary restore for point #{id}")
    return cached
  end

  result = fetch_from_archive  # Internally logs cache hits/misses
  Rails.logger.debug("Cache miss: fetched from S3 for point #{id}") if result
  result
end
```

---

## Appendix A: What is JSONL?

**JSONL** stands for **JSON Lines** (also called **newline-delimited JSON** or **ndjson**).

### Definition

JSONL is a text format where **each line is a separate, complete, valid JSON object**. Unlike regular JSON which wraps everything in an array or object, JSONL stores multiple JSON objects separated by newlines.

### Format Comparison

**Regular JSON (Array):**
```json
[
  {"id": 1, "name": "Alice", "age": 30},
  {"id": 2, "name": "Bob", "age": 25},
  {"id": 3, "name": "Charlie", "age": 35}
]
```

**JSONL (JSON Lines):**
```jsonl
{"id": 1, "name": "Alice", "age": 30}
{"id": 2, "name": "Bob", "age": 25}
{"id": 3, "name": "Charlie", "age": 35}
```

No commas, no brackets—just one JSON object per line.

### Why We Use JSONL for Archives

#### 1. **Memory-Efficient Streaming**

```ruby
# Regular JSON: Must load entire array into memory
data = JSON.parse(File.read('huge_file.json'))  # ❌ Could be gigabytes!
data.each { |item| process(item) }

# JSONL: Process line-by-line
File.foreach('huge_file.jsonl') do |line|  # ✅ Only one line in memory
  item = JSON.parse(line)
  process(item)
end
```

For a month with 100,000 points:
- JSON: Must hold all 100k objects in memory (~200MB+)
- JSONL: Process one at a time (~2KB per point in memory)

#### 2. **Fast Searching Without Full Parse**

```ruby
# Find one specific point without parsing everything
def find_point_raw_data(archive_file, point_id)
  Zlib::GzipReader.new(archive_file).each_line do |line|
    data = JSON.parse(line)
    return data['raw_data'] if data['id'] == point_id  # Found it! Stop reading.
  end
end
```

With regular JSON, you'd have to:
1. Download entire file
2. Parse entire JSON array
3. Search through array
4. Return result

With JSONL, you:
1. Stream file line by line
2. Parse only lines until found
3. Stop immediately (could be after 10 lines instead of 100k!)

#### 3. **Perfect for Append-Only Architecture**

```bash
# June 1st: Create initial archive
echo '{"id":1,"raw_data":{...}}' >> raw_data.jsonl
echo '{"id":2,"raw_data":{...}}' >> raw_data.jsonl
# ... 1000 lines

# July 1st: User imports 50 retrospective points
# Just append new lines!
echo '{"id":1001,"raw_data":{...}}' >> raw_data.jsonl
echo '{"id":1002,"raw_data":{...}}' >> raw_data.jsonl
# ... 50 more lines

# Done! No need to download, parse, merge, and re-upload.
```

With regular JSON, you'd need to:
1. Download entire array
2. Parse JSON
3. Add new objects to array
4. Re-serialize entire array
5. Re-upload entire file

#### 4. **Excellent Compression**

```bash
# JSONL compresses very well with gzip
raw_data.jsonl          # 10 MB (uncompressed)
raw_data.jsonl.gz       # 1 MB (compressed)  # 90% reduction!
```

Each line has similar structure, so gzip finds repeated patterns:
- Same keys: `"id"`, `"raw_data"`, `"lon"`, `"lat"`, etc.
- Same formats: numbers, nested objects
- Repetitive whitespace

### Our Implementation Examples

#### Writing Archive (Archiver Service)
```ruby
gz = Zlib::GzipWriter.new(io)

points.find_each(batch_size: 1000) do |point|
  # Each point becomes one JSONL line
  gz.puts({ id: point.id, raw_data: point.raw_data }.to_json)
end

# Result file (compressed):
# Line 1: {"id":123,"raw_data":{"lon":13.4,"lat":52.5,"accuracy":10}}
# Line 2: {"id":124,"raw_data":{"lon":13.5,"lat":52.6,"accuracy":12}}
# Line 3: {"id":125,"raw_data":{"lon":13.6,"lat":52.7,"accuracy":8}}
# ...
```

#### Reading Archive (Point Model)
```ruby
gz = Zlib::GzipReader.new(compressed_file)

# Stream search - only parse lines until we find our point
gz.each_line do |line|
  data = JSON.parse(line)
  return data['raw_data'] if data['id'] == target_id  # Found! Done.
end
```

#### Restoring Archive (Restorer Service)
```ruby
# Process entire archive line-by-line (memory efficient)
decompressed_content.each_line do |line|
  data = JSON.parse(line)

  Point.where(id: data['id']).update_all(
    raw_data: data['raw_data']
  )
end
```

### Performance Comparison

| Operation | Regular JSON | JSONL | Winner |
|-----------|--------------|-------|--------|
| Archive 100k points | Load all 100k in memory | Process 1k batches | JSONL |
| Find 1 point | Parse entire 100k array | Stop after finding (avg 50k) | JSONL |
| Add 50 new points | Download, merge, re-upload | Append 50 lines | JSONL |
| Memory usage (100k points) | ~200 MB | ~2 MB | JSONL |
| Compression ratio | 60-70% | 85-95% | JSONL |
| Processing speed | 5-10 sec | 0.5-2 sec | JSONL |

### Common Use Cases for JSONL

- **Log aggregation** - Kibana, Logstash, Splunk
- **Big data** - Apache Spark, Hadoop, BigQuery native support
- **Machine learning datasets** - TensorFlow, PyTorch data pipelines
- **API streaming** - Twitter API, Slack RTM API
- **Database exports** - MongoDB export, PostgreSQL COPY
- **Our use case** - Point data archives!

### File Extensions

All are valid and recognized:
- `.jsonl` - Official extension (JSONL)
- `.ndjson` - Alternative (Newline-Delimited JSON)
- `.jsonl.gz` - Compressed (what we use)
- `.ndjson.gz` - Compressed alternative

### Key Takeaway

**JSONL = One JSON object per line**

Perfect for our archive system because it enables:
1. ✅ **Stream processing** - Low memory usage
2. ✅ **Fast searching** - Stop when found
3. ✅ **Append-only** - No merge needed
4. ✅ **Great compression** - 90%+ size reduction
5. ✅ **Simple format** - Easy to read/write/debug

It's essentially the difference between:
- **Phone book** (JSON) - One big book, must open entire thing
- **Index cards** (JSONL) - One card per entry, process individually

---

## Appendix B: File Checklist

### Files to Create (17)

**Migrations (3):**
- [ ] `db/migrate/YYYYMMDDHHMMSS_create_points_raw_data_archives.rb`
- [ ] `db/migrate/YYYYMMDDHHMMSS_add_archival_columns_to_points.rb`
- [ ] `db/migrate/YYYYMMDDHHMMSS_add_generated_timestamp_columns_to_points.rb`

**Models & Concerns (2):**
- [ ] `app/models/points/raw_data_archive.rb` (or `app/models/points_raw_data_archive.rb`)
- [ ] `app/models/concerns/archivable.rb` ✨ **NEW**

**Services (3):**
- [ ] `app/services/points/raw_data/archiver.rb`
- [ ] `app/services/points/raw_data/restorer.rb`
- [ ] `app/services/points/raw_data/chunk_compressor.rb`

**Jobs (2):**
- [ ] `app/jobs/points/raw_data/archive_job.rb`
- [ ] `app/jobs/points/raw_data/re_archive_month_job.rb`

**Rake Tasks (1):**
- [ ] `lib/tasks/points_raw_data.rake`

**Specs (6):**
- [ ] `spec/models/points_raw_data_archive_spec.rb`
- [ ] `spec/models/concerns/archivable_spec.rb` ✨ **NEW**
- [ ] `spec/services/points/raw_data/archiver_spec.rb`
- [ ] `spec/services/points/raw_data/restorer_spec.rb`
- [ ] `spec/jobs/points/raw_data/archive_job_spec.rb`
- [ ] `spec/lib/tasks/points_raw_data_rake_spec.rb`

### Files to Modify (6+)

**Core Models:**
- [ ] `app/models/point.rb` - Add `include Archivable` (one line!)
- [ ] `app/models/user.rb` - Add `has_many :raw_data_archives` relationship

**Services:**
- [ ] `app/services/users/export_data/points.rb` - Batch load archives (see Phase 4)
- [ ] `app/services/imports/create.rb` - Trigger re-archival after import
- [ ] `app/services/points/raw_data_lonlat_extractor.rb` - Use `raw_data_with_archive`

**Serializers (if needed):**
- [ ] `app/serializers/export_serializer.rb` - Use `raw_data_with_archive`
- [ ] Other serializers that access `raw_data` (find with grep)

**Config:**
- [ ] `.env.template` - Add archival configuration variable:
  ```bash
  # Raw Data Archival (Optional)
  ARCHIVE_RAW_DATA=false    # Set to "true" to enable archival (archives data 2+ months old)
  # Note: Requires STORAGE_BACKEND configured (s3, local, etc.)
  ```

### Files NOT Modified (Already Configured!)

- ✅ `config/storage.yml` - ActiveStorage already configured
- ✅ `config/initializers/aws.rb` - S3 credentials already set
- ✅ `config/environments/production.rb` - Storage backend already set
- ✅ `Gemfile` - aws-sdk-s3 already included

---

## Appendix C: User Model Integration

### Archive Deletion Policy & Cascade Behavior

**Requirement:** When a user is deleted, all their raw_data archives (both database records and S3 files) must be deleted.

### Implementation

**User Model Addition:**
```ruby
# app/models/user.rb
class User < ApplicationRecord
  # ... existing associations ...
  has_many :raw_data_archives, class_name: 'Points::RawDataArchive', dependent: :destroy
  # ... rest of model ...
end
```

### How Cascade Deletion Works

1. **User deletion triggered** → `user.destroy`
2. **`dependent: :destroy` on association** → Rails calls `destroy` on each `Points::RawDataArchive` record
3. **Archive model's `has_one_attached :file`** → ActiveStorage's built-in callback triggers
4. **ActiveStorage purges blob** → S3 file deleted via `file.purge`
5. **Archive record deleted** → Database row removed

### Automatic Cleanup Chain

```
user.destroy
  ↓
user.raw_data_archives.destroy_all
  ↓
archive.destroy (for each archive)
  ↓
ActiveStorage::Attachment callback fires
  ↓
active_storage_blobs.purge
  ↓
S3 file deleted
  ↓
active_storage_attachments row deleted
  ↓
active_storage_blobs row deleted
  ↓
points_raw_data_archives row deleted
```

### GDPR Compliance

✅ **Complete data removal:**
- Database: `points` table records deleted (via `has_many :points, dependent: :destroy`)
- Database: `points_raw_data_archives` table records deleted
- Storage: All archive `.jsonl.gz` files in S3/local storage deleted
- Database: ActiveStorage metadata (`active_storage_blobs`, `active_storage_attachments`) deleted

✅ **No manual intervention needed** - Standard Rails cascade handles everything

### Why No `after_destroy` Callback Needed

**You might think you need this:**
```ruby
# ❌ NOT NEEDED
after_destroy :purge_raw_data_archives

def purge_raw_data_archives
  raw_data_archives.find_each { |a| a.file.purge }
end
```

**But you don't because:**
1. ActiveStorage **automatically** purges attached files when the parent record is destroyed
2. This is the same behavior as existing `Import` and `Export` models in Dawarich
3. Adding manual purge would duplicate the work and potentially cause errors

### Verification Test

```ruby
# spec/models/user_spec.rb
RSpec.describe User, type: :model do
  describe 'archive deletion cascade' do
    let(:user) { create(:user) }
    let!(:archive) { create(:points_raw_data_archive, user: user) }

    before do
      # Attach a file to the archive
      archive.file.attach(
        io: StringIO.new('test data'),
        filename: 'test.jsonl.gz',
        content_type: 'application/gzip'
      )
    end

    it 'deletes archives and their S3 files when user is deleted' do
      blob_id = archive.file.blob.id

      expect {
        user.destroy
      }.to change(Points::RawDataArchive, :count).by(-1)
        .and change(ActiveStorage::Blob, :count).by(-1)

      expect(ActiveStorage::Blob.find_by(id: blob_id)).to be_nil
    end
  end
end
```

### Notes

- This pattern is **consistent with existing Dawarich code** (Import/Export models)
- No special configuration needed for S3 deletion - ActiveStorage handles it
- Works with any storage backend (S3, GCS, Azure, local disk)
- Deletion is **transactional** - if user deletion fails, archives remain intact

---

## Conclusion

This implementation plan provides a comprehensive, production-ready approach to archiving `points.raw_data` using ActiveStorage, with:

✅ **Consistency:** Uses same patterns as existing Import/Export
✅ **Safety:** Append-only, transactional, idempotent
✅ **Flexibility:** Works with any ActiveStorage backend
✅ **Observability:** Comprehensive rake tasks and monitoring
✅ **Reversibility:** Full restore capabilities

**Next Steps:**
1. Review plan with team
2. Approve and prioritize
3. Create GitHub issue with checklist
4. Begin Week 1 implementation

**Questions?** Review the FAQ section or ask for clarification on specific components.
