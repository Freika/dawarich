# frozen_string_literal: true

class VideoExport < ApplicationRecord
  include Rails.application.routes.url_helpers

  belongs_to :user
  belongs_to :track, optional: true

  enum :status, { created: 0, processing: 1, completed: 2, failed: 3 }

  validates :start_at, :end_at, presence: true

  has_one_attached :file

  before_save :set_processing_started_at, if: :status_changed_to_processing?

  after_commit -> { VideoExportJob.perform_later(id) }, on: :create
  after_commit -> { file.purge_later }, on: :destroy
  after_commit :broadcast_status, on: %i[create update]

  def display_name
    config&.dig('track_name').presence || "#{start_at.strftime('%Y-%m-%d')} — #{end_at.strftime('%Y-%m-%d')}"
  end

  def download_filename
    base = config&.dig('track_name').presence || "route-#{start_at.strftime('%Y-%m-%d')}"
    "#{base.parameterize}.mp4"
  end

  def preview_path
    return unless completed? && file.attached?

    rails_blob_path(file, disposition: 'inline', only_path: true)
  end

  private

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
      download_url: completed? && file.attached? ? download_path : nil,
      preview_url: preview_path
    }
  end

  def download_path
    rails_blob_path(file, disposition: 'attachment', only_path: true)
  end
end
