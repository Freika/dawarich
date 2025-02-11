# frozen_string_literal: true

class Import < ApplicationRecord
  belongs_to :user
  has_many :points, dependent: :destroy

  delegate :count, to: :points, prefix: true

  include ImportUploader::Attachment(:raw)

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
end
