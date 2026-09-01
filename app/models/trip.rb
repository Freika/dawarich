# frozen_string_literal: true

class Trip < ApplicationRecord
  include Demoable
  include Calculateable
  include DistanceConvertible
  include Notable

  RECALCULATE_COOLDOWN = 60.seconds

  has_rich_text :description

  belongs_to :user
  has_many :shared_links, -> { where(resource_type: SharedLink.resource_types[:trip]) },
           foreign_key: :resource_id, inverse_of: false, dependent: :destroy

  validates :name, :started_at, :ended_at, presence: true
  validate :started_at_before_ended_at

  after_create :enqueue_calculation_jobs, unless: :demo?
  after_update :enqueue_calculation_jobs, if: :should_recalculate_after_update?

  def enqueue_calculation_jobs
    Trips::CalculateAllJob.perform_later(id, user.safe_settings.distance_unit)
  end

  def recalculating?
    last_recalculated_at.present? && last_recalculated_at > RECALCULATE_COOLDOWN.ago
  end

  def points
    user.points.not_anomaly.where(timestamp: started_at.to_i..ended_at.to_i).order(:timestamp)
  end

  def photo_previews
    @photo_previews ||= select_dominant_orientation(photos).sample(12)
  end

  def photo_sources
    @photo_sources ||= photos.map { _1[:source] }.uniq
  end

  def photos_by_day(timezone)
    zone = Time.find_zone(timezone) || Time.find_zone('UTC')

    photos.each_with_object({}) do |photo, acc|
      date = parse_photo_date(photo[:taken_at], zone)
      next if date.nil?

      (acc[date] ||= []) << photo
    end
  end

  def calculate_countries
    self.visited_countries = points.joins(:country).reorder(nil).distinct.pluck('countries.name')
  end

  private

  def should_recalculate_after_update?
    return false if demo?

    saved_change_to_started_at? || saved_change_to_ended_at?
  end

  def photos
    @photos ||= Trips::Photos.new(self, user).call
  end

  def parse_photo_date(raw, zone)
    return nil if raw.blank?

    zone.parse(raw.to_s)&.to_date
  rescue ArgumentError, TypeError
    nil
  end

  def select_dominant_orientation(photos)
    vertical_photos = photos.select { |photo| photo[:orientation] == 'portrait' }
    horizontal_photos = photos.select { |photo| photo[:orientation] == 'landscape' }

    # this is ridiculous, but I couldn't find my way around frontend
    # to show all photos in the same height
    vertical_photos.count > horizontal_photos.count ? vertical_photos : horizontal_photos
  end

  def started_at_before_ended_at
    return if started_at.blank? || ended_at.blank?
    return unless started_at >= ended_at

    errors.add(:ended_at, I18n.t('models.trip.must_be_after_start_date'))
  end
end
