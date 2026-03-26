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
        redirect_to root_path, notice: 'Demo data is being imported! Your map will populate shortly.'
      when :exists
        redirect_to root_path, notice: 'Demo data has already been loaded.'
      end
    end

    def destroy_demo_data
      demo_import = current_user.imports.find_by(demo: true)

      if demo_import
        demo_import.deleting!
        Imports::DestroyJob.perform_later(demo_import.id)
        redirect_to root_path, notice: 'Demo data is being deleted.'
      else
        redirect_to root_path, notice: 'No demo data found.'
      end
    end
  end
end
