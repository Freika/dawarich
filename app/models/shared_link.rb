# frozen_string_literal: true

class SharedLink < ApplicationRecord
  RESOURCE_TYPES_REQUIRING_ID = %w[trip track].freeze
  LIVE_FRESHNESS_KEY = 'live_freshness_seconds'
  DEFAULT_LIVE_FRESHNESS = 15.minutes.to_i
  LIVE_FRESHNESS_WINDOWS = [DEFAULT_LIVE_FRESHNESS, 1.hour.to_i, 6.hours.to_i, 24.hours.to_i].freeze

  belongs_to :user

  enum :resource_type, { trip: 0, track: 1, timeline: 2, live: 3 }

  SETTING_KEYS = %i[show_photos show_stats show_route show_countries show_description show_days show_day_notes
                    show_map_notes].freeze
  DEFAULT_SETTINGS = {
    trip: {
      'show_photos' => false, 'show_stats' => false
    }.freeze,
    track: {
      'show_photos' => false, 'show_stats' => false
    }.freeze,
    timeline: {
      'show_photos' => false
    }.freeze,
    live: {
      'show_photos' => false, 'show_route' => false, LIVE_FRESHNESS_KEY => DEFAULT_LIVE_FRESHNESS
    }.freeze
  }.freeze

  def self.default_settings_for(resource_type)
    DEFAULT_SETTINGS.fetch(resource_type.to_sym).dup
  end

  # Form values arrive as strings. One that is not a number is kept as sent so
  # validation rejects it instead of it silently becoming the default.
  def self.live_freshness_setting(value)
    return {} if value.nil?

    { LIVE_FRESHNESS_KEY => Integer(value, exception: false) || value }
  end

  validates :name, presence: true, length: { maximum: 255 }
  validates :magic_phrase, length: { maximum: 255 }, allow_nil: true
  validate :resource_id_matches_type
  validate :timeline_import_owned, if: -> { new_record? || will_save_change_to_settings? }
  validate :timeline_dates_present_and_ordered
  validate :expires_at_in_future
  validate :valid_family_audience, if: -> { new_record? || will_save_change_to_settings? }
  validate :allowed_live_freshness, if: -> { live? && (new_record? || will_save_change_to_settings?) }

  after_save -> { Trip.mark_touched_by_user(resource_id) },
             if: -> { trip? && (saved_change_to_resource_id? || saved_change_to_resource_type?) }

  scope :active, lambda {
    where(revoked_at: nil)
      .where('expires_at IS NULL OR expires_at > ?', Time.current)
  }

  def self.family_trips_for(viewer)
    family = viewer&.family
    return none unless family&.access_live? && viewer.feature_enabled?(:family)

    owner_ids = family.members.select { |member| member.feature_enabled?(:family) }.map(&:id)
    active.where(resource_type: :trip, user_id: owner_ids)
          .where("settings ->> 'audience' = 'family' AND settings ->> 'family_id' = ?", family.id.to_s)
          .where.not(user_id: viewer.id)
  end

  def family_only?
    settings['audience'] == 'family'
  end

  def accessible_to?(viewer)
    return true unless family_only?
    return false unless viewer&.feature_enabled?(:family) && user&.feature_enabled?(:family)

    family = user&.family
    return false unless family&.access_live? && family.id.to_s == settings['family_id'].to_s

    family.family_memberships.exists?(user_id: viewer.id)
  end

  def live_freshness_seconds
    allowed_live_freshness_window || DEFAULT_LIVE_FRESHNESS
  end

  def resource
    case resource_type.to_sym
    when :trip     then user.trips.find_by(id: resource_id)
    when :track    then user.tracks.find_by(id: resource_id)
    when :timeline then nil
    when :live     then user
    end
  end

  def active?
    revoked_at.nil? && (expires_at.nil? || expires_at > Time.current)
  end

  def touch_access!
    self.class.where(id: id).update_all(['view_count = view_count + 1, last_accessed_at = ?', Time.current])
  end

  # Value stored in the visitor's unlock cookie. Derived from the current
  # phrase so regenerating it invalidates everyone's prior unlock.
  def unlock_cookie_name
    "shared_link_#{id}"
  end

  def revoke!
    update!(revoked_at: Time.current)
    broadcast_live_share_ended
  end

  def broadcast_live_share_ended
    SharedLocationChannel.broadcast_to(self, { revoked: true }) if resource_type == 'live'
  end

  # First and last instant of the shared timeline in the owner's zone, or nil
  # when the settings hold no usable dates.
  def timeline_window
    zone = Time.find_zone(user.timezone_iana) || Time.find_zone('UTC')
    first_day = zone.parse(settings['start_date'].to_s)
    last_day = zone.parse(settings['end_date'].to_s)
    return if first_day.nil? || last_day.nil?

    [first_day.beginning_of_day, last_day.end_of_day]
  rescue ArgumentError, TypeError
    nil
  end

  def unlock_token
    return if magic_phrase.blank?

    Digest::SHA256.hexdigest("#{id}:#{magic_phrase}")
  end

  def timeline_import_scoped?
    timeline? && settings.key?('import_id')
  end

  def timeline_import
    return unless timeline_import_scoped?

    import_id = settings['import_id'].to_s
    return unless import_id.match?(/\A[1-9]\d*\z/)

    user&.imports&.find_by(id: import_id)
  end

  private

  def timeline_import_owned
    return unless timeline_import_scoped? && timeline_import.nil?

    errors.add(:settings, I18n.t('shared_links.timeline_scope.unavailable'))
  end

  def valid_family_audience
    return unless family_only?
    return if trip? && user&.family&.access_live? && user.family.id.to_s == settings['family_id'].to_s

    errors.add(:base, I18n.t('shared_links.family.unavailable'))
  end

  def allowed_live_freshness
    return if !settings.key?(LIVE_FRESHNESS_KEY) || allowed_live_freshness_window

    errors.add(:settings, I18n.t('models.shared_link.live_freshness_not_allowed'))
  end

  def allowed_live_freshness_window
    LIVE_FRESHNESS_WINDOWS.find { |window| window.to_s == settings[LIVE_FRESHNESS_KEY].to_s }
  end

  def resource_id_matches_type
    needs_id = RESOURCE_TYPES_REQUIRING_ID.include?(resource_type)
    if needs_id && resource_id.blank?
      errors.add(:resource_id, I18n.t('models.shared_link.is_required_for_this_resource_type'))
    elsif !needs_id && resource_id.present?
      errors.add(:resource_id, I18n.t('models.shared_link.must_be_blank_for_this_resource_type'))
    end
  end

  def expires_at_in_future
    return if expires_at.blank?
    return unless new_record? || will_save_change_to_expires_at?

    errors.add(:expires_at, I18n.t('models.shared_link.must_be_in_the_future')) if expires_at <= Time.current
  end

  def timeline_dates_present_and_ordered
    return unless timeline?

    start_date = settings['start_date'].presence
    end_date   = settings['end_date'].presence

    if start_date.blank? || end_date.blank?
      errors.add(:settings, I18n.t('models.shared_link.must_include_start_date_and_end_date_for_timeline_shares'))
      return
    end

    parsed_start = safe_parse_date(start_date)
    parsed_end   = safe_parse_date(end_date)

    if parsed_start.nil? || parsed_end.nil?
      errors.add(:settings, I18n.t('models.shared_link.start_date_and_end_date_must_be_parseable_as_dates'))
      return
    end

    return unless parsed_end < parsed_start

    errors.add(:settings,
               I18n.t('models.shared_link.end_date_must_be_on_or_after_start_date'))
  end

  def safe_parse_date(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
