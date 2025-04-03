# frozen_string_literal: true

class Export < ApplicationRecord
  belongs_to :user

  enum :status, { created: 0, processing: 1, completed: 2, failed: 3 }
  enum :file_format, { json: 0, gpx: 1 }

  validates :name, presence: true

  has_one_attached :file

  after_commit -> { ExportJob.perform_later(id) }, on: :create
  after_commit -> { remove_attached_file }, on: :destroy

  def process!
    Exports::Create.new(export: self).call
  end

  private

  def remove_attached_file
    storage_config = Rails.application.config.active_storage

    if storage_config.service == :local
      file.purge_later
    else
      file.purge
    end
  end
end
