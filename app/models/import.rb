# frozen_string_literal: true

class Import < ApplicationRecord
  belongs_to :user
  has_many :points, dependent: :destroy

  has_one_attached :file

  after_commit -> { Import::ProcessJob.perform_later(id) }, on: :create
  after_commit :remove_attached_file, on: :destroy

  validates :name, presence: true, uniqueness: { scope: :user_id }

  enum :source, {
    google_semantic_history: 0, owntracks: 1, google_records: 2,
    google_phone_takeout: 3, gpx: 4, immich_api: 5, geojson: 6, photoprism_api: 7
  }

  def process!
    Imports::Create.new(user, self).call
  end

  def reverse_geocoded_points_count
    points.reverse_geocoded.count
  end

  def years_and_months_tracked
    points.order(:timestamp).pluck(:timestamp).map do |timestamp|
      time = Time.zone.at(timestamp)
      [time.year, time.month]
    end.uniq
  end

  def migrate_to_new_storage
    return if file.attached?

    raw_file = File.new(raw_data)

    file.attach(io: raw_file, filename: name, content_type: 'application/json')
  end

  private

  def remove_attached_file
    file.purge_later
  end
end
