# frozen_string_literal: true

class VideoExport < ApplicationRecord
  belongs_to :user
  belongs_to :track, optional: true

  enum :status, { created: 0, processing: 1, completed: 2, failed: 3 }

  validates :start_at, :end_at, presence: true

  has_one_attached :file

  before_validation :generate_callback_nonce, on: :create
  before_save :set_processing_started_at, if: :status_changed_to_processing?

  after_commit -> { VideoExportJob.perform_later(id) }, on: :create
  after_commit -> { file.purge_later }, on: :destroy
  after_commit :broadcast_status, on: %i[create update], if: :saved_change_to_status?

  def display_name
    config&.dig('track_name').presence || "#{start_at&.strftime('%Y-%m-%d')} — #{end_at&.strftime('%Y-%m-%d')}"
  end

  def download_filename
    base = config&.dig('track_name').presence || "route-#{start_at&.strftime('%Y-%m-%d')}"
    "#{base.parameterize}.mp4"
  end

  def preview_path
    return unless completed? && file.attached?

    url_helpers.rails_blob_path(file, disposition: 'inline', only_path: true)
  end

  private

  def url_helpers
    Rails.application.routes.url_helpers
  end

  def generate_callback_nonce
    self.callback_nonce ||= SecureRandom.urlsafe_base64(32)
  end

  def set_processing_started_at
    self.processing_started_at = Time.current
  end

  def status_changed_to_processing?
    status_changed? && processing?
  end

  def broadcast_status
    VideoExportsChannel.broadcast_to(user, broadcast_payload)
  end

  def broadcast_payload
    {
      id:,
      name: display_name,
      status:,
      error_message:,
      created_at: created_at&.strftime('%e %b %Y, %H:%M'),
      file_size: completed? && file.attached? ? human_file_size : nil,
      download_url: completed? && file.attached? ? download_path : nil,
      preview_url: preview_path,
      delete_url: url_helpers.video_export_path(self, only_path: true)
    }
  end

  def human_file_size
    ActiveSupport::NumberHelper.number_to_human_size(file.byte_size)
  end

  def download_path
    url_helpers.rails_blob_path(file, disposition: 'attachment', only_path: true)
  end
end
