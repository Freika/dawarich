# frozen_string_literal: true

class Users::ImportData::Notifications
  BATCH_SIZE = 1000

  def initialize(user, notifications_data)
    @user = user
    @notifications_data = notifications_data
  end

  def call
    return 0 unless notifications_data.is_a?(Array)

    Rails.logger.info "Importing #{notifications_data.size} notifications for user: #{user.email}"

    # Filter valid notifications and prepare for bulk import
    valid_notifications = filter_and_prepare_notifications

    if valid_notifications.empty?
      Rails.logger.info "Notifications import completed. Created: 0"
      return 0
    end

    # Remove existing notifications to avoid duplicates
    deduplicated_notifications = filter_existing_notifications(valid_notifications)

    if deduplicated_notifications.size < valid_notifications.size
      Rails.logger.debug "Skipped #{valid_notifications.size - deduplicated_notifications.size} duplicate notifications"
    end

    # Bulk import in batches
    total_created = bulk_import_notifications(deduplicated_notifications)

    Rails.logger.info "Notifications import completed. Created: #{total_created}"
    total_created
  end

  private

  attr_reader :user, :notifications_data

  def filter_and_prepare_notifications
    valid_notifications = []
    skipped_count = 0

    notifications_data.each do |notification_data|
      next unless notification_data.is_a?(Hash)

      # Skip notifications with missing required data
      unless valid_notification_data?(notification_data)
        skipped_count += 1
        next
      end

      # Prepare notification attributes for bulk insert
      prepared_attributes = prepare_notification_attributes(notification_data)
      valid_notifications << prepared_attributes if prepared_attributes
    end

    if skipped_count > 0
      Rails.logger.warn "Skipped #{skipped_count} notifications with invalid or missing required data"
    end

    valid_notifications
  end

  def prepare_notification_attributes(notification_data)
    # Start with base attributes, excluding only updated_at (preserve created_at for duplicate logic)
    attributes = notification_data.except('updated_at')

    # Add required attributes for bulk insert
    attributes['user_id'] = user.id

    # Preserve original created_at if present, otherwise use current time
    unless attributes['created_at'].present?
      attributes['created_at'] = Time.current
    end

    attributes['updated_at'] = Time.current

    # Convert string keys to symbols for consistency
    attributes.symbolize_keys
  rescue StandardError => e
    Rails.logger.error "Failed to prepare notification attributes: #{e.message}"
    Rails.logger.error "Notification data: #{notification_data.inspect}"
    nil
  end

  def filter_existing_notifications(notifications)
    return notifications if notifications.empty?

    # Build lookup hash of existing notifications for this user
    # Use title and content as the primary deduplication key
    existing_notifications_lookup = {}
    user.notifications.select(:title, :content, :created_at, :kind).each do |notification|
      # Primary key: title + content
      primary_key = [notification.title.strip, notification.content.strip]

      # Secondary key: include timestamp for exact matches
      exact_key = [notification.title.strip, notification.content.strip, normalize_timestamp(notification.created_at)]

      existing_notifications_lookup[primary_key] = true
      existing_notifications_lookup[exact_key] = true
    end

    # Filter out notifications that already exist
    filtered_notifications = notifications.reject do |notification|
      title = notification[:title]&.strip
      content = notification[:content]&.strip

      # Check both primary key (title + content) and exact key (with timestamp)
      primary_key = [title, content]
      exact_key = [title, content, normalize_timestamp(notification[:created_at])]

      if existing_notifications_lookup[primary_key] || existing_notifications_lookup[exact_key]
        Rails.logger.debug "Notification already exists: #{notification[:title]}"
        true
      else
        false
      end
    end

    filtered_notifications
  end

  def normalize_timestamp(timestamp)
    case timestamp
    when String
      # Parse string and convert to unix timestamp for consistent comparison
      Time.parse(timestamp).to_i
    when Time, DateTime
      # Convert time objects to unix timestamp for consistent comparison
      timestamp.to_i
    else
      timestamp.to_s
    end
  rescue StandardError => e
    Rails.logger.debug "Failed to normalize timestamp #{timestamp}: #{e.message}"
    timestamp.to_s
  end

  def bulk_import_notifications(notifications)
    total_created = 0

    notifications.each_slice(BATCH_SIZE) do |batch|
      begin
        # Use upsert_all to efficiently bulk insert notifications
        result = Notification.upsert_all(
          batch,
          returning: %w[id],
          on_duplicate: :skip
        )

        batch_created = result.count
        total_created += batch_created

        Rails.logger.debug "Processed batch of #{batch.size} notifications, created #{batch_created}, total created: #{total_created}"

      rescue StandardError => e
        Rails.logger.error "Failed to process notification batch: #{e.message}"
        Rails.logger.error "Batch size: #{batch.size}"
        Rails.logger.error "Backtrace: #{e.backtrace.first(3).join('\n')}"
        # Continue with next batch instead of failing completely
      end
    end

    total_created
  end

  def valid_notification_data?(notification_data)
    # Check for required fields
    return false unless notification_data.is_a?(Hash)

    unless notification_data['title'].present?
      Rails.logger.error "Failed to create notification: Validation failed: Title can't be blank"
      return false
    end

    unless notification_data['content'].present?
      Rails.logger.error "Failed to create notification: Validation failed: Content can't be blank"
      return false
    end

    true
  rescue StandardError => e
    Rails.logger.debug "Notification validation failed: #{e.message} for data: #{notification_data.inspect}"
    false
  end
end
