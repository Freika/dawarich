# frozen_string_literal: true

class Users::ImportData::Stats
  BATCH_SIZE = 1000

  def initialize(user, stats_data)
    @user = user
    @stats_data = stats_data
  end

  def call
    return 0 unless stats_data.is_a?(Array)

    Rails.logger.info "Importing #{stats_data.size} stats for user: #{user.email}"

    # Filter valid stats and prepare for bulk import
    valid_stats = filter_and_prepare_stats

    if valid_stats.empty?
      Rails.logger.info "Stats import completed. Created: 0"
      return 0
    end

    # Remove existing stats to avoid duplicates
    deduplicated_stats = filter_existing_stats(valid_stats)

    if deduplicated_stats.size < valid_stats.size
      Rails.logger.debug "Skipped #{valid_stats.size - deduplicated_stats.size} duplicate stats"
    end

    # Bulk import in batches
    total_created = bulk_import_stats(deduplicated_stats)

    Rails.logger.info "Stats import completed. Created: #{total_created}"
    total_created
  end

  private

  attr_reader :user, :stats_data

  def filter_and_prepare_stats
    valid_stats = []
    skipped_count = 0

    stats_data.each do |stat_data|
      next unless stat_data.is_a?(Hash)

      # Skip stats with missing required data
      unless valid_stat_data?(stat_data)
        skipped_count += 1
        next
      end

      # Prepare stat attributes for bulk insert
      prepared_attributes = prepare_stat_attributes(stat_data)
      valid_stats << prepared_attributes if prepared_attributes
    end

    if skipped_count > 0
      Rails.logger.warn "Skipped #{skipped_count} stats with invalid or missing required data"
    end

    valid_stats
  end

  def prepare_stat_attributes(stat_data)
    # Start with base attributes, excluding timestamp fields
    attributes = stat_data.except('created_at', 'updated_at')

    # Add required attributes for bulk insert
    attributes['user_id'] = user.id
    attributes['created_at'] = Time.current
    attributes['updated_at'] = Time.current

    # Convert string keys to symbols for consistency
    attributes.symbolize_keys
  rescue StandardError => e
    Rails.logger.error "Failed to prepare stat attributes: #{e.message}"
    Rails.logger.error "Stat data: #{stat_data.inspect}"
    nil
  end

  def filter_existing_stats(stats)
    return stats if stats.empty?

    # Build lookup hash of existing stats for this user
    existing_stats_lookup = {}
    user.stats.select(:year, :month).each do |stat|
      key = [stat.year, stat.month]
      existing_stats_lookup[key] = true
    end

    # Filter out stats that already exist
    filtered_stats = stats.reject do |stat|
      key = [stat[:year], stat[:month]]
      if existing_stats_lookup[key]
        Rails.logger.debug "Stat already exists: #{stat[:year]}-#{stat[:month]}"
        true
      else
        false
      end
    end

    filtered_stats
  end

  def bulk_import_stats(stats)
    total_created = 0

    stats.each_slice(BATCH_SIZE) do |batch|
      begin
        # Use upsert_all to efficiently bulk insert stats
        result = Stat.upsert_all(
          batch,
          returning: %w[id],
          on_duplicate: :skip
        )

        batch_created = result.count
        total_created += batch_created

        Rails.logger.debug "Processed batch of #{batch.size} stats, created #{batch_created}, total created: #{total_created}"

      rescue StandardError => e
        Rails.logger.error "Failed to process stat batch: #{e.message}"
        Rails.logger.error "Batch size: #{batch.size}"
        Rails.logger.error "Backtrace: #{e.backtrace.first(3).join('\n')}"
        # Continue with next batch instead of failing completely
      end
    end

    total_created
  end

  def valid_stat_data?(stat_data)
    # Check for required fields
    return false unless stat_data.is_a?(Hash)

    unless stat_data['year'].present?
      Rails.logger.error "Failed to create stat: Validation failed: Year can't be blank"
      return false
    end

    unless stat_data['month'].present?
      Rails.logger.error "Failed to create stat: Validation failed: Month can't be blank"
      return false
    end

    unless stat_data['distance'].present?
      Rails.logger.error "Failed to create stat: Validation failed: Distance can't be blank"
      return false
    end

    true
  rescue StandardError => e
    Rails.logger.debug "Stat validation failed: #{e.message} for data: #{stat_data.inspect}"
    false
  end
end
