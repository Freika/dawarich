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

    valid_notifications = filter_and_prepare_notifications

    if valid_notifications.empty?
      Rails.logger.info 'Notifications import completed. Created: 0'
      return 0
    end

    deduplicated_notifications = filter_existing_notifications(valid_notifications)

    if deduplicated_notifications.size < valid_notifications.size
      Rails.logger.debug "Skipped #{valid_notifications.size - deduplicated_notifications.size} duplicate notifications"
    end

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

      unless valid_notification_data?(notification_data)
        skipped_count += 1
        next
      end

      prepared_attributes = prepare_notification_attributes(notification_data)
      valid_notifications << prepared_attributes if prepared_attributes
    end

    if skipped_count.positive?
      Rails.logger.warn "Skipped #{skipped_count} notifications with invalid or missing required data"
    end

    valid_notifications
  end

  def prepare_notification_attributes(notification_data)
    attributes = notification_data.except('updated_at')

    attributes['user_id'] = user.id

    attributes['created_at'] = Time.current if attributes['created_at'].blank?

    attributes['updated_at'] = Time.current

    attributes.symbolize_keys
  rescue StandardError => e
    Rails.logger.error "Failed to prepare notification attributes: #{e.message}"
    Rails.logger.error "Notification data: #{notification_data.inspect}"
    nil
  end

  def filter_existing_notifications(notifications)
    return notifications if notifications.empty?

    lookup = build_existing_notifications_lookup

    notifications.reject do |notification|
      title = notification[:title]&.strip
      content = notification[:content]&.strip

      primary_key = [title, content]
      exact_key = [title, content, normalize_timestamp(notification[:created_at])]

      if lookup[primary_key] || lookup[exact_key]
        Rails.logger.debug "Notification already exists: #{notification[:title]}"
        true
      else
        false
      end
    end
  end

  def build_existing_notifications_lookup
    lookup = {}
    user.notifications.select(:title, :content, :created_at, :kind).each do |notification|
      title = notification.title.strip
      content = notification.content.strip

      lookup[[title, content]] = true
      lookup[[title, content, normalize_timestamp(notification.created_at)]] = true
    end
    lookup
  end

  def normalize_timestamp(timestamp)
    case timestamp
    when String then Time.parse(timestamp).utc.to_i
    when Time, DateTime then timestamp.utc.to_i
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
      result = Notification.upsert_all(
        batch,
        returning: %w[id],
        on_duplicate: :skip
      )
      # rubocop:enable Rails/SkipsModelValidations

      batch_created = result.count
      total_created += batch_created

      Rails.logger.debug(
        "Processed batch of #{batch.size} notifications, created #{batch_created}, total: #{total_created}"
      )
    rescue StandardError => e
      Rails.logger.error "Failed to process notification batch: #{e.message}"
      Rails.logger.error "Batch size: #{batch.size}"
      Rails.logger.error "Backtrace: #{e.backtrace.first(3).join('\n')}"
    end

    total_created
  end

  def valid_notification_data?(notification_data)
    return false unless notification_data.is_a?(Hash)

    if notification_data['title'].blank?
      Rails.logger.error "Failed to create notification: Validation failed: Title can't be blank"
      return false
    end

    if notification_data['content'].blank?
      Rails.logger.error "Failed to create notification: Validation failed: Content can't be blank"
      return false
    end

    true
  rescue StandardError => e
    Rails.logger.debug "Notification validation failed: #{e.message} for data: #{notification_data.inspect}"
    false
  end
end
