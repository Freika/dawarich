# frozen_string_literal: true

class Note < ApplicationRecord
  include Nearable

  has_rich_text :body

  belongs_to :user
  belongs_to :attachable, polymorphic: true, optional: true

  before_validation :build_lonlat_from_coords, if: -> { @latitude.present? && @longitude.present? }

  validates :noted_at, presence: true

  validate :unique_date_per_attachable
  validate :date_within_attachable_range
  validate :attachable_belongs_to_user

  scope :standalone, -> { where(attachable_id: nil) }
  scope :attached, -> { where.not(attachable_id: nil) }
  scope :for_trip_day, ->(trip, date) { where(attachable: trip).where('CAST(noted_at AS date) = ?', date) }
  scope :for_date, ->(date) { where('CAST(noted_at AS date) = ?', date) }
  scope :in_date_range, ->(start_at, end_at) { where(noted_at: start_at..end_at) }
  scope :ordered, -> { order(noted_at: :desc) }
  scope :for_user, ->(user) { where(user: user) }

  def date
    noted_at&.to_date
  end

  def date=(val)
    return if val.blank?

    self.noted_at = val.to_date.to_datetime.noon
  end

  def latitude
    lonlat&.y
  end

  def longitude
    lonlat&.x
  end

  def latitude=(val)
    @latitude = val.presence&.to_f
  end

  def longitude=(val)
    @longitude = val.presence&.to_f
  end

  private

  def build_lonlat_from_coords
    self.lonlat = "POINT(#{@longitude} #{@latitude})"
  end

  def unique_date_per_attachable
    return if noted_at.blank? || attachable_id.blank?

    scope = self.class.where(attachable_type: attachable_type, attachable_id: attachable_id)
                .where('CAST(noted_at AS date) = ?', noted_at.to_date)
    scope = scope.where.not(id: id) if persisted?

    errors.add(:date, 'has already been taken') if scope.exists?
  end

  def date_within_attachable_range
    return unless attachable.is_a?(Trip)
    return if date.blank? || attachable.blank?
    return if attachable.started_at.blank? || attachable.ended_at.blank?
    return unless date < attachable.started_at.to_date || date > attachable.ended_at.to_date

    errors.add(:date, 'must be within the trip date range')
  end

  def attachable_belongs_to_user
    return if attachable.blank?
    return unless attachable.respond_to?(:user_id)
    return if attachable.user_id == user_id

    errors.add(:attachable, 'must belong to the same user')
  end
end
