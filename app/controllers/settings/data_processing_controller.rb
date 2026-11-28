# frozen_string_literal: true

# How points become tracks and visits, which readings count as GPS noise, how
# long a stay counts toward a city, and which transportation modes are detected. These
# change data the user already has, so they live in Settings, not on the map.
class Settings::DataProcessingController < ApplicationController
  before_action :authenticate_user!
  before_action :authenticate_active_user!, except: :show
  # The recalculations and points APIs keep these rebuilds to full access too.
  before_action :require_pro!, only: %i[recalculate reapply_anomaly_filter]

  BOOLEAN_KEYS = %w[split_tracks_at_midnight gps_filtering_enabled gps_accuracy_filter_enabled].freeze
  # Stored as sent, like the visits page they came from did; SafeSettings clamps them on read.
  VISIT_KEYS = %w[visit_radius_meters visit_min_points visit_min_duration_minutes].freeze
  INTEGER_KEYS = %w[meters_between_routes minutes_between_routes gps_accuracy_threshold
                    min_minutes_spent_in_city].concat(VISIT_KEYS).freeze
  MODES_KEY = 'enabled_transportation_modes'

  def show
    @reclassifying = Tracks::TransportationRecalculationStatus.new(current_user.id).in_progress?
  end

  def update
    settings = coerced_settings
    if settings.key?(MODES_KEY) && settings[MODES_KEY].empty?
      return back_with(alert: t('services.users.settings_updater.enable_at_least_one_transportation_mode'))
    end

    # The updater refuses any change to the modes while a re-classification
    # runs; an unchanged list from a page opened earlier must not block the rest.
    stored_modes = current_user.safe_settings.enabled_transportation_modes
    settings.delete(MODES_KEY) if settings[MODES_KEY]&.sort == stored_modes.sort

    visit_settings = settings.extract!(*VISIT_KEYS)
    result = Users::SettingsUpdater.new(current_user, settings).call
    if result.success?
      merge_visit_settings(visit_settings) if visit_settings.any?
      back_with(notice: t('controllers.settings.general.settings_updated'))
    else
      back_with(alert: result.error || t('controllers.api.v1.settings.something_went_wrong'))
    end
  end

  def recalculate
    scope = 'controllers.api.v1.recalculations'
    only = params[:only].presence_in(Users::RecalculateDataJob::ONLY)
    year = Integer(params[:year], exception: false)
    if Users::QueueDataRecalculation.new(current_user, year:, only:).call
      back_with(notice: t("#{scope}.recalculation_queued_tracks_stats_and_digests_will_be_regenerated_in"))
    else
      back_with(notice: t("#{scope}.recalculation_already_in_progress_for_this_user"))
    end
  end

  # Trip Detection reads the whole history on every run; this starts one now.
  def detect_trips
    return back_with(alert: t('.trip_detection_is_off')) unless current_user.safe_settings.trip_detection_enabled?

    Trips::DetectJob.schedule(current_user.id)
    back_with(notice: t('.trip_detection_queued'))
  end

  def reapply_anomaly_filter
    if Points::QueueAnomalyReevaluation.new(current_user).call
      back_with(notice: t('controllers.api.v1.points.re_evaluation_queued_existing_anomaly_flags_will_be_cleared_and'))
    else
      back_with(notice: t('controllers.api.v1.points.anomaly_re_evaluation_already_in_progress'))
    end
  end

  private

  # Merged in the database, so a key another process writes meanwhile (trip
  # detection records long absences there) is not overwritten.
  def merge_visit_settings(visit_settings)
    User.where(id: current_user.id)
        .update_all(["settings = COALESCE(settings, '{}'::jsonb) || ?::jsonb", visit_settings.to_json])
  end

  def back_with(flash_message)
    redirect_to settings_data_processing_path, flash_message
  end

  # A form sends strings and "0"/"1"; store the booleans and integers the map
  # panel used to send, since parts of the app read these settings raw.
  def coerced_settings
    raw = params.require(:settings).permit(*BOOLEAN_KEYS, *INTEGER_KEYS, MODES_KEY => []).to_h
    settings = raw.to_h do |key, value|
      next [key, ActiveModel::Type::Boolean.new.cast(value)] if BOOLEAN_KEYS.include?(key)
      next [key, value.to_i] if INTEGER_KEYS.include?(key)

      [key, value.compact_blank]
    end
    # An emptied or garbled number field keeps the stored value instead of saving 0.
    settings.reject { |key, value| INTEGER_KEYS.include?(key) && !value.positive? }
  end
end
