# frozen_string_literal: true

class Export < ApplicationRecord
  belongs_to :user

  enum :status, { created: 0, processing: 1, completed: 2, failed: 3 }
  # file_format describes the *payload* format inside the stored blob, not
  # the blob itself. For points exports (file_type: :points) the stored blob
  # is always a single-entry zip (content_type: application/zip) containing
  # one file in the format named by this enum.
  enum :file_format, { json: 0, gpx: 1, archive: 2 }
  enum :file_type, { points: 0, user_data: 1 }

  validates :name, presence: true

  has_one_attached :file

  before_save :set_processing_started_at, if: :status_changed_to_processing?

  after_commit -> { ExportJob.perform_later(id) }, on: :create, unless: -> { user_data? || archive? }
  after_commit -> { remove_attached_file }, on: :destroy

  def process!
    Exports::Create.new(export: self).call
  end

  def migrate_to_new_storage
    return if file.attached?
    return if url.blank?

    file_path = "public/#{url}"
    return unless File.file?(file_path)

    file.attach(io: File.open(file_path), filename: name)
    old_url = url
    update!(url: nil)

    File.delete("public/#{old_url}") if File.exist?("public/#{old_url}")
  rescue StandardError => e
    Rails.logger.debug("Error migrating export #{id}: #{e.message}")
  end

  private

  def set_processing_started_at
    self.processing_started_at = Time.current
  end

  def status_changed_to_processing?
    status_changed? && processing?
  end

  def remove_attached_file
    file.purge_later if file.attached?

    File.delete("public/#{url}") if url.present? && File.exist?("public/#{url}")
  rescue StandardError => e
    Rails.logger.debug("Error removing export #{id}: #{e.message}")
  end
end
