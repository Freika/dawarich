# frozen_string_literal: true

module Settings
  class OnboardingsController < ApplicationController
    before_action :authenticate_user!

    def update
      current_user.settings['onboarding_completed'] = true
      current_user.save!
      head :ok
    end

    def demo_data
      result = DemoData::Importer.new(current_user).call

      case result[:status]
      when :created
        redirect_to demo_data_landing_path, notice: 'Demo data loaded.'
      when :exists
        redirect_to demo_data_landing_path, notice: 'Demo data is already loaded.'
      else
        redirect_to root_path, alert: 'Something went wrong loading demo data.'
      end
    end

    def destroy_demo_data
      result = DemoData::Destroyer.new(current_user).call

      case result[:status]
      when :destroyed
        redirect_to root_path, notice: 'Demo data removed.'
      when :no_demo_data
        redirect_to root_path, notice: 'No demo data found.'
      else
        redirect_to root_path, alert: 'Something went wrong removing demo data.'
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
