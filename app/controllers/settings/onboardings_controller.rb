# frozen_string_literal: true

module Settings
  class OnboardingsController < ApplicationController
    EVENTS = %w[
      onboarding_shown onboarding_track_selected onboarding_import_selected
      onboarding_demo_selected onboarding_family_selected onboarding_skipped
    ].freeze

    before_action :authenticate_user!

    def update
      return head :unprocessable_content unless current_user.settings.is_a?(Hash)

      current_user.with_lock do
        current_user.settings['onboarding_completed'] = true
        current_user.save!
      end
      head :ok
    end

    def event
      return head :no_content if DawarichSettings.self_hosted?
      return head :unprocessable_content unless EVENTS.include?(params[:name])
      return head :unprocessable_content unless current_user.settings.is_a?(Hash)

      current_user.with_lock do
        events = current_user.settings['onboarding_events'] || {}
        events[params[:name]] ||= Time.current.utc.iso8601
        current_user.settings['onboarding_events'] = events
        current_user.save!
      end
      head :no_content
    end

    def demo_data
      result = DemoData::Importer.new(current_user).call

      case result[:status]
      when :created
        redirect_to demo_data_landing_path, notice: I18n.t('controllers.settings.onboardings.demo_data_loaded')
      when :exists
        redirect_to demo_data_landing_path,
                    notice: I18n.t('controllers.settings.onboardings.demo_data_is_already_loaded')
      else
        redirect_to root_path, alert: I18n.t('controllers.settings.onboardings.something_went_wrong_loading_demo_data')
      end
    end

    def destroy_demo_data
      result = DemoData::Destroyer.new(current_user).call

      case result[:status]
      when :destroyed
        redirect_to root_path, notice: I18n.t('controllers.settings.onboardings.demo_data_removed')
      when :no_demo_data
        redirect_to root_path, notice: I18n.t('controllers.settings.onboardings.no_demo_data_found')
      else
        redirect_to root_path, alert: I18n.t('controllers.settings.onboardings.something_went_wrong_removing_demo_data')
      end
    end

    private

    def demo_data_landing_path
      tz = current_user.safe_settings.timezone.presence || 'UTC'
      Time.use_zone(tz) do
        yesterday = Time.zone.today - 1
        map_v2_path(
          panel: 'timeline',
          date: yesterday.iso8601,
          start_at: yesterday.beginning_of_day.iso8601,
          end_at: yesterday.end_of_day.iso8601
        )
      end
    end
  end
end
