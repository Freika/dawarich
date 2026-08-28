# frozen_string_literal: true

class Import < ApplicationRecord
  belongs_to :user
  has_many :points, dependent: :destroy
  has_many :extracted_visits, class_name: 'Visit', dependent: :nullify
  has_many :extracted_places, class_name: 'Place', dependent: :nullify
  has_many :extracted_tracks, class_name: 'Track', dependent: :nullify

  has_one_attached :file

  # Flag to skip background processing during user data import
  attr_accessor :skip_background_processing

  before_save :resolve_additional_data_extraction_availability

  after_commit -> { Import::ProcessJob.perform_later(id) unless skip_background_processing }, on: :create
  after_commit :remove_attached_file, on: :destroy
  before_commit :recalculate_stats, on: :destroy, if: -> { !demo && points.exists? }

  before_save :set_processing_started_at, if: :status_changed_to_processing?

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validate :file_size_within_limit, if: -> { user.legacy_trial? && !demo }
  validate :import_count_within_limit, if: -> { user.legacy_trial? && !demo }

  enum :status, { created: 0, processing: 1, completed: 2, failed: 3, deleting: 4 }

  enum :source, {
    google_semantic_history: 0, owntracks: 1, google_records: 2,
    google_phone_takeout: 3, gpx: 4, immich_api: 5, geojson: 6, photoprism_api: 7,
    user_data_archive: 8, kml: 9,
    csv: 10, tcx: 11, fit: 12, polarsteps: 13, google_photos: 14,
    mobile_photo_library: 15
  }, allow_nil: true

  enum :additional_data_extraction_status, {
    not_attempted: 0,
    pending: 1,
    running: 2,
    completed: 3,
    failed: 4,
    unsupported: 5
  }, prefix: :additional_data_extraction

  after_commit :enqueue_additional_data_extraction, on: :update,
               if: :should_enqueue_additional_data_extraction?

  def process!
    if user_data_archive?
      process_user_data_archive!
    else
      Imports::Create.new(user, self).call
    end
  end

  def process_user_data_archive!
    Users::ImportDataJob.perform_later(id)
  end

  def reverse_geocoded_points_count
    points.reverse_geocoded.count
  end

  def years_and_months_tracked
    quoted_tz = ActiveRecord::Base.connection.quote(Time.zone.tzinfo.identifier)
    points
      .select(Arel.sql(
                "DISTINCT EXTRACT(YEAR FROM TO_TIMESTAMP(timestamp) AT TIME ZONE #{quoted_tz})::integer AS year, \
                 EXTRACT(MONTH FROM TO_TIMESTAMP(timestamp) AT TIME ZONE #{quoted_tz})::integer AS month"
              ))
      .map { |row| [row[:year], row[:month]] }
  end

  def migrate_to_new_storage
    return if file.attached?

    raw_file = File.new(raw_data)

    file.attach(io: raw_file, filename: name, content_type: 'application/json')
  end

  def additional_data_extraction_supported?
    EnhancedImport::Translator.supported?(source)
  end

  def extraction_counts
    additional_data_extraction.fetch('counts', {}).transform_keys(&:to_sym)
  end

  def extraction_error_message
    additional_data_extraction['error_message']
  end

  # Sidekiq loses in-flight jobs on SIGKILL, so an extraction that never
  # reported back stops counting as running after this window.
  EXTRACTION_STALE_AFTER = 6.hours

  def extraction_in_flight?
    additional_data_extraction_pending? || additional_data_extraction_running?
  end

  def extraction_stalled?
    return false unless extraction_in_flight?

    started_at = additional_data_extraction['started_at']
    return false if started_at.blank?

    Time.zone.parse(started_at.to_s) <= EXTRACTION_STALE_AFTER.ago
  rescue ArgumentError, TypeError
    false
  end

  def trust_source_for_extraction?
    additional_data_extraction.dig('options', 'trust_source') != false
  end

  # Two rapid submissions both pass the extraction policy before either
  # writes; the compare-and-swap lets exactly one of them move the status
  # to pending and enqueue the job.
  def claim_additional_data_extraction!(payload)
    self.class.where(id: id, additional_data_extraction_status: additional_data_extraction_status)
        .update_all(
          additional_data_extraction_status: self.class.additional_data_extraction_statuses[:pending],
          additional_data_extraction: payload
        ).positive?
  end

  private

  def set_processing_started_at
    self.processing_started_at = Time.current
  end

  def status_changed_to_processing?
    status_changed? && processing?
  end

  def remove_attached_file
    file.purge_later
  end

  def file_size_within_limit
    return unless file.attached?

    return unless file.blob.byte_size > 11.megabytes

    errors.add(:file, I18n.t('models.import.is_too_large_trial_users_can_only_upload_files_up'))
  end

  def import_count_within_limit
    return unless new_record?

    existing_imports_count = user.imports.where(demo: false).count
    return unless existing_imports_count >= 5

    errors.add(:base, I18n.t('models.import.trial_users_can_only_create_up_to_5_imports_please'))
  end

  def recalculate_stats
    years_and_months_tracked.each do |year, month|
      Stats::CalculatingJob.perform_later(user.id, year, month)
    end
  end

  # Uploads are created before their source is detected, so availability has to
  # settle in both directions: only the two "nothing has happened yet" states
  # are ever rewritten, never a finished or in-flight extraction.
  def resolve_additional_data_extraction_availability
    if additional_data_extraction_supported?
      return unless additional_data_extraction_unsupported?

      self.additional_data_extraction_status = :not_attempted
    else
      return unless additional_data_extraction_not_attempted?

      self.additional_data_extraction_status = :unsupported
    end
  end

  def should_enqueue_additional_data_extraction?
    return false unless saved_change_to_status? && completed?
    return false unless additional_data_extraction_supported?
    return false unless additional_data_extraction_not_attempted?

    true
  end

  def enqueue_additional_data_extraction
    update_columns(
      additional_data_extraction_status: Import.additional_data_extraction_statuses[:pending],
      additional_data_extraction: additional_data_extraction.merge('started_at' => Time.current.iso8601)
    )
    EnhancedImport::ExtractJob.perform_later(id)
  end
end
