# frozen_string_literal: true

class Export < ApplicationRecord
  belongs_to :user

  enum :status, { created: 0, processing: 1, completed: 2, failed: 3 }
  enum :format, { json: 0, gpx: 1 }

  validates :name, presence: true

  has_one_attached :file

  after_commit -> { ExportJob.perform_later(id) }, on: :create
  after_commit -> { file.purge }, on: :destroy

  def process!
    Exports::Create.new(export: self).call
  end
end
